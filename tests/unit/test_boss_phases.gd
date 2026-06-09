extends GutTest

# Boss phase system. Single-phase bosses (crimson_matron, shadewitch) now synthesize
# escalating "enrage" phases that speed up attacks (and move speed) as HP drops, while
# authored multi-phase bosses (hellgate_sovereign, lich_empress) keep their data
# unchanged. The phase dict is the extension point for future per-phase skills/attacks.

const BOSS_SCENE := "res://scenes/entities/boss.tscn"

var _container: Node2D = null
var _prev_scene: Node = null


# Boss attacks spawn telegraphs/projectiles into current_scene (null under GUT).
func before_each() -> void:
	_prev_scene = get_tree().current_scene
	_container = Node2D.new()
	get_tree().root.add_child(_container)
	get_tree().current_scene = _container
	var p := Node2D.new()  # a target so dispatched attacks resolve
	p.add_to_group("player")
	p.global_position = Vector2(200, 0)
	_container.add_child(p)


func after_each() -> void:
	get_tree().current_scene = _prev_scene
	if is_instance_valid(_container):
		_container.free()


func _boss(id: String) -> Node:
	var b: Node = (load(BOSS_SCENE) as PackedScene).instantiate()
	add_child_autofree(b)
	b.configure(id, 1)
	return b


func test_single_phase_boss_synthesizes_escalation() -> void:
	var b := _boss("crimson_matron")
	assert_eq(b.phases.size(), 3, "single-phase boss gets 3 escalation phases")
	var first := float((b.phases[0] as Dictionary).get("attack_speed_mult", 1.0))
	var last := float((b.phases[2] as Dictionary).get("attack_speed_mult", 1.0))
	assert_gt(last, first, "later phase attacks faster")


func test_multiphase_boss_keeps_authored_phases() -> void:
	var b := _boss("hellgate_sovereign")
	assert_eq(b.phases.size(), 3, "authored phases preserved")
	assert_almost_eq(b._phase_attack_speed_mult, 1.0, 0.001, "authored bosses get no synthetic speedup")


func test_phase_advances_and_speeds_up_at_low_hp() -> void:
	var b := _boss("crimson_matron")
	assert_eq(b.current_phase_idx, 0)
	var base_speed: float = b.move_speed
	b.hp = int(round(float(b.max_hp) * 0.3))
	b._maybe_advance_phase()
	assert_gt(b.current_phase_idx, 0, "advanced phase at low HP")
	assert_gt(b._phase_attack_speed_mult, 1.0, "attacks sped up")
	assert_gt(b.move_speed, base_speed, "moves faster in the enrage phase")


func test_attacks_fire_sooner_in_later_phase() -> void:
	var b := _boss("crimson_matron")
	b.attack_idx = 0
	b._fire_next_attack()
	var t0: float = b.attack_t
	b.hp = int(round(float(b.max_hp) * 0.2))
	b._maybe_advance_phase()
	b._fire_next_attack()
	var t2: float = b.attack_t
	assert_lt(t2, t0, "enrage phase fires the next attack sooner")
