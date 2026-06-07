class_name EnemyAIComponent
extends Node

# Target acquisition for enemies. Scans the configured target groups for the
# nearest valid combatant, applying the standard co-op / visibility filters:
# remote-player puppets are skipped (the host targets the real player), and
# stealthed, airborne, or dead targets are ignored. The owning enemy keeps its
# own movement / attack logic — this component only answers "who do I target?".

@export var target_groups: Array[String] = ["player", "pet_ally"]


# Nearest valid target to `from_pos`, or null when nothing qualifies. Callers
# typically keep their previous target when this returns null (avoids enemies
# freezing for a frame while a fresh target spawns).
func find_nearest_target(from_pos: Vector2) -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = INF
	for grp in target_groups:
		for n in tree.get_nodes_in_group(grp):
			if not _is_valid_target(n):
				continue
			var d: float = from_pos.distance_to((n as Node2D).global_position)
			if d < best_d:
				best_d = d
				best = n as Node2D
	return best


# Every target within `radius` of `center`. Used by AOE attacks, which hit
# stealthed/low-hp targets too — so this only filters remote puppets and
# (optionally) airborne targets, not the full valid-target predicate.
func gather_targets_in_radius(center: Vector2, radius: float, ignore_airborne: bool = true) -> Array:
	var result: Array = []
	var tree := get_tree()
	if tree == null:
		return result
	for grp in target_groups:
		for n in tree.get_nodes_in_group(grp):
			if not is_instance_valid(n):
				continue
			if n.is_in_group("remote_player"):
				continue
			if ignore_airborne and n.is_in_group("airborne"):
				continue
			if center.distance_to((n as Node2D).global_position) <= radius:
				result.append(n)
	return result


func _is_valid_target(n: Node) -> bool:
	if not is_instance_valid(n):
		return false
	# Co-op: the host's enemies DO target remote players (the other party
	# members) — but not while they're downed or dead.
	if n.get("is_downed") == true or n.get("is_dead") == true:
		return false
	if n.is_in_group("airborne") or n.is_in_group("stealthed"):
		return false
	if n.get("dead") == true:
		return false
	if n.get("hp") != null and int(n.get("hp")) <= 0:
		return false
	return true
