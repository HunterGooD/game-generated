class_name SkillEffectCasterCall
extends SkillEffect

# Calls a method on the caster, if present. Covers the common "self-buff" skills:
# apply_buff / start_frenzy / start_flameblade / enter_dome, etc. In multiplayer the
# visual-only remote copy has a null caster, so the call is simply skipped there
# (matching how the old bespoke scripts guarded with `if caster.has_method(...)`).

@export var method: String = ""
@export var args: Array = []


func execute(ctx: SkillContext, _host: Node2D) -> void:
	var caster := ctx.caster
	if caster and method != "" and caster.has_method(method):
		caster.callv(method, args)


static func from_data(d: Dictionary) -> SkillEffectCasterCall:
	var e := SkillEffectCasterCall.new()
	e.method = String(d.get("method", ""))
	e.args = d.get("args", [])
	return e
