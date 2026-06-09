extends Node

# Dev/test commands for limbo_console (registered once at startup, after LimboConsole).
# Spawn commands are host/solo only — the host owns enemy simulation; on a client they
# print a notice. Toggle the console with the limbo_console_toggle key (default `~`).


func _ready() -> void:
	var c = _console()
	if c == null:
		return
	c.register_command(cmd_spawn_elite, "spawn_elite", "spawn an elite: spawn_elite <type> <affixes csv | empty = random>")
	c.register_command(cmd_spawn_enemy, "spawn_enemy", "spawn enemies: spawn_enemy <type> <count>")
	c.register_command(cmd_spawn_boss, "spawn_boss", "spawn a boss: spawn_boss <id>")
	c.register_command(cmd_give_levels, "give_levels", "grant N levels")
	c.register_command(cmd_give_gold, "give_gold", "grant gold")
	c.register_command(cmd_give_item, "give_item", "roll + grant items: give_item <count> <wave 0=current>")
	c.register_command(cmd_list_affixes, "list_affixes", "list elite affix ids")
	c.register_command(cmd_list_enemies, "list_enemies", "list enemy type ids")
	c.register_command(cmd_heal, "heal", "full-heal the player")
	c.register_command(cmd_kill_all, "kill_all", "kill all live enemies")
	c.register_command(cmd_open_map, "open_map", "open the run-map screen (picks difficulty if no run active)")
	c.register_command(cmd_start_run, "start_run", "start a run: start_run <difficulty 0-3> <seed | -1 random>")


# ── commands ──────────────────────────────────────────────────────────────────
func cmd_spawn_elite(type: String = "skeleton", affixes: String = "") -> void:
	if not _require_host():
		return
	var sp := _spawner()
	if sp == null:
		_err("no enemy_spawner in scene")
		return
	var ids: Array = []
	if affixes.strip_edges() != "":
		for a in affixes.split(","):
			var id := a.strip_edges()
			if not EnemyAffixes.AFFIXES.has(id):
				_err("unknown affix '%s' (try list_affixes)" % id)
				return
			ids.append(id)
	else:
		ids = EnemyAffixes.roll(EnemyAffixes.roll_count())
	if sp.dev_spawn(type, ids, _spawn_pos()):
		_info("spawned %s elite [%s]" % [type, ", ".join(ids)])
	else:
		_err("unknown enemy type '%s' (try list_enemies)" % type)


func cmd_spawn_enemy(type: String = "skeleton", count: int = 1) -> void:
	if not _require_host():
		return
	var sp := _spawner()
	if sp == null:
		_err("no enemy_spawner in scene")
		return
	var n := 0
	for i in maxi(1, count):
		if sp.dev_spawn(type, [], _spawn_pos()):
			n += 1
	if n > 0:
		_info("spawned %d × %s" % [n, type])
	else:
		_err("unknown enemy type '%s' (try list_enemies)" % type)


func cmd_spawn_boss(id: String = "crimson_matron") -> void:
	if not _require_host():
		return
	var sp := _spawner()
	if sp == null:
		_err("no enemy_spawner in scene")
		return
	if sp.dev_spawn_boss(id):
		_info("spawned boss %s" % id)
	else:
		_err("unknown boss id '%s'" % id)


func cmd_give_levels(n: int = 1) -> void:
	if GameManager == null:
		return
	for i in maxi(1, n):
		GameManager.debug_grant_level()
	_info("granted %d level(s) → level %d" % [maxi(1, n), GameManager.player_level])


func cmd_give_gold(amount: int = 500) -> void:
	if GameManager == null:
		return
	GameManager.add_gold(amount)
	_info("gold +%d → %d" % [amount, GameManager.gold])


func cmd_give_item(count: int = 1, wave: int = 0) -> void:
	if GameManager == null or InventorySystem == null:
		return
	var w: int = wave if wave > 0 else maxi(1, _current_wave())
	var cls: String = String(GameManager.player_class)
	var n := 0
	for i in maxi(1, count):
		var it = LootRoller.roll_item(w, cls)
		if it != null and InventorySystem.add_item(it):
			n += 1
	_info("granted %d item(s) at wave %d" % [n, w])


func cmd_list_affixes() -> void:
	_info("affixes: " + ", ".join(EnemyAffixes.AFFIXES.keys()))


func cmd_list_enemies() -> void:
	var sp := _spawner()
	if sp and sp.has_method("enemy_type_ids"):
		_info("enemies: " + ", ".join(sp.call("enemy_type_ids")))
	else:
		_err("no enemy_spawner in scene")


func cmd_heal() -> void:
	if GameManager == null:
		return
	GameManager.heal_player(GameManager.player_max_hp)
	_info("full healed")


func cmd_kill_all() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var n := 0
	for e in tree.get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not bool(e.get("dead")) and e.has_method("take_damage"):
			e.call("take_damage", 999999)
			n += 1
	_info("killed %d enemies" % n)


func cmd_start_run(difficulty: int = 0, seed_value: int = -1) -> void:
	if RunFlow == null:
		return
	RunFlow.start_run(difficulty, seed_value)
	_info(
		"started run: %s (seed %d) → map" % [Difficulty.name_of(GameManager.run_difficulty), GameManager.run_seed]
	)


func cmd_open_map() -> void:
	if RunFlow == null:
		_err("RunFlow unavailable")
		return
	RunFlow.open_map()
	_info("opened run-map")


# ── helpers ───────────────────────────────────────────────────────────────────
func _console() -> Node:
	return get_node_or_null("/root/LimboConsole")


func _spawner() -> Node:
	var tree := get_tree()
	return tree.get_first_node_in_group("enemy_spawner") if tree else null


func _current_wave() -> int:
	var sp := _spawner()
	return int(sp.get("current_wave")) if sp else 1


func _player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("player"):
		if is_instance_valid(p) and p is Node2D and not p.is_in_group("remote_player"):
			return p as Node2D
	return null


func _spawn_pos() -> Vector2:
	var p := _player()
	if p:
		return p.global_position + Vector2(120, 0).rotated(randf() * TAU)
	return Vector2(672, 432)


func _require_host() -> bool:
	if NetManager and NetManager.is_multiplayer and not NetManager.is_host:
		_err("spawn commands are host-only (you are a client)")
		return false
	return true


func _info(msg: String) -> void:
	var c := _console()
	if c:
		c.call("info", "[dev] " + msg)


func _err(msg: String) -> void:
	var c := _console()
	if c:
		c.call("error", "[dev] " + msg)
