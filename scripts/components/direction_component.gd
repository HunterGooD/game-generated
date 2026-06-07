class_name DirectionComponent
extends Node


@export var sprite: Node
@export var hit_box: HitBoxComponent

var facing: Vector2 = Vector2.RIGHT


func set_facing(direction: Vector2) -> void:
	if direction.length_squared() <= 0.0001:
		return

	facing = direction.normalized()
	_apply_sprite_direction()

	if hit_box != null:
		hit_box.flip_collision(facing)


func update_facing_toward(from_position: Vector2, target_position: Vector2) -> void:
	set_facing(from_position.direction_to(target_position))


func _apply_sprite_direction() -> void:
	if sprite == null:
		return

	if sprite is Sprite2D:
		(sprite as Sprite2D).flip_h = facing.x < 0.0
	elif sprite is AnimatedSprite2D:
		(sprite as AnimatedSprite2D).flip_h = facing.x < 0.0
