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
	{"name": "chest", "icon": "crystal_blue", "label": "Сокровище"},
	{"name": "altar", "icon": "rune_circle", "label": "Алтарь"},
	{"name": "roulette", "icon": "crystal_purple", "label": "Колесо"},
	{"name": "ritual", "icon": "statue_guardian", "label": "Ритуал"},
]

@export var floor_layer: Node2D
@export var wall_layer: Node2D
@export var decor_layer: Node2D
@export var player: CharacterBody2D
@export var camera: Camera2D
@export var hud: CanvasLayer

const CLASS_SELECTOR_SCENE: PackedScene = preload("res://scenes/ui/class_selector.tscn")
const LEVEL_UP_SCENE: PackedScene = preload("res://scenes/ui/level_up_choice.tscn")
const SKILL_TREE_PANEL_SCRIPT: Script = preload("res://scripts/ui/skill_tree_panel.gd")
const GAME_OVER_SCENE: PackedScene = preload("res://scenes/ui/game_over.tscn")
const NET_SYNC_SCRIPT: Script = preload("res://scripts/world/net_sync.gd")
const WORLD_BACKDROP_SCRIPT: Script = preload("res://scripts/world/world_backdrop.gd")

var pending_level_ups: int = 0
var level_up_active: bool = false
# Level-up is opt-in now: a HUD button appears when you have pending choices, and you
# open the 3-card overlay when it's safe (it can be minimised + reopened). Much kinder
# in co-op where the world keeps running.
var _level_up_btn: Button = null
# Open unified skill-tree panel [T]; null when closed. Holds skills, stats AND
# the ascension pick (folded in — no separate overlay).
var _tree_panel: CanvasLayer = null
# The current level-up's rolled cards, kept so minimising + reopening shows the SAME offer
# (no free re-roll). Cleared only when a card is actually taken — the next level rolls fresh.
var _saved_offers: Array = []
var spec_path_pending: bool = false
var spec_path_active: bool = false
# Bottom-left "AWAKENING" button (mirrors the level-up button) — appears whenever an ascension
# is owed but not open, so the choice can never be lost behind a roulette or a scene change.
var _spec_btn: Button = null
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

	# Dark backdrop + dust behind the world so the engine clear-colour never shows past map
	# edges (arena borders, dungeon gaps). World-anchored — sized/themed once the map bounds
	# are final (after build), so it must come from the camera limits below.
	var backdrop: Node2D = WORLD_BACKDROP_SCRIPT.new()
	add_child(backdrop)

	# A graph-built dungeon node carries a DungeonRunner child that lays out the rooms
	# itself; skip the default arena floor/walls/decor and hand off to it.
	var dungeon_runner: Node = get_node_or_null("DungeonRunner")
	if dungeon_runner:
		_setup_camera_limits()  # runner overrides limits to the dungeon bounds
		dungeon_runner.call("build")
		var biome: String = (
			String(dungeon_runner.get("_biome"))
			if dungeon_runner.get("_biome") != null
			else "ruins"
		)
		backdrop.call("setup_from_camera", camera, biome)
	else:
		_build_floor()
		_build_walls()
		_place_decorations()
		#	_place_activities()
		_setup_camera_limits()
		backdrop.call("setup_from_camera", camera, "ruins")

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

	# Dungeon nodes carry affixes rolled by the Rust generator — spawn the controller
	# that reads them and activates their live hazards (gloom / orbs / wrath).
	if GameManager and String(GameManager.run_node_active.get("type", "")) == RunMap.TYPE_DUNGEON:
		add_child(DungeonAffixController.new())

	# Listen for level-ups so we can queue choice overlays.
	if GameManager:
		GameManager.player_levelled_up.connect(_on_player_levelled_up)
		# Talent-tree mode: the button mirrors unspent points (they survive scene
		# changes on the autoload, unlike the per-world pending_level_ups counter).
		GameManager.talents_changed.connect(_refresh_level_up_button)
		if GameManager.use_talent_tree:
			call_deferred("_refresh_level_up_button")
		GameManager.spec_path_offered.connect(_on_spec_path_offered)
		GameManager.spec_path_chosen.connect(_on_spec_path_chosen)
		GameManager.player_revived.connect(_on_player_revived_retry_spec)
		GameManager.player_died.connect(_on_player_died)
		# Re-arm a pending awakening that carried over from a previous node (e.g. levelled up
		# on the boss kill, then the scene changed before picking). GameManager holds the
		# persistent state; we just re-surface the HUD button.
		if GameManager.has_method("has_pending_spec_path") and GameManager.has_pending_spec_path():
			spec_path_pending = true
			call_deferred("_refresh_spec_button")

	# Multiplayer fork — spawn NetSync + N-1 remote players.
	if NetManager and NetManager.is_multiplayer:
		net_sync = Node.new()
		net_sync.set_script(NET_SYNC_SCRIPT)
		net_sync.name = "NetSync"
		add_child(net_sync)
		net_sync.call_deferred("bind_world", self)
		net_sync.call_deferred("spawn_remote_players")
		# Clients announce readiness AFTER NetSync is bound + listening, so the host
		# waits for everyone before populating a dungeon (no missed enemy_spawn burst).
		# Queued after bind_world above, so we're already receiving when the host fires.
		if not NetManager.is_host:
			NetManager.call_deferred("send", "node_ready", {})
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
	# Talent-tree mode: the point was already granted by GameManager.add_xp and
	# talents_changed refreshed the button. A level-up can also unlock a skill
	# block — refresh so the button flips to «НОВЫЙ НАВЫК».
	if GameManager and GameManager.use_talent_tree:
		_refresh_level_up_button()
		return
	pending_level_ups += 1
	# Don't slam a modal in the player's face mid-fight — surface a HUD button they
	# open when it's safe.
	_refresh_level_up_button()


