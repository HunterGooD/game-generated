class_name SkillEffect
extends Resource

# Base class for a composable skill behaviour block. A SkillDefinition can carry an
# `effects` array; the generic `skill_composed.gd` runner executes each block's
# execute() in order instead of every skill needing a bespoke scene script. This
# is the data-driven authoring path for NEW skills (especially simple buff/summon/
# pulse skills) — existing bespoke scripts keep working unchanged via SkillCaster.
#
# Each concrete effect lives in its own file (GDScript requires one class_name per
# file) under scripts/resources/effects/ and overrides execute().

# Run the effect. `ctx` carries caster/direction/target/damage/visual_only;
# `host` is the spawned composed-skill Node2D (positioned at the cast point).
func execute(_ctx: SkillContext, _host: Node2D) -> void:
	pass


# Build one effect from a raw catalog dict: {"type": "<id>", ...fields}. Unknown
# types return null (skipped) so a typo can't hard-crash a cast.
static func from_data(d: Dictionary) -> SkillEffect:
	match String(d.get("type", "")):
		"caster_call":
			return SkillEffectCasterCall.from_data(d)
		"caster_set":
			return SkillEffectCasterSet.from_data(d)
		"group_call":
			return SkillEffectGroupCall.from_data(d)
		"area_damage":
			return SkillEffectAreaDamage.from_data(d)
		"summon":
			return SkillEffectSummon.from_data(d)
		"group_heal":
			return SkillEffectGroupHeal.from_data(d)
		"group_shield":
			return SkillEffectGroupShield.from_data(d)
		"transform":
			return SkillEffectTransform.from_data(d)
		"dash":
			return SkillEffectDash.from_data(d)
		"projectile":
			return SkillEffectProjectile.from_data(d)
		"aura":
			return SkillEffectAura.from_data(d)
		"telegraph":
			return SkillEffectTelegraph.from_data(d)
		"vfx":
			return SkillEffectVfx.from_data(d)
		_:
			push_warning("Unknown skill effect type: %s" % str(d.get("type", "")))
			return null


# Build a typed effect list from a catalog `effects` array.
static func list_from(arr: Array) -> Array[SkillEffect]:
	var out: Array[SkillEffect] = []
	for d in arr:
		if d is Dictionary:
			var e := from_data(d)
			if e != null:
				out.append(e)
	return out
