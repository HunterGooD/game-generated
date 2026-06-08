extends Node2D

# Hide of the Beast — Primal Alpha transform of Stone Armor. Grants a one-hit ward
# (reusing the Stone Armor absorb) plus a brief burst of speed.

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
	if not visual_only and caster:
		var cur: int = int(caster.get("stone_armor_charges")) if caster.has_method("get") else 0
		caster.set("stone_armor_charges", maxi(cur, 2))
		if caster.has_method("apply_buff"):
			caster.call("apply_buff", 6.0, 1.0, 1.3)
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.8, 0.7, 0.5, 1), 12)
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)
