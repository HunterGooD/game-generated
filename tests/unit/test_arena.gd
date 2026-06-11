extends GutTest

# Arena cycle v3: shared local-currency economy (award / spend / 1:2 dump), the wave-start
# pillars (green/red/purple → emit `chosen`), the per-wave batch-size growth, the finale
# reward chests, and the silent survivor wipe.

var _cur0: int
var _pow0: float
var _gold0: int
var _inv0: int
var _class0: String
var _carry0: bool
var _thr0: int
var _spawn0: float
var _bd0: float
var _bs0: float


func before_each() -> void:
	_cur0 = GameManager.arena_currency
	_pow0 = GameManager.arena_enemy_power
	_gold0 = GameManager.gold
	_inv0 = InventorySystem.inventory.size()
	_class0 = GameManager.player_class
	_carry0 = GameManager.arena_carryover
	_thr0 = GameManager.arena_event_threshold
	_spawn0 = GameManager.arena_spawn_bonus
	_bd0 = GameManager.arena_buff_dmg
	_bs0 = GameManager.arena_buff_spd
	GameManager.arena_carryover = false


func after_each() -> void:
	GameManager.arena_currency = _cur0
	GameManager.arena_enemy_power = _pow0
	GameManager.gold = _gold0
	GameManager.player_class = _class0
	GameManager.arena_carryover = _carry0
	GameManager.arena_event_threshold = _thr0
	GameManager.arena_spawn_bonus = _spawn0
	GameManager.arena_buff_dmg = _bd0
	GameManager.arena_buff_spd = _bs0
	while InventorySystem.inventory.size() > _inv0:
		InventorySystem.inventory.pop_back()


# ── currency economy ──────────────────────────────────────────────────────────
func test_award_and_spend() -> void:
	GameManager.arena_currency = 0
	watch_signals(GameManager)
	GameManager.arena_award(40)
	assert_eq(GameManager.arena_currency, 40)
	assert_signal_emitted(GameManager, "arena_currency_changed")
	assert_false(GameManager.arena_spend(50), "can't overspend")
	assert_true(GameManager.arena_spend(25))
	assert_eq(GameManager.arena_currency, 15)


func test_dump_converts_at_one_to_two() -> void:
	GameManager.arena_currency = 50
	var gained := GameManager.arena_dump_to_gold()
	assert_eq(gained, 100, "1 coin → 2 gold")
	assert_eq(GameManager.arena_currency, 0, "pool emptied")
	assert_eq(GameManager.gold, _gold0 + 100, "gold credited")


func test_carryover_keeps_effects_between_arenas() -> void:
	GameManager.arena_currency = 50
	GameManager.arena_enemy_power = 1.5
	GameManager.arena_carryover = true
	GameManager.arena_reset()
	assert_eq(GameManager.arena_currency, 50)
	assert_almost_eq(GameManager.arena_enemy_power, 1.5, 0.001)
	GameManager.arena_carryover = false
	GameManager.arena_reset()
	assert_eq(GameManager.arena_currency, 0)
	assert_eq(GameManager.arena_enemy_power, 1.0)


# ── wave-start pillars ────────────────────────────────────────────────────────
func test_pillar_emits_kind_and_effect_on_activation() -> void:
	var pillar := ArenaPillar.new()
	pillar.configure("red", "brutality", "Brutality — enemies +40% power")
	add_child_autofree(pillar)
	watch_signals(pillar)
	pillar._activate()
	assert_signal_emitted_with_parameters(pillar, "chosen", ["red", "brutality"])


func test_pillar_kinds_have_colors() -> void:
	for k in ["green", "red", "purple"]:
		assert_true(ArenaPillar.KIND_COLOR.has(k), "%s has a colour" % k)


func test_three_effects_each_for_green_and_red() -> void:
	var sp = load("res://scripts/world/enemy_spawner.gd").new()
	assert_eq(sp.GREEN_EFFECTS.size(), 3, "3 green boons")
	assert_eq(sp.RED_EFFECTS.size(), 3, "3 red escalations")
	sp.free()


