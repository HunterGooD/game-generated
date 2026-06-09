extends GutTest

# Commander's Mark (Deathlord): the necromancer marks the enemy under their cursor and
# their minions focus-fire it (forced-target override at acquisition). No mark → normal
# nearest-enemy behaviour. The override is generic (any owner with get_marked_target),
# the hook future mark mechanics (mark-throwing enemy, player draw-attention) plug into.

const MINION_SCENE := "res://scenes/entities/necro_minion.tscn"
const PLAYER_SCENE := "res://scenes/entities/player.tscn"


class _MockOwner:
	extends Node2D
	var mark: Node2D = null
	func get_marked_target() -> Node2D:
		return mark


class _MockEnemy:
	extends Node2D
	var dead: bool = false


func after_each() -> void:
	GameManager.player_spec_path = ""


func _minion() -> CharacterBody2D:
	var m: CharacterBody2D = (load(MINION_SCENE) as PackedScene).instantiate()
	add_child_autofree(m)
	m.configure("skeleton", 20)
	m.global_position = Vector2.ZERO
	return m


func _enemy(pos: Vector2) -> _MockEnemy:
	var e := _MockEnemy.new()
	e.add_to_group("enemy")
	e.global_position = pos
	add_child_autofree(e)
	return e


# ── minion-side override (works for BT and legacy — both call bt_acquire_target) ──
func test_minion_focuses_owner_mark_over_nearest() -> void:
	var m := _minion()
	var near := _enemy(Vector2(50, 0))
	var far := _enemy(Vector2(300, 0))  # within detection*1.5, but not the nearest
	var owner := _MockOwner.new()
	add_child_autofree(owner)
	m.owner_caster = owner
	owner.mark = far
	assert_eq(m.bt_acquire_target(), far, "minion focuses the marked target, not the nearest")


func test_minion_falls_back_to_nearest_without_mark() -> void:
	var m := _minion()
	var near := _enemy(Vector2(50, 0))
	_enemy(Vector2(300, 0))
	var owner := _MockOwner.new()
	add_child_autofree(owner)
	m.owner_caster = owner
	owner.mark = null
	assert_eq(m.bt_acquire_target(), near, "no mark → nearest enemy (normal behaviour)")


func test_minion_ignores_mark_across_the_map() -> void:
	var m := _minion()
	var near := _enemy(Vector2(50, 0))
	var owner := _MockOwner.new()
	add_child_autofree(owner)
	m.owner_caster = owner
	owner.mark = _enemy(Vector2(5000, 0))  # well beyond detection*1.5 → not honored
	assert_eq(m.bt_acquire_target(), near, "out-of-range mark → falls back to nearest")


# ── player-side marking (Deathlord only) ──────────────────────────────────────
func _player() -> Node2D:
	var p: Node2D = (load(PLAYER_SCENE) as PackedScene).instantiate()
	add_child_autofree(p)
	p.set_physics_process(false)
	p.set_process(false)
	return p


func test_deathlord_marks_enemy_under_cursor() -> void:
	var p := _player()
	GameManager.player_spec_path = "deathlord"
	var e := _enemy(p.get_global_mouse_position())  # right at the aim point
	p._update_commanders_mark()
	assert_eq(p.get_marked_target(), e, "Deathlord marks the aimed-at enemy")


func test_non_deathlord_has_no_mark() -> void:
	var p := _player()
	GameManager.player_spec_path = "berserker"
	_enemy(p.get_global_mouse_position())
	p._update_commanders_mark()
	assert_null(p.get_marked_target(), "non-Deathlord never marks")
