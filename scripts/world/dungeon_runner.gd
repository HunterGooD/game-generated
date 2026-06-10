class_name DungeonRunner
extends Node2D

## Builds a real, explorable dungeon from the Rust generator's room graph and drives its
## encounters. Lives as a "DungeonRunner" child of game_world (which reuses all the run
## lifecycle — level-ups, spec paths, game-over, NetSync); game_world calls build() and
## skips its default arena floor when we're present.
##
## v1 layout: open floor (no wall collision) — rooms are floor patches at their graph
## `cell`, joined by corridor strips, forming the "кишка". Combat rooms (pylon/elite/
## pocket) spawn a pack when the player gets near; the boss room spawns a boss; on its
## defeat a loot chest + exit portal (and, if the layer offers it, a Descent portal one
## layer deeper) appear. Wall collision / tighter corridors are a follow-up.

const FLOOR_TEX := "res://assets/textures/floors/ruins_floor.webp"
const WALL_TEX := "res://assets/textures/walls/ruins_wall.webp"
const PORTAL_SCENE := preload("res://scenes/pickups/wave_portal.tscn")
const MERCHANT_SCENE := preload("res://scenes/pickups/merchant.tscn")
const CHEST_PATH := "res://scenes/pickups/loot_chest.tscn"
const PYLON_TEX := "res://assets/sprites/items/column_standing.png"
const ELITE_TEX := "res://assets/sprites/items/crystal_purple.png"
const BOSS_TEX := "res://assets/sprites/items/statue_guardian.png"
const EVENT_PILLAR := preload("res://scripts/world/dungeon_event_pillar.gd")
const LAVA_PATCH := preload("res://scripts/world/dungeon_lava_patch.gd")
const DUNGEON_MAP := preload("res://scripts/ui/dungeon_map_ui.gd")

const CELL_PX := 700.0      # world distance between adjacent graph cells
const TILE := 96
const ROOM_HALF := 3        # normal room floor patch = (2·HALF+1)² tiles (7×7)
const BOSS_HALF := 6        # boss room is much larger (13×13) — the finale chamber
const ACTIVATE_RADIUS := 360.0  # player proximity that wakes the boss
const ENTRY_SAFE := 560.0       # no enemies spawn this close to the entry (room to settle)
const CORRIDOR_SPACING := 300.0 # px between corridor wanderers
const MAX_DUNGEON_ENEMIES := 64 # global cap so big/deep dungeons don't over-populate

const NEIGHBORS8 := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


var _layer = null  # DungeonLayerRef
var _spawner: Node = null
var _floor_layer: Node2D = null
var _wall_layer: Node2D = null
var _decor_layer: Node2D = null
var _player: Node2D = null
var _camera: Node = null

var _room_world: Dictionary = {}  # room id -> Vector2 world centre
var _floor_tiles: Dictionary = {}  # Vector2i tile -> true (the walkable set)
var _boss_tiles: Dictionary = {}   # Vector2i tile -> true (for distinct boss-floor tint)
var _biome: String = "ruins"
var _spawn_budget: int = 0  # remaining enemies we may spawn (capped at build time)
var _boss_room_id: int = -1
var _boss_spawned: bool = false
var _boss_done: bool = false
var _portals_spawned: bool = false


func build() -> void:
	add_to_group("dungeon_runner")
	var gw := get_parent()
	if gw:
		# Resolve by node name (robust — doesn't depend on game_world's @export node_paths,
		# which don't include player/camera and so come back null via get()).
		_floor_layer = gw.get_node_or_null("FloorLayer")
		_wall_layer = gw.get_node_or_null("WallLayer")
		_decor_layer = gw.get_node_or_null("DecorLayer")
		_player = gw.get_node_or_null("Player")
		_camera = gw.get_node_or_null("Player/Camera2D")
		_spawner = gw.get_node_or_null("EnemySpawner")

	var node: Dictionary = GameManager.run_node_active if GameManager else {}
	var seed_value: int = DungeonAffixes.node_seed(int(GameManager.run_seed), int(node.get("id", 0)))
	_layer = DungeonAffixes.generate_node_layer(seed_value, GameManager.run_difficulty, GameManager.dungeon_depth)

	if _layer == null:
		_build_fallback()
		return

	_biome = String(_layer.call("biome"))
	_apply_biome_light()
	_compute_room_positions()
	_mark_walkable()       # rooms + corridors → the floor tile set
	_render_floor()
	_render_walls()        # collision walls hugging the walkable boundary
	_populate_rooms()
	_populate_enemies()    # enemies everywhere — rooms AND corridors (Diablo-style)
	_spawn_biome_hazards()
	_place_player_at_entry()
	_fit_camera()
	_spawn_map_ui()
	_announce()
	set_process(true)


