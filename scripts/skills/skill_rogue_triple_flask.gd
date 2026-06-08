extends Node2D

# Triple Flask — Venomancer transform of Poison Vial. Lobs three flasks in a fan;
# each bursts for a little damage and a poison stack.

const RADIUS: float = 90.0

var damage: int = 16
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false


func setup_with_mods(dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 5
	var center: Vector2 = global_position + direction * 120.0
	for off in [-0.35, 0.0, 0.35]:
		var spot: Vector2 = global_position + direction.rotated(off) * 130.0
		if VfxManager:
			VfxManager.spawn_explosion(spot, 0.7, Color(0.4, 0.8, 0.2, 1))
		if not visual_only:
			_burst(spot)
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)


func _burst(spot: Vector2) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if spot.distance_to((e as Node2D).global_position) > RADIUS:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", damage, spot)
		if e.has_method("apply_poison"):
			e.call("apply_poison", 2, 4.0, float(damage) * 0.2)
