extends Node2D

# Confusion Flask — Trickster transform of Poison Vial. Enemies in the splash turn
# on each other: each confused foe is taunted toward another nearby enemy.

const RADIUS: float = 150.0
const CONFUSE_TIME: float = 4.0

var visual_only: bool = false


func setup_with_mods(_dir: Vector2, _dmg: int, mods: Dictionary) -> void:
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 5
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.0, Color(0.7, 0.5, 1.0, 1))
	if not visual_only:
		var tree := get_tree()
		if tree:
			var nearby: Array = []
			for e in tree.get_nodes_in_group("enemy"):
				if is_instance_valid(e) and not bool(e.get("dead")) and global_position.distance_to((e as Node2D).global_position) <= RADIUS:
					nearby.append(e)
			for e in nearby:
				var other: Node2D = _other_than(e, nearby)
				if other and e.has_method("apply_taunt"):
					e.call("apply_taunt", other, CONFUSE_TIME)
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)


func _other_than(self_e, pool: Array) -> Node2D:
	for o in pool:
		if o != self_e and is_instance_valid(o):
			return o as Node2D
	return null