func _spawn_map_ui() -> void:
	var map := DUNGEON_MAP.new()
	map.setup(_layer, _room_world, _player, CELL_PX)
	add_child(map)


func _apply_biome_light() -> void:
	var gw := get_parent()
	var light := gw.get_node_or_null("WorldLight") if gw else null
	if light and light is CanvasModulate:
		(light as CanvasModulate).color = DungeonBiome.light_color(_biome)


# ── layout ───────────────────────────────────────────────────────────────────
func _compute_room_positions() -> void:
	for r in _layer.call("rooms"):
		var cell: Vector2i = r["cell"]
		_room_world[int(r["id"])] = Vector2(float(cell.x), float(cell.y)) * CELL_PX


# Build the walkable tile set: a square patch per room (boss room much larger) plus a
# 3-wide corridor band along every edge. Walls are then derived from this set's boundary.
func _mark_walkable() -> void:
	var boss_id: int = int(_layer.call("boss_id"))
	for r in _layer.call("rooms"):
		var id: int = int(r["id"])
		var half: int = BOSS_HALF if id == boss_id else ROOM_HALF
		_mark_room(_room_world.get(id, Vector2.ZERO), half, id == boss_id)
	for e in _layer.call("edges"):
		_mark_corridor(_room_world.get(int(e["a"]), Vector2.ZERO), _room_world.get(int(e["b"]), Vector2.ZERO))


func _world_to_tile(w: Vector2) -> Vector2i:
	return Vector2i(roundi(w.x / float(TILE)), roundi(w.y / float(TILE)))


func _mark_room(center: Vector2, half: int, is_boss: bool) -> void:
	var ct: Vector2i = _world_to_tile(center)
	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var t := Vector2i(ct.x + dx, ct.y + dy)
			_floor_tiles[t] = true
			if is_boss:
				_boss_tiles[t] = true


func _mark_corridor(a: Vector2, b: Vector2) -> void:
	var ta: Vector2i = _world_to_tile(a)
	var tb: Vector2i = _world_to_tile(b)
	var steps: int = maxi(absi(tb.x - ta.x), absi(tb.y - ta.y))
	if steps <= 0:
		return
	for i in range(steps + 1):
		var f: float = float(i) / float(steps)
		var cx: int = roundi(lerpf(float(ta.x), float(tb.x), f))
		var cy: int = roundi(lerpf(float(ta.y), float(tb.y), f))
		# 3×3 band → a solid, comfortably walkable corridor.
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				_floor_tiles[Vector2i(cx + dx, cy + dy)] = true


func _render_floor() -> void:
	if _floor_layer == null:
		return
	var tex: Texture2D = load(FLOOR_TEX) as Texture2D if ResourceLoader.exists(FLOOR_TEX) else null
	if tex == null:
		return
	var ts: Vector2 = tex.get_size()
	var sc := Vector2.ONE
	if ts.x > 0 and ts.y > 0:
		sc = Vector2(float(TILE) / ts.x, float(TILE) / ts.y)
	var floor_tint: Color = DungeonBiome.floor_tint(_biome)
	for t in _floor_tiles:
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.position = Vector2(t) * float(TILE)
		s.scale = sc
		# Boss chamber floor reads warmer/ominous; the rest takes the biome tint.
		s.modulate = Color(0.82, 0.45, 0.42) if _boss_tiles.has(t) else floor_tint
		_floor_layer.add_child(s)


# Walls = every non-floor tile adjacent (8-way) to a floor tile. Mirrors the collision
# setup of game_world._place_wall (StaticBody2D on layer 1, TILE×TILE box + wall sprite).
func _render_walls() -> void:
	if _wall_layer == null:
		return
	var tex: Texture2D = load(WALL_TEX) as Texture2D if ResourceLoader.exists(WALL_TEX) else null
	var wall_tiles: Dictionary = {}
	for t in _floor_tiles:
		for n in NEIGHBORS8:
			var w: Vector2i = t + n
			if not _floor_tiles.has(w):
				wall_tiles[w] = true
	var ts: Vector2 = tex.get_size() if tex else Vector2(TILE, TILE)
	var sc := Vector2.ONE
	if tex and ts.x > 0 and ts.y > 0:
		sc = Vector2(float(TILE) / ts.x, float(TILE) / ts.y)
	for w in wall_tiles:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = Vector2(w) * float(TILE)
		_wall_layer.add_child(body)
		if tex:
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.scale = sc
			s.modulate = DungeonBiome.wall_tint(_biome)
			body.add_child(s)
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(TILE, TILE)
		col.shape = shape
		col.position = Vector2(TILE, TILE) * 0.5
		body.add_child(col)


