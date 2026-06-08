extends Node2D

# Scarlet Possession — Blood Witch (Hexen) R. A 20s blood frenzy: empowers the
# witch's melee (damage + speed) and leeches life from struck foes via the kit.
# (The HP-per-hit cost / low-HP bonus is a planned refinement.)

const DURATION: float = 20.0


func setup_context(ctx: SkillContext) -> void:
	var caster = ctx.caster
	if caster and caster.has_method("apply_buff"):
		caster.call("apply_buff", DURATION, 1.4, 1.1)
	if VfxManager and caster is Node2D:
		VfxManager.spawn_hit_sparks((caster as Node2D).global_position, Color(0.8, 0.05, 0.1, 1), 18)
		VfxManager.screen_flash(Color(0.6, 0.0, 0.05, 0.2), 0.22)
	queue_free()
