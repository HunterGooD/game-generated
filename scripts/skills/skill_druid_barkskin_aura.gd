extends Node2D

# Barkskin Aura — Grovekeeper transform of Stone Armor. The druid's bark hardens and
# spreads: a one-hit ward for the druid plus damage reduction for nearby allies.

const RADIUS: float = 240.0

var visual_only: bool = false
var caster: Node2D = null


func setup_with_mods(_dir: Vector2, _dmg: int, mods: Dictionary) -> void:
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	var pos: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	global_position = pos
	if not visual_only and caster:
		var cur: int = int(caster.get("stone_armor_charges")) if caster.has_method("get") else 0
		caster.set("stone_armor_charges", maxi(cur, 1))
		var tree := get_tree()
		if tree:
			for a in tree.get_nodes_in_group("remote_player"):
				if not is_instance_valid(a) or not (a is Node2D):
					continue
				if pos.distance_to((a as Node2D).global_position) <= RADIUS and a.has_method("apply_aura"):
					a.call("apply_aura", 1.0, 0.15, 8.0)
	if VfxManager:
		VfxManager.spawn_explosion(pos, 1.1, Color(0.5, 0.7, 0.4, 1))
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)
