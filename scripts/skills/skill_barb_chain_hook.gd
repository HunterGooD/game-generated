extends Node2D

# Chain Hook (Цепной захват) — barbarian skill-block option (slot 1). Hurls
# chains in a cone toward the cursor and drags caught enemies to the caster,
# dealing light damage. The cone half-angle grows with the barb_hook_angle
# modifier (ctx.mods["angle_bonus"], degrees) so ranks widen the catch.

const RANGE: float = 300.0
const BASE_HALF_ANGLE_DEG: float = 28.0
const PULL_TIME: float = 0.22
const PULL_STOP_DIST: float = 56.0  # enemies land this far from the caster

var damage: int = 12
var half_angle: float = deg_to_rad(BASE_HALF_ANGLE_DEG)
var direction: Vector2 = Vector2.RIGHT
var caster: Node2D = null
var visual_only: bool = false


func setup_context(ctx: SkillContext) -> void:
	damage = ctx.damage
	direction = ctx.direction
	caster = ctx.caster as Node2D
	visual_only = ctx.is_visual_only
	half_angle = deg_to_rad(BASE_HALF_ANGLE_DEG + float(ctx.get_mod("angle_bonus", 0.0)))


func _ready() -> void:
	_draw_chains()
	if not visual_only:
		_hook_enemies()
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(queue_free)


# Quick visual: a few chain lines fanned over the cone, fading out.
func _draw_chains() -> void:
	var base_ang: float = direction.angle()
	for i in 3:
		var t: float = -1.0 + float(i)  # -1, 0, 1
		var ang: float = base_ang + half_angle * 0.7 * t
		var line := Line2D.new()
		line.width = 3.0
		line.default_color = Color(0.75, 0.7, 0.6, 0.9)
		line.add_point(Vector2.ZERO)
		line.add_point(Vector2.RIGHT.rotated(ang) * RANGE)
		add_child(line)
		var tw := line.create_tween()
		tw.tween_property(line, "modulate:a", 0.0, 0.3)


func _hook_enemies() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var origin: Vector2 = global_position
	if caster and is_instance_valid(caster):
		origin = caster.global_position
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var to_enemy: Vector2 = (e as Node2D).global_position - origin
		var dist: float = to_enemy.length()
		if dist > RANGE or dist < PULL_STOP_DIST:
			continue
		if absf(direction.angle_to(to_enemy)) > half_angle:
			continue
		var dest: Vector2 = origin + to_enemy.normalized() * PULL_STOP_DIST
		var tw := (e as Node2D).create_tween()
		(
			tw
			. tween_property(e, "global_position", dest, PULL_TIME)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		if e.has_method("take_damage"):
			e.call("take_damage", damage, origin)
		# Pulls count as control (feeds Titanbreaker's Seismic Momentum etc.).
		if caster and caster.has_method("notify_control_applied"):
			caster.call("notify_control_applied")
		if VfxManager:
			VfxManager.spawn_hit_sparks((e as Node2D).global_position, Color(0.8, 0.75, 0.6, 1), 6)
