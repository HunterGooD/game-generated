extends Node2D

# Rally Pulse — Deathlord transform of Death Pulse. A command shock that damages
# enemies and heals the necromancer's minions around the caster.

const RADIUS: float = 200.0

var damage: int = 24
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
		VfxManager.spawn_explosion(pos, 1.4, Color(0.6, 0.4, 0.9, 1))
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				if pos.distance_to((e as Node2D).global_position) <= RADIUS and e.has_method("take_damage"):
					e.call("take_damage", damage, pos)
			for m in tree.get_nodes_in_group("necro_minion"):
				if not is_instance_valid(m) or not (m is Node2D):
					continue
				if pos.distance_to((m as Node2D).global_position) <= RADIUS:
					var mhp: int = int(m.get("hp"))
					var mmax: int = int(m.get("max_hp"))
					m.set("hp", mini(mmax, mhp + int(round(float(mmax) * 0.25))))
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)
