extends GutTest

# Activity-beacon events (V4). The effect methods are per-player and host-free, so they
# test directly against GameManager + a mock player. Random outcomes are injected via
# the `roll` param for determinism.

const BEACON_SCENE := "res://scenes/world/activity_beacon.tscn"


class _MockPlayer:
	extends Node2D
	var buffs: Array = []
	func apply_buff(d, dm, sm) -> void:
		buffs.append([d, dm, sm])


var _gold0: int = 0
var _hp0: int = 0


func before_each() -> void:
	_gold0 = GameManager.gold
	_hp0 = GameManager.player_hp


func after_each() -> void:
	GameManager.gold = _gold0
	GameManager.player_hp = _hp0


func _beacon() -> Node:
	var b: Node = (load(BEACON_SCENE) as PackedScene).instantiate()
	add_child_autofree(b)
	return b


func test_treasure_grants_gold_and_heals() -> void:
	GameManager.player_hp = GameManager.player_max_hp - 50
	var before: int = GameManager.gold
	var msg: String = _beacon().event_treasure(null)
	assert_gt(GameManager.gold, before, "treasure granted gold")
	assert_gt(GameManager.player_hp, GameManager.player_max_hp - 50, "treasure healed")
	assert_true(msg.contains("Сокровище"))


func test_altar_blessing_buffs_and_heals() -> void:
	GameManager.player_hp = 50
	var p := _MockPlayer.new()
	add_child_autofree(p)
	var msg: String = _beacon().event_altar(p, 0.1)  # blessing roll (< 0.55)
	assert_eq(p.buffs, [[30.0, 1.30, 1.15]], "blessing applied the empower buff")
	assert_true(msg.contains("Благословение"))


func test_altar_curse_drains_hp() -> void:
	GameManager.player_hp = GameManager.player_max_hp
	var before: int = GameManager.player_hp
	var msg: String = _beacon().event_altar(null, 0.9)  # curse roll (>= 0.55)
	assert_lt(GameManager.player_hp, before, "curse drained HP")
	assert_true(msg.contains("Проклятие"))


func test_roulette_win_nets_gold() -> void:
	GameManager.gold = 100
	var msg: String = _beacon().event_roulette(null, 0.1)  # win
	assert_eq(GameManager.gold, 200, "stake 50 spent, won 150 → +100 net")
	assert_true(msg.contains("Джекпот"))


func test_roulette_loss_costs_stake() -> void:
	GameManager.gold = 100
	var msg: String = _beacon().event_roulette(null, 0.9)  # lose
	assert_eq(GameManager.gold, 50, "lost the 50 stake")
	assert_true(msg.contains("Проигрыш"))


func test_roulette_needs_enough_gold() -> void:
	GameManager.gold = 10
	var msg: String = _beacon().event_roulette(null, 0.1)
	assert_eq(GameManager.gold, 10, "no gamble below the stake")
	assert_true(msg.contains("Недостаточно"))


func test_ritual_sacrifices_hp_for_buff() -> void:
	GameManager.player_hp = GameManager.player_max_hp
	var p := _MockPlayer.new()
	add_child_autofree(p)
	var before: int = GameManager.player_hp
	var msg: String = _beacon().event_ritual(p)
	assert_lt(GameManager.player_hp, before, "ritual sacrificed HP")
	assert_eq(p.buffs, [[45.0, 1.5, 1.25]], "ritual granted the strong buff")
	assert_true(msg.contains("Ритуал"))


func test_hp_cost_is_non_lethal() -> void:
	GameManager.player_hp = 5
	_beacon().event_ritual(null)
	assert_eq(GameManager.player_hp, 1, "HP cost is floored at 1 (events never kill)")
