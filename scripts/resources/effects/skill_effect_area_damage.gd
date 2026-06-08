class_name SkillEffectAreaDamage
extends SkillEffect

# Instant area-of-effect damage around the cast origin (the spawned host's
# position — caster position for at_caster skills, the aim point for at_target).
# Damages every live enemy within `radius`, optionally marking an element, applying
# a slow, and/or knocking back. Skipped on the multiplayer visual-only copy — the
# host is authoritative for damage (matches the old bespoke `if not visual_only`).

@export var radius: float = 180.0
@export var damage_mult: float = 1.0  # multiplies ctx.damage (already class-scaled)
@export var mark_element: String = ""  # "" = none; e.g. "storm" / "fire" / "frost"
@export var slow_duration: float = 0.0  # <= 0 = no slow
@export var slow_mult: float = 1.0
@export var knockback: float = 0.0  # <= 0 = none; speed pushed away from origin


func execute(ctx: SkillContext, host: Node2D) -> void:
	if ctx.is_visual_only:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var origin: Vector2 = host.global_position
	var dmg: int = int(round(float(ctx.damage) * damage_mult))
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var ep: Vector2 = (e as Node2D).global_position
		if origin.distance_to(ep) > radius:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", dmg, origin)
		if mark_element != "" and e.has_method("mark_element"):
			e.call("mark_element", mark_element)
		if slow_duration > 0.0 and e.has_method("apply_slow"):
			e.call("apply_slow", slow_duration, slow_mult)
		if knockback > 0.0:
			(e as Node2D).set("velocity", (ep - origin).normalized() * knockback)


static func from_data(d: Dictionary) -> SkillEffectAreaDamage:
	var e := SkillEffectAreaDamage.new()
	e.radius = float(d.get("radius", 180.0))
	e.damage_mult = float(d.get("damage_mult", 1.0))
	e.mark_element = String(d.get("mark_element", ""))
	e.slow_duration = float(d.get("slow_duration", 0.0))
	e.slow_mult = float(d.get("slow_mult", 1.0))
	e.knockback = float(d.get("knockback", 0.0))
	return e
