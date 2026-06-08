use std::{
    collections::{HashMap, HashSet},
    net::SocketAddr,
    sync::Arc,
    time::{Duration, Instant},
};

use axum::{
    extract::{ws::WebSocket, Path, Query, State, WebSocketUpgrade},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use futures_util::{SinkExt, StreamExt};
use tokio::sync::{mpsc, RwLock};
use tracing::{debug, warn};

use crate::{
    protocol::{
        joined_message, parse_client_message, player_disconnected_message, CreateRoomRequest,
        CreateRoomResponse, ErrorResponse, HealthResponse,
    },
    room::{generate_room_code, Room},
};

#[derive(Debug, Clone)]
pub struct Config {
    pub host: String,
    pub port: u16,
    pub max_rooms: usize,
    pub room_ttl_secs: u64,
    pub code_length: usize,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            host: "0.0.0.0".to_string(),
            port: 7777,
            max_rooms: 1000,
            room_ttl_secs: 3600,
            code_length: 6,
        }
    }
}

#[derive(Debug, Default)]
pub struct ServerState {
    pub rooms: HashMap<String, Room>,
}

#[derive(Debug, Default)]
pub struct Metrics {
    pub msg_in_total: u64,
    pub msg_drop_total: u64,
    pub invalid_msg_total: u64,
    pub ws_error_total: u64,
}

#[derive(Debug, Clone)]
pub struct AppState {
    pub config: Config,
    pub state: Arc<RwLock<ServerState>>,
    pub metrics: Arc<RwLock<Metrics>>,
}

impl AppState {
    pub fn new(config: Config) -> Self {
        Self {
            config,
            state: Arc::new(RwLock::new(ServerState::default())),
            metrics: Arc::new(RwLock::new(Metrics::default())),
        }
    }
}

pub fn app_router(app_state: AppState) -> Router {
    Router::new()
        .route("/lobby/create", post(create_room))
        .route("/health", get(health))
        .route("/metrics", get(metrics))
        .route("/ws/room/:code", get(ws_room))
        .with_state(app_state)
}

pub fn bind_addr(cfg: &Config) -> anyhow::Result<SocketAddr> {
    Ok(format!("{}:{}", cfg.host, cfg.port).parse()?)
}

async fn create_room(
    State(app): State<AppState>,
    Json(req): Json<CreateRoomRequest>,
) -> impl IntoResponse {
    if let Err(err) = req.validate() {
        return (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse { error: err }),
        )
            .into_response();
    }
    let max_players = req.max_players;
    let mut state = app.state.write().await;
    if state.rooms.len() >= app.config.max_rooms {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(ErrorResponse {
                error: "max rooms reached".to_string(),
            }),
        )
            .into_response();
    }

    let code = loop {
        let c = generate_room_code(app.config.code_length);
        if !state.rooms.contains_key(&c) {
            break c;
        }
    };

    state
        .rooms
        .insert(code.clone(), Room::new(code.clone(), max_players, req.version));

    (StatusCode::OK, Json(CreateRoomResponse { code })).into_response()
}

async fn health(State(app): State<AppState>) -> impl IntoResponse {
    let state = app.state.read().await;
    let rooms = state.rooms.len();
    let players = state.rooms.values().map(Room::peer_count).sum();
    (
        StatusCode::OK,
        Json(HealthResponse {
            status: "ok".to_string(),
            rooms,
            players,
        }),
    )
}

async fn metrics(State(app): State<AppState>) -> impl IntoResponse {
    let state = app.state.read().await;
    let m = app.metrics.read().await;
    let players: usize = state.rooms.values().map(Room::peer_count).sum();
    let body = format!(
        "rooms_total {}\nplayers_total {}\nmsg_in_total {}\nmsg_drop_total {}\ninvalid_msg_total {}\nws_error_total {}\n",
        state.rooms.len(),
        players,
        m.msg_in_total,
        m.msg_drop_total,
        m.invalid_msg_total,
        m.ws_error_total,
    );
    (StatusCode::OK, body)
}

fn send_ws_error(tx: &mpsc::UnboundedSender<axum::extract::ws::Message>, code: &str, message: &str) {
    let _ = tx.send(axum::extract::ws::Message::Text(
        serde_json::json!({"t":"error","code": code, "error": message}).to_string(),
    ));
}

#[derive(Debug)]
struct RateLimiter {
    window_start: Instant,
    all_count: u32,
    pos_count: u32,
}

impl RateLimiter {
    fn new() -> Self {
        Self {
            window_start: Instant::now(),
            all_count: 0,
            pos_count: 0,
        }
    }

    fn allow(&mut self, t: &str) -> bool {
        let now = Instant::now();
        if now.duration_since(self.window_start) >= Duration::from_secs(1) {
            self.window_start = now;
            self.all_count = 0;
            self.pos_count = 0;
        }
        self.all_count += 1;
        if self.all_count > 240 {
            return false;
        }
        if t == "pos" {
            self.pos_count += 1;
            if self.pos_count > 80 {
                return false;
            }
        }
        true
    }
}

async fn ws_room(
    ws: WebSocketUpgrade,
    Path(code): Path<String>,
    Query(params): Query<std::collections::HashMap<String, String>>,
    State(app): State<AppState>,
) -> impl IntoResponse {
    let client_version = params.get("v").cloned().unwrap_or_default();
    ws.on_upgrade(move |socket| handle_socket(socket, code.to_uppercase(), client_version, app))
}

