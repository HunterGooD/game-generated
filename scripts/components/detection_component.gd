class_name DetectionComponent
extends Area2D


@export var collision_shape: CollisionShape2D
@export var detection_radius: float = 100.0


func _ready() -> void:
	apply_radius()


func apply_radius() -> void:
	if collision_shape == null:
		return

	if collision_shape.shape is CircleShape2D:
		(collision_shape.shape as CircleShape2D).radius = detection_radius
