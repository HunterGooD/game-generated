# Echoes Server (RU)

Rust relay-сервер для Godot-игры из этого репозитория (`game-generated`).

Сервер предоставляет:
- создание комнат по коду (`POST /lobby/create`)
- транспорт по WebSocket (`/ws/room/{code}`)
- типизированный и валидируемый протокол сообщений
- правила маршрутизации (host-only, directed, broadcast)
- базовый rate limit и inactivity timeout
- TTL-очистку пустых комнат и endpoint метрик

Предназначен для кооператива на 2-4 игроков и используется `NetManager` в проекте.

---

## 1) Структура

```text
server/
├── Cargo.toml
├── Dockerfile
├── Dockerfile.slim
├── docker-compose.yml
├── README.md
├── README-RU.md
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

## 2) Быстрый старт (локально)

Из корня репозитория:

```bash
cd server
cargo run
```

По умолчанию:
- `HOST=0.0.0.0`
- `PORT=7777`

Сервер слушает:
- HTTP: `http://127.0.0.1:7777`
- WS: `ws://127.0.0.1:7777`

---

## 3) Переменные окружения

| Переменная | По умолчанию | Описание |
|---|---:|---|
| `HOST` | `0.0.0.0` | Адрес bind |
| `PORT` | `7777` | Порт HTTP + WebSocket |
| `MAX_ROOMS` | `1000` | Максимум одновременных комнат |
| `ROOM_TTL_SECS` | `3600` | Через сколько секунд удалять пустую комнату |
| `CODE_LENGTH` | `6` | Длина кода комнаты (минимум 4) |

Пример:

```bash
HOST=0.0.0.0 PORT=7777 MAX_ROOMS=200 ROOM_TTL_SECS=1800 CODE_LENGTH=6 cargo run
```

---

## 4) Docker

### Обычный образ

```bash
cd server
docker compose up --build
```

Поднимается сервис:
- `echoes-server` на `localhost:7777`

### Slim-профиль (уменьшенный бинарник)

```bash
cd server
docker compose --profile slim up --build
```

Поднимается:
- `echoes-server-slim` на `localhost:7778` (внутри контейнера порт `7777`)

---

## 5) HTTP API

## `POST /lobby/create`

Создание комнаты с лимитом 2..4 игрока.

Request:

```json
{
  "max_players": 2
}
```

Успех (`200`):

```json
{
  "code": "A3F7K2"
}
```

Ошибка валидации (`400`):

```json
{
  "error": "max_players must be between 2 and 4"
}
```

Ошибка лимита (`503`):

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

Prometheus-подобные метрики в plain text:

```text
rooms_total 2
players_total 3
msg_in_total 128
msg_drop_total 4
invalid_msg_total 1
ws_error_total 2
```

---

## 6) WebSocket endpoint

Подключение:

```text
ws://<host>:<port>/ws/room/<ROOM_CODE>
```

При успехе сервер отправляет:

```json
{
  "t": "joined",
  "player_id": 0,
  "total": 1,
  "max_players": 2
}
```

Ошибки комнаты:

```json
{"t":"error","code":"room_not_found","error":"room not found"}
{"t":"error","code":"room_full","error":"room full"}
```

---

## 7) Правила маршрутизации

Поведение сервера по типам сообщений:

1. `ping` -> только отправителю `pong`
2. `enemy_hit` -> только хосту
3. `portal_activate` -> только хосту
4. `item_gift` -> только игроку из `to`
5. остальные типы -> broadcast всем в комнате, кроме отправителя

Для пересылаемых сообщений сервер добавляет поле `from`.

---

## 8) Валидация и защита

### Типизированный протокол

Входящий JSON парсится в enum `ClientMessage` (`src/protocol.rs`).

Неизвестные типы и неверные схемы отклоняются.

### Валидация

- `room_config.max_players` должен быть 2..4
- `item_gift.item` должен быть JSON object
- `item_gift.to` не может быть самим отправителем
- `enemy_hit`:
  - `id >= 0`
  - `damage > 0`
  - `damage <= 1_000_000`

### Dedupe по `seq`

Если клиент передает `seq` (u64) для критичных сообщений (`enemy_hit`, `item_gift`),
дубликаты на одном соединении отбрасываются.

### Rate limit

На одно соединение, окно 1 сек:
- все сообщения: максимум `240/s`
- `pos`: максимум `80/s`

При превышении:

```json
{"t":"error","code":"rate_limited","error":"too many messages"}
```

### Таймаут неактивности

Если нет входящих кадров 15 секунд, соединение закрывается с ошибкой timeout.

---

## 9) Жизненный цикл комнаты

1. Хост вызывает `POST /lobby/create`
2. Хост подключается к WS (`player_id = 0`)
3. Клиенты подключаются по коду (получают следующий свободный `player_id`)
4. При disconnect сервер рассылает `player_disconnected`
5. Пустая комната удаляется cleanup-задачей после `ROOM_TTL_SECS`

---

## 10) Тесты и бенчмарки

Запуск тестов:

```bash
cd server
cargo test
```

Сборка бенчмарков:

```bash
cargo bench --no-run
```

Запуск бенчмарков:

```bash
cargo bench
```

Текущий benchmark:
- `benches/routing.rs` (путь broadcast-маршрутизации)

---

## 11) Интеграция с Godot-клиентом

В проекте `NetManager` уже переведен на конфигурируемый host/port.

В прером-UI лобби укажи адрес сервера, например:
- `127.0.0.1:7777` (локально)
- `192.168.1.100:7777` (LAN)

Сценарий:
1. Игрок A: Host -> create room -> получает код
2. Игрок B: Join -> вводит адрес сервера + код комнаты

---

## 12) Полезные команды

```bash
# форматирование
cargo fmt

# линт
cargo clippy --all-targets --all-features -- -D warnings

# тесты
cargo test

# запуск
cargo run
```

---

## 13) Примечания

- По умолчанию используется plain WS/HTTP (`ws://`, `http://`).
- Для продакшена через интернет рекомендуется TLS termination (`wss://`) через reverse proxy.
- `/metrics` сделан максимально простым и легким.
