# Echoes Server

Rust relay server for the Godot game in this repository (`game-generated`).

This server provides:
- room creation by code (`POST /lobby/create`)
- WebSocket room transport (`/ws/room/{code}`)
- typed/validated message protocol
- host-only and directed routing rules
- basic rate limiting and inactivity timeout
- room TTL cleanup and metrics endpoint

It is designed for co-op sessions (2-4 players) used by the project's `NetManager`.

---

## 1) Project Layout

```text
server/
├── Cargo.toml
├── Dockerfile
├── Dockerfile.slim
├── docker-compose.yml
├── README.md
├── benches/
│   └── routing.rs
├── tests/
│   └── api_tests.rs
└── src/
    ├── main.rs
    ├── lib.rs
    ├── api.rs
    ├── protocol.rs
    ├── room.rs
    └── router.rs
```

---

## 2) Quick Start (Local)

From repository root:

```bash
cd server
cargo run
```

Default bind:
- `HOST=0.0.0.0`
- `PORT=7777`

Server will listen on:
- HTTP: `http://127.0.0.1:7777`
- WS: `ws://127.0.0.1:7777`

---

## 3) Environment Variables

| Variable | Default | Description |
|---|---:|---|
| `HOST` | `0.0.0.0` | Bind address |
| `PORT` | `7777` | HTTP + WebSocket port |
| `MAX_ROOMS` | `1000` | Maximum simultaneous rooms |
| `ROOM_TTL_SECS` | `3600` | Remove empty rooms after N seconds |
| `CODE_LENGTH` | `6` | Generated room code length (min 4) |

Example:

```bash
HOST=0.0.0.0 PORT=7777 MAX_ROOMS=200 ROOM_TTL_SECS=1800 CODE_LENGTH=6 cargo run
```

---

## 4) Docker

### Standard image

```bash
cd server
docker compose up --build
```

This starts service:
- `echoes-server` at `localhost:7777`

### Slim profile (stripped binary)

```bash
cd server
docker compose --profile slim up --build
```

This starts:
- `echoes-server-slim` exposed as `localhost:7778` (container still listens on `7777`)

---

## 5) HTTP API

## `POST /lobby/create`

Create room with max players 2..4.

Request:

```json
{
  "max_players": 2
}
```

Success (`200`):

```json
{
  "code": "A3F7K2"
}
```

Validation error (`400`):

```json
{
  "error": "max_players must be between 2 and 4"
}
```

Capacity error (`503`):

```json
{
  "error": "max rooms reached"
}
```

## `GET /health`

```json
{
  "status": "ok",
  "rooms": 3,
  "players": 7
}
```

## `GET /metrics`

Prometheus-like plain text counters:

```text
rooms_total 2
players_total 3
msg_in_total 128
msg_drop_total 4
invalid_msg_total 1
ws_error_total 2
```

---

## 6) WebSocket Endpoint

Connect to:

```text
ws://<host>:<port>/ws/room/<ROOM_CODE>
```

On success server sends:

```json
{
  "t": "joined",
  "player_id": 0,
  "total": 1,
  "max_players": 2
}
```

On room errors:

```json
{"t":"error","code":"room_not_found","error":"room not found"}
{"t":"error","code":"room_full","error":"room full"}
```

---

## 7) Routing Rules

Server behavior by message type:

1. `ping` -> responds only to sender with `pong`
2. `enemy_hit` -> routed to host only
3. `portal_activate` -> routed to host only
4. `item_gift` -> routed only to peer in `to`
5. all others -> broadcast to all peers in room except sender

Server adds `from` to relayed messages.

---

## 8) Validation and Safety

### Typed protocol

Incoming JSON is parsed into strongly-typed `ClientMessage` enum (`src/protocol.rs`).

Unknown/invalid schema is rejected.

### Message validation

- `room_config.max_players` must be 2..4
- `item_gift.item` must be JSON object
- `item_gift.to` cannot be sender itself (guardrail)
- `enemy_hit` bounds:
  - `id >= 0`
  - `damage > 0`
  - `damage <= 1_000_000`

### Dedupe (`seq`)

If client includes `seq` (u64) for critical messages (`enemy_hit`, `item_gift`),
duplicates are dropped per connection.

### Rate limiting

Per connection, 1-second window:
- all messages: max `240/s`
- `pos`: max `80/s`

When exceeded:

```json
{"t":"error","code":"rate_limited","error":"too many messages"}
```

### Inactivity timeout

If no incoming frames for 15s, connection is closed with timeout error.

---

## 9) Room Lifecycle

1. Host creates room (`POST /lobby/create`)
2. Host connects to WS room (gets `player_id = 0`)
3. Clients connect by code (receive next free `player_id`)
4. On disconnect server broadcasts `player_disconnected`
5. Empty room is kept temporarily and removed by TTL cleanup task

---

## 10) Testing and Benchmarks

Run tests:

```bash
cd server
cargo test
```

Compile benchmarks:

```bash
cargo bench --no-run
```

Run benchmark:

```bash
cargo bench
```

Current benchmark target:
- `benches/routing.rs` (broadcast routing path)

---

## 11) Godot Client Integration

This repository already points `NetManager` to configurable server host/port.

In lobby pre-room UI set server address, for example:
- `127.0.0.1:7777` (same machine)
- `192.168.1.100:7777` (LAN host)

Flow:
1. Player A: Host -> create room -> gets code
2. Player B: Join -> enter same server address + room code

---

## 12) Common Dev Commands

```bash
# format
cargo fmt

# lint
cargo clippy --all-targets --all-features -- -D warnings

# test
cargo test

# run
cargo run
```

---

## 13) Notes

- Transport is plain WS/HTTP by default (`ws://`, `http://`).
- For production internet deployment use TLS termination (`wss://`) behind reverse proxy.
- Metrics endpoint is intentionally simple and lightweight.
