extends GutTest

# Enemy host-AI behaviour trees. Melee + ranged replicate the existing in-detection
# mode decisions (parity, flag off AND on). Spider is a NEW hit-and-run archetype.
# Co-op-safe: BT runs host-only; puppets / idle / no-target / AOE stay legacy. The
# tests set enemy.player directly and block retargeting so the decision is isolated.

const ENEMY_SCENE := "res://scenes/entities/enemy.tscn"


class _MockPlayer:
	extends Node2D
	var is_downed: bool = false
	var is_dead: bool = false
	func take_damage(_a, _b = null) -> void:
		pass
	func receive_damage_payload(_p) -> bool:
		return false


var _container: Node2D = null
var _prev_scene: Node = null


# Ranged attacks spawn a projectile into get_tree().current_scene (null under GUT) —
# stand up a container so that code path runs.
func before_each() -> void:
	_prev_scene = get_tree().current_scene
	_container = Node2D.new()
	get_tree().root.add_child(_container)
	get_tree().current_scene = _container


func after_each() -> void:
	GameManager.use_bt_enemies = false
	get_tree().current_scene = _prev_scene
	if is_instance_valid(_container):
		_container.free()


func _enemy(cfg: Dictionary = {}) -> CharacterBody2D:
	var e: CharacterBody2D = (load(ENEMY_SCENE) as PackedScene).instantiate()
	add_child_autofree(e)
	e.configure(cfg)
	e.global_position = Vector2.ZERO
	return e


func _target_at(e: CharacterBody2D, pos: Vector2) -> _MockPlayer:
	var p := _MockPlayer.new()
	p.add_to_group("player")
	p.global_position = pos
	add_child_autofree(p)
	e.player = p
	e.retarget_t = 1.0  # don't re-acquire during the tested tick
	return p


# ── melee parity (legacy AND BT) ──────────────────────────────────────────────
func test_melee_chases_distant_player(use_bt = use_parameters([false, true])) -> void:
	GameManager.use_bt_enemies = use_bt
	var e := _enemy()
	_target_at(e, Vector2(200, 0))
	e._physics_process(0.05)
	assert_gt(e.velocity.x, 0.0, "chases toward player (bt=%s)" % str(use_bt))


func test_melee_attacks_in_range(use_bt = use_parameters([false, true])) -> void:
	GameManager.use_bt_enemies = use_bt
	var e := _enemy()
	_target_at(e, Vector2(35, 0))
	e.attack_cd = 0.0
	e.attack_lockout = 0.0
	e._physics_process(0.05)
	assert_gt(e.attack_cd, 0.0, "attacked in melee range (bt=%s)" % str(use_bt))
	assert_almost_eq(e.velocity.length(), 0.0, 1.0, "holds while attacking (bt=%s)" % str(use_bt))


# ── ranged kite parity (legacy AND BT) ────────────────────────────────────────
func _ranged_enemy() -> CharacterBody2D:
	return _enemy({"ranged": true, "attack_range": 250.0, "kite_distance": 200.0})


func test_ranged_retreats_when_too_close(use_bt = use_parameters([false, true])) -> void:
	GameManager.use_bt_enemies = use_bt
	var e := _ranged_enemy()
	_target_at(e, Vector2(120, 0))  # < kite-30 (170) → back away
	e._physics_process(0.05)
	assert_lt(e.velocity.x, 0.0, "retreats from a too-close target (bt=%s)" % str(use_bt))


func test_ranged_approaches_when_too_far(use_bt = use_parameters([false, true])) -> void:
	GameManager.use_bt_enemies = use_bt
	var e := _ranged_enemy()
	_target_at(e, Vector2(300, 0))  # > kite+30 (230) → close in
	e._physics_process(0.05)
	assert_gt(e.velocity.x, 0.0, "approaches a too-far target (bt=%s)" % str(use_bt))


func test_ranged_holds_and_fires_in_band(use_bt = use_parameters([false, true])) -> void:
	GameManager.use_bt_enemies = use_bt
	var e := _ranged_enemy()
	_target_at(e, Vector2(200, 0))  # in the kite band, within attack_range
	e.attack_cd = 0.0
	e.attack_lockout = 0.0
	e._physics_process(0.05)
	assert_gt(e.attack_cd, 0.0, "fired a ranged attack (bt=%s)" % str(use_bt))
	assert_almost_eq(e.velocity.length(), 0.0, 1.0, "holds in the band (bt=%s)" % str(use_bt))


# ── spider hit-and-run (BT-only new behaviour) ────────────────────────────────
func _spider_enemy() -> CharacterBody2D:
	return _enemy({"spider": true, "attack_range": 60.0, "attack_cooldown": 1.0})


func test_spider_bites_then_scuttles_away() -> void:
	GameManager.use_bt_enemies = true
	var e := _spider_enemy()
	_target_at(e, Vector2(40, 0))  # in melee range
	e.attack_cd = 0.0
	e.attack_lockout = 0.0
	e._physics_process(0.05)  # bite
	assert_gt(e.attack_cd, 0.0, "bit the target")
	assert_gt(e._spider_retreat_t, 0.0, "opened a retreat window")
	e._physics_process(0.05)  # now retreating
	assert_lt(e.velocity.x, 0.0, "scuttles away from the target after the bite")


func test_spider_approaches_between_bites() -> void:
	GameManager.use_bt_enemies = true
	var e := _spider_enemy()
	_target_at(e, Vector2(200, 0))  # out of melee, not retreating
	e._physics_process(0.05)
	assert_gt(e.velocity.x, 0.0, "closes in on a distant target")


func test_spider_bites_after_approaching_into_range() -> void:
	# Regression: a plain BTSelector latches on the RUNNING Approach and never
	# re-checks Bite (spider chases into the player but never attacks/retreats). A
	# BTDynamicSelector re-evaluates each tick, so it bites once it reaches melee.
	GameManager.use_bt_enemies = true
	var e := _spider_enemy()
	var p := _target_at(e, Vector2(200, 0))  # start far → Approach runs (RUNNING)
	e._physics_process(0.05)
	assert_eq(e.attack_cd, 0.0, "no bite while still out of range")
	e.global_position = p.global_position - Vector2(20, 0)  # now in melee range
	e.attack_cd = 0.0
	e.attack_lockout = 0.0
	e._physics_process(0.05)
	assert_gt(e.attack_cd, 0.0, "bites once it reaches melee range")
	assert_gt(e._spider_retreat_t, 0.0, "opens the retreat window after biting")


func test_spider_falls_back_to_melee_when_flag_off() -> void:
	GameManager.use_bt_enemies = false
	var e := _spider_enemy()
	_target_at(e, Vector2(40, 0))
	e.attack_cd = 0.0
	e.attack_lockout = 0.0
	e._physics_process(0.05)
	assert_gt(e.attack_cd, 0.0, "legacy path melee-attacks")
	assert_eq(e._spider_retreat_t, 0.0, "legacy path never opens a retreat window")
