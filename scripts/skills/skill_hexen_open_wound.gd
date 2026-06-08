extends Node2D

# Open Wound — Blood Witch transform of Hex Mark. Marks the target so it takes
# extra damage (Armor Break) and counts as cursed/hex-marked for the kit.

const SEEK_RADIUS: float = 160.0

var damage: int = 14
var visual_only: bool = false


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	if not visual_only:
		var target: Node2D = _nearest()
		if target:
			if target.has_method("take_damage"):
				target.call("take_damage", damage, global_position)
			if target.has_method("apply_vulnerable"):
				target.call("apply_vulnerable", 6.0, 0.3)
			if target.has_method("add_curse_stack"):
				target.call("add_curse_stack")
			target.set_meta("hex_marked", true)
			if VfxManager:
				VfxManager.spawn_hit_sparks(target.global_position, Color(0.8, 0.1, 0.2, 1), 8)
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
