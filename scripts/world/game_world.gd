extends Node2D

# Game world — builds an ancient ruins dungeon room with floor, walls, decorations.
# Hosts the player and the camera. Phase 1: explorable room.

const TILE_SIZE: int = 96
const ROOM_COLS: int = 28
const ROOM_ROWS: int = 18

const FLOOR_TEX: String = "res://assets/textures/floors/ruins_floor.webp"
const WALL_TEX: String = "res://assets/textures/walls/ruins_wall.webp"

const DECOR_PATHS := {
	"column_standing": "res://assets/sprites/items/column_standing.png",
	"column_broken": "res://assets/sprites/items/column_broken.png",
	"torch": "res://assets/sprites/items/torch.png",
	"crystal_blue": "res://assets/sprites/items/crystal_blue.png",
	"crystal_purple": "res://assets/sprites/items/crystal_purple.png",
	"rune_circle": "res://assets/sprites/items/rune_circle.png",
	"statue_guardian": "res://assets/sprites/items/statue_guardian.png",
}

const ACTIVITY_DEFS := [
	{"name": "chest", "icon": "crystal_blue", "label": "Treasure"},
	{"name": "altar", "icon": "rune_circle", "label": "Altar"},
	{"name": "roulette", "icon": "crystal_purple", "label": "Wheel"},
	{"name": "ritual", "icon": "statue_guardian", "label": "Ritual"},
]

@export var floor_layer: Node2D
@export var wall_layer: Node2D
@export var decor_layer: Node2D
@export var player: CharacterBody2D
@export var camera: Camera2D
@export var hud: CanvasLayer

const CLASS_SELECTOR_SCENE: PackedScene = preload("res://scenes/ui/class_selector.tscn")
const LEVEL_UP_SCENE: PackedScene = preload("res://scenes/ui/level_up_choice.tscn")
const GAME_OVER_SCENE: PackedScene = preload("res://scenes/ui/game_over.tscn")
const NET_SYNC_SCRIPT: Script = preload("res://scripts/world/net_sync.gd")

var pending_level_ups: int = 0
var level_up_active: bool = false
var spec_path_pending: bool = false
var spec_path_active: bool = false
var game_over_shown: bool = false
var net_sync: Node = null


