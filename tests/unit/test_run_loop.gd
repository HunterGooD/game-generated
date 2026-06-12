extends GutTest

# Endless-run loop counter: scaling helpers + lifecycle (reset on fresh run,
# carried by continue).


func after_each() -> void:
	GameManager.run_loop = 0
	GameManager.run_state = null


func test_loop_zero_is_neutral() -> void:
	GameManager.run_loop = 0
	assert_eq(GameManager.loop_enemy_hp_mult(), 1.0)
	assert_eq(GameManager.loop_enemy_dmg_mult(), 1.0)
	assert_eq(GameManager.loop_reward_mult(), 1.0)
	assert_eq(GameManager.loop_loot_luck(), 0.0)


func test_loop_scaling_grows() -> void:
	GameManager.run_loop = 3
	assert_almost_eq(GameManager.loop_enemy_hp_mult(), 1.6, 0.001, "+20% HP per loop")
	assert_almost_eq(GameManager.loop_enemy_dmg_mult(), 1.45, 0.001, "+15% dmg per loop")
	assert_almost_eq(GameManager.loop_reward_mult(), 1.3, 0.001, "+10% reward per loop")
	assert_almost_eq(GameManager.loop_loot_luck(), 0.15, 0.001, "+5% loot luck per loop")


func test_reset_run_clears_loop() -> void:
	GameManager.run_loop = 4
	GameManager.reset_run()
	assert_eq(GameManager.run_loop, 0)


func test_fresh_run_resets_loop_but_keeps_character() -> void:
	# start_run itself must NOT touch character state (that's what makes
	# Continue keep the build) — only the loop/map are re-rolled.
	GameManager.run_loop = 2
	GameManager.gold = 123
	GameManager.player_level = 7
	GameManager.start_run(0, 42)
	assert_eq(GameManager.run_loop, 2, "start_run alone keeps the loop (RunFlow resets it)")
	assert_eq(GameManager.gold, 123, "gold untouched")
	assert_eq(GameManager.player_level, 7, "level untouched")
	assert_not_null(GameManager.run_state, "fresh map generated")
	GameManager.gold = 0
	GameManager.player_level = 1
