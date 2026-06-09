class_name RunState
extends RefCounted

## Live traversal state over a generated RunMap: where the party currently is, where it
## may go next, and what it has visited. Pure logic (no scene/autoload deps) so it is
## fully unit-testable; GameManager owns one instance and adds the host-authority gate +
## co-op replication on top.

var map: RunMap.RunMapData = null
# Current node id, or -1 when the party is at the entry gate (hasn't entered any node yet).
var current_id: int = -1
var visited: Dictionary = {}  # node id -> true


func _init(m: RunMap.RunMapData = null) -> void:
	map = m


func is_active() -> bool:
	return map != null


# Node ids the party may travel to right now. At the entry gate that's the whole entry
# row; otherwise it's the current node's outgoing edges (minus the boss once beaten).
func reachable() -> Array:
	if map == null:
		return []
	if current_id < 0:
		return map.start_ids()
	return (map.node_by_id(current_id).get("next", []) as Array).duplicate()


func can_travel(id: int) -> bool:
	return id in reachable()


# Move to `id` if it's a legal next step. Returns false (no state change) otherwise.
func travel(id: int) -> bool:
	if not can_travel(id):
		return false
	current_id = id
	visited[id] = true
	return true


func current_node() -> Dictionary:
	if map == null or current_id < 0:
		return {}
	return map.node_by_id(current_id)


func is_at_boss() -> bool:
	return map != null and current_id >= 0 and current_id == map.boss_id()


# The run is finished once the party has reached (and thus fought) the boss node.
func is_complete() -> bool:
	return is_at_boss()


func visited_count() -> int:
	return visited.size()
