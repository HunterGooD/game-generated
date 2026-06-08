extends Node2D

# Grand Malediction — Curseweaver (Hexen) R. Curses every enemy in a wide radius
# (Armor Break + Bleed + a curse stack). Enemies that were already Hex-Marked
# detonate instantly for bonus damage.

const RADIUS: float = 300.0

var damage: int = 26
var visual_only: bool = false


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 2.0, Color(0.6, 0.1, 0.7, 1))
		VfxManager.screen_shake(5.0, 0.25)
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				if global_position.distance_to((e as Node2D).global_position) > RADIUS:
					continue
				if e.has_method("apply_vulnerable"):
					e.call("apply_vulnerable", 6.0, 0.25)
				if e.has_method("apply_bleed"):
					e.call("apply_bleed", 4.0, float(damage) * 0.2)
				if e.has_method("add_curse_stack"):
					e.call("add_curse_stack")
				# Already Hex-Marked → detonate now.
				if e.has_meta("hex_marked") and e.has_method("take_damage"):
					e.call("take_damage", int(round(float(damage) * 1.5)), global_position)
					e.set_meta("hex_marked", false)
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)
