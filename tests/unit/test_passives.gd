extends GutTest

# Ascension passive math. ARCHITECTURE NOTE: every test here must instantiate the
# whole player.tscn (~1800-line monolith) just to exercise a few lines of passive
# logic — these passives are coupled to Player. Contrast with test_skill_effects,
# where decoupled resources test trivially. Finding: ascension/passive state is a
# candidate to extract into an AscensionComponent. (Captured, not refactored here.)


class _MockEnemy:
	extends Node2D
	var dead: bool = false
	var hits: Array = []
	var elem: Array = []
	func take_damage(d, _s) -> void:
		hits.append(d)
	func mark_element(s) -> void:
		elem.append(s)


var player: Node2D = null


func before_each() -> void:
	player = (load("res://scenes/entities/player.tscn") as PackedScene).instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = Vector2.ZERO
	await wait_process_frames(1)


func _enemy(pos: Vector2) -> _MockEnemy:
	var e := _MockEnemy.new()
	e.add_to_group("enemy")
	e.global_position = pos
	add_child_autofree(e)
	return e


func test_close_circuit_scales_with_proximity() -> void:
	GameManager.player_spec_path = "thunderblade"
	var e := _enemy(Vector2(100, 0))
	assert_almost_eq(player._spec_outgoing_mult(), 1.30, 0.001, "<120px")
	e.global_position = Vector2(200, 0)
	assert_almost_eq(player._spec_outgoing_mult(), 1.15, 0.001, "<240px")
	e.global_position = Vector2(500, 0)
	assert_almost_eq(player._spec_outgoing_mult(), 1.0, 0.001, "far")


func test_bones_from_death_banks_then_consumes() -> void:
	GameManager.player_spec_path = "bone_architect"
	var e := _enemy(Vector2(50, 0))
	for i in 5:
		player._on_enemy_died_passives({"actor": e})
	assert_true(player.bone_empowered)
	assert_almost_eq(player._spec_outgoing_mult(), 1.5, 0.001)
	player.on_skill_cast("any", "")
	assert_false(player.bone_empowered)
	assert_eq(player.bone_shards, 0)
	assert_almost_eq(player._spec_outgoing_mult(), 1.0, 0.001)


func test_predator_rhythm_stacks_and_ignores_far_kills() -> void:
	GameManager.player_spec_path = "primal_alpha"
	var e := _enemy(Vector2(50, 0))
	player._on_enemy_died_passives({"actor": e})
	player._on_enemy_died_passives({"actor": e})
	assert_eq(player.predator_stacks, 2)
	assert_almost_eq(player._spec_outgoing_mult(), 1.12, 0.001)
	var far := _enemy(Vector2(2000, 0))
	player._on_enemy_died_passives({"actor": far})
	assert_eq(player.predator_stacks, 2, "far kill ignored")


func test_pain_dividend_banks_then_consumes() -> void:
	GameManager.player_spec_path = "blood_witch"
	var mhp: float = float(GameManager.player_max_hp)
	player.pain_bank = 0.0
	player._bank_pain(int(round(mhp * 0.2)))
	assert_almost_eq(player._spec_outgoing_mult(), 1.0 + 0.2, 0.02, "~+20%")
	player._bank_pain(int(round(mhp * 5.0)))
	assert_almost_eq(player._spec_outgoing_mult(), 1.5, 0.001, "capped +50%")
	player.on_skill_cast("any", "")
	assert_eq(player.pain_bank, 0.0)
	assert_almost_eq(player._spec_outgoing_mult(), 1.0, 0.001)


func test_form_casting_bonus_while_shapeshifted() -> void:
	GameManager.player_spec_path = "stormshaper"
	assert_not_null(player.skill_system, "player has SkillSystem")
	player.skill_system.druid_form = "human"
	assert_almost_eq(player._spec_outgoing_mult(), 1.0, 0.001)
	player.skill_system.druid_form = "wolf"
	assert_almost_eq(player._spec_outgoing_mult(), 1.20, 0.001)


func test_static_cascade_zaps_nearest_three() -> void:
	GameManager.player_spec_path = "tempest_lord"
	var base: int = maxi(1, int(round(float(GameManager.player_damage) * 0.6)))
	var dead_actor := _MockEnemy.new()
	add_child_autofree(dead_actor)
	var n1 := _enemy(Vector2(50, 0))
	var n2 := _enemy(Vector2(100, 0))
	var n3 := _enemy(Vector2(150, 0))
	var n4 := _enemy(Vector2(180, 0))  # within radius but over the 3-target cap
	var far := _enemy(Vector2(400, 0))
	player._on_enemy_died_passives({"actor": dead_actor})
	assert_eq(n1.hits, [base])
	assert_eq(n2.hits, [base])
	assert_eq(n3.hits, [base])
	assert_eq(n1.elem, ["storm"])
	assert_eq(n4.hits, [], "over cap untouched")
	assert_eq(far.hits, [], "out of radius untouched")
