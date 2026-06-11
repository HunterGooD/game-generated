extends Node2D
## Walkable hub — the staging area between runs. You spawn as your last-played hero
## (default barbarian), walk around, and use two props:
##   • WARDROBE (шкаф) → hero-select overlay (change class, live)
##   • PORTAL → the run map (difficulty pick → node selection)
## Solo for now; co-op (an NPC that creates a room + shows a lobby code) is a later task.
##
## Props use the beacon/merchant interaction pattern: proximity + the `interact` action,
## with an "[E]" prompt. Built in code to avoid .tscn node_path fragility.

const FLOOR_TEX: String = "res://assets/textures/floors/ruins_floor.webp"
const HERO_SELECT := preload("res://scripts/ui/hero_select.gd")
const COOP_PANEL := preload("res://scripts/ui/hub_coop_panel.gd")
# NetSync is loaded lazily (not preloaded) — it pulls in the whole combat scene
# graph (boss / merchant / minions), which a solo hub has no need to compile.
const NET_SYNC_PATH: String = "res://scripts/world/net_sync.gd"
const INTERACT_RANGE: float = 96.0

@onready var _player: Node2D = $Player

# Each prop: {node:Node2D, label:Label, pos:Vector2, base_text:String, action:Callable, in_range:bool}
var _props: Array = []
var _overlay_open: bool = false

# Co-op: the hub runs its own NetSync so party puppets walk around with you.
var _net_sync: Node = null
var _coop_banner: Label = null


func _ready() -> void:
	# Spawn as the last-played hero. choose_class resets the run + emits class_selected,
	# so the Player (already _ready) re-applies the class live.
	if GameManager:
		var hero: String = GameManager.last_class
		if not GameManager.CLASSES.has(hero):
			hero = "barbarian"
		GameManager.choose_class(hero)

	_build_floor()
	_spawn_props()
	_build_coop_banner()

	# Co-op wiring. The relay connection (NetManager) persists across scenes, so we
	# may arrive here already in a lobby (e.g. returning from a co-op run); re-bind
	# our NetSync either way and react to the party joining / the host launching.
	if NetManager:
		NetManager.connected_to_room.connect(_on_net_connected)
		NetManager.player_joined.connect(_on_net_player_joined)
		NetManager.player_disconnected.connect(_on_net_player_disconnected)
		if NetManager.is_multiplayer:
			_ensure_net_sync()
	# Broadcast hero changes (wardrobe) so party puppets re-skin live.
	if GameManager and GameManager.has_signal("class_selected"):
		GameManager.class_selected.connect(_on_local_class_changed)
	_refresh_coop_banner()

	if AudioManager:
		var music: AudioStream = load("res://assets/audio/music/music_exploration_dungeon_explore.mp3") as AudioStream
		if music:
			AudioManager.play_music(music, -14.0)


func _build_floor() -> void:
	if not ResourceLoader.exists(FLOOR_TEX):
		return
	var tex: Texture2D = load(FLOOR_TEX) as Texture2D
	if tex == null:
		return
	var ts: Vector2 = tex.get_size()
	var cols: int = 16
	var rows: int = 11
	var origin := Vector2(-float(cols) * ts.x * 0.5, -float(rows) * ts.y * 0.5)
	var layer := Node2D.new()
	layer.name = "FloorLayer"
	layer.z_index = -10
	add_child(layer)
	for y in rows:
		for x in cols:
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.modulate = Color(0.62, 0.62, 0.72)  # cool, peaceful tone
			s.position = origin + Vector2(x * ts.x, y * ts.y)
			layer.add_child(s)


func _spawn_props() -> void:
	_props.append(
		_make_prop("Wardrobe  —  change hero", Vector2(-260, -40), Color(0.55, 0.7, 1.0), _open_wardrobe)
	)
	_props.append(
		_make_prop("Portal  —  begin the run", Vector2(260, -40), Color(1.0, 0.55, 0.35), _enter_portal)
	)
	_props.append(
		_make_prop("Beacon  —  co-op", Vector2(0, -220), Color(0.5, 0.85, 0.6), _open_coop_panel)
	)


func _make_prop(text: String, pos: Vector2, tint: Color, action: Callable) -> Dictionary:
	var root := Node2D.new()
	root.position = pos
	add_child(root)
	# Simple glowing marker (art polish later).
	var body := ColorRect.new()
	body.color = tint
	body.size = Vector2(64, 88)
	body.position = Vector2(-32, -88)
	root.add_child(body)
	var glow := ColorRect.new()
	glow.color = Color(tint.r, tint.g, tint.b, 0.25)
	glow.size = Vector2(96, 120)
	glow.position = Vector2(-48, -104)
	glow.z_index = -1
	root.add_child(glow)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-120, -128)
	label.custom_minimum_size = Vector2(240, 0)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	root.add_child(label)
	return {"node": root, "label": label, "pos": pos, "base_text": text, "action": action, "in_range": false}


func _process(_delta: float) -> void:
	if _overlay_open or _player == null or not is_instance_valid(_player):
		return
	for prop in _props:
		var in_range: bool = _player.global_position.distance_to(prop["pos"]) <= INTERACT_RANGE
		if in_range != prop["in_range"]:
			prop["in_range"] = in_range
			prop["label"].text = (prop["base_text"] + "   [E]") if in_range else prop["base_text"]
		if in_range and Input.is_action_just_pressed("interact"):
			(prop["action"] as Callable).call()
			return


