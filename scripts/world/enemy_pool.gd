extends Node
## Object pool for enemies (autoload `EnemyPool`).
##
## Mass spawning (waves, brood bursts, elite packs) and the matching `queue_free` on
## death cause GC/instancing hitches. Instead we recycle enemy nodes: a dead enemy is
## reset and parked here (hidden, processing off, out of the "enemy" group) rather than
## freed; the next spawn reparents it back into the world and `configure()`s it afresh.
##
## Used on the host AND on client puppets (net_sync). Both go through acquire/release:
## death (`enemy._die` / `die_remote`) ends in `enemy._release_or_free()`, which calls
## back into `release()` when the enemy is pool-managed (`enemy._pool` set).

const ENEMY_SCENE: PackedScene = preload("res://scenes/entities/enemy.tscn")

# Idle (released) enemies, parented to this autoload, waiting to be handed back out.
var _free: Array = []
# Soft cap so a pathological run can't park thousands of idle nodes forever.
const MAX_IDLE: int = 64


# Hand out an enemy at `pos` parented under `parent` (defaults to the current scene).
# Caller should `configure()` it afterwards — reset_for_reuse wipes the previous life,
# configure re-applies stats/sprite/affixes.
func acquire(parent: Node = null, pos: Vector2 = Vector2.ZERO) -> Node:
	if parent == null:
		var tree := get_tree()
		parent = tree.current_scene if tree else null
	if parent == null:
		return null
	var node: Node = null
	while node == null and not _free.is_empty():
		var candidate = _free.pop_back()
		if is_instance_valid(candidate):
			node = candidate
	if node == null:
		node = ENEMY_SCENE.instantiate()  # first entry — add_child runs _ready (setup, groups)
	elif node.get_parent() != null:
		node.get_parent().remove_child(node)  # detach from the pool before reparenting
	parent.add_child(node)  # reused nodes do NOT re-run _ready
	if node is Node2D:
		(node as Node2D).global_position = pos
	node.process_mode = Node.PROCESS_MODE_INHERIT
	if node.has_method("reset_for_reuse"):
		node.call("reset_for_reuse")  # after positioning so _puppet_target_pos is right
	node.set("_pool", self)
	node.set("_release_done", false)  # cleared here (not in reset) — re-arms the death guard
	_attach_groups(node)
	return node


# Return a dead enemy to the pool: clean its state, pull it out of the world and the
# "enemy" group, and park it here. Over the soft cap → just free it.
func release(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("reset_for_reuse"):
		node.call("reset_for_reuse")
	_detach_groups(node)
	if node.get_parent():
		node.get_parent().remove_child(node)
	if _free.size() >= MAX_IDLE:
		node.queue_free()
		return
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	add_child(node)
	_free.append(node)


# Pre-instance `n` distinct enemies into the pool so the first wave doesn't hitch. Acquire
# them all first (each finds the pool empty → a new instance), then release them together —
# acquiring one at a time would just keep recycling the same node.
func prewarm(n: int, parent: Node = null) -> void:
	var temp: Array = []
	for i in n:
		var e := acquire(parent)
		if e:
			temp.append(e)
	for e in temp:
		release(e)


func idle_count() -> int:
	return _free.size()


func clear() -> void:
	for n in _free:
		if is_instance_valid(n):
			n.queue_free()
	_free.clear()


func _attach_groups(node: Node) -> void:
	node.add_to_group("enemy")
	var hb = node.get("hurtbox")
	if hb and is_instance_valid(hb):
		hb.add_to_group("enemy_hit")


func _detach_groups(node: Node) -> void:
	if node.is_in_group("enemy"):
		node.remove_from_group("enemy")
	var hb = node.get("hurtbox")
	if hb and is_instance_valid(hb) and hb.is_in_group("enemy_hit"):
		hb.remove_from_group("enemy_hit")
