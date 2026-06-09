extends GutTest

# Spirit pet (ghost wolf) host AI. The shared chase/attack/follow behaviour must match
# under the LimboAI flag both off and on (parity). The pounce is a BT-only addition:
# the wolf leaps onto a mid-range target then melees normally; the legacy path never
# leaps. Co-op-safe: BT runs host-only, puppets do no AI.

const PET_SCENE := "res://scenes/entities/spirit_pet.tscn"


class _MockEnemy:
	extends Node2D
	var dead: bool = false
	var hits: Array = []
	func take_damage(d, _s) -> void:
		hits.append(d)


func after_each() -> void:
	GameManager.use_bt_minions = false


func _pet(puppet := false) -> CharacterBody2D:
	var p: CharacterBody2D = (load(PET_SCENE) as PackedScene).instantiate()
	add_child_autofree(p)
	if puppet:
		p.set_puppet()
	p.configure("wolf", 20)
	p.global_position = Vector2.ZERO
	return p


func _enemy(pos: Vector2) -> _MockEnemy:
	var e := _MockEnemy.new()
	e.add_to_group("enemy")
	e.global_position = pos
	add_child_autofree(e)
	return e


# ── parity: shared behaviour identical legacy vs BT ───────────────────────────
func test_attacks_enemy_in_range(use_bt = use_parameters([false, true])) -> void:
	GameManager.use_bt_minions = use_bt
	var p := _pet()
	var e := _enemy(Vector2(40, 0))
	p._physics_process(0.05)
	assert_eq(e.hits.size(), 1, "attacked in melee (bt=%s)" % str(use_bt))


func test_chases_distant_enemy_outside_leap_band(use_bt = use_parameters([false, true])) -> void:
	GameManager.use_bt_minions = use_bt
	var p := _pet()
	_enemy(Vector2(400, 0))  # > LEAP_MAX (300) → plain chase, no pounce
	p._physics_process(0.05)
	assert_gt(p.velocity.x, 0.0, "chases toward distant enemy (bt=%s)" % str(use_bt))
	assert_eq(p._leap_t, 0.0, "no leap outside the band (bt=%s)" % str(use_bt))


func test_follows_owner_when_no_enemy(use_bt = use_parameters([false, true])) -> void:
	GameManager.use_bt_minions = use_bt
	var p := _pet()
	var owner := Node2D.new()
	owner.global_position = Vector2(400, 0)
	add_child_autofree(owner)
	p.owner_caster = owner
	p._physics_process(0.05)
	assert_gt(p.velocity.x, 0.0, "follows distant owner (bt=%s)" % str(use_bt))


func test_puppet_does_no_ai(use_bt = use_parameters([false, true])) -> void:
	GameManager.use_bt_minions = use_bt
	var p := _pet(true)
	var e := _enemy(Vector2(40, 0))
	p._physics_process(0.05)
	assert_eq(e.hits, [], "puppet never attacks (bt=%s)" % str(use_bt))


# ── pounce: BT-only mid-range leap ────────────────────────────────────────────
func test_wolf_pounces_on_mid_range_target() -> void:
	GameManager.use_bt_minions = true
	var p := _pet()
	_enemy(Vector2(200, 0))  # inside [LEAP_MIN 90, LEAP_MAX 300]
	p._physics_process(0.05)
	assert_gt(p._leap_t, 0.0, "wolf is mid-leap")
	assert_gt(p._leap_cd, 0.0, "leap put on cooldown")


func test_legacy_never_pounces() -> void:
	GameManager.use_bt_minions = false
	var p := _pet()
	_enemy(Vector2(200, 0))
	p._physics_process(0.05)
	assert_eq(p._leap_t, 0.0, "legacy path uses plain chase, no leap")
	assert_gt(p.velocity.x, 0.0, "it chases instead")


func test_pounce_carries_the_wolf_toward_the_enemy() -> void:
	GameManager.use_bt_minions = true
	var p := _pet()
	_enemy(Vector2(250, 0))
	await wait_seconds(0.4)  # auto physics drives the BT; the leap tween lands it
	assert_gt(p.global_position.x, 150.0, "pounced a long way toward the enemy")
