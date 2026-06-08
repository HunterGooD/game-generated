extends Node2D

# Rotating Hex — Curseweaver transform of Hex Mark. A heavier mark: Armor Break +
# curse + the hex_marked flag (so the Curseweaver's detonations chain off it).

const SEEK_RADIUS: float = 180.0

var damage: int = 16
var visual_only: bool = false


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	if not visual_only:
		var target: Node2D = _nearest()
		if target:
			if target.has_method("take_damage"):
				target.call("take_damage", damage, global_position)
			if target.has_method("apply_vulnerable"):
				target.call("apply_vulnerable", 8.0, 0.35)
			if target.has_method("add_curse_stack"):
				target.call("add_curse_stack")
			target.set_meta("hex_marked", true)
			if VfxManager:
				VfxManager.spawn_hit_sparks(target.global_position, Color(0.7, 0.1, 0.7, 1), 8)
	var t := get_tree().create_timer(0.3)
	t.timeout.connect(queue_free)


func _nearest() -> Node2D:
	var best: Node2D = null
	var bd: float = SEEK_RADIUS
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d < bd:
			bd = d
			best = e
	return best
