class_name SkillEffectDash
extends SkillEffect

# Dashes the caster toward the aim point (cursor) in ctx.direction, a distance
# clamped to [min_distance, max_distance], tweened over `duration`. Optionally damages
# every enemy within `width` of the dash segment once (a lunge), with an optional
# element mark / slow. The tween lives on the caster, so it continues after the
# (immediately freed) composed host. Movement is skipped on the visual-only remote
# copy (caster is null there); path damage is host-authoritative.

@export var max_distance: float = 240.0
@export var min_distance: float = 0.0
@export var duration: float = 0.15
@export var width: float = 64.0
@export var path_damage: bool = false
@export var damage_mult: float = 1.0
@export var mark_element: String = ""
@export var slow_duration: float = 0.0
@export var slow_mult: float = 1.0
@export var sparks_color: Color = Color(0.7, 0.85, 1.0, 1)
@export var sparks_count: int = 0


func execute(ctx: SkillContext, host: Node2D) -> void:
	var caster := ctx.caster
	var origin: Vector2 = host.global_position
	var dir: Vector2 = ctx.direction
	var dest: Vector2 = origin + dir * max_distance
	if caster is Node2D and is_instance_valid(caster):
		var cpos: Vector2 = (caster as Node2D).global_position
		origin = cpos
		var to_mouse: Vector2 = (caster as Node2D).get_global_mouse_position() - cpos
		var dist: float = clampf(to_mouse.length(), min_distance, max_distance)
		dest = cpos + dir * dist
		if not ctx.is_visual_only:
			var tw := (caster as Node2D).create_tween()
			(
				tw
				. tween_property(caster, "global_position", dest, duration)
				. set_trans(Tween.TRANS_QUAD)
				. set_ease(Tween.EASE_OUT)
			)

	if VfxManager and sparks_count > 0:
		VfxManager.spawn_hit_sparks(dest, sparks_color, sparks_count)

	if not path_damage or ctx.is_visual_only:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var seg: Vector2 = dest - origin
	var seg_len: float = maxf(seg.length(), 1.0)
	var ndir: Vector2 = seg / seg_len
	var perp := Vector2(-ndir.y, ndir.x)
	var dmg: int = int(round(float(ctx.damage) * damage_mult))
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var rel: Vector2 = (e as Node2D).global_position - origin
		var along: float = rel.dot(ndir)
		if along < -30.0 or along > seg_len + 30.0:
			continue
		if absf(rel.dot(perp)) > width:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", dmg, origin)
		ctx.apply_on_hit(e)
		if mark_element != "" and e.has_method("mark_element"):
			e.call("mark_element", mark_element)
		if slow_duration > 0.0 and e.has_method("apply_slow"):
			e.call("apply_slow", slow_duration, slow_mult)


static func from_data(d: Dictionary) -> SkillEffectDash:
	var e := SkillEffectDash.new()
	e.max_distance = float(d.get("max_distance", 240.0))
	e.min_distance = float(d.get("min_distance", 0.0))
	e.duration = float(d.get("duration", 0.15))
	e.width = float(d.get("width", 64.0))
	e.path_damage = bool(d.get("path_damage", false))
	e.damage_mult = float(d.get("damage_mult", 1.0))
	e.mark_element = String(d.get("mark_element", ""))
	e.slow_duration = float(d.get("slow_duration", 0.0))
	e.slow_mult = float(d.get("slow_mult", 1.0))
	e.sparks_color = d.get("sparks_color", Color(0.7, 0.85, 1.0, 1))
	e.sparks_count = int(d.get("sparks_count", 0))
	return e
