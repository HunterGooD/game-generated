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
const HERO_SELECT := preload("res://scripts/ui/menus/hero_select.gd")
const COOP_PANEL := preload("res://scripts/ui/panels/hub_coop_panel.gd")
const META_TREE := preload("res://scripts/ui/panels/meta_tree_ui.gd")
const GAMBLE_SHOP := preload("res://scripts/ui/panels/gamble_shop.gd")
const MIRROR_SHADER := preload("res://assets/shaders/hub_mirror.gdshader")
const PORTAL_SHADER := preload("res://assets/shaders/hub_portal.gdshader")
const WARDROBE_SHADER := preload("res://assets/shaders/hub_wardrobe.gdshader")
const BEACON_SHADER := preload("res://assets/shaders/hub_beacon.gdshader")
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
		_make_prop(
			"Гардероб  —  сменить героя",
			Vector2(-260, -40),
			Color(0.55, 0.7, 1.0),
			_open_wardrobe,
			WARDROBE_SHADER,
			"spark"
		)
	)
	_props.append(
		_make_prop(
			"Портал  —  начать забег",
			Vector2(260, -30),
			Color(1.0, 0.55, 0.35),
			_enter_portal,
			PORTAL_SHADER,
			"fire",
			Vector2(96, 150)
		)
	)
	_props.append(
		_make_prop(
			"Маяк  —  кооператив",
			Vector2(0, -220),
			Color(0.5, 0.85, 0.6),
			_open_coop_panel,
			BEACON_SHADER,
			"green",
			Vector2(128, 88)
		)
	)
	_props.append(_make_mirror_prop("Зеркало  —  мета-дерево", Vector2(260, -220), _open_mirror))
	_props.append(
		_make_prop(
			"Гадалка  —  камни за осколки",
			Vector2(-260, -220),
			Color(0.85, 0.45, 0.78),
			_open_gamble,
			null,
			"spark",
			Vector2(64, 96)
		)
	)


func _make_prop(
	text: String,
	pos: Vector2,
	tint: Color,
	action: Callable,
	shader: Shader = null,
	particle_kind: String = "",
	body_size: Vector2 = Vector2(64, 88)
) -> Dictionary:
	var root := Node2D.new()
	root.position = pos
	add_child(root)
	# Body: a flat marker by default, or a shader-driven surface (portal/wardrobe/beacon).
	# Stands on the ground line (bottom at y=0), centred horizontally.
	var body := ColorRect.new()
	body.color = tint
	body.size = body_size
	body.position = Vector2(-body_size.x * 0.5, -body_size.y)
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("tint", tint)
		body.material = mat
	BlobShadow.attach(root, body_size.x * 1.05, body_size.x * 0.34)
	root.add_child(body)
	# Optional ambient particles (fire embers / green sparks / sparkles) rising off the prop.
	if particle_kind != "":
		root.add_child(_make_particles(particle_kind, tint, body_size))
	# Atmospheric glow keyed to the particle kind (additive — no scene darkening).
	_attach_prop_light(root, particle_kind, tint, body_size)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-120, -body_size.y - 40.0)
	label.custom_minimum_size = Vector2(240, 0)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	root.add_child(label)
	return {"node": root, "label": label, "pos": pos, "base_text": text, "action": action, "in_range": false}


# Warm/cool atmospheric glow for a prop, keyed to its particle kind. Sits at the
# body's mid-height; additive so it only brightens (no global darkening pass).
func _attach_prop_light(root: Node2D, kind: String, tint: Color, body_size: Vector2) -> void:
	var y: float = -body_size.y * 0.5
	match kind:
		"fire":
			SoftLight.attach(root, Color(1.0, 0.6, 0.25), 170.0, 0.9, y)
		"green":
			SoftLight.attach(root, Color(0.5, 0.95, 0.6), 150.0, 0.7, y)
		"spark":
			SoftLight.attach(root, tint.lerp(Color(1, 1, 1), 0.3), 130.0, 0.6, y)


