extends GutTest

# Parity net for the necromancer minion's host-side AI. The behaviour tests run with
# the LimboAI flag BOTH off (legacy state machine) and on (behaviour tree): identical
# observable behaviour proves the BT is a faithful drop-in. Acquisition-helper and
# puppet tests are flag-independent.

const MINION_SCENE := "res://scenes/entities/necro_minion.tscn"


class _MockEnemy:
	extends Node2D
	var dead: bool = false
	var hits: Array = []
	func take_damage(d, _s) -> void:
		hits.append(d)


func after_each() -> void:
	GameManager.use_bt_minions = false


func _minion(puppet := false) -> CharacterBody2D:
	var m: CharacterBody2D = (load(MINION_SCENE) as PackedScene).instantiate()
	add_child_autofree(m)
	if puppet:
		m.set_puppet()
	m.configure("skeleton", 20)
	m.global_position = Vector2.ZERO
	return m


func _enemy(pos: Vector2, dead := false) -> _MockEnemy:
	var e := _MockEnemy.new()
	e.dead = dead
	e.add_to_group("enemy")
	e.global_position = pos
	add_child_autofree(e)
	return e


# ── flag-independent acquisition helper (shared by legacy + BT) ───────────────
func test_finds_nearest_live_enemy() -> void:
	var m := _minion()
	_enemy(Vector2(300, 0))
	var near := _enemy(Vector2(120, 0))
	_enemy(Vector2(80, 0), true)  # dead — ignored
	assert_eq(m._find_nearest_enemy(), near, "picks nearest LIVE enemy")


func test_ignores_enemies_beyond_detection_range() -> void:
	var m := _minion()
	_enemy(Vector2(900, 0))  # > DETECTION_RANGE (520)
	assert_null(m._find_nearest_enemy())


# ── parity behaviour (legacy AND behaviour-tree) ──────────────────────────────
func test_attacks_enemy_in_range(use_bt = use_parameters([false, true])) -> void:
	GameManager.use_bt_minions = use_bt
	var m := _minion()
	var e := _enemy(Vector2(40, 0))  # within ATTACK_RANGE (60)
	m._physics_process(0.1)
	assert_eq(e.hits.size(), 1, "attacked in-range enemy (bt=%s)" % str(use_bt))
	assert_gt(m.attack_cd, 0.0, "attack on cooldown (bt=%s)" % str(use_bt))


func test_chases_enemy_out_of_range(use_bt = use_parameters([false, true])) -> void:
	GameManager.use_bt_minions = use_bt
	var m := _minion()
	_enemy(Vector2(300, 0))  # beyond attack range, within detection
	m._physics_process(0.1)
	assert_gt(m.velocity.length(), 0.0, "moving toward target (bt=%s)" % str(use_bt))
	assert_gt(m.velocity.x, 0.0, "moving toward +x enemy (bt=%s)" % str(use_bt))


func test_follows_owner_when_no_enemy(use_bt = use_parameters([false, true])) -> void:
	GameManager.use_bt_minions = use_bt
	var m := _minion()
	var owner := Node2D.new()
	owner.global_position = Vector2(400, 0)
	add_child_autofree(owner)
	m.owner_caster = owner
	m._physics_process(0.1)
	assert_gt(m.velocity.x, 0.0, "moves toward distant owner (bt=%s)" % str(use_bt))


# ── puppet never runs AI (host owns it), regardless of flag ───────────────────
func test_puppet_does_no_ai(use_bt = use_parameters([false, true])) -> void:
	GameManager.use_bt_minions = use_bt
	var m := _minion(true)
	var e := _enemy(Vector2(40, 0))
	m._physics_process(0.1)
	assert_eq(e.hits, [], "puppet must not attack (bt=%s)" % str(use_bt))
