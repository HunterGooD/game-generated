extends Area2D

@export var sprite: Sprite2D
@export var label: Label

var amount: int = 1
var collected: bool = false
var spawn_pos: Vector2 = Vector2.ZERO


func setup(amt: int) -> void:
	amount = max(amt, 1)


func _ready() -> void:
	collision_layer = 32  # pickup layer
	collision_mask = 2  # player hurtbox
	monitoring = true
	area_entered.connect(_on_area_entered)
	# Pop animation — drop arcs to nearby location.
	var dx: float = randf_range(-40.0, 40.0)
	var dy: float = randf_range(-30.0, -10.0)
	var landing: Vector2 = global_position + Vector2(dx, dy)
	spawn_pos = landing
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "global_position", landing, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	if sprite:
		tw.tween_property(sprite, "scale", sprite.scale * 1.15, 0.18).set_trans(Tween.TRANS_SINE)
	# Bob loop bound to this node so freeing kills the tween.
	await tw.finished
	if not is_instance_valid(self):
		return
	var bob := create_tween().set_loops()
	bob.tween_property(self, "position:y", position.y - 4.0, 0.7).set_trans(Tween.TRANS_SINE)
	bob.tween_property(self, "position:y", position.y + 4.0, 0.7).set_trans(Tween.TRANS_SINE)
	if label:
		label.text = "+%d" % amount


func _on_area_entered(area: Area2D) -> void:
	if collected:
		return
	var p = area.get_parent()
	if p and p.is_in_group("player"):
		collected = true
		if GameManager:
			GameManager.add_gold_with_bonus(amount)
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/pickup/pickup_gold_pickup.mp3", -8.0)
		# Sparkle effect.
		if VfxManager:
			VfxManager.spawn_hit_sparks(global_position, Color(1, 0.9, 0.4, 1), 5)
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
		call_deferred("queue_free")
