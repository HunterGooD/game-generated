class_name HurtBoxComponent
extends Area2D


@export var health_component: HealthComponent
@export var status_effect_receiver: StatusEffectReceiverComponent
@export var damage_receiver: Node


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	if not area is HitBoxComponent:
		return

	receive_hit(area as HitBoxComponent)


func receive_hit(hit_box: HitBoxComponent) -> bool:
	if hit_box.payload == null:
		push_warning("HitBoxComponent payload is null")
		return false

	var damage_applied := false
	if damage_receiver != null and damage_receiver.has_method("receive_damage_payload"):
		damage_applied = bool(damage_receiver.call("receive_damage_payload", hit_box.payload))
	elif health_component != null:
		health_component.apply_damage(hit_box.payload)
		damage_applied = true

	if damage_applied and status_effect_receiver != null and not hit_box.payload.status_effects.is_empty():
		status_effect_receiver.apply_effects(hit_box.payload.status_effects, hit_box.payload)

	return damage_applied
