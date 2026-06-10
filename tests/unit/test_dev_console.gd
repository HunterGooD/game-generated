extends GutTest

# DevConsole limbo_console commands. The command callables are tested directly (the
# console only parses args → callable). Spawn commands delegate to a mock spawner in
# the "enemy_spawner" group; give/heal/kill commands act on the real autoloads.


class _MockSpawner:
	extends Node
	var spawned: Array = []
	var current_wave: int = 4
	var arena_mode: bool = false
	var finished: bool = false
	func dev_finish_arena() -> bool:
		finished = true
		return true
	func dev_spawn(type, affixes, _pos) -> bool:
		if type == "skeleton" or type == "cultist":
			spawned.append([type, (affixes as Array).duplicate()])
			return true
		return false
	func dev_spawn_boss(id) -> bool:
		spawned.append(["boss", id])
		return id == "crimson_matron"
	func enemy_type_ids() -> Array:
		return ["skeleton", "cultist"]


class _MockEnemy:
	extends Node2D
	var dead: bool = false
	var hits: Array = []
	func take_damage(d, _s = null) -> void:
		hits.append(d)


var _gold0: int
var _hp0: int
var _lvl0: int
var _inv0: int
var _class0: String
var _sp: _MockSpawner


func before_each() -> void:
	_gold0 = GameManager.gold
	_hp0 = GameManager.player_hp
	_lvl0 = GameManager.player_level
	_inv0 = InventorySystem.inventory.size()
	_class0 = GameManager.player_class
	_sp = _MockSpawner.new()
	_sp.add_to_group("enemy_spawner")
	add_child_autofree(_sp)


func after_each() -> void:
	GameManager.gold = _gold0
	GameManager.player_hp = _hp0
	GameManager.player_class = _class0
	while InventorySystem.inventory.size() > _inv0:
		InventorySystem.inventory.pop_back()


# ── spawn_elite ───────────────────────────────────────────────────────────────
func test_spawn_elite_with_explicit_affixes() -> void:
	DevConsole.cmd_spawn_elite("skeleton", "swift,brutal")
	assert_eq(_sp.spawned.size(), 1)
	assert_eq(_sp.spawned[0][0], "skeleton")
	assert_eq(_sp.spawned[0][1], ["swift", "brutal"])


func test_spawn_elite_random_affixes() -> void:
	DevConsole.cmd_spawn_elite("skeleton", "")
	assert_eq(_sp.spawned.size(), 1)
	var ids: Array = _sp.spawned[0][1]
	assert_between(ids.size(), 1, 3)
	for id in ids:
		assert_true(EnemyAffixes.AFFIXES.has(id))


func test_spawn_elite_rejects_unknown_affix() -> void:
	DevConsole.cmd_spawn_elite("skeleton", "nonsense")
	assert_eq(_sp.spawned.size(), 0, "bad affix → no spawn")


func test_spawn_elite_rejects_unknown_type() -> void:
	DevConsole.cmd_spawn_elite("dragon", "swift")
	assert_eq(_sp.spawned.size(), 0, "bad type → no spawn")


func test_spawn_enemy_count() -> void:
	DevConsole.cmd_spawn_enemy("cultist", 3)
	assert_eq(_sp.spawned.size(), 3)


func test_spawn_boss() -> void:
	DevConsole.cmd_spawn_boss("crimson_matron")
	assert_eq(_sp.spawned, [["boss", "crimson_matron"]])


# ── give / heal / kill ────────────────────────────────────────────────────────
func test_give_levels() -> void:
	DevConsole.cmd_give_levels(2)
	assert_eq(GameManager.player_level, _lvl0 + 2)


func test_give_gold() -> void:
	DevConsole.cmd_give_gold(300)
	assert_eq(GameManager.gold, _gold0 + 300)


func test_give_item_adds_to_inventory() -> void:
	GameManager.player_class = "mage"
	DevConsole.cmd_give_item(2, 5)
	assert_eq(InventorySystem.inventory.size(), _inv0 + 2)


func test_heal_fills_hp() -> void:
	GameManager.player_hp = 1
	DevConsole.cmd_heal()
	assert_eq(GameManager.player_hp, GameManager.player_max_hp)


func test_kill_all_hits_every_enemy() -> void:
	var e1 := _MockEnemy.new()
	e1.add_to_group("enemy")
	add_child_autofree(e1)
	var e2 := _MockEnemy.new()
	e2.add_to_group("enemy")
	add_child_autofree(e2)
	DevConsole.cmd_kill_all()
	assert_eq(e1.hits.size(), 1)
	assert_eq(e2.hits.size(), 1)


func test_finish_arena_grants_coin_and_finishes() -> void:
	var cur0: int = GameManager.arena_currency
	_sp.arena_mode = true
	DevConsole.cmd_finish_arena()
	assert_true(_sp.finished, "dev_finish_arena invoked")
	assert_eq(GameManager.arena_currency, cur0 + 200, "test coin granted for reward testing")
	GameManager.arena_currency = cur0


func test_finish_arena_noop_outside_arena() -> void:
	_sp.arena_mode = false
	DevConsole.cmd_finish_arena()
	assert_false(_sp.finished, "does nothing when not in an arena")


func test_list_commands_do_not_error() -> void:
	DevConsole.cmd_list_affixes()
	DevConsole.cmd_list_enemies()
	assert_true(true)
