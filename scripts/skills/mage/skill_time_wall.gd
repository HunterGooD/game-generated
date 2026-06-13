extends Node2D

# Time Wall — Chronomancer transform of Fire Wall (slot 0). Deals no damage; a
# band of warped time where enemies are slowed and allies are hastened. A purely
# tactical control tool. Slowing foes feeds Borrowed Second.

const LIFETIME: float = 4.0
const LENGTH: float = 240.0
const THICKNESS: float = 70.0
const ENEMY_SLOW_MULT: float = 0.5
const BORROW_TICK: float = 0.5

var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false
var caster: Node2D = null
var _life: float = LIFETIME
var _borrow_t: float = 0.0


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)
	rotation = direction.angle() + PI / 2.0


func _ready() -> void:
	z_index = 8
	var band := Sprite2D.new()
	var path := "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		band.texture = load(path) as Texture2D
	band.modulate = Color(0.45, 0.85, 1.0, 0.45)
	band.scale = Vector2(LENGTH / 128.0, THICKNESS / 64.0)
	add_child(band)
	var tw := band.create_tween().set_loops()
	tw.tween_property(band, "modulate:a", 0.2, 0.6)
	tw.tween_property(band, "modulate:a", 0.45, 0.6)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	var tree := get_tree()
	if tree == null:
		return
	_borrow_t -= delta
	var grant_borrow: bool = _borrow_t <= 0.0
	if grant_borrow:
		_borrow_t = BORROW_TICK
	var slowed_any: bool = false
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if _in_band((e as Node2D).global_position):
			if e.has_method("apply_slow"):
				e.call("apply_slow", 0.3, ENEMY_SLOW_MULT)
				slowed_any = true
	for grp in ["player", "remote_player"]:
		for a in tree.get_nodes_in_group(grp):
			if not is_instance_valid(a) or not (a is Node2D):
				continue
			if _in_band((a as Node2D).global_position) and a.has_method("enter_dome"):
				a.call("enter_dome", 0.4)
	if grant_borrow and slowed_any and caster and caster.has_method("notify_control_applied"):
		caster.call("notify_control_applied")


func _in_band(point: Vector2) -> bool:
	var local: Vector2 = (point - global_position)
	# Project onto the wall's along/across axes (along = perpendicular to cast dir).
	var along: Vector2 = Vector2(-direction.y, direction.x)
	var across_d: float = abs(local.dot(direction))
	var along_d: float = abs(local.dot(along))
	return across_d <= THICKNESS * 0.5 and along_d <= LENGTH * 0.5
