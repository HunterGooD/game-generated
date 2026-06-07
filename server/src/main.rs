use axum::serve;
use echoes_server::api::{app_router, bind_addr, spawn_room_ttl_cleanup, AppState, Config};
use tokio::net::TcpListener;
use tracing::info;

fn config_from_env() -> Config {
    let mut cfg = Config::default();
    if let Ok(v) = std::env::var("HOST") {
        if !v.is_empty() {
            cfg.host = v;
        }
    }
    if let Ok(v) = std::env::var("PORT") {
        if let Ok(p) = v.parse::<u16>() {
            cfg.port = p;
        }
    }
    if let Ok(v) = std::env::var("MAX_ROOMS") {
        if let Ok(m) = v.parse::<usize>() {
            cfg.max_rooms = m;
        }
    }
    if let Ok(v) = std::env::var("ROOM_TTL_SECS") {
        if let Ok(t) = v.parse::<u64>() {
            cfg.room_ttl_secs = t;
        }
    }
    if let Ok(v) = std::env::var("CODE_LENGTH") {
        if let Ok(l) = v.parse::<usize>() {
            cfg.code_length = l.max(4);
        }
    }
    cfg
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info".into()),
        )
        .init();

    let cfg = config_from_env();
    let addr = bind_addr(&cfg)?;
    let app_state = AppState::new(cfg);
    spawn_room_ttl_cleanup(app_state.clone());
    let app = app_router(app_state);

    let listener = TcpListener::bind(addr).await?;
    info!("echoes-server listening on {}", addr);
    serve(listener, app).await?;
    Ok(())
}
