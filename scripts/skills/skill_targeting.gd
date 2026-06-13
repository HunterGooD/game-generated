class_name SkillTargeting
extends RefCounted

# Shared enemy-targeting primitives for skill scenes.
#
# Before this, ~78 skill scripts hand-rolled near-identical loops over the
# "enemy" group (find nearest / collect within radius), each repeating the
# is_instance_valid + dead + distance boilerplate. These statics collapse the
# two dominant shapes; skill-specific filtering (cones, dot products, status
# application) layers on top of the returned set.
#
# Behaviour note: both helpers skip invalid AND dead enemies — the convention
# the large majority of call sites already used. A couple of call sites omitted
# the dead-check; routing them here gains that skip (corpses are despawned
# almost immediately, so this is a correctness nudge, not a balance change).

# Nearest live enemy to `from`, within `range_max`, excluding instance ids in
# `exclude` (keys = instance_id). Returns null if none qualify.
static func nearest(
	tree: SceneTree, from: Vector2, range_max: float = INF, exclude: Dictionary = {}
) -> Node2D:
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = range_max
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if not exclude.is_empty() and exclude.has(e.get_instance_id()):
			continue
		var d: float = from.distance_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e as Node2D
	return best


# All live enemies within `radius` of `from`, excluding instance ids in
# `exclude`. Order is group order (unspecified).
static func in_radius(
	tree: SceneTree, from: Vector2, radius: float, exclude: Dictionary = {}
) -> Array:
	var out: Array = []
	if tree == null:
		return out
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if not exclude.is_empty() and exclude.has(e.get_instance_id()):
			continue
		if from.distance_to((e as Node2D).global_position) <= radius:
			out.append(e)
	return out
