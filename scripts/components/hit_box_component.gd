class_name HitBoxComponent
extends Area2D


signal hit(area2d: Area2D)


const DISABLED_PROPERTY: StringName = &"disabled"


@export var offset_collision: Vector2 = Vector2.ZERO
@export var collision_shape: CollisionShape2D

var payload: DamageInstance


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _on_area_entered(area2d: Area2D) -> void:
	if area2d is HurtBoxComponent:
		# Deliver the hit AFTER the physics query flush. Damage can trigger a
		# death cascade (loot/merchant/hatchling spawns) that toggles collision
		# state, which is illegal mid-flush — so defer it one idle step.
		call_deferred("_deliver_hit", area2d)


func _deliver_hit(area2d: Area2D) -> void:
	if not is_instance_valid(area2d):
		return
	# Apply our damage payload through the hurtbox (HP, status effects,
	# knockback, death). The `hit` signal lets the hitbox's owner react —
	# projectiles _impact()/die, melee plays feedback.
	(area2d as HurtBoxComponent).receive_hit(self)
	hit.emit(area2d)


func enable_collision() -> void:
	if collision_shape == null:
		return
	collision_shape.set_deferred(DISABLED_PROPERTY, false)


func disable_collision() -> void:
	if collision_shape == null:
		return
	collision_shape.set_deferred(DISABLED_PROPERTY, true)


func flip_collision(direction: Vector2) -> void:
	if collision_shape == null or direction.length_squared() <= 0.0001:
		return

	if abs(direction.x) >= abs(direction.y):
		collision_shape.rotation = 0.0
		collision_shape.position = Vector2(offset_collision.x * signf(direction.x), 0.0)
	else:
		collision_shape.rotation = deg_to_rad(90)
		collision_shape.position = Vector2(0.0, offset_collision.y * signf(direction.y))