# Ambient particle emitter for a prop. "fire" = rising orange embers (portal), "green" =
# small rising green sparks (beacon), anything else = drifting sparkles (wardrobe). Emission
# is scaled to the body (which spans y ∈ [-body_size.y, 0], centred on x).
func _make_particles(kind: String, _tint: Color, body_size: Vector2 = Vector2(64, 88)) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = true
	p.lifetime_randomness = 0.4
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var base_y: float = -body_size.y * 0.14  # just above the prop's base
	var half_w: float = body_size.x * 0.42
	match kind:
		"fire":
			p.position = Vector2(0, base_y)
			p.amount = 26
			p.lifetime = 1.1
			p.emission_rect_extents = Vector2(half_w, 6)
			p.direction = Vector2(0, -1)
			p.spread = 22.0
			p.gravity = Vector2(0, -30)
			p.initial_velocity_min = 18.0
			p.initial_velocity_max = 42.0
			p.scale_amount_min = 2.0
			p.scale_amount_max = 4.0
			p.color = Color(1.0, 0.6, 0.2)
			p.color_ramp = _fade_ramp(Color(1.0, 0.85, 0.4), Color(0.95, 0.25, 0.12))
		"green":
			p.position = Vector2(0, base_y)
			p.amount = 26
			p.lifetime = 1.4
			p.emission_rect_extents = Vector2(half_w, 6)
			p.direction = Vector2(0, -1)
			p.spread = 16.0
			p.gravity = Vector2(0, -22)
			p.initial_velocity_min = 14.0
			p.initial_velocity_max = 34.0
			p.scale_amount_min = 1.5
			p.scale_amount_max = 3.0
			p.color = Color(0.5, 0.95, 0.55)
			p.color_ramp = _fade_ramp(Color(0.7, 1.0, 0.7), Color(0.3, 0.8, 0.4))
		_:  # "spark" — drifting twinkles across the body.
			p.position = Vector2(0, -body_size.y * 0.5)
			p.amount = 18
			p.lifetime = 1.6
			p.emission_rect_extents = Vector2(body_size.x * 0.45, body_size.y * 0.45)
			p.direction = Vector2(0, -1)
			p.spread = 180.0
			p.gravity = Vector2(0, -6)
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 14.0
			p.scale_amount_min = 1.0
			p.scale_amount_max = 2.5
			p.color = Color(0.75, 0.85, 1.0)
			p.color_ramp = _fade_ramp(Color(0.85, 0.92, 1.0), Color(0.55, 0.7, 1.0))
	return p


# Two-stop gradient that fades the particle out (start opaque → end transparent).
func _fade_ramp(c_start: Color, c_end: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c_start.r, c_start.g, c_start.b, 1.0))
	g.set_color(1, Color(c_end.r, c_end.g, c_end.b, 0.0))
	return g


# The Mirror prop is a tall pane of enchanted glass driven by hub_mirror.gdshader (a
# violet, rippling, sheening surface) inside a dark gilt frame — so the meta-tree portal
# reads differently from the flat marker props. Same return shape / interaction contract.
func _make_mirror_prop(text: String, pos: Vector2, action: Callable) -> Dictionary:
	var root := Node2D.new()
	root.position = pos
	add_child(root)
	BlobShadow.attach(root, 92.0, 30.0)
	SoftLight.attach(root, Color(0.7, 0.85, 1.0), 150.0, 0.6, -70.0)
	# Gilt frame behind the glass.
	var frame := ColorRect.new()
	frame.color = Color(0.18, 0.14, 0.10)
	frame.size = Vector2(80, 132)
	frame.position = Vector2(-40, -132)
	root.add_child(frame)
	# Shader-driven mirror surface.
	var glass := ColorRect.new()
	glass.size = Vector2(68, 120)
	glass.position = Vector2(-34, -126)
	var mat := ShaderMaterial.new()
	mat.shader = MIRROR_SHADER
	glass.material = mat
	root.add_child(glass)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-120, -168)
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


func _open_mirror() -> void:
	if _overlay_open:
		return
	_overlay_open = true
	# Freeze the local player while the tree is open — clicking nodes uses the same mouse
	# button as the basic attack, so without this you'd swing/move behind the overlay.
	_set_player_locked(true)
	var ov := META_TREE.new()
	ov.closed.connect(
		func():
			_overlay_open = false
			_set_player_locked(false)
	)
	add_child(ov)


# The Fortune Teller — gamble mirror shards for random meta gems. Locks the player like
# the mirror does (the shop is click-driven and shares the attack mouse button).
func _open_gamble() -> void:
	if _overlay_open:
		return
	_overlay_open = true
	_set_player_locked(true)
	var ov := GAMBLE_SHOP.new()
	ov.closed.connect(
		func():
			_overlay_open = false
			_set_player_locked(false)
	)
	add_child(ov)


func _set_player_locked(locked: bool) -> void:
	if _player != null and is_instance_valid(_player):
		_player.set("control_locked", locked)


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
