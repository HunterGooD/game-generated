class_name MoveComponent
extends Node


@export var body: CharacterBody2D
@export var main_stats: StatsComponent

var velocity: Vector2 = Vector2.ZERO
var speed_multiplier: float = 1.0
var slow_multiplier: float = 1.0
var rooted: bool = false


func accelerate_towards(
	direction: Vector2,
	delta: float,
	acceleration: float = 1800.0,
	friction: float = 1600.0
) -> void:
	var desired := direction.normalized() * get_move_speed()
	if direction.length_squared() > 0.0:
		velocity = velocity.move_toward(desired, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)


func set_velocity(next_velocity: Vector2) -> void:
	velocity = next_velocity


func stop() -> void:
	velocity = Vector2.ZERO
	if body != null:
		body.velocity = Vector2.ZERO


func apply_velocity() -> void:
	if body == null:
		return

	if rooted:
		body.velocity = Vector2.ZERO
		body.move_and_slide()
		return

	body.velocity = velocity.limit_length(get_move_speed())
	body.move_and_slide()


func get_move_speed() -> float:
	var base_speed := main_stats.get_move_speed() if main_stats != null else 0.0
	return max(0.0, base_speed * speed_multiplier * slow_multiplier)
