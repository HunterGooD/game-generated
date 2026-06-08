extends Node2D

# Time Link — Chronomancer transform of Chain Lightning (slot 2). A temporal arc
# that threads through nearby combatants: allies it touches gain a shield, enemies
# take damage and have their attacks slowed. Both feed Borrowed Second.

const MAX_LINKS: int = 5
const LINK_RANGE: float = 260.0
const ENEMY_SLOW_MULT: float = 0.55
const ALLY_SHIELD_FRAC: float = 0.6  # of the ability damage, as shield HP

var damage: int = 18
var visual_only: bool = false
var caster: Node2D = null
var _start: Vector2 = Vector2.ZERO


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 55
	_start = (caster as Node2D).global_position if caster is Node2D else global_position
	if not visual_only:
		_run_chain()
	if VfxManager:
		VfxManager.spawn_hit_sparks(_start, Color(0.5, 0.9, 1.0, 1), 10)
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(queue_free)


func _run_chain() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var used: Dictionary = {}
	var prev: Vector2 = _start
	for _i in MAX_LINKS:
		var target: Node = _nearest_unused(prev, used)
		if target == null:
			break
		used[target.get_instance_id()] = true
		var tpos: Vector2 = (target as Node2D).global_position
		_draw_link(prev, tpos)
		if target.is_in_group("enemy"):
			if target.has_method("take_damage"):
				target.call("take_damage", damage, prev)
			if target.has_method("apply_slow"):
				target.call("apply_slow", 2.0, ENEMY_SLOW_MULT)
			if caster and caster.has_method("notify_control_applied"):
				caster.call("notify_control_applied")
		else:
			# Ally (player / remote_player) — grant a shield.
			if target.has_method("add_shield"):
				target.call("add_shield", float(damage) * ALLY_SHIELD_FRAC, -1.0)
			if caster and caster.has_method("notify_control_applied"):
				caster.call("notify_control_applied")
		prev = tpos


func _nearest_unused(from: Vector2, used: Dictionary) -> Node:
	var best: Node = null
	var best_d: float = LINK_RANGE
	var tree := get_tree()
	for grp in ["enemy", "player", "remote_player"]:
		for n in tree.get_nodes_in_group(grp):
			if not is_instance_valid(n) or not (n is Node2D):
				continue
			if used.has(n.get_instance_id()) or bool(n.get("dead")):
				continue
			var d: float = from.distance_to((n as Node2D).global_position)
			if d < best_d:
				best_d = d
				best = n
	return best


func _draw_link(a: Vector2, b: Vector2) -> void:
	var line := Line2D.new()
	line.width = 3.0
	line.default_color = Color(0.5, 0.9, 1.0, 0.9)
	line.add_point(to_local(a))
	line.add_point(to_local(b))
	add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.4)
