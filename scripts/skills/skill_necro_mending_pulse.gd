extends Node2D

# Mending Pulse — Gravebinder transform of Death Pulse. Damages enemies and shields
# allies in range (scaling with how many foes were struck).

const RADIUS: float = 200.0

var damage: int = 20
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
		VfxManager.spawn_explosion(pos, 1.3, Color(0.5, 0.8, 0.6, 1))
	if not visual_only:
		var tree := get_tree()
		var hits: int = 0
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				if pos.distance_to((e as Node2D).global_position) <= RADIUS and e.has_method("take_damage"):
					e.call("take_damage", damage, pos)
					hits += 1
			var shield: float = float(damage) * (0.5 + 0.3 * float(hits))
			for grp in ["player", "remote_player"]:
				for a in tree.get_nodes_in_group(grp):
					if not is_instance_valid(a) or not (a is Node2D):
						continue
					if pos.distance_to((a as Node2D).global_position) <= RADIUS and a.has_method("add_shield"):
						a.call("add_shield", shield, -1.0)
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)
