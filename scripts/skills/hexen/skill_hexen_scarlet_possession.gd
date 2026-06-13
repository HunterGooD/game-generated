extends Node2D

# Scarlet Possession — Blood Witch (Hexen) R. 20s blood trance per the spec:
# Blood Whip becomes wider (lashes everything on its line), each cast pays 1%
# current HP (feeding Pain Dividend), every 3rd lash heals per enemy struck,
# and below 35% HP the whip hits +40% harder — all handled by
# player.start_possession / possession_* and skill_hexen_blood_whip. A light
# generic buff stays so the rest of the kit feels the trance too.

const DURATION: float = 20.0


func setup_context(ctx: SkillContext) -> void:
	var caster = ctx.caster
	if caster and caster.has_method("start_possession"):
		caster.call("start_possession", DURATION)
	if caster and caster.has_method("apply_buff"):
		caster.call("apply_buff", DURATION, 1.1, 1.05)
	if VfxManager and caster is Node2D:
		VfxManager.spawn_hit_sparks((caster as Node2D).global_position, Color(0.8, 0.05, 0.1, 1), 18)
		VfxManager.screen_flash(Color(0.6, 0.0, 0.05, 0.2), 0.22)
	queue_free()
