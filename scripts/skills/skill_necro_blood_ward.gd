extends Node2D

# Blood Ward — Gravebinder transform of Blood Pact. Shields the nearest ally by
# sacrificing one of the necromancer's minions.

const RANGE: float = 320.0
const SHIELD_FRAC: float = 0.25

var visual_only: bool = false
var caster: Node2D = null


func setup_with_mods(_dir: Vector2, _dmg: int, mods: Dictionary) -> void:
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	var pos: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	if not visual_only:
		var max_hp: float = float(GameManager.player_max_hp) if GameManager else 100.0
		var ally: Node2D = _nearest_ally(pos)
		if ally == null and caster is Node2D:
			ally = caster as Node2D
		if ally and ally.has_method("add_shield"):
			ally.call("add_shield", max_hp * SHIELD_FRAC, -1.0)
		# Sacrifice one minion to power the ward.
		var tree := get_tree()
		if tree:
			for m in tree.get_nodes_in_group("necro_minion"):
				if is_instance_valid(m) and m.get("owner_caster") == caster:
					if m.has_method("queue_free"):
						m.queue_free()
					break
	if VfxManager:
		VfxManager.spawn_hit_sparks(pos, Color(0.7, 0.1, 0.3, 1), 10)
	var t := get_tree().create_timer(0.3)
	t.timeout.connect(queue_free)


func _nearest_ally(from: Vector2) -> Node2D:
	var best: Node2D = null
	var bd: float = RANGE
	for rp in get_tree().get_nodes_in_group("remote_player"):
		if not is_instance_valid(rp) or not (rp is Node2D):
			continue
		var d: float = from.distance_to((rp as Node2D).global_position)
		if d < bd:
			bd = d
			best = rp
	return best
