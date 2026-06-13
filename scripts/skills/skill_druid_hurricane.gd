extends Node2D

# Hurricane — replaces Wolf Form when the unique is equipped. A swirling
# wind funnel that auto-targets the nearest enemy and damages anything in
# its 90 px radius every 0.4 s for 8 seconds. Caster doesn't shapeshift.

const LIFETIME: float = 8.0
const MOVE_SPEED: float = 220.0
const RADIUS: float = 95.0
const TICK_INTERVAL: float = 0.4

var damage: int = 14
var visual_only: bool = false
var current_target: Node2D = null
var retarget_t: float = 0.0
var damage_t: float = 0.0
var sprite: Sprite2D = null
# "Eye of the Storm" unique (hurricane_twin): a second, smaller hurricane.
var _is_twin: bool = false


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	_is_twin = bool(ctx.get_mod("twin_child", false))
	if _is_twin:
		damage = int(round(float(damage) * 0.6))
		scale = Vector2(0.6, 0.6)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 50
	# Eye of the Storm — the lead hurricane spawns its twin sister.
	if not _is_twin and InventorySystem and InventorySystem.has_unique("hurricane_twin"):
		_spawn_twin()
	sprite = Sprite2D.new()
	var path := "res://assets/sprites/effects/hurricane_vfx.png"
	if ResourceLoader.exists(path):
		sprite.texture = load(path) as Texture2D
	sprite.modulate = Color(0.85, 1.0, 0.85, 0.95)
	if sprite.texture:
		var src_h: float = float(sprite.texture.get_size().y)
		if src_h > 1.0:
			var sc: float = clamp((RADIUS * 2.6) / src_h, 0.1, 1.5)
			sprite.scale = Vector2(sc, sc)
	add_child(sprite)
	# Spinning twist.
	var rot := sprite.create_tween().set_loops()
	rot.tween_property(sprite, "rotation", sprite.rotation + TAU, 0.6)
	# Lifetime.
	var done := get_tree().create_timer(LIFETIME)
	done.timeout.connect(_finish)


func _physics_process(delta: float) -> void:
	# Periodically re-target the nearest enemy.
	retarget_t -= delta
	if retarget_t <= 0.0 or current_target == null or not is_instance_valid(current_target):
		retarget_t = 0.3
		current_target = SkillTargeting.nearest(get_tree(), global_position)
	# Chase target.
	if current_target and is_instance_valid(current_target):
		var to_t: Vector2 = current_target.global_position - global_position
		var step_len: float = MOVE_SPEED * delta
		if to_t.length() > step_len:
			global_position += to_t.normalized() * step_len
		else:
			global_position = current_target.global_position
	# Tick damage in radius.
	if not visual_only:
		damage_t -= delta
		if damage_t <= 0.0:
			damage_t = TICK_INTERVAL
			_apply_damage()


func _apply_damage() -> void:
	for e in SkillTargeting.in_radius(get_tree(), global_position, RADIUS):
		if e.has_method("take_damage"):
			e.take_damage(damage, global_position)


func _spawn_twin() -> void:
	var packed: PackedScene = load(scene_file_path) as PackedScene
	if packed == null:
		return
	var twin: Node2D = packed.instantiate()
	twin.position = global_position + Vector2(randf_range(-130, 130), randf_range(-130, 130))
	var ctx := SkillContext.from_mods(
		Vector2.RIGHT, damage, {"twin_child": true, "visual_only": visual_only}
	)
	SkillContext.apply(twin, ctx)
	# Deferred: _ready runs before we're in the tree ourselves.
	call_deferred("_add_twin_to_scene", twin)


func _add_twin_to_scene(twin: Node2D) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		twin.queue_free()
		return
	tree.current_scene.add_child(twin)


func _finish() -> void:
	if sprite:
		var tw := sprite.create_tween()
		tw.tween_property(sprite, "modulate:a", 0.0, 0.4)
		tw.tween_callback(queue_free)
	else:
		queue_free()