# ── room contents ──────────────────────────────────────────────────────────────
func _populate_rooms() -> void:
	for r in _layer.call("rooms"):
		var id: int = int(r["id"])
		var kind: String = String(r["kind"])
		var center: Vector2 = _room_world.get(id, Vector2.ZERO)
		match kind:
			"boss":
				_boss_room_id = id
				_marker(BOSS_TEX, center, Color(1.0, 0.5, 0.45), 1.6)  # the finale chamber
			"pylon", "pocket":
				_marker(PYLON_TEX, center, Color(0.7, 0.8, 1.0), 0.6)
			"elite_pylon":
				_marker(ELITE_TEX, center, Color(1.0, 0.5, 0.9), 0.7)
			"event_pillar":
				_spawn_event_pillar(center)
			"vault":
				_spawn_chest(center)  # the only world chest now (plus the boss chest) — kept rare
			"dead_end":
				pass  # quiet dead-end (no chest) — chests were too plentiful
			"merchant":
				# The surrounding ambient enemies act as the guard now.
				_spawn_merchant(center)
				_marker(PYLON_TEX, center, Color(0.92, 0.78, 0.3), 0.7)
			_:
				pass


func _marker(tex_path: String, pos: Vector2, tint: Color, scale: float) -> void:
	if _decor_layer == null or not ResourceLoader.exists(tex_path):
		return
	var s := Sprite2D.new()
	s.texture = load(tex_path) as Texture2D
	s.position = pos
	s.scale = Vector2(scale, scale)
	s.modulate = tint
	_decor_layer.add_child(s)


func _spawn_chest(center: Vector2) -> void:
	if not ResourceLoader.exists(CHEST_PATH):
		return
	var scene: PackedScene = load(CHEST_PATH) as PackedScene
	if scene == null:
		return
	var chest: Node2D = scene.instantiate()
	add_child(chest)
	chest.global_position = center
	if chest.has_method("configure"):
		chest.call("configure", _loot_wave())


func _spawn_merchant(center: Vector2) -> void:
	var m: Node2D = MERCHANT_SCENE.instantiate()
	add_child(m)
	m.global_position = center


func _spawn_event_pillar(center: Vector2) -> void:
	var p := EVENT_PILLAR.new()
	p.spawner = _spawner
	add_child(p)
	p.global_position = center


# Biome floor hazards. Currently: infernal → lava pools scattered in non-entry rooms.
func _spawn_biome_hazards() -> void:
	if DungeonBiome.hazard(_biome) != "lava":
		return
	var entry_id: int = int(_layer.call("entry_id"))
	var diff: int = GameManager.run_difficulty if GameManager else 0
	for r in _layer.call("rooms"):
		var id: int = int(r["id"])
		var kind: String = String(r["kind"])
		# Skip entry/boss/exit/descent so spawns and the finale stay clean.
		if id == entry_id or kind in ["boss", "exit", "descent", "entry", "merchant"]:
			continue
		# A pool in roughly half the eligible rooms, offset from the centre.
		if randf() < 0.5:
			var lava := LAVA_PATCH.new()
			lava.difficulty = diff
			add_child(lava)
			var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(60.0, 150.0)
			lava.global_position = _room_world.get(id, Vector2.ZERO) + off


# ── encounters ───────────────────────────────────────────────────────────────
# Only the boss is proximity-gated now (its arrival is the finale beat). Everything else is
# populated across the whole dungeon at build time — see _populate_enemies.
func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if GameManager and GameManager.game_over:
		return
	if (
		not _boss_spawned
		and _boss_room_id >= 0
		and _player.global_position.distance_to(_room_world.get(_boss_room_id, Vector2.ZERO)) <= ACTIVATE_RADIUS
	):
		_spawn_boss()


