extends Node2D

# Generic runner for data-driven skills. Instead of a bespoke script, a skill whose
# SkillDefinition carries `effects` points its catalog `scene` at skill_composed.tscn;
# on cast this reads ctx.definition.effects and runs each block in order, then frees
# itself (after `params.lifetime` seconds, default 0 = immediately). The same scene
# is shared by all composed skills — they differ only by their definition's effects.
#
# Multiplayer: the replicated visual-only copy resolves its definition from the
# skill id (NetSync), so effects still run — caster-targeted effects no-op on the
# null remote caster, VFX still plays. Matches the old bespoke self-buff behaviour.


func setup_context(ctx: SkillContext) -> void:
	var def := ctx.definition
	if def != null:
		for effect in def.effects:
			if effect != null:
				effect.execute(ctx, self)
	var lifetime: float = float(def.params.get("lifetime", 0.0)) if def else 0.0
	if lifetime > 0.0:
		await get_tree().create_timer(lifetime).timeout
	queue_free()
