extends Node2D

# Second Funeral — Gravebinder (Necromancer) R. Marks the necromancer (and nearby
# allies in co-op) so they cannot die for 8s, granting a shield. Cheating death sets
# them to 1 HP (see player._try_cheat_death).

const DURATION: float = 8.0
const RADIUS: float = 260.0
const SHIELD_FRAC: float = 0.3

var visual_only: bool = false
var caster: Node2D = null


func setup_with_mods(_dir: Vector2, _dmg: int, mods: Dictionary) -> void:
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	var pos: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	if VfxManager:
		VfxManager.spawn_explosion(pos, 1.4, Color(0.5, 0.4, 0.8, 1))
	if not visual_only:
		var max_hp: float = float(GameManager.player_max_hp) if GameManager else 100.0
		# Always cover the caster; allies too in co-op.
		if caster and caster.has_method("grant_funeral"):
			caster.call("grant_funeral", DURATION)
			caster.call("add_shield", max_hp * SHIELD_FRAC, -1.0)
		var tree := get_tree()
		if tree:
			for a in tree.get_nodes_in_group("remote_player"):
				if not is_instance_valid(a) or not (a is Node2D):
					continue
				if pos.distance_to((a as Node2D).global_position) <= RADIUS and a.has_method("grant_funeral"):
					a.call("grant_funeral", DURATION)
					a.call("add_shield", max_hp * SHIELD_FRAC, -1.0)
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)