func test_reset_clears_accumulators() -> void:
	GameManager.arena_enemy_power = 2.0
	GameManager.arena_event_threshold = 4
	GameManager.arena_spawn_bonus = 1.0
	GameManager.arena_buff_dmg = 1.5
	GameManager.arena_reset()
	assert_eq(GameManager.arena_enemy_power, 1.0)
	assert_eq(GameManager.arena_event_threshold, GameManager.ARENA_BASE_THRESHOLD)
	assert_eq(GameManager.arena_spawn_bonus, 0.0)
	assert_eq(GameManager.arena_buff_dmg, 1.0)


# ── zone event ────────────────────────────────────────────────────────────────
func test_zone_event_rewards_when_goal_met() -> void:
	GameManager.arena_currency = 0
	var zone := ArenaZone.new()
	zone.goal = 2
	zone.reward = 30
	add_child_autofree(zone)
	zone.global_position = Vector2.ZERO
	for i in 2:
		var dummy := Node2D.new()
		add_child_autofree(dummy)
		dummy.global_position = Vector2(10, 0)  # inside the ring
		var ev := ActorDeathEvent.new()
		ev.actor = dummy
		GameEvents.enemy_died.emit(ev)
	assert_eq(GameManager.arena_currency, 30, "clearing the zone goal pays out")


# ── waves ─────────────────────────────────────────────────────────────────────
func test_batch_size_grows_per_wave() -> void:
	var sp = load("res://scripts/world/enemy_spawner.gd").new()
	assert_eq(sp._arena_batch_size(1), 10, "wave 1 = 10")
	assert_eq(sp._arena_batch_size(2), 15, "+5 per wave")
	assert_eq(sp._arena_batch_size(5), 30)
	sp.free()


func test_arena_node_runs_five_waves() -> void:
	var node := {"type": RunMap.TYPE_ARENA, "affixes": []}
	assert_eq(int(RunMap.combat_plan(node)["waves"]), 5, "arena cycle = 5 waves → finale boss")


func test_combat_node_modes() -> void:
	var sp = load("res://scripts/world/enemy_spawner.gd").new()
	assert_eq(sp._combat_node_mode(RunMap.TYPE_ELITE), "elite")
	assert_eq(sp._combat_node_mode(RunMap.TYPE_BOSS), "boss")
	assert_eq(sp._combat_node_mode(RunMap.TYPE_ARENA), "arena")
	assert_eq(sp._combat_node_mode(RunMap.TYPE_DUNGEON), "managed", "dungeon is runner-managed (own scene)")
	assert_eq(sp._combat_node_mode(RunMap.TYPE_MERCHANT), "", "non-combat → no mode")
	sp.free()


func test_despawn_silent_removes_without_reward() -> void:
	var e: Node = (load("res://scenes/entities/enemy.tscn") as PackedScene).instantiate()
	add_child_autofree(e)
	e.configure({"max_hp": 50, "xp_value": 99})
	watch_signals(GameEvents)
	e.despawn_silent()
	assert_true(e.dead, "survivor removed")
	assert_signal_not_emitted(GameEvents, "enemy_died", "no death reward on silent despawn")


# ── physical reward chests ────────────────────────────────────────────────────
func _chest(cfg: Dictionary) -> ArenaChest:
	var c := ArenaChest.new()
	c.configure(cfg)
	add_child_autofree(c)
	return c


func test_cache_chest_spends_and_grants_items() -> void:
	GameManager.arena_currency = 200
	GameManager.player_class = "mage"
	var c := _chest({"kind": "cache", "cost": 70, "items": 2, "ilvl": 3})
	c._open()
	assert_eq(GameManager.arena_currency, 130, "cache cost spent")
	assert_eq(InventorySystem.inventory.size(), _inv0 + 2, "two items granted")


func test_cache_chest_no_open_when_too_poor() -> void:
	GameManager.arena_currency = 10
	var c := _chest({"kind": "cache", "cost": 70, "items": 2})
	c._open()
	assert_eq(GameManager.arena_currency, 10, "nothing spent")
	assert_eq(InventorySystem.inventory.size(), _inv0, "no item")
	assert_false(c._used, "chest stays openable")


func test_dump_chest_converts_all_at_one_to_two() -> void:
	GameManager.arena_currency = 35
	var c := _chest({"kind": "dump"})
	c._open()
	assert_eq(GameManager.gold, _gold0 + 70, "35 coin → 70 gold")
	assert_eq(GameManager.arena_currency, 0, "pool emptied")
	assert_true(c._used, "dump chest consumed")