# Diablo-style population: enemies stand throughout the whole dungeon (rooms AND corridors)
# from the start, idle until the player draws near, so you fight your way through to explore.
# Host/solo-gated, with an entry safe-zone and a global cap. Built once at load.
func _populate_enemies() -> void:
	var host_auth: bool = NetManager == null or not NetManager.is_multiplayer or NetManager.is_host
	if not host_auth or _spawner == null or not _spawner.has_method("spawn_room_pack"):
		return
	var entry_c: Vector2 = _room_world.get(int(_layer.call("entry_id")), Vector2.ZERO)
	var depth: int = GameManager.dungeon_depth if GameManager else 0
	var diff: int = GameManager.run_difficulty if GameManager else 0
	var types: Array = DungeonEnemies.types_for(_biome, depth)
	_spawn_budget = MAX_DUNGEON_ENEMIES

	# Per-room clusters (content rooms get real packs; the rest a light wandering group).
	for r in _layer.call("rooms"):
		if _spawn_budget <= 0:
			break
		var kind: String = String(r["kind"])
		if kind in ["entry", "boss", "exit", "descent", "vault", "dead_end"]:
			continue
		var c: Vector2 = _room_world.get(int(r["id"]), Vector2.ZERO)
		if c.distance_to(entry_c) < ENTRY_SAFE:
			continue
		match kind:
			"elite_pylon":
				if randf() < DungeonEnemies.MINIBOSS_CHANCE and _spawner.has_method("spawn_miniboss"):
					_spawner.call("spawn_miniboss", DungeonEnemies.miniboss_type(_biome), c, 3)
					_spawn_budget -= 2
				else:
					_spawn_pack(types, c, 230.0, DungeonEnemies.count_for("elite_pylon", depth, diff), DungeonEnemies.elite_affixes(depth))
			"pylon", "pocket":
				_spawn_pack(types, c, 230.0, DungeonEnemies.count_for(kind, depth, diff), 0)
			_:
				_spawn_pack(types, c, 170.0, 2 + depth / 2, 0)  # junction/pillar/merchant guards

	# Corridor wanderers — so you fight through the halls, not just the rooms.
	for e in _layer.call("edges"):
		if _spawn_budget <= 0:
			break
		_scatter_corridor(_room_world.get(int(e["a"]), Vector2.ZERO), _room_world.get(int(e["b"]), Vector2.ZERO), types, entry_c)


func _spawn_pack(types: Array, center: Vector2, radius: float, count: int, affix_n: int) -> void:
	count = mini(count, _spawn_budget)
	if count <= 0:
		return
	_spawner.call("spawn_room_pack", types, center, radius, count, affix_n)
	_spawn_budget -= count


func _scatter_corridor(a: Vector2, b: Vector2, types: Array, entry_c: Vector2) -> void:
	var dist: float = a.distance_to(b)
	var steps: int = int(dist / CORRIDOR_SPACING)
	if steps <= 0:
		return
	var dir: Vector2 = (b - a) / float(steps)
	for i in range(1, steps):  # skip the room endpoints
		if _spawn_budget <= 0:
			return
		var p: Vector2 = a + dir * float(i)
		if p.distance_to(entry_c) < ENTRY_SAFE:
			continue
		if randf() < 0.6:
			_spawn_pack(types, p, 60.0, 1 + (1 if randf() < 0.4 else 0), 0)


func _spawn_boss() -> void:
	_boss_spawned = true
	var host_auth: bool = NetManager == null or not NetManager.is_multiplayer or NetManager.is_host
	if _spawner and _spawner.has_method("_spawn_boss") and host_auth:
		# Thematic boss per biome.
		var boss_id: String = DungeonEnemies.boss_for(_biome)
		if BossDatabase.get_boss(boss_id).is_empty():
			boss_id = "crimson_matron"
		var eff: int = 6 + (GameManager.run_difficulty if GameManager else 0) * 2 + (GameManager.dungeon_depth if GameManager else 0) * 2
		# _spawn_boss places the boss at the centre of the spawner's room_min/room_max —
		# point that at the boss chamber so it spawns IN the boss room (not the arena centre).
		var bc: Vector2 = _room_world.get(_boss_room_id, Vector2.ZERO)
		_spawner.set("room_min", bc)
		_spawner.set("room_max", bc)
		_spawner.call("_spawn_boss", boss_id, eff)
		# Watch for the boss going down to drop rewards + portals.
		for b in get_tree().get_nodes_in_group("boss"):
			if is_instance_valid(b) and b.has_signal("boss_defeated") and not b.is_connected("boss_defeated", _on_boss_defeated):
				b.connect("boss_defeated", _on_boss_defeated)
	if GameManager:
		GameManager.notice.emit("The dungeon's guardian awakens!", Color(1.0, 0.4, 0.35))