func _build_ambient_particles() -> void:
	# Drifting embers across the arena — always-on atmosphere. Parented to
	# the camera so they stay in-frame as the player moves.
	var cam: Camera2D = $Player/Camera2D
	if cam == null:
		return
	var emb := GPUParticles2D.new()
	emb.name = "Embers"
	emb.amount = 80
	emb.lifetime = 6.0
	emb.preprocess = 3.0
	emb.local_coords = false
	emb.z_index = 80
	emb.modulate = Color(1.0, 0.7, 0.45, 0.85)
	# Procedural particle process material.
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 25.0
	pm.gravity = Vector3(0, -10, 0)
	pm.initial_velocity_min = 8.0
	pm.initial_velocity_max = 30.0
	pm.scale_min = 0.1
	pm.scale_max = 0.4
	pm.angular_velocity_min = -20.0
	pm.angular_velocity_max = 20.0
	# Emit from a wide horizontal band below the camera so embers drift up
	# through the visible area.
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1000, 30, 1)
	# Fade color gradient toward transparent for the upper end of life.
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.55, 0.25, 0.9))
	grad.set_color(1, Color(1.0, 0.85, 0.5, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	emb.process_material = pm
	# Small spark texture — reuse the cast flash sprite.
	var tex_path := "res://assets/sprites/effects/cast_flash.png"
	if ResourceLoader.exists(tex_path):
		emb.texture = load(tex_path) as Texture2D
	emb.position = Vector2(0, 540)
	cam.add_child(emb)


func _ready() -> void:
	# Reset run state when entering the dungeon (uses default class if none). Skip the
	# reset when we arrived here as a run-map node — the run (HP/level/gold) must carry
	# across nodes; only standalone/endless Play starts fresh.
	if GameManager and GameManager.run_node_active.is_empty():
		GameManager.reset_run()

	_build_floor()
	_build_walls()
	_place_decorations()
#	_place_activities()

	_setup_camera_limits()

#	call_deferred("_build_ambient_particles")

	# Start ambient + music.
	if AudioManager:
		var ambient: AudioStream = (
			load("res://assets/audio/ambient/ambient_dungeon_dungeon_ambient.mp3") as AudioStream
		)
		if ambient:
			AudioManager.play_ambient(ambient, -16.0)
		var music: AudioStream = (
			load("res://assets/audio/music/music_exploration_dungeon_explore.mp3") as AudioStream
		)
		if music:
			AudioManager.play_music(music, -12.0)

	# Class is picked in the lobby now — only spawn the overlay if somebody
	# entered game_world without going through the lobby (e.g. dev shortcut).
	if GameManager and GameManager.player_class == "":
		call_deferred("_spawn_class_selector")

	# Listen for level-ups so we can queue choice overlays.
	if GameManager:
		GameManager.player_levelled_up.connect(_on_player_levelled_up)
		GameManager.spec_path_offered.connect(_on_spec_path_offered)
		GameManager.player_revived.connect(_on_player_revived_retry_spec)
		GameManager.player_died.connect(_on_player_died)

	# Multiplayer fork — spawn NetSync + N-1 remote players.
	if NetManager and NetManager.is_multiplayer:
		net_sync = Node.new()
		net_sync.set_script(NET_SYNC_SCRIPT)
		net_sync.name = "NetSync"
		add_child(net_sync)
		net_sync.call_deferred("bind_world", self)
		net_sync.call_deferred("spawn_remote_players")
		# Gate the spawner — only host generates enemy waves; clients spectate
		# enemies indirectly (host's enemies are simulated locally too in v1 —
		# acceptable desync for v1; full enemy sync is future work).


func on_remote_class_picked(_pid: int, _class_id: String) -> void:
	# Future hook for UI updates (e.g. show party portraits). No-op for now.
	pass


func _spawn_class_selector() -> void:
	var sel := CLASS_SELECTOR_SCENE.instantiate()
	add_child(sel)


func _on_player_levelled_up(_lv: int) -> void:
	pending_level_ups += 1
	call_deferred("_try_show_level_up")


func _try_show_level_up() -> void:
	if level_up_active or pending_level_ups <= 0:
		return
	level_up_active = true
	var ov := LEVEL_UP_SCENE.instantiate()
	ov.tree_exited.connect(_on_level_up_overlay_closed)
	add_child(ov)


func _on_level_up_overlay_closed() -> void:
	level_up_active = false
	pending_level_ups = max(0, pending_level_ups - 1)
	if pending_level_ups > 0:
		call_deferred("_try_show_level_up")
	else:
		# Level-ups cleared — a pending spec-path choice (level 5) can show now.
		call_deferred("_try_show_spec_path")


func _on_spec_path_offered() -> void:
	spec_path_pending = true
	call_deferred("_try_show_spec_path")


func _try_show_spec_path() -> void:
	# Mandatory choice: wait until level-up overlays clear AND the player isn't
	# downed/dead (offer re-opens on revive — see _ready's player_revived hook),
	# so a player who hit level 7 mid-chaos still gets to pick.
	if spec_path_active or not spec_path_pending or level_up_active or pending_level_ups > 0:
		return
	if GameManager and (GameManager.player_downed or GameManager.game_over):
		return
	spec_path_active = true
	spec_path_pending = false
	var ov := SpecPathChoice.new()
	ov.tree_exited.connect(_on_spec_path_closed)
	add_child(ov)


func _on_spec_path_closed() -> void:
	spec_path_active = false


func _on_player_revived_retry_spec() -> void:
	# A pending ascension choice deferred because the player was downed at level 7.
	if spec_path_pending:
		call_deferred("_try_show_spec_path")


func _on_player_died() -> void:
	if game_over_shown:
		return
	game_over_shown = true
	# Clear pending level ups so they don't pop after death.
	pending_level_ups = 0
	# Short delay so the death VFX is visible before the overlay.
	var t := get_tree().create_timer(1.0)
	t.timeout.connect(_spawn_game_over)


func _spawn_game_over() -> void:
	if not is_inside_tree():
		return
	var over := GAME_OVER_SCENE.instantiate()
	add_child(over)


const LAVA_SHADER: Shader = preload("res://assets/shaders/lava_pulse.gdshader")


func _build_floor() -> void:
	if not ResourceLoader.exists(FLOOR_TEX):
		return
	var tex: Texture2D = load(FLOOR_TEX) as Texture2D
	if tex == null:
		return
	# Single shared ShaderMaterial for every floor tile — uniforms animate in
	# lockstep across the whole arena.
	var shared_mat := ShaderMaterial.new()
	shared_mat.shader = LAVA_SHADER
	shared_mat.set_shader_parameter("warm_color", Color(1.0, 0.45, 0.22, 1.0))
	shared_mat.set_shader_parameter("cool_color", Color(0.55, 0.12, 0.16, 1.0))
	shared_mat.set_shader_parameter("pulse_speed", 0.45)
	shared_mat.set_shader_parameter("scroll_speed", 0.18)
	shared_mat.set_shader_parameter("intensity", 0.55)
	for y in ROOM_ROWS:
		for x in ROOM_COLS:
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.position = Vector2(x * TILE_SIZE, y * TILE_SIZE)
			# Scale to tile size.
			var tex_size: Vector2 = tex.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				s.scale = Vector2(TILE_SIZE / tex_size.x, TILE_SIZE / tex_size.y)
			s.modulate = Color(0.85, 0.78, 0.85, 1.0)
#			s.material = shared_mat
			floor_layer.add_child(s)


func _build_walls() -> void:
	if not ResourceLoader.exists(WALL_TEX):
		return
	var tex: Texture2D = load(WALL_TEX) as Texture2D
	if tex == null:
		return
	# Border walls — visual + collision.
	for x in ROOM_COLS:
		_place_wall(x, -1, tex)
		_place_wall(x, ROOM_ROWS, tex)
	for y in range(-1, ROOM_ROWS + 1):
		_place_wall(-1, y, tex)
		_place_wall(ROOM_COLS, y, tex)


func _place_wall(gx: int, gy: int, tex: Texture2D) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector2(gx * TILE_SIZE, gy * TILE_SIZE)
	wall_layer.add_child(body)

	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	var tex_size: Vector2 = tex.get_size()
	if tex_size.x > 0 and tex_size.y > 0:
		s.scale = Vector2(TILE_SIZE / tex_size.x, TILE_SIZE / tex_size.y)
	s.modulate = Color(0.55, 0.55, 0.78, 1.0)
	body.add_child(s)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE, TILE_SIZE)
	col.shape = shape
	col.position = Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	body.add_child(col)


func _place_decorations() -> void:
	# A curated set of decor positions to make the room feel alive.
	# Coordinates in grid tiles. Format: [name, gx, gy, scale_mult].
	var decor_plan: Array = [
		["column_standing", 3, 2, 1.2],
		["column_standing", ROOM_COLS - 4, 2, 1.2],
		["column_standing", 3, ROOM_ROWS - 3, 1.2],
		["column_standing", ROOM_COLS - 4, ROOM_ROWS - 3, 1.2],
		["column_broken", 8, 4, 1.0],
		["column_broken", ROOM_COLS - 9, ROOM_ROWS - 5, 1.0],
		# Doubled torch count — more warm light pools across the room.
		["torch", 2, 5, 0.6],
		["torch", ROOM_COLS - 3, 5, 0.6],
		["torch", 2, ROOM_ROWS - 6, 0.6],
		["torch", ROOM_COLS - 3, ROOM_ROWS - 6, 0.6],
		["torch", 12, 3, 0.55],
		["torch", ROOM_COLS - 13, 3, 0.55],
		["torch", 12, ROOM_ROWS - 4, 0.55],
		["torch", ROOM_COLS - 13, ROOM_ROWS - 4, 0.55],
		# Extra glow crystals scattered through the mid-room.
		["crystal_blue", 6, 9, 0.7],
		["crystal_purple", ROOM_COLS - 7, 8, 0.7],
		["crystal_blue", ROOM_COLS / 2 - 5, ROOM_ROWS - 4, 0.6],
		["crystal_purple", ROOM_COLS / 2 + 5, ROOM_ROWS - 4, 0.6],
		["rune_circle", ROOM_COLS / 2, ROOM_ROWS / 2 - 1, 1.4],
		["statue_guardian", ROOM_COLS / 2 - 3, 1, 1.0],
		["statue_guardian", ROOM_COLS / 2 + 3, 1, 1.0],
	]
	for entry in decor_plan:
		var key: String = entry[0]
		var gx: int = entry[1]
		var gy: int = entry[2]
		var scale_mult: float = entry[3]
		_place_decor(key, gx, gy, scale_mult)


func _place_decor(key: String, gx: int, gy: int, scale_mult: float) -> void:
	var path_v = DECOR_PATHS.get(key, "")
	var path: String = String(path_v)
	if path == "" or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	# Generated sprites at ~256px should fit within ~1.5 tiles.
	var target_size: float = float(TILE_SIZE) * 1.6 * scale_mult
	var max_dim: float = max(tex.get_size().x, tex.get_size().y)
	if max_dim > 0:
		var sc: float = target_size / max_dim
		s.scale = Vector2(sc, sc)
	s.position = Vector2(gx * TILE_SIZE + TILE_SIZE / 2.0, gy * TILE_SIZE + TILE_SIZE / 2.0)
	# Y-sort: depth by Y.
	s.z_index = int(-1)
	decor_layer.add_child(s)

	# Torches and crystals get a glow.
	if key == "torch":
		var light := PointLight2D.new()
		var grad := GradientTexture2D.new()
		grad.width = 256
		grad.height = 256
		grad.fill = GradientTexture2D.FILL_RADIAL
		grad.fill_from = Vector2(0.5, 0.5)
		grad.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1.0, 0.7, 0.3, 1.0), Color(1.0, 0.5, 0.1, 0.0)])
		grad.gradient = g
		light.texture = grad
		light.energy = 1.4
		light.color = Color(1.0, 0.7, 0.4, 1.0)
		light.texture_scale = 2.5
		s.add_child(light)
	elif key == "crystal_blue":
		var light := PointLight2D.new()
		var grad := GradientTexture2D.new()
		grad.width = 192
		grad.height = 192
		grad.fill = GradientTexture2D.FILL_RADIAL
		grad.fill_from = Vector2(0.5, 0.5)
		grad.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0.4, 0.7, 1.0, 1.0), Color(0.4, 0.7, 1.0, 0.0)])
		grad.gradient = g
		light.texture = grad
		light.energy = 1.0
		light.color = Color(0.4, 0.7, 1.0, 1.0)
		light.texture_scale = 2.0
		s.add_child(light)
	elif key == "crystal_purple":
		var light := PointLight2D.new()
		var grad := GradientTexture2D.new()
		grad.width = 192
		grad.height = 192
		grad.fill = GradientTexture2D.FILL_RADIAL
		grad.fill_from = Vector2(0.5, 0.5)
		grad.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0.85, 0.4, 1.0, 1.0), Color(0.85, 0.4, 1.0, 0.0)])
		grad.gradient = g
		light.texture = grad
		light.energy = 1.0
		light.color = Color(0.85, 0.4, 1.0, 1.0)
		light.texture_scale = 2.0
		s.add_child(light)
	elif key == "rune_circle":
		var tw := s.create_tween().set_loops()
		tw.tween_property(s, "modulate", Color(1.2, 1.05, 0.6, 1.0), 1.8).set_trans(
			Tween.TRANS_SINE
		)
		tw.tween_property(s, "modulate", Color(0.8, 0.75, 0.5, 1.0), 1.8).set_trans(
			Tween.TRANS_SINE
		)


func _place_activities() -> void:
	# Four activity beacons in the four "corners" of the room.
	var corners := [
		Vector2(4, 4),
		Vector2(ROOM_COLS - 5, 4),
		Vector2(4, ROOM_ROWS - 5),
		Vector2(ROOM_COLS - 5, ROOM_ROWS - 5),
	]
	for i in ACTIVITY_DEFS.size():
		var def: Dictionary = ACTIVITY_DEFS[i]
		var corner_v: Vector2 = corners[i]
		var beacon := preload("res://scenes/world/activity_beacon.tscn").instantiate()
		decor_layer.add_child(beacon)
		beacon.position = Vector2(
			corner_v.x * TILE_SIZE + TILE_SIZE / 2.0, corner_v.y * TILE_SIZE + TILE_SIZE / 2.0
		)
		if beacon.has_method("configure"):
			beacon.call(
				"configure",
				String(def.get("name", "")),
				String(def.get("icon", "")),
				String(def.get("label", ""))
			)


func _setup_camera_limits() -> void:
	if camera == null:
		return
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = ROOM_COLS * TILE_SIZE
	camera.limit_bottom = ROOM_ROWS * TILE_SIZE
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.zoom = Vector2(1.2, 1.2)
