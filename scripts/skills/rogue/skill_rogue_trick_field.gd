extends Node2D

# Trick Field — Trickster transform of Caltrops. Warped ground: enemies are slowed,
# allies passing through are hastened (brief move-speed via the dome buff hook).

const LIFETIME: float = 6.0
const RADIUS: float = 130.0

var visual_only: bool = false
var _life: float = LIFETIME


func setup_context(ctx: SkillContext) -> void:
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 3
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.6, 0.8, 1.0, 1), 8)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	var tree := get_tree()
	if tree == null:
		return
	for e in SkillTargeting.in_radius(tree, global_position, RADIUS):
		if e.has_method("apply_slow"):
			e.call("apply_slow", 0.4, 0.5)
	for grp in ["player", "remote_player"]:
		for a in tree.get_nodes_in_group(grp):
			if not is_instance_valid(a) or not (a is Node2D):
				continue
			if global_position.distance_to((a as Node2D).global_position) <= RADIUS and a.has_method("enter_dome"):
				a.call("enter_dome", 0.3)
