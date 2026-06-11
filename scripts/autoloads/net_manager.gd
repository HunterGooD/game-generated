extends Node

signal message_received(type: String, data: Dictionary, from_player: int)
signal connected_to_room
signal room_created(code: String)
signal player_joined(player_id: int, total_players: int)
signal player_disconnected(player_id: int)
signal all_players_joined
signal connection_failed(reason: String)

var is_multiplayer: bool = false
var is_host: bool = false
var room_code: String = ""
var max_players: int = 2
var local_player_id: int = 0
var connected_players: int = 0

var lobby_intent: String = ""

var server_host: String = "127.0.0.1"
var server_port: int = 7777

# App/protocol version. The host sends it on /lobby/create; joiners send it as
# ?v= on the ws URL. The relay rejects a join whose version != the room's host
# version (error code "version_mismatch") so old clients can't connect to a room
# hosted by a newer build. BUMP THIS whenever the netcode/protocol changes.
const APP_VERSION: String = "0.0.01-alpha.5"

# Co-op party cap. The relay enforces the same ceiling (server/src/protocol.rs);
# keep them in sync. Hosts pick a size in [MIN_PLAYERS, MAX_PLAYERS] at the hub NPC.
const MIN_PLAYERS: int = 2
const MAX_PLAYERS: int = 10

var _ws: WebSocketPeer = null
var _ping_timer: float = 0.0
var _was_open: bool = false
const PING_INTERVAL: float = 5.0


func _ready() -> void:
	# The transport pump (_process → _ws.poll) MUST keep running even when the
	# local tree is paused by a UI overlay (character sheet / merchant / level-up /
	# game over). Otherwise a paused peer stops sending AND receiving: the host
	# stalls all clients' enemy/state broadcasts, and a paused client freezes its
	# puppet enemies and drops rp_hp/damage updates → co-op desync. NetSync is
	# already PROCESS_MODE_ALWAYS; this is the matching half that was missed.
	process_mode = Node.PROCESS_MODE_ALWAYS


func get_server_ws_url() -> String:
	return "ws://%s:%d" % [server_host, server_port]


func get_server_http_url() -> String:
	return "http://%s:%d" % [server_host, server_port]


func create_room(player_count: int = 2) -> void:
	max_players = clamp(player_count, MIN_PLAYERS, MAX_PLAYERS)
	is_host = true
	local_player_id = 0
	var http := HTTPRequest.new()
	Engine.get_main_loop().root.add_child(http)
	http.request_completed.connect(
		func(_result, _code, _headers, body):
			http.queue_free()
			var s: String = body.get_string_from_utf8()
			var json = JSON.parse_string(s)
			if json == null or not json.has("code"):
				connection_failed.emit("Failed to create room")
				return
			room_code = String(json["code"])
			room_created.emit(room_code)
			connect_to_room(room_code)
	)
	http.request(
		get_server_http_url() + "/lobby/create",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify({"max_players": max_players, "version": APP_VERSION})
	)


func connect_to_room(code: String) -> void:
	room_code = code
	_ws = WebSocketPeer.new()
	var err: int = _ws.connect_to_url(
		get_server_ws_url() + "/ws/room/" + code + "?v=" + APP_VERSION.uri_encode()
	)
	if err != OK:
		connection_failed.emit("WebSocket connect failed: " + str(err))


func disconnect_from_room() -> void:
	if _ws:
		_ws.close()
	_ws = null
	_was_open = false
	is_multiplayer = false
	is_host = false
	room_code = ""
	local_player_id = 0
	connected_players = 0
	max_players = 2


func send(type: String, data: Dictionary = {}) -> void:
	if _ws == null:
		return
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	data["t"] = type
	data["from"] = local_player_id
	_ws.send_text(JSON.stringify(data))


func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state: int = _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			connected_to_room.emit()
		_ping_timer += delta
		if _ping_timer >= PING_INTERVAL:
			_ping_timer = 0.0
			send("ping")
		while _ws.get_available_packet_count() > 0:
			var payload: String = _ws.get_packet().get_string_from_utf8()
			var msg = JSON.parse_string(payload)
			if msg == null:
				continue
			var msg_type: String = String(msg.get("t", ""))
			match msg_type:
				"joined":
					local_player_id = int(msg.get("player_id", 0))
					connected_players = int(msg.get("total", 1))
					if msg.has("max_players"):
						max_players = int(msg.get("max_players", max_players))
					player_joined.emit(local_player_id, connected_players)
					if connected_players >= max_players:
						all_players_joined.emit()
				"player_disconnected":
					var dc_id: int = int(msg.get("player_id", -1))
					# Keep the party count correct even in scenes without a NetSync (the
					# run map): a leave is the only count change there. NetSync's absolute
					# recompute overrides this in scenes that have one.
					if dc_id >= 0:
						connected_players = max(1, connected_players - 1)
					player_disconnected.emit(dc_id)
				"error":
					# Relay rejected us (room_not_found / room_full / version_mismatch).
					var reason: String = String(msg.get("error", "connection rejected"))
					connection_failed.emit(reason)
					disconnect_from_room()
				"pong":
					pass
				_:
					var from_player: int = int(msg.get("from", -1))
					message_received.emit(msg_type, msg, from_player)
	elif state == WebSocketPeer.STATE_CLOSED:
		if is_multiplayer:
			player_disconnected.emit(-1)
		_ws = null
