extends Node2D

# Talon Swoop — eagle dives forward, slashing the first target it hits hard.

const SWOOP_TIME: float = 0.30
const MAX_DISTANCE: float = 260.0
const HIT_RADIUS: float = 70.0

var damage: int = 28
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false
var start_pos: Vector2 = Vector2.ZERO
var end_pos: Vector2 = Vector2.ZERO
var _caster: Node = null


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = ctx.is_visual_only
	_caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)
	var caster = _caster
	if caster:
		start_pos = caster.global_position
		var to_mouse: Vector2 = caster.get_global_mouse_position() - caster.global_position
		var dist: float = min(max(to_mouse.length(), 160.0), MAX_DISTANCE)
		end_pos = start_pos + direction * dist
	elif visual_only:
		start_pos = global_position
		end_pos = start_pos + direction * 220.0


func _ready() -> void:
	z_index = 60
	if start_pos == Vector2.ZERO:
		start_pos = global_position
		end_pos = start_pos + direction * 220.0
	# Move caster via tween on host/local only.
	if not visual_only:
		var caster := _resolve_caster()
		if caster:
			var tw := caster.create_tween()
			(
				tw
				. tween_property(caster, "global_position", end_pos, SWOOP_TIME)
				. set_trans(Tween.TRANS_QUART)
				. set_ease(Tween.EASE_OUT)
			)
		# Damage pass mid-way through the dive.
		var t := get_tree().create_timer(SWOOP_TIME * 0.5)
		t.timeout.connect(_apply_damage)
	if VfxManager:
		VfxManager.screen_shake(2.5, 0.12)
	var done := get_tree().create_timer(SWOOP_TIME + 0.15)
	done.timeout.connect(queue_free)


func _apply_damage() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hit_set: Dictionary = {}
	var steps: int = 5
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var p: Vector2 = start_pos.lerp(end_pos, t)
		for e in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(e):
				continue
			var id: int = e.get_instance_id()
			if hit_set.has(id):
				continue
			if p.distance_to((e as Node2D).global_position) <= HIT_RADIUS:
				hit_set[id] = true
				if e.has_method("take_damage"):
					e.take_damage(damage, p)
				if VfxManager:
					VfxManager.spawn_hit_sparks(
						(e as Node2D).global_position, Color(1.0, 0.85, 0.5, 1), 6
					)
	if VfxManager:
		VfxManager.hit_stop(0.06)


func _resolve_caster() -> Node2D:
	if _caster != null and is_instance_valid(_caster):
		return _caster as Node2D
	var tree := get_tree()
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("player"):
		if not p.is_in_group("remote_player"):
			return p as Node2D
	return null
