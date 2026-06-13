extends Node

# Headless logic test for the unified skill tree: point spending, constellation
# gating, stat application, ult gating, variant radio, and respec refunds — pure
# GameManager/SkillTrees state (skill-side effects no-op without a SkillSystem).
#
# Run:  godot --headless res://tests/talent_test.tscn --path .
# Exit: 0 = all checks passed, 1 = at least one failure.

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	print("=== SKILL TREE TEST ===")
	_test_spend_and_gating()
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
	GameManager.player_spec_path = ""
	GameManager.tree_nodes = {}
	GameManager.talent_points = points


func _test_spend_and_gating() -> void:
	_fresh_mage(12)
	# Edge gating: flame_cleave hangs off the fw_duration diamond (row 2) → closed
	# until that passive is taken.
	_expect(
		GameManager.node_block_reason("flame_cleave") != "",
		"variant must be gated before its parent passive"
	)
	# Passive under the root is open immediately (root satisfies its children).
	_expect(GameManager.node_block_reason("fw_damage") == "", "passive under root must be open")
	_expect(GameManager.spend_node("fw_damage"), "passive spend must succeed")
	_expect(GameManager.spend_node("fw_duration"), "diamond passive spend must succeed")
	_expect(
		GameManager.node_block_reason("flame_cleave") == "",
		"variant must open once its parent passive is taken"
	)
	# Leveling the root skill itself.
	_expect(GameManager.spend_node("fire_wall"), "root skill spend must succeed")
	_expect(GameManager.get_skill_level(0) == 1, "skill level must be 1 after one rank")
	# Variant costs VARIANT_COST; switching to a sibling under the same diamond is net-0.
	var pts: int = GameManager.talent_points
	_expect(GameManager.spend_node("flame_cleave"), "variant select must succeed")
	_expect(GameManager.talent_points == pts - SkillTrees.VARIANT_COST, "variant costs 2")
	var pts2: int = GameManager.talent_points
	_expect(GameManager.spend_node("ice_wall"), "variant switch must succeed")
	_expect(
		int(GameManager.tree_nodes.get("flame_cleave", 0)) == 0, "old variant refunded on switch"
	)
	_expect(GameManager.talent_points == pts2, "switch is net-0 points")
	# Unknown node id is rejected.
	_expect(not GameManager.spend_node("no_such_node"), "unknown node must be rejected")


func _test_ult_gating() -> void:
	_fresh_mage(5)
	_expect(
		GameManager.node_block_reason("ult_power") == "Требуется вознесение",
		"ult node must require an ascension"
	)
	GameManager.choose_spec_path("battlemage")
	_expect(GameManager.spend_node("ult_power"), "ult spend must succeed after ascension")
	_expect(GameManager.get_talent_rank("ult_power") == 1, "ult rank must be 1")


func _test_respec() -> void:
	_fresh_mage(6)
	var str_base: int = GameManager.player_strength
	for i in 3:
		GameManager.spend_node("stat_strength")
	GameManager.spend_node("fw_damage")
	_expect(GameManager.talent_points == 2, "2 points must remain before respec")
	_expect(GameManager.talent_respec_refund() == 4, "respec must refund 4 points")
	GameManager.respec_talents()
	_expect(GameManager.talent_points == 6, "all points must be back after respec")
	_expect(
		GameManager.player_strength == str_base,
		(
			"stat ranks must be reverted on respec (got %d, want %d)"
			% [GameManager.player_strength, str_base]
		)
	)
	_expect(GameManager.tree_nodes.is_empty(), "tree_nodes must be empty after respec")


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
