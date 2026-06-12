extends Node2D

# Frost Nova — talent transform of Ice Bolt: an instant frost burst around the
# caster that damages and slows every enemy in the ring. The ib_slow modifier
# keeps working on the transformed skill (wired in as slow_stacks).

const BASE_RADIUS: float = 220.0
const BASE_SLOW_DURATION: float = 2.5
const BASE_SLOW_MULT: float = 0.45

var damage: int = 20
var slow_duration: float = BASE_SLOW_DURATION
var slow_mult: float = BASE_SLOW_MULT
var _visual_only: bool = false


func setup_context(ctx: SkillContext) -> void:
	damage = ctx.damage
	_visual_only = ctx.is_visual_only
	var slow_stacks: int = int(ctx.get_mod("slow_stacks", 0))
	slow_duration = BASE_SLOW_DURATION + 1.5 * float(slow_stacks)
	slow_mult = max(0.2, BASE_SLOW_MULT - 0.08 * float(slow_stacks))


func _ready() -> void:
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.5, Color(0.55, 0.8, 1.0, 1))
		VfxManager.screen_shake(5.0, 0.2)
	# Damage only on the caster's machine (visual-only copies just show the VFX).
	if not _visual_only:
		_damage_ring()
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)


func _damage_ring() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var ep: Vector2 = (e as Node2D).global_position
		if global_position.distance_to(ep) > BASE_RADIUS:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", damage, global_position)
		if e.has_method("mark_element"):
			e.call("mark_element", "frost")
		if e.has_method("apply_slow"):
			e.call("apply_slow", slow_duration, slow_mult)
