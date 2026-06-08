extends Node2D

# Energizing Discharge — Conductor transform of Static Discharge. Damages enemies and
# restores mana to nearby allies.

const RADIUS: float = 150.0

var damage: int = 22
var visual_only: bool = false
var caster: Node2D = null


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	var pos: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	global_position = pos
	if VfxManager:
		VfxManager.spawn_explosion(pos, 1.1, Color(0.6, 0.85, 1.0, 1))
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				if pos.distance_to((e as Node2D).global_position) <= RADIUS:
					if e.has_method("take_damage"):
						e.call("take_damage", damage, pos)
					if e.has_method("mark_element"):
						e.call("mark_element", "storm")
		# Local player mana refund (allies regen their own).
		if GameManager and GameManager.has_method("regen_mana"):
			GameManager.regen_mana(20.0)
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)
