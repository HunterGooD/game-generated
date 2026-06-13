extends Node2D

# Toxic Spikes — Venomancer transform of Caltrops. A trap field that poisons whatever
# stands in it; poisoned foes carry the venom outward as they move.

const LIFETIME: float = 6.0
const RADIUS: float = 120.0
const TICK: float = 0.7

var damage: int = 12
var visual_only: bool = false
var _life: float = LIFETIME
var _t: float = 0.0


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 3
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.5, 0.9, 0.3, 1), 10)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	var tree := get_tree()
	if tree == null:
		return
	for e in SkillTargeting.in_radius(tree, global_position, RADIUS):
		if e.has_method("apply_poison"):
			e.call("apply_poison", 1, 5.0, float(damage) * 0.3)
