class_name SkillEffectCasterSet
extends SkillEffect

# Sets a property on the caster — the "self-buff via property" pattern that
# caster_call can't express (e.g. stone_armor_charges = max(current, N)). Skipped
# on the null-caster visual-only remote copy, matching the bespoke `if not
# visual_only and caster` guard.
#   mode "set" -> overwrite with value
#   mode "max" -> max(current, value)   (integer counters)
#   mode "add" -> current + value        (integer counters)

@export var property: String = ""
@export var value: float = 0.0
@export var mode: String = "set"


func execute(ctx: SkillContext, _host: Node2D) -> void:
	var caster := ctx.caster
	if caster == null or property == "":
		return
	match mode:
		"max":
			caster.set(property, maxi(int(caster.get(property)), int(value)))
		"add":
			caster.set(property, int(caster.get(property)) + int(value))
		_:
			caster.set(property, value)


static func from_data(d: Dictionary) -> SkillEffectCasterSet:
	var e := SkillEffectCasterSet.new()
	e.property = String(d.get("property", ""))
	e.value = float(d.get("value", 0.0))
	e.mode = String(d.get("mode", "set"))
	return e
