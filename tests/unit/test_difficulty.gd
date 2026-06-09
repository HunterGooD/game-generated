extends GutTest

# Difficulty tiers + their effect on loot rarity. The tier table is the single source of
# balance scaling; LootRoller reads loot_rarity_bonus so higher tiers drop better.

var _diff0: int


func before_each() -> void:
	_diff0 = GameManager.run_difficulty


func after_each() -> void:
	GameManager.run_difficulty = _diff0


# ── the tier table ────────────────────────────────────────────────────────────
func test_has_multiple_tiers() -> void:
	assert_gte(Difficulty.count(), 3, "at least normal/hard/nightmare")
	assert_eq(Difficulty.name_of(0), "Normal")


func test_tiers_scale_monotonically() -> void:
	var keys := [
		"enemy_hp_mult", "enemy_dmg_mult", "elite_chance", "loot_rarity_bonus", "reward_mult"
	]
	for k in keys:
		for t in range(1, Difficulty.count()):
			assert_gte(
				Difficulty.value(t, k),
				Difficulty.value(t - 1, k),
				"%s does not decrease from tier %d to %d" % [k, t - 1, t],
			)


func test_normal_tier_is_neutral() -> void:
	assert_almost_eq(Difficulty.value(0, "enemy_hp_mult"), 1.0, 0.001)
	assert_almost_eq(Difficulty.value(0, "reward_mult"), 1.0, 0.001)
	assert_eq(int(Difficulty.value(0, "elite_affix_bonus")), 0)


func test_clamp_tier_bounds() -> void:
	assert_eq(Difficulty.clamp_tier(-5), 0, "below floor clamps to 0")
	assert_eq(Difficulty.clamp_tier(999), Difficulty.count() - 1, "above ceiling clamps to last")


func test_game_manager_holds_run_tier() -> void:
	GameManager.run_difficulty = 2
	assert_eq(GameManager.run_difficulty, 2, "run tier persists on the manager")


# ── loot rarity responds to difficulty ────────────────────────────────────────
func _non_common_fraction(difficulty: int) -> float:
	var hits: int = 0
	var n: int = 3000
	for i in n:
		# Fixed wave so only difficulty varies the rarity weights.
		if LootRoller._roll_rarity(5, difficulty) != ItemDatabase.RARITY_COMMON:
			hits += 1
	return float(hits) / float(n)


func test_higher_difficulty_drops_better_loot() -> void:
	var f_low := _non_common_fraction(0)
	var f_high := _non_common_fraction(Difficulty.count() - 1)
	assert_gt(f_high, f_low, "top tier yields a higher non-common drop rate than normal")
