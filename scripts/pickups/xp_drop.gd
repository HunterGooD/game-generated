extends Area2D

@export var sprite: Sprite2D

var amount: int = 10
var collected: bool = false
var magnet_range: float = 130.0
var magnet_speed: float = 320.0


func setup(amt: int) -> void:
	amount = max(amt, 1)


func _ready() -> void:
	collision_layer = 32
	collision_mask = 2
	monitoring = true
	area_entered.connect(_on_area_entered)
	# Initial pop.
	var dx: float = randf_range(-30.0, 30.0)
	var dy: float = randf_range(-30.0, -8.0)
	var landing: Vector2 = global_position + Vector2(dx, dy)
	var tw := create_tween()
	tw.tween_property(self, "global_position", landing, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	# Pulse loop.
	var pulse := create_tween().set_loops()
	if sprite:
		pulse.tween_property(sprite, "modulate", Color(1.3, 1.0, 1.6, 1.0), 0.5).set_trans(
			Tween.TRANS_SINE
		)
		pulse.tween_property(sprite, "modulate", Color(0.8, 0.7, 1.2, 1.0), 0.5).set_trans(
			Tween.TRANS_SINE
		)


func _physics_process(delta: float) -> void:
	if collected:
		return
	# Magnet toward player.
	var tree := get_tree()
	if tree == null:
		return
	var players := tree.get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node2D = players[0]
	if not is_instance_valid(player):
		return
	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()
	if dist < magnet_range:
		var pull: float = lerp(60.0, magnet_speed, 1.0 - (dist / magnet_range))
		global_position += to_player.normalized() * pull * delta


func _on_area_entered(area: Area2D) -> void:
	if collected:
		return
	var p = area.get_parent()
	if p and p.is_in_group("player"):
		collected = true
		if GameManager:
			GameManager.add_xp(amount)
		if AudioManager:
			AudioManager.play_sfx_path("res://assets/audio/sfx/pickup/pickup_xp_pickup.mp3", -10.0)
		if VfxManager:
			VfxManager.spawn_hit_sparks(global_position, Color(0.7, 0.5, 1.0, 1), 7)
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
		call_deferred("queue_free")