async fn handle_socket(socket: WebSocket, code: String, client_version: String, app: AppState) {
    let (mut ws_tx, mut ws_rx) = socket.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<axum::extract::ws::Message>();

    let player_id = {
        let mut state = app.state.write().await;
        let room = match state.rooms.get_mut(&code) {
            Some(r) => r,
            None => {
                let _ = ws_tx
                    .send(axum::extract::ws::Message::Text(
                        serde_json::json!({"t":"error","code":"room_not_found","error":"room not found"}).to_string(),
                    ))
                    .await;
                return;
            }
        };

        // Version gate: a joiner must present the same app version the host
        // created the room with (?v= on the ws URL). Prevents an old client from
        // connecting to a room hosted by a newer build. Empty room version = no gate.
        if !room.version.is_empty() && room.version != client_version {
            let _ = ws_tx
                .send(axum::extract::ws::Message::Text(
                    serde_json::json!({"t":"error","code":"version_mismatch","error":"game version mismatch — update to join"}).to_string(),
                ))
                .await;
            return;
        }

        if room.is_full() {
            let _ = ws_tx
                .send(axum::extract::ws::Message::Text(
                    serde_json::json!({"t":"error","code":"room_full","error":"room full"}).to_string(),
                ))
                .await;
            return;
        }

        let pid = match room.allocate_player_id() {
            Some(p) => p,
            None => return,
        };
        room.add_peer(pid, tx.clone());

        let joined = joined_message(pid, room.peer_count(), room.max_players);
        room.send_json(pid, &joined);
        pid
    };

    let writer = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if ws_tx.send(msg).await.is_err() {
                break;
            }
        }
    });

    let mut limiter = RateLimiter::new();
    let mut seen_seq: HashSet<u64> = HashSet::new();

    loop {
        let next = tokio::time::timeout(Duration::from_secs(15), ws_rx.next()).await;
        let Some(Ok(msg)) = (match next {
            Ok(v) => v,
            Err(_) => {
                send_ws_error(&tx, "timeout", "connection timed out (no activity)");
                break;
            }
        }) else {
            break;
        };

        match msg {
            axum::extract::ws::Message::Text(text) => {
                match parse_client_message(&text) {
                    Ok((typed, val)) => {
                        let t = typed.message_type();
                        {
                            let mut metrics = app.metrics.write().await;
                            metrics.msg_in_total += 1;
                        }
                        if !limiter.allow(t) {
                            let mut metrics = app.metrics.write().await;
                            metrics.msg_drop_total += 1;
                            send_ws_error(&tx, "rate_limited", "too many messages");
                            continue;
                        }

                        if let Some(seq) = val.get("seq").and_then(|v| v.as_u64()) {
                            if matches!(typed, crate::protocol::ClientMessage::EnemyHit { .. } | crate::protocol::ClientMessage::ItemGift { .. }) {
                                if seen_seq.contains(&seq) {
                                    let mut metrics = app.metrics.write().await;
                                    metrics.msg_drop_total += 1;
                                    continue;
                                }
                                seen_seq.insert(seq);
                                if seen_seq.len() > 4096 {
                                    seen_seq.clear();
                                }
                            }
                        }

                        if let crate::protocol::ClientMessage::EnemyHit { id, damage } = typed {
                            if id < 0 || damage <= 0 || damage > 1_000_000 {
                                let mut metrics = app.metrics.write().await;
                                metrics.msg_drop_total += 1;
                                send_ws_error(&tx, "invalid_enemy_hit", "enemy_hit out of bounds");
                                continue;
                            }
                        }
                        if let crate::protocol::ClientMessage::ItemGift { to, .. } = typed {
                            if to == player_id {
                                let mut metrics = app.metrics.write().await;
                                metrics.msg_drop_total += 1;
                                send_ws_error(&tx, "invalid_item_gift", "cannot gift to self");
                                continue;
                            }
                        }

                        let state = app.state.read().await;
                        if let Some(room) = state.rooms.get(&code) {
                            room.route_and_send(player_id, &typed, &val);
                        }
                    }
                    Err(err) => {
                        warn!(%err, "invalid message payload");
                        let mut metrics = app.metrics.write().await;
                        metrics.invalid_msg_total += 1;
                        metrics.ws_error_total += 1;
                        send_ws_error(&tx, "invalid_message", &err);
                    }
                }
            }
            axum::extract::ws::Message::Close(_) => break,
            _ => {}
        }
    }

    writer.abort();

    let mut state = app.state.write().await;
    if let Some(room) = state.rooms.get_mut(&code) {
        room.remove_peer(player_id);
        let dc = player_disconnected_message(player_id);
        let peers = room.peer_ids();
        for pid in peers {
            room.send_json(pid, &dc);
        }
        if room.is_empty() {
            debug!(room = %code, "room became empty; waiting for ttl cleanup");
        }
    }
}

pub fn spawn_room_ttl_cleanup(app: AppState) {
    let ttl = Duration::from_secs(app.config.room_ttl_secs.max(5));
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(5));
        loop {
            interval.tick().await;
            let mut state = app.state.write().await;
            let mut to_remove: Vec<String> = Vec::new();
            for (code, room) in state.rooms.iter() {
                if room.is_empty() {
                    if let Some(since) = room.empty_since {
                        if since.elapsed() >= ttl {
                            to_remove.push(code.clone());
                        }
                    }
                }
            }
            for code in to_remove {
                state.rooms.remove(&code);
            }
        }
    });
}
