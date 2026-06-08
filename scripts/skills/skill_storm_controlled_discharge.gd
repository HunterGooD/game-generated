extends Node2D

# Controlled Discharge — Tempest Lord transform of Static Discharge. A precise zap at
# the aim point that statics and slightly slows.

const RADIUS: float = 140.0

var damage: int = 22
var visual_only: bool = false


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.1, Color(0.6, 0.8, 1.0, 1))
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				if global_position.distance_to((e as Node2D).global_position) > RADIUS:
					continue
				if e.has_method("take_damage"):
					e.call("take_damage", damage, global_position)
				if e.has_method("apply_slow"):
					e.call("apply_slow", 1.5, 0.6)
				if e.has_method("mark_element"):
					e.call("mark_element", "storm")
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)
