extends Node2D

# Vanish — Assassin transform of Smoke Bomb. Brief invisibility; the next attack
# auto-crits, and the Backstab Window opens.

const STEALTH_TIME: float = 1.5

var visual_only: bool = false
var caster: Node2D = null


func setup_with_mods(_dir: Vector2, _dmg: int, mods: Dictionary) -> void:
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	if caster is Node2D:
		global_position = (caster as Node2D).global_position
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.5, 0.5, 0.6, 1), 16)
	if not visual_only and caster:
		if caster.has_method("apply_stealth"):
			caster.call("apply_stealth", STEALTH_TIME)
		if caster.has_method("start_backstab"):
			caster.call("start_backstab", 2.0)
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(queue_free)