func _on_boss_defeated(_boss_id: String, _reward: String) -> void:
	if _boss_done:
		return
	_boss_done = true
	var center: Vector2 = _room_world.get(_boss_room_id, Vector2.ZERO)
	_spawn_chest(center + Vector2(0, 80))
	_spawn_portals(center)


# ── portals: exit (to map) + optional descent (one layer deeper) ────────────────
func _spawn_portals(boss_center: Vector2) -> void:
	if _portals_spawned:
		return
	_portals_spawned = true
	var exit_portal: Node2D = PORTAL_SCENE.instantiate()
	add_child(exit_portal)
	exit_portal.global_position = boss_center + Vector2(-160, -200)
	if exit_portal.has_signal("activated"):
		exit_portal.connect("activated", _on_exit)

	var msg := "Boss slain! Take the portal to the map."
	if bool(_layer.call("has_descent")) and (GameManager.dungeon_depth if GameManager else 0) < 4:
		var descent: Node2D = PORTAL_SCENE.instantiate()
		add_child(descent)
		descent.global_position = boss_center + Vector2(160, -200)
		descent.modulate = Color(1.0, 0.55, 0.5)
		if descent.has_signal("activated"):
			descent.connect("activated", _on_descend)
		var next_level: int = (GameManager.dungeon_depth if GameManager else 0) + 2
		msg = "Boss slain!  Left portal → map.  Right portal → Level %d (×1.5 loot, harder)." % next_level
	if GameManager:
		GameManager.notice.emit(msg, Color(1.0, 0.86, 0.5))


func _on_exit() -> void:
	if GameManager:
		GameManager.clear_run_node()  # → RunFlow back to the map (resets dungeon_depth)


func _on_descend() -> void:
	if GameManager:
		GameManager.dungeon_depth += 1
		# Deeper loot luck stacks a little each layer (the ×1.5-loot feel).
		GameManager.dungeon_loot_luck += 0.15
		GameManager.notice.emit("Descending to Level %d…" % (GameManager.dungeon_depth + 1), Color(1.0, 0.6, 0.5))
	get_tree().reload_current_scene()  # rebuild the dungeon one layer deeper


# ── misc ─────────────────────────────────────────────────────────────────────
func _place_player_at_entry() -> void:
	if _player == null:
		return
	var entry_id: int = int(_layer.call("entry_id"))
	_player.global_position = _room_world.get(entry_id, Vector2.ZERO)


func _fit_camera() -> void:
	if _camera == null or _room_world.is_empty():
		return
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in _room_world.values():
		mn = mn.min(p)
		mx = mx.max(p)
	var pad: float = CELL_PX
	_camera.set("limit_left", int(mn.x - pad))
	_camera.set("limit_top", int(mn.y - pad))
	_camera.set("limit_right", int(mx.x + pad))
	_camera.set("limit_bottom", int(mx.y + pad))


func _loot_wave() -> int:
	return 6 + (GameManager.run_difficulty if GameManager else 0) * 2 + (GameManager.dungeon_depth if GameManager else 0) * 2


func _announce() -> void:
	if GameManager == null:
		return
	# Level = depth + 1 (Level 1 is the surface layer), shown to the player.
	var label: String = "%s — Level %d" % [DungeonBiome.display_name(_biome), GameManager.dungeon_depth + 1]
	GameManager.notice.emit(label, DungeonBiome.light_color(_biome).lightened(0.3))


# If the native generator isn't available, still give a completable room.
func _build_fallback() -> void:
	push_warning("DungeonRunner: generator unavailable — building a single fallback room.")
	_mark_room(Vector2.ZERO, 5, false)
	_render_floor()
	_render_walls()
	if _player:
		_player.global_position = Vector2.ZERO
	var portal: Node2D = PORTAL_SCENE.instantiate()
	add_child(portal)
	portal.global_position = Vector2(0, -260)
	if portal.has_signal("activated"):
		portal.connect("activated", _on_exit)
	if GameManager:
		GameManager.notice.emit("Dungeon (fallback room) — take the portal to the map.", Color(1.0, 0.86, 0.5))
