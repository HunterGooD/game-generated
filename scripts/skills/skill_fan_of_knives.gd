extends Node2D

# Fan of Knives — throw 8 daggers in radial pattern from the caster.

const DAGGER_SCENE: PackedScene = preload("res://scenes/combat/player/thrown_dagger.tscn")
const DAGGER_COUNT: int = 8

var damage: int = 14
var caster_ref: Node = null


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	caster_ref = mods.get("caster", null) if mods != null else null


func _ready() -> void:
	var venomweave: bool = InventorySystem != null and InventorySystem.has_unique("venomweave")
	for i in DAGGER_COUNT:
		var angle: float = (float(i) / float(DAGGER_COUNT)) * TAU
		var dir: Vector2 = Vector2.RIGHT.rotated(angle)
		var d := DAGGER_SCENE.instantiate()
		d.position = global_position + dir * 28.0
		if d.has_method("setup_with_mods"):
			d.call("setup_with_mods", dir, damage, {"caster": caster_ref})
		elif d.has_method("setup"):
			d.call("setup", dir, damage)
		if venomweave and d.has_method("set_meta"):
			d.set_meta("venomweave", true)
		get_tree().current_scene.add_child(d)
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(1.0, 0.8, 0.6, 1), 8)
	queue_free()
