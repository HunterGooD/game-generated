extends Area2D

# Poison Vial — spawns a poison cloud on impact that DoTs enemies inside.

const LIFETIME: float = 5.0
const RADIUS: float = 70.0
const TICK_INTERVAL: float = 0.5

@export var sprite: Sprite2D
@export var hit_box: HitBoxComponent

var damage: int = 6
var life: float = LIFETIME
var tick_t: float = 0.0
var caster_ref: Node = null


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	caster_ref = mods.get("caster", null) if mods != null else null


func _ready() -> void:
	collision_layer = 0
	collision_mask = 16
	if hit_box:
		hit_box.monitoring = false
		hit_box.monitorable = false
		hit_box.payload = _build_damage_payload()
	# Visual cloud — pulsing and rotating.
	if sprite:
		sprite.scale = Vector2(0.2, 0.2)
		var tw := create_tween().set_parallel(true)
		(
			tw
			. tween_property(sprite, "scale", Vector2(1.4, 1.4), 0.35)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		var spin := sprite.create_tween().set_loops()
		spin.tween_property(sprite, "rotation", sprite.rotation + TAU, 4.0)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		# Fade out and destroy.
		if sprite:
			var tw := create_tween()
			tw.tween_property(sprite, "modulate:a", 0.0, 0.4)
			tw.tween_callback(_done)
		else:
			_done()
		return
	tick_t -= delta
	if tick_t <= 0.0:
		tick_t = TICK_INTERVAL
		_tick()


func _tick() -> void:
	for area in get_overlapping_areas():
		if not area.is_in_group("enemy_hit"):
			continue
		var enemy = area.get_parent()
		if area is HurtBoxComponent and hit_box:
			hit_box.payload = _build_damage_payload()
			(area as HurtBoxComponent).receive_hit(hit_box)
		elif enemy and enemy.has_method("take_damage"):
			enemy.take_damage(damage, global_position)


func _done() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	queue_free()


func _build_damage_payload() -> DamageInstance:
	return DamageInstance.new(float(damage), _resolve_damage_source(), self, [&"player", &"skill", &"poison_vial"], [])


func _resolve_damage_source() -> Node:
	if is_instance_valid(caster_ref):
		return caster_ref
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("player"):
		if node is Node and not node.is_in_group("remote_player"):
			return node
	return null
