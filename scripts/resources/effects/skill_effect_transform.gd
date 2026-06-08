class_name SkillEffectTransform
extends SkillEffect

# Druid shapeshift: calls `set_druid_form(form, duration)` on the caster. The
# duration is `base_duration` plus `per_stack` per stack of an optional upgrade
# modifier read from the caster's SkillSystem (slot `modifier_slot`). Skipped on
# the visual-only remote copy and when there is no caster — the form change is
# pure caster state (the host/owner drives it; peers see the puppet shapeshift via
# normal sync).

@export var form: String = ""  # "bear" / "wolf" / "dire_wolf" / ...
@export var base_duration: float = 20.0
@export var per_stack: float = 0.0
@export var duration_modifier: String = ""  # "" = no per-stack scaling
@export var modifier_slot: int = 0


func execute(ctx: SkillContext, _host: Node2D) -> void:
	if ctx.is_visual_only or ctx.caster == null:
		return
	var caster := ctx.caster
	var stacks: int = 0
	if duration_modifier != "":
		var ss := caster.get_node_or_null("SkillSystem")
		if ss and ss.has_method("get_modifier"):
			stacks = int(ss.call("get_modifier", modifier_slot, duration_modifier))
	var dur: float = base_duration + per_stack * float(stacks)
	if caster.has_method("set_druid_form"):
		caster.call("set_druid_form", form, dur)


static func from_data(d: Dictionary) -> SkillEffectTransform:
	var e := SkillEffectTransform.new()
	e.form = String(d.get("form", ""))
	e.base_duration = float(d.get("base_duration", 20.0))
	e.per_stack = float(d.get("per_stack", 0.0))
	e.duration_modifier = String(d.get("duration_modifier", ""))
	e.modifier_slot = int(d.get("modifier_slot", 0))
	return e