# Build (once) a bottom-left "LEVEL UP" button that opens the choice overlay.
func _ensure_level_up_button() -> void:
	if _level_up_btn != null and is_instance_valid(_level_up_btn):
		return
	var layer := CanvasLayer.new()
	layer.layer = 25  # under the choice overlay (30), above the world
	add_child(layer)
	_level_up_btn = Button.new()
	_level_up_btn.focus_mode = Control.FOCUS_NONE
	_level_up_btn.custom_minimum_size = Vector2(220, 56)
	_level_up_btn.add_theme_font_size_override("font_size", 20)
	_level_up_btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_level_up_btn.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.0))
	_level_up_btn.add_theme_constant_override("outline_size", 4)
	# Bottom-left, above the hotbar / to the left of the skills.
	_level_up_btn.anchor_left = 0.0
	_level_up_btn.anchor_right = 0.0
	_level_up_btn.anchor_top = 1.0
	_level_up_btn.anchor_bottom = 1.0
	# Shifted right of the HP globe (bottom-left corner is the health flask now).
	_level_up_btn.offset_left = 178
	_level_up_btn.offset_right = 398
	_level_up_btn.offset_top = -190
	_level_up_btn.offset_bottom = -134
	_level_up_btn.visible = false
	_level_up_btn.pressed.connect(_open_level_up_choice)
	layer.add_child(_level_up_btn)
	# Single looping pulse bound to the button (dies with it) — draws the eye without
	# stacking a new tween on every refresh.
	var pulse := _level_up_btn.create_tween().set_loops()
	pulse.tween_property(_level_up_btn, "modulate", Color(1.25, 1.15, 0.7, 1.0), 0.6)
	pulse.tween_property(_level_up_btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.6)


# Show/hide + label the button based on how many choices are queued.
func _refresh_level_up_button() -> void:
	_ensure_level_up_button()
	if _level_up_btn == null:
		return
	var show: bool
	if GameManager and GameManager.use_talent_tree:
		# Surface unspent points; hide while the tree panel is open.
		var panel_closed: bool = _tree_panel == null or not is_instance_valid(_tree_panel)
		var pts: int = GameManager.talent_points
		show = panel_closed and pts > 0
		if show:
			_level_up_btn.text = "⬆ РАЗВИТИЕ ×%d" % pts if pts > 1 else "⬆ РАЗВИТИЕ"
	else:
		show = pending_level_ups > 0 and not level_up_active
		if show:
			_level_up_btn.text = (
				"⬆ LEVEL UP ×%d" % pending_level_ups if pending_level_ups > 1 else "⬆ LEVEL UP"
			)
	_level_up_btn.visible = show
	# Keep the awakening button in sync (it hides while a level-up overlay is open).
	_refresh_spec_button()


# Toggle the unified skill-tree panel (button, [T] or [B]). Browsable any time;
# only spending is gated. Holds skills, stats and the ascension pick.
func _toggle_tree_panel() -> void:
	if _tree_panel != null and is_instance_valid(_tree_panel):
		_tree_panel.queue_free()
		_tree_panel = null
		_refresh_level_up_button()
		return
	var panel: CanvasLayer = SKILL_TREE_PANEL_SCRIPT.new()
	panel.closed.connect(_on_tree_panel_closed)
	add_child(panel)
	_tree_panel = panel
	_refresh_level_up_button()


func _on_tree_panel_closed() -> void:
	_tree_panel = null
	_refresh_level_up_button()


func _unhandled_input(event: InputEvent) -> void:
	if (
		(event.is_action_pressed("open_talents") or event.is_action_pressed("open_skills"))
		and GameManager
		and GameManager.can_open_skill_tree()
	):
		_toggle_tree_panel()
		get_viewport().set_input_as_handled()


