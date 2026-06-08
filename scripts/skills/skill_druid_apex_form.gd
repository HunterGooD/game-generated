extends Node2D

# Apex Form — Primal Alpha (Druid) R. For 18s the druid takes a hybrid predator
# shape, sharply empowering its melee (damage + speed). The per-form combo nuance
# is a planned refinement; this is the working power spike.

const DURATION: float = 18.0


func setup_with_mods(_dir: Vector2, _dmg: int, mods: Dictionary) -> void:
	var caster = mods.get("caster", null)
	if caster and caster.has_method("apply_buff"):
		caster.call("apply_buff", DURATION, 1.4, 1.2)
	if VfxManager and caster is Node2D:
		VfxManager.spawn_hit_sparks((caster as Node2D).global_position, Color(0.9, 0.7, 0.3, 1), 20)
		VfxManager.screen_flash(Color(0.7, 0.5, 0.2, 0.18), 0.2)
	queue_free()
