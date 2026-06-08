extends Node2D

# Bone Nova — Bone Architect transform of Death Pulse. Erupts bone spikes in all
# directions, damaging every enemy in a wide radius.

const RADIUS: float = 230.0

var damage: int = 26
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
		VfxManager.spawn_explosion(pos, 1.6, Color(0.85, 0.8, 0.7, 1))
		VfxManager.screen_shake(5.0, 0.2)
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				if pos.distance_to((e as Node2D).global_position) <= RADIUS and e.has_method("take_damage"):
					e.call("take_damage", damage, pos)
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)
