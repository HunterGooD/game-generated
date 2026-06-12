class_name DungeonAffixController
extends Node2D

## Orchestrates a dungeon node's affixes. On entering a dungeon it asks the Rust
## generator (echoes-dungeon) for this node's layer — deterministic by
## (run_seed ^ node id, difficulty) — reads the rolled affixes, announces the
## negatives, and spawns their live hazards (gloom / volatile spheres / wrath).
##
## Positives (gold_vein / echo_of_power / fortunes_favor) are data-only for now;
## their gameplay is a follow-up (see docs/dungeon_generator.md §4). The boss chest
## already reads `fortunes_favor` to add a 4th reel.
##
## Co-op: hazard spawning is host/solo-gated (mirrors enemy_spawner's host_auth). Full
## client hazard parity is future work, consistent with the v1 enemy-sync limitation.

const GLOOM := preload("res://scripts/world/dungeon_gloom.gd")
const ORB := preload("res://scripts/world/dungeon_volatile_orb.gd")
const WRATH := preload("res://scripts/world/dungeon_wrath.gd")
const SHRINE := preload("res://scripts/world/dungeon_shrine.gd")
const CHEST_SCENE_PATH := "res://scenes/pickups/loot_chest.tscn"

const ORB_INTERVAL: float = 5.5  # how often a volatile sphere appears
const GOLDEN_INTERVAL: float = 12.0  # how often a "golden" enemy is anointed
const ECHO_SHRINES: int = 3  # Echo of Power shrines per layer
const ECHO_DMG_PER_SHRINE: float = 0.12
const ECHO_SPD_PER_SHRINE: float = 0.08
const ECHO_BUFF_DURATION: float = 900.0  # "the whole layer"
const FORTUNE_LOOT_LUCK: float = 0.5

var active_negatives: Array = []  # affix id strings
var active_positives: Array = []
# Set once the layer is fully cleared (boss down): damaging curses stop hitting
# and stop spawning. Positives (gold vein, shrines, loot luck) keep working.
var _disarmed: bool = false
var _orb_timer: Timer = null
var _golden_timer: Timer = null
var _difficulty: int = 0
# Echo of Power running totals (stack as each shrine is claimed).
var _echo_dmg: float = 1.0
var _echo_spd: float = 1.0


func _ready() -> void:
	add_to_group("dungeon_affix_controller")
	if GameManager == null:
		return
	var node: Dictionary = GameManager.run_node_active
	if String(node.get("type", "")) != RunMap.TYPE_DUNGEON:
		return  # only dungeon nodes carry dungeon affixes
	_difficulty = GameManager.run_difficulty
	var layer = _generate_layer(node)  # DungeonLayerRef (native) or null
	if layer == null:
		return
	var affixes: Array = layer.call("affixes")
	active_negatives = DungeonAffixes.ids_from(affixes, "negative")
	active_positives = DungeonAffixes.ids_from(affixes, "positive")
	_announce()
	# Positives that are pure flags apply everywhere (loot luck is read by the host's
	# roller anyway, and is harmless on clients). World-spawning effects (shrines, golden
	# enemies, hazards) are host/solo-gated — co-op parity is future work.
	_apply_flag_positives()
	var host_auth: bool = NetManager == null or not NetManager.is_multiplayer or NetManager.is_host
	if host_auth:
		_activate_hazards()
		_activate_world_positives()


# Returns a DungeonLayerRef, or null if the native extension isn't loaded.
func _generate_layer(node: Dictionary):
	var seed_value: int = DungeonAffixes.node_seed(int(GameManager.run_seed), int(node.get("id", 0)))
	var layer = DungeonAffixes.generate_node_layer(seed_value, _difficulty, GameManager.dungeon_depth)
	if layer == null:
		push_warning("DungeonAffixController: DungeonGenerator extension not loaded — build `dungeon` crate (cargo build --features bridge).")
	return layer


