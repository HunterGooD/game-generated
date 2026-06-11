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
	c.register_command(cmd_finish_arena, "finish_arena", "instantly end the current arena → reward screen (grants test coin)")
	c.register_command(cmd_list_dungeon_affixes, "list_dungeon_affixes", "list the 6 dungeon affixes (polarity / shown|hidden)")
	c.register_command(cmd_dungeon_info, "dungeon_info", "show this dungeon's active affixes, or the run map's per-node negatives")
	c.register_command(cmd_meta_info, "meta_info", "show the current class's meta-mirror level/points/allocated nodes")
	c.register_command(cmd_meta_nodes, "meta_nodes", "list the current class's meta-tree node ids (type, allocated?)")
	c.register_command(cmd_meta_xp, "meta_xp", "grant meta XP to the current class: meta_xp <amount>")
	c.register_command(cmd_meta_levels, "meta_levels", "grant N meta levels to the current class: meta_levels <n>")
	c.register_command(cmd_meta_alloc, "meta_alloc", "allocate a meta node for the current class: meta_alloc <node_id>")
	c.register_command(cmd_meta_respec, "meta_respec", "free full respec of the current class's meta tree")


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


func cmd_finish_arena() -> void:
	var sp := _spawner()
	if sp == null or not bool(sp.get("arena_mode")):
		_err("not in an arena node")
		return
	if GameManager:
		GameManager.arena_award(200)  # so the reward chests are affordable to test
	if sp.call("dev_finish_arena"):
		_info("arena finished → reward screen (pick a reward to return to the map)")
	else:
		_err("could not finish arena")


func cmd_list_dungeon_affixes() -> void:
	var lines: Array = []
	for id in DungeonAffixes.DEFS.keys():
		var pol: String = "+" if DungeonAffixes.is_positive(id) else "−"
		var vis: String = "hidden" if DungeonAffixes.is_hidden(id) else "shown"
		lines.append("[%s] %-18s %s (%s)" % [pol, id, DungeonAffixes.display_name(id), vis])
	_info("dungeon affixes:\n  " + "\n  ".join(lines))


func cmd_dungeon_info() -> void:
	var tree := get_tree()
	# In a live dungeon node? Read the controller's rolled affixes directly.
	var ctrl: Node = tree.get_first_node_in_group("dungeon_affix_controller") if tree else null
	if ctrl:
		_info(
			"current dungeon — negatives: %s  positives: %s"
			% [str(ctrl.get("active_negatives")), str(ctrl.get("active_positives"))]
		)
		return
	# Otherwise preview the active run's dungeon nodes (negatives only; positives stay hidden).
	if GameManager and GameManager.run_state and GameManager.run_state.is_active():
		var out: Array = []
		for node in GameManager.run_state.map.all_nodes():
			if String(node.get("type", "")) != RunMap.TYPE_DUNGEON:
				continue
			var s: int = DungeonAffixes.node_seed(GameManager.run_seed, int(node["id"]))
			var af: Array = DungeonAffixes.generate_node_affixes(s, GameManager.run_difficulty)
			var negs: Array = DungeonAffixes.ids_from(af, "negative")
			out.append("node %d: %s" % [int(node["id"]), str(negs) if not negs.is_empty() else "(none)"])
		if out.is_empty():
			_info("no dungeon nodes in the current run")
		else:
			_info("dungeon node negatives (positives hidden until entry):\n  " + "\n  ".join(out))
		return
	_err("not in a dungeon and no active run — try list_dungeon_affixes")


# ── meta-mirror (Phase A) ──────────────────────────────────────────────────────
# The class whose mirror the dev commands act on — the active class, falling back to the
# last-selected hero so the commands work in the hub before a run starts.
func _meta_class() -> String:
	if GameManager == null:
		return ""
	var c: String = String(GameManager.player_class)
	return c if c != "" else String(GameManager.last_class)


func cmd_meta_info() -> void:
	if MetaProgress == null:
		_err("MetaProgress unavailable")
		return
	var cls: String = _meta_class()
	var s: Dictionary = MetaProgress.summary(cls)
	var alloc: Array = s.get("allocated", [])
	_info(
		(
			"meta[%s] lvl %d  (xp %d/%d)  points %d/%d  allocated: %s"
			% [
				cls,
				int(s.get("meta_level", 1)),
				int(s.get("meta_xp", 0)),
				int(s.get("xp_to_next", 0)),
				int(s.get("points_available", 0)),
				int(s.get("points_total", 0)),
				str(alloc) if not alloc.is_empty() else "(none)",
			]
		)
	)


func cmd_meta_nodes() -> void:
	if MetaProgress == null:
		_err("MetaProgress unavailable")
		return
	var cls: String = _meta_class()
	var tree: Dictionary = MetaTrees.tree_for(cls)
	if tree.is_empty():
		_info("meta[%s] has no tree yet (Phase C rollout)" % cls)
		return
	var lines: Array = []
	for id in tree:
		var nd: Dictionary = tree[id]
		var mark: String = "✓" if MetaProgress.is_allocated(cls, String(id)) else " "
		lines.append("[%s] %-10s %s" % [mark, String(id), String(nd.get("type", "?"))])
	_info("meta[%s] nodes:\n  %s" % [cls, "\n  ".join(lines)])


func cmd_meta_xp(amount: int = 100) -> void:
	if MetaProgress == null:
		return
	var cls: String = _meta_class()
	MetaProgress.award_xp(cls, maxi(1, amount))
	cmd_meta_info()


func cmd_meta_levels(n: int = 1) -> void:
	if MetaProgress == null:
		return
	var cls: String = _meta_class()
	for i in maxi(1, n):
		# Grant exactly enough XP to cross the next level threshold.
		MetaProgress.award_xp(cls, MetaProgress.xp_to_next(cls) - MetaProgress.get_meta_xp(cls))
	cmd_meta_info()


func cmd_meta_alloc(node_id: String = "") -> void:
	if MetaProgress == null:
		return
	var cls: String = _meta_class()
	if MetaProgress.allocate(cls, node_id):
		_info("meta[%s] allocated '%s' (re-enter a run to apply bonuses)" % [cls, node_id])
	else:
		_err("could not allocate '%s' (unknown, no points, or not connected — try meta_nodes)" % node_id)


func cmd_meta_respec() -> void:
	if MetaProgress == null:
		return
	var cls: String = _meta_class()
	MetaProgress.respec(cls)
	_info("meta[%s] respec — all points refunded" % cls)


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
