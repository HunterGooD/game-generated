extends Node2D

# Razor Trap — Assassin transform of Caltrops. A ground field that bleeds whatever
# steps on it (Assassins hit bleeding targets harder via their kit).

const LIFETIME: float = 6.0
const RADIUS: float = 110.0
const TICK: float = 0.6

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
		VfxManager.spawn_hit_sparks(global_position, Color(0.8, 0.2, 0.2, 1), 10)


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
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > RADIUS:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", damage, global_position)
		if e.has_method("apply_bleed"):
			e.call("apply_bleed", 4.0, float(damage) * 0.5)
