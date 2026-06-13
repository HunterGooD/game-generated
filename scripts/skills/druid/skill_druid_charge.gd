extends Node2D

# Stone Charge — bear-form dash that damages and knocks back enemies in its path.

const CHARGE_TIME: float = 0.32
const MAX_DISTANCE: float = 360.0
const HIT_RADIUS: float = 70.0
const KNOCKBACK: float = 280.0

var damage: int = 20
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
		var dist: float = min(max(to_mouse.length(), 200.0), MAX_DISTANCE)
		end_pos = start_pos + direction * dist


func _ready() -> void:
	z_index = 60
	if start_pos == Vector2.ZERO:
		start_pos = global_position
		end_pos = start_pos + direction * 280.0
	# Move caster on host/local.
	if not visual_only:
		var caster := _resolve_caster()
		if caster:
			var tw := caster.create_tween()
			(
				tw
				. tween_property(caster, "global_position", end_pos, CHARGE_TIME)
				. set_trans(Tween.TRANS_QUAD)
				. set_ease(Tween.EASE_OUT)
			)
			# Dust trail along path.
			_spawn_dust_trail(caster)
			var t := get_tree().create_timer(CHARGE_TIME * 0.4)
			t.timeout.connect(_apply_damage)
	if VfxManager:
		VfxManager.screen_shake(3.5, 0.18)
	var done := get_tree().create_timer(CHARGE_TIME + 0.2)
	done.timeout.connect(queue_free)


func _spawn_dust_trail(caster: Node2D) -> void:
	for i in 5:
		var delay: float = float(i) * (CHARGE_TIME / 6.0)
		var t := get_tree().create_timer(delay)
		t.timeout.connect(_spawn_dust.bind(caster))


func _spawn_dust(caster: Node2D) -> void:
	if not is_instance_valid(caster):
		return
	if VfxManager:
		VfxManager.spawn_hit_sparks(caster.global_position, Color(0.7, 0.6, 0.45, 1), 4)


func _apply_damage() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hit_set: Dictionary = {}
	# Sample along the charge path and hit nearby enemies.
	var steps: int = 8
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
				# Knockback along the charge direction.
				if (e as Node2D).has_method("set"):
					(e as Node2D).set("velocity", direction * KNOCKBACK)
				if VfxManager:
					VfxManager.spawn_hit_sparks(
						(e as Node2D).global_position, Color(1.0, 0.65, 0.4, 1), 6
					)


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