func _announce() -> void:
	if GameManager == null:
		return
	if active_negatives.is_empty():
		return
	var names: Array = []
	for id in active_negatives:
		names.append(DungeonAffixes.display_name(id))
	GameManager.notice.emit("Аффиксы подземелья: %s" % ", ".join(names), Color(0.9, 0.55, 0.5))


func _activate_hazards() -> void:
	for id in active_negatives:
		match id:
			"suffocating_gloom":
				var g := GLOOM.new()
				g.difficulty = _difficulty
				_add_hazard(g)
				# Co-op: replicate the drifting cloud (host-gated damage); it spawns at a
				# random spot off the player, so broadcast the host's actual position and
				# both peers drift it toward the (synced) nearest player from there.
				if NetManager and NetManager.is_multiplayer and NetManager.is_host:
					var gns := _find_net_sync()
					if gns and gns.has_method("broadcast_fx"):
						gns.call(
							"broadcast_fx",
							"res://scripts/world/dungeon_gloom.gd",
							(g as Node2D).global_position,
							Vector2.ZERO
						)
			"heavens_wrath":
				var w := WRATH.new()
				w.difficulty = _difficulty
				_add_hazard(w)
			"volatile_spheres":
				_start_orb_emitter()


func _add_hazard(h: Node2D) -> void:
	var parent: Node = get_parent() if get_parent() else self
	parent.add_child(h)


func _start_orb_emitter() -> void:
	if _orb_timer and is_instance_valid(_orb_timer):
		return
	_orb_timer = Timer.new()
	_orb_timer.wait_time = ORB_INTERVAL
	_orb_timer.autostart = true
	add_child(_orb_timer)
	_orb_timer.timeout.connect(_spawn_orb)


func _find_net_sync() -> Node:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.get_node_or_null("NetSync")


# Full clear (boss defeated): kill every live damaging hazard and stop new ones
# from appearing. Called via the "dungeon_affix_controller" group from
# dungeon_runner on BOTH the host (boss_defeated) and clients (boss_reward msg),
# so replicated gloom clouds / orbs vanish for everyone.
func disarm_hazards() -> void:
	if _disarmed:
		return
	_disarmed = true
	if _orb_timer and is_instance_valid(_orb_timer):
		_orb_timer.stop()
	var tree := get_tree()
	if tree:
		for h in tree.get_nodes_in_group("dungeon_hazard"):
			if is_instance_valid(h):
				h.queue_free()
	var had_damaging: bool = false
	for id in active_negatives:
		if id in ["suffocating_gloom", "heavens_wrath", "volatile_spheres"]:
			had_damaging = true
	if GameManager and had_damaging:
		GameManager.notice.emit("Проклятия подземелья рассеиваются!", Color(0.6, 0.9, 0.6))


func _spawn_orb() -> void:
	if _disarmed:
		return
	if GameManager and GameManager.game_over:
		return
	var player := _nearest_player()
	if player == null:
		return
	var orb := ORB.new()
	orb.difficulty = _difficulty
	# Drop it a little off the player so they have room to react.
	var offset: Vector2 = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(120.0, 220.0)
	var parent: Node = get_parent() if get_parent() else self
	parent.add_child(orb)
	orb.global_position = player.global_position + offset
	# Co-op: replicate the orb so clients see the blast telegraph and can move clear
	# (host adjudicates the detonation → player_hit).
	if NetManager and NetManager.is_multiplayer and NetManager.is_host:
		var ns := _find_net_sync()
		if ns and ns.has_method("broadcast_fx"):
			ns.call(
				"broadcast_fx",
				"res://scripts/world/dungeon_volatile_orb.gd",
				orb.global_position,
				Vector2.ZERO
			)


# ── positive affixes ─────────────────────────────────────────────────────────
# Pure-flag positives apply regardless of host/client.
func _apply_flag_positives() -> void:
	if "fortunes_favor" in active_positives and GameManager:
		GameManager.dungeon_loot_luck += FORTUNE_LOOT_LUCK
		GameManager.dungeon_extra_reel = true


func _activate_world_positives() -> void:
	for id in active_positives:
		match id:
			"gold_vein":
				_start_gold_vein()
			"echo_of_power":
				_spawn_echo_shrines()