func _open_wardrobe() -> void:
	if _overlay_open:
		return
	_overlay_open = true
	var ov := HERO_SELECT.new()
	ov.closed.connect(func(): _overlay_open = false)
	add_child(ov)


func _enter_portal() -> void:
	# Co-op clients can't open the run — the host leads the party onto the shared map.
	# RunFlow broadcasts run_start when the host picks difficulty, which pulls every
	# client onto the map automatically (no need to stand on the portal).
	if NetManager and NetManager.is_multiplayer and not NetManager.is_host:
		_show_toast("Хост ведёт отряд — дождитесь выбора пути.")
		return
	# Host + solo: open the run map (difficulty pick → StS map → nodes, now with co-op voting).
	if RunFlow:
		RunFlow.open_map()


# ─────────────────────────────────────────────────────────────────────────────
# Co-op
func _open_coop_panel() -> void:
	if _overlay_open:
		return
	_overlay_open = true
	var panel := COOP_PANEL.new()
	panel.closed.connect(func(): _overlay_open = false)
	panel.leave_requested.connect(_leave_coop)
	add_child(panel)


# Spin up the hub's NetSync so remote players appear and our position broadcasts.
# Idempotent — safe to call from _ready and from every connect/join signal.
func _ensure_net_sync() -> void:
	if NetManager == null or not NetManager.is_multiplayer:
		return
	if _net_sync != null and is_instance_valid(_net_sync):
		return
	_net_sync = Node.new()
	_net_sync.set_script(load(NET_SYNC_PATH))
	_net_sync.name = "NetSync"
	# Party puppets fan out around the hub origin (where the local player stands),
	# not the arena coordinates game_world uses.
	_net_sync.set("spawn_center", Vector2.ZERO)
	add_child(_net_sync)
	# Lazy spawn handles the roster — do NOT pre-spawn (an under-full lobby would
	# otherwise show ghost puppets for slots nobody joined).
	_net_sync.call_deferred("bind_world", self)


func _leave_coop() -> void:
	if _net_sync != null and is_instance_valid(_net_sync):
		_net_sync.call("clear_remote_players")
		_net_sync.queue_free()
	_net_sync = null
	if NetManager:
		NetManager.disconnect_from_room()
	_refresh_coop_banner()


# ─────────────────────────────────────────────────────────────────────────────
# Net signal handlers
func _on_net_connected() -> void:
	_ensure_net_sync()
	_refresh_coop_banner()


func _on_net_player_joined(_pid: int, _total: int) -> void:
	_ensure_net_sync()
	# Re-announce our hero so the newcomer renders us correctly (NetSync also does
	# this, but doing it here covers the host before its NetSync exists).
	if NetManager and GameManager and GameManager.player_class != "":
		NetManager.send("lobby_class", {"class_id": GameManager.player_class})
	_refresh_coop_banner()


func _on_net_player_disconnected(pid: int) -> void:
	if pid < 0:
		# Connection lost entirely — drop back to solo presence in the hub.
		if _net_sync != null and is_instance_valid(_net_sync):
			_net_sync.call("clear_remote_players")
			_net_sync.queue_free()
		_net_sync = null
	_refresh_coop_banner()


func _on_local_class_changed(_class_id: String) -> void:
	if NetManager and NetManager.is_multiplayer and GameManager:
		NetManager.send("lobby_class", {"class_id": GameManager.player_class})


# ─────────────────────────────────────────────────────────────────────────────
# "Лобби <CODE>" banner — top-centre, visible while in a lobby.
func _build_coop_banner() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_coop_banner = Label.new()
	_coop_banner.add_theme_font_size_override("font_size", 28)
	_coop_banner.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	_coop_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_coop_banner.add_theme_constant_override("outline_size", 6)
	_coop_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coop_banner.anchor_left = 0.5
	_coop_banner.anchor_right = 0.5
	_coop_banner.anchor_top = 0.0
	_coop_banner.offset_left = -360
	_coop_banner.offset_right = 360
	_coop_banner.offset_top = 24
	_coop_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coop_banner.visible = false
	layer.add_child(_coop_banner)


func _refresh_coop_banner() -> void:
	if _coop_banner == null:
		return
	if NetManager and NetManager.is_multiplayer and NetManager.room_code != "":
		var c: int = max(1, NetManager.connected_players)
		_coop_banner.text = "Лобби %s   (%d/%d)" % [NetManager.room_code, c, NetManager.max_players]
		_coop_banner.visible = true
	else:
		_coop_banner.visible = false


func _show_toast(text: String) -> void:
	var toast := Label.new()
	toast.text = text
	toast.add_theme_font_size_override("font_size", 22)
	toast.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	toast.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	toast.add_theme_constant_override("outline_size", 5)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_top = 0.5
	toast.offset_left = -320
	toast.offset_right = 320
	toast.offset_top = 120
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.layer = 45
	add_child(layer)
	layer.add_child(toast)
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(toast, "modulate:a", 0.0, 0.6)
	tw.tween_callback(layer.queue_free)
