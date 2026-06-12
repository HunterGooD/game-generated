extends Node

# Headless logic test for the in-run talent tree: point spending, tier gating,
# stat application, ult gating, and respec refunds — pure GameManager/TalentTrees
# state, no player node needed (skill-side effects no-op without a SkillSystem).
#
# Run:  godot --headless res://tests/talent_test.tscn --path .
# Exit: 0 = all checks passed, 1 = at least one failure.

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	print("=== TALENT TEST ===")
	_test_spend_and_tiers()
	_test_ult_gating()
	_test_respec()
	_test_stat_effects()
	print("=== RESULT: %d checks, %d failures ===" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: " + msg)


func _fresh_mage(points: int) -> void:
	GameManager.use_talent_tree = true
	GameManager.choose_class("mage")
	GameManager.talent_points = points


func _test_spend_and_tiers() -> void:
	_fresh_mage(10)
	# Tier-2 node is locked until 3 points sit in the branch.
	_expect(
		GameManager.talent_block_reason("fw_damage") != "",
		"tier-2 node must be locked at 0 branch points"
	)
	# Tier-1 stat node: 3 ranks = +6 Strength and unlocks tier 2.
	var str_before: int = GameManager.player_strength
	for i in 3:
		_expect(
			GameManager.spend_talent_point("battlemage_strength"),
			"tier-1 stat spend %d must succeed" % i
		)
	_expect(
		GameManager.player_strength == str_before + 6,
		"3 stat ranks must add +6 Strength (got %d, was %d)"
		% [GameManager.player_strength, str_before]
	)
	_expect(GameManager.talent_points == 7, "7 points must remain after 3 spends")
	_expect(
		GameManager.talent_block_reason("fw_damage") == "",
		"tier-2 node must unlock at 3 branch points"
	)
	_expect(GameManager.spend_talent_point("fw_damage"), "tier-2 spend must succeed")
	# Cross-branch isolation: elementalist tier 2 is still locked.
	_expect(
		GameManager.talent_block_reason("ib_damage") != "",
		"other branch's tier 2 must stay locked"
	)
	# Unknown node id is rejected.
	_expect(not GameManager.spend_talent_point("no_such_node"), "unknown node must be rejected")
	# Zero points: everything blocked.
	GameManager.talent_points = 0
	_expect(
		GameManager.talent_block_reason("battlemage_strength") != "",
		"spending with 0 points must be blocked"
	)


func _test_ult_gating() -> void:
	_fresh_mage(5)
	_expect(
		GameManager.talent_block_reason("ult_power") == "Requires an ascension",
		"ult node must require an ascension"
	)
	GameManager.choose_spec_path("battlemage")
	_expect(GameManager.spend_talent_point("ult_power"), "ult spend must succeed after ascension")
	_expect(GameManager.get_talent_rank("ult_power") == 1, "ult rank must be 1")


func _test_respec() -> void:
	_fresh_mage(6)
	var str_base: int = GameManager.player_strength
	for i in 3:
		GameManager.spend_talent_point("battlemage_strength")
	GameManager.spend_talent_point("fw_damage")
	_expect(GameManager.talent_points == 2, "2 points must remain before respec")
	_expect(GameManager.talent_respec_refund() == 4, "respec must refund 4 points")
	GameManager.respec_talents()
	_expect(GameManager.talent_points == 6, "all points must be back after respec")
	_expect(
		GameManager.player_strength == str_base,
		"stat ranks must be reverted on respec (got %d, want %d)"
		% [GameManager.player_strength, str_base]
	)
	_expect(GameManager.talents.is_empty(), "talents must be empty after respec")


func _test_stat_effects() -> void:
	_fresh_mage(0)
	var hp_before: int = GameManager.get_effective_max_hp()
	var mana_before: int = GameManager.get_effective_max_mana()
	GameManager.player_strength += 10
	GameManager.player_intelligence += 10
	_expect(
		GameManager.get_effective_max_hp() == hp_before + 50,
		"+10 Str must add +50 effective max HP"
	)
	_expect(
		GameManager.get_effective_max_mana() == mana_before + 30,
		"+10 Int must add +30 effective max mana"
	)
	_expect(
		is_equal_approx(
			GameManager.get_stat_skill_damage_mult(),
			1.0 + 0.01 * float(GameManager.player_intelligence)
		),
		"skill damage mult must follow Intelligence"
	)
	_expect(
		is_equal_approx(
			GameManager.get_stat_attack_speed_mult(),
			1.0 + 0.01 * float(GameManager.player_dexterity)
		),
		"attack speed mult must follow Dexterity"
	)
