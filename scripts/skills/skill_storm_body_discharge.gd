extends Node2D

# Body Discharge — Thunderblade transform of Static Discharge. The discharge erupts
# from the hero: tighter radius, heavier damage.

const RADIUS: float = 130.0

var damage: int = 30
var visual_only: bool = false
var caster: Node2D = null


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = int(round(float(dmg) * 1.25))
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	var pos: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	global_position = pos
	if VfxManager:
		VfxManager.spawn_explosion(pos, 1.2, Color(0.7, 0.85, 1.0, 1))
		VfxManager.screen_shake(5.0, 0.2)
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				if pos.distance_to((e as Node2D).global_position) > RADIUS:
					continue
				if e.has_method("take_damage"):
					e.call("take_damage", damage, pos)
				if e.has_method("mark_element"):
					e.call("mark_element", "storm")
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)