func _open_level_up_choice() -> void:
	if GameManager and GameManager.use_talent_tree:
		_toggle_tree_panel()
		return
	if level_up_active or pending_level_ups <= 0:
		return
	level_up_active = true
	_refresh_level_up_button()  # hide the button while the overlay is open
	var ov := LEVEL_UP_SCENE.instantiate()
	ov.preset_offers = _saved_offers  # empty → overlay rolls; non-empty → reuse the saved cards
	ov.choice_made.connect(_on_level_up_picked)
	ov.collapsed.connect(_on_level_up_collapsed)
	add_child(ov)
	# Capture whatever ended up on offer (fresh roll or the reused set) so it survives a
	# minimise/reopen cycle.
	_saved_offers = (ov.current_offers as Array).duplicate()


# A card was taken — spend one level-up, then re-show the button if more remain or
# fall through to a pending spec-path choice.
func _on_level_up_picked(_id: String) -> void:
	level_up_active = false
	pending_level_ups = max(0, pending_level_ups - 1)
	_saved_offers.clear()  # spent → the next level-up rolls a fresh set of cards
	_refresh_level_up_button()
	if pending_level_ups > 0:
		# Still owed choices → immediately chain into the next one (fresh roll) without making
		# the player reopen the HUD button. They can minimise to stop the chain whenever.
		call_deferred("_open_level_up_choice")
	else:
		# Level-ups done — surface the awakening button if one is owed (no forced modal).
		_refresh_spec_button()


# Minimised without picking — keep the level-up pending and re-show the button.
func _on_level_up_collapsed() -> void:
	level_up_active = false
	_refresh_level_up_button()


func _on_spec_path_offered() -> void:
	# Like a level-up: surface the HUD button rather than slamming a modal over the fight (or the
	# boss-reward roulette). The player opens the ascension when it's safe.
	spec_path_pending = true
	_refresh_spec_button()


# Ascension is its own level-7 choice (R ability + passive), NOT part of the
# skill tree. Open the dedicated overlay; the choice stays PENDING until a card
# is actually picked, so a minimise / scene change can never lose it.
func _try_show_spec_path() -> void:
	if spec_path_active or not spec_path_pending or level_up_active or pending_level_ups > 0:
		_refresh_spec_button()
		return
	if GameManager and (GameManager.player_downed or GameManager.game_over):
		_refresh_spec_button()
		return
	spec_path_active = true
	_refresh_spec_button()  # hide the button while the overlay is open
	var ov := SpecPathChoice.new()
	ov.collapsed.connect(_on_spec_path_collapsed)
	ov.tree_exited.connect(_on_spec_path_closed)
	add_child(ov)


func _on_spec_path_collapsed() -> void:
	spec_path_active = false
	_refresh_spec_button()


func _on_spec_path_closed() -> void:
	spec_path_active = false
	_refresh_spec_button()


# Build (once) the bottom-left "AWAKENING" button — sits just above the level-up button.
func _ensure_spec_button() -> void:
	if _spec_btn != null and is_instance_valid(_spec_btn):
		return
	var layer := CanvasLayer.new()
	layer.layer = 25
	add_child(layer)
	_spec_btn = Button.new()
	_spec_btn.focus_mode = Control.FOCUS_NONE
	_spec_btn.custom_minimum_size = Vector2(220, 56)
	_spec_btn.text = "✦ ПРОБУЖДЕНИЕ"
	_spec_btn.add_theme_font_size_override("font_size", 20)
	_spec_btn.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	_spec_btn.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.0))
	_spec_btn.add_theme_constant_override("outline_size", 4)
	_spec_btn.anchor_left = 0.0
	_spec_btn.anchor_right = 0.0
	_spec_btn.anchor_top = 1.0
	_spec_btn.anchor_bottom = 1.0
	# Stacked above the level-up button, clear of the HP globe.
	_spec_btn.offset_left = 178
	_spec_btn.offset_right = 398
	_spec_btn.offset_top = -258
	_spec_btn.offset_bottom = -202
	_spec_btn.visible = false
	_spec_btn.pressed.connect(_try_show_spec_path)
	layer.add_child(_spec_btn)
	var pulse := _spec_btn.create_tween().set_loops()
	pulse.tween_property(_spec_btn, "modulate", Color(1.3, 1.1, 0.6, 1.0), 0.6)
	pulse.tween_property(_spec_btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.6)


func _refresh_spec_button() -> void:
	_ensure_spec_button()
	if _spec_btn == null:
		return
	_spec_btn.visible = spec_path_pending and not spec_path_active and not level_up_active


# A path was actually chosen (GameManager.spec_path_chosen) — clear the pending awakening.
func _on_spec_path_chosen(_path_id: String) -> void:
	spec_path_pending = false
	spec_path_active = false
	_refresh_spec_button()


func _on_player_revived_retry_spec() -> void:
	# A pending ascension choice deferred because the player was downed at level 7 — just make
	# sure the button is showing again now that they're back up.
	if spec_path_pending:
		_refresh_spec_button()


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