# Gold Vein: every kill pays bonus gold, and a periodically-anointed "golden" enemy
# drops a cache when slain.
func _start_gold_vein() -> void:
	if GameEvents and not GameEvents.enemy_died.is_connected(_on_enemy_died_gold):
		GameEvents.enemy_died.connect(_on_enemy_died_gold)
	if _golden_timer and is_instance_valid(_golden_timer):
		return
	_golden_timer = Timer.new()
	_golden_timer.wait_time = GOLDEN_INTERVAL
	_golden_timer.autostart = true
	add_child(_golden_timer)
	_golden_timer.timeout.connect(_anoint_golden)


func _on_enemy_died_gold(ev) -> void:
	if GameManager == null or ev == null:
		return
	GameManager.add_gold(2 + _difficulty)  # the "×gold" feel, per kill
	var actor = ev.actor
	if actor and is_instance_valid(actor) and actor.has_meta("gold_vein_golden"):
		actor.remove_meta("gold_vein_golden")
		GameManager.add_gold(40 + 20 * _difficulty)
		if actor is Node2D:
			_drop_cache((actor as Node2D).global_position)
		GameManager.notice.emit("Золотая жила — золотой враг рассыпал свой клад!", Color(1.0, 0.84, 0.3))


func _anoint_golden() -> void:
	if GameManager and GameManager.game_over:
		return
	var tree := get_tree()
	if tree == null:
		return
	var candidates: Array = []
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if e.get("dead") == true or e.get("is_puppet") == true:
			continue
		if e.has_meta("gold_vein_golden"):
			continue
		candidates.append(e)
	if candidates.is_empty():
		return
	var pick = candidates[randi() % candidates.size()]
	pick.set_meta("gold_vein_golden", true)
	if pick is CanvasItem:
		(pick as CanvasItem).modulate = Color(1.0, 0.84, 0.3)


func _drop_cache(pos: Vector2) -> void:
	if not ResourceLoader.exists(CHEST_SCENE_PATH):
		return
	var scene: PackedScene = load(CHEST_SCENE_PATH) as PackedScene
	if scene == null:
		return
	var chest: Node2D = scene.instantiate()
	var parent: Node = get_parent() if get_parent() else self
	parent.add_child(chest)
	chest.global_position = pos
	if chest.has_method("configure"):
		# Bias toward a good drop using the active dungeon luck.
		chest.call("configure", 6 + _difficulty * 2)


# Echo of Power: scatter shrines; claiming one stacks a buff for the whole layer.
func _spawn_echo_shrines() -> void:
	var center: Vector2 = Vector2.ZERO
	var p := _nearest_player()
	if p:
		center = p.global_position
	for i in ECHO_SHRINES:
		var s := SHRINE.new()
		s.claimed.connect(_on_shrine_claimed)
		var parent: Node = get_parent() if get_parent() else self
		parent.add_child(s)
		var ang: float = TAU * float(i) / float(ECHO_SHRINES) + randf()
		s.global_position = center + Vector2(cos(ang), sin(ang)) * randf_range(280.0, 480.0)


func _on_shrine_claimed(_node) -> void:
	_echo_dmg += ECHO_DMG_PER_SHRINE
	_echo_spd += ECHO_SPD_PER_SHRINE
	_apply_echo_buff()
	if GameManager:
		GameManager.notice.emit(
			"Эхо силы — +%d%% урона / +%d%% скорости" % [int((_echo_dmg - 1.0) * 100.0), int((_echo_spd - 1.0) * 100.0)],
			Color(0.45, 0.7, 1.0)
		)


# Re-apply the running total to every player (apply_buff keeps the strongest, so the
# growing total effectively stacks).
func _apply_echo_buff() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for pl in tree.get_nodes_in_group("player"):
		if is_instance_valid(pl) and pl.has_method("apply_buff"):
			pl.call("apply_buff", ECHO_BUFF_DURATION, _echo_dmg, _echo_spd)


func _nearest_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var players := tree.get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D
