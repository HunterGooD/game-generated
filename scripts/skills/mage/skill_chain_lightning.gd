extends Node2D

# Chain lightning — finds the nearest enemy, then chains to N more.

const MAX_JUMPS: int = 4
const JUMP_RANGE: float = 320.0
const SEARCH_RANGE: float = 480.0

var damage: int = 12
var target_world: Vector2 = Vector2.ZERO
var jumps_bonus: int = 0
var _ctx: SkillContext = null


func setup(target: Vector2, dmg: int) -> void:
	setup_context(SkillContext.from_mods(target, dmg, {}))


func setup_context(ctx: SkillContext) -> void:
	_ctx = ctx
	var target := ctx.direction
	var dmg := ctx.damage
	target_world = target
	damage = dmg
	jumps_bonus = int(ctx.get_mod("jumps_bonus", 0))


func _ready() -> void:
	# Find chain.
	var chain: Array = []
	var hit_set: Dictionary = {}
	var start_pos: Vector2 = global_position
	var nearest: Node = SkillTargeting.nearest(get_tree(), start_pos, SEARCH_RANGE, hit_set)
	if nearest == null:
		# No target — still play a small fizzle so cast feels responsive.
		if VfxManager:
			VfxManager.spawn_hit_sparks(start_pos + Vector2(0, -10), Color(0.9, 0.95, 1.4, 1.0), 5)
		queue_free()
		return

	chain.append(nearest)
	hit_set[nearest.get_instance_id()] = true
	var total_jumps: int = MAX_JUMPS + jumps_bonus
	# Storm Sigil unique adds 3 extra jumps.
	if InventorySystem and InventorySystem.has_unique("storm_sigil"):
		total_jumps += 3
	for i in total_jumps - 1:
		var prev: Node2D = chain[chain.size() - 1] as Node2D
		var next: Node = SkillTargeting.nearest(get_tree(), prev.global_position, JUMP_RANGE, hit_set)
		if next == null:
			break
		chain.append(next)
		hit_set[next.get_instance_id()] = true

	# Draw segments and deal damage in sequence with falloff.
	var dmg_now: int = damage
	var prev_pos: Vector2 = start_pos
	for j in chain.size():
		var enemy: Node2D = chain[j] as Node2D
		_draw_bolt_segment(prev_pos, enemy.global_position)
		if enemy.has_method("take_damage"):
			enemy.take_damage(dmg_now, prev_pos)
		if enemy.has_method("mark_element"):
			enemy.call("mark_element", "storm")
		if _ctx != null:
			_ctx.apply_on_hit(enemy)
		if VfxManager:
			VfxManager.spawn_hit_sparks(enemy.global_position, Color(0.85, 0.95, 1.4, 1.0), 8)
		prev_pos = enemy.global_position
		dmg_now = int(round(float(dmg_now) * 0.75))

	# Self-destruct shortly after the bolts fade.
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(queue_free)


func _draw_bolt_segment(a: Vector2, b: Vector2) -> void:
	# Jagged line2d.
	var ln := Line2D.new()
	ln.width = 4.5
	ln.default_color = Color(0.95, 0.95, 1.0, 1.0)
	ln.z_index = 175
	add_child(ln)
	var diff: Vector2 = b - a
	var dist: float = diff.length()
	if dist < 1.0:
		return
	var segs: int = max(4, int(dist / 40.0))
	var perp: Vector2 = diff.normalized().rotated(PI / 2.0)
	for i in segs + 1:
		var t: float = float(i) / float(segs)
		var base: Vector2 = a + diff * t
		var jitter: float = 0.0
		if i != 0 and i != segs:
			jitter = randf_range(-14.0, 14.0)
		ln.add_point(base + perp * jitter - global_position)
	# Outer glow line.
	var glow := Line2D.new()
	glow.width = 12.0
	glow.default_color = Color(0.55, 0.7, 1.0, 0.55)
	glow.z_index = 170
	add_child(glow)
	for i in ln.points.size():
		glow.add_point(ln.points[i])

	# Fade and free — each line owns its own tween.
	var tw_l := ln.create_tween()
	tw_l.tween_interval(0.05)
	tw_l.tween_property(ln, "modulate:a", 0.0, 0.32)
	tw_l.tween_callback(ln.queue_free)
	var tw_g := glow.create_tween()
	tw_g.tween_interval(0.05)
	tw_g.tween_property(glow, "modulate:a", 0.0, 0.32)
	tw_g.tween_callback(glow.queue_free)
