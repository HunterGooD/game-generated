extends Area2D

@export var sprite: Sprite2D
@export var label: Label

var amount: int = 1
var collected: bool = false
var spawn_pos: Vector2 = Vector2.ZERO

# Magnet: once the local player is within range the coin flies to them, so you no
# longer have to walk onto each coin (this is the pull XP orbs used to have — XP is
# a number now, so the juice moved to gold). Co-op spawns coins per-player locally,
# so each coin homes on ITS peer's real player, not a teammate's puppet.
const MAGNET_RANGE: float = 160.0
const MAGNET_SPEED: float = 360.0
var _settled: bool = false
var _bob_tween: Tween = null


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
	_settled = true
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(self, "position:y", position.y - 4.0, 0.7).set_trans(Tween.TRANS_SINE)
	_bob_tween.tween_property(self, "position:y", position.y + 4.0, 0.7).set_trans(Tween.TRANS_SINE)
	if label:
		label.text = "+%d" % amount


func _physics_process(delta: float) -> void:
	if collected or not _settled:
		return
	var player := _local_player()
	if player == null:
		return
	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()
	if dist < MAGNET_RANGE:
		# Hand position over to the magnet — kill the idle bob so it doesn't fight us.
		if _bob_tween != null and _bob_tween.is_valid():
			_bob_tween.kill()
			_bob_tween = null
		var pull: float = lerpf(80.0, MAGNET_SPEED, 1.0 - (dist / MAGNET_RANGE))
		global_position += to_player.normalized() * pull * delta


# The peer's own real player (in the "player" group but NOT a remote puppet). In
# solo this is just the player; in co-op it skips teammates' puppets.
func _local_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("player"):
		if is_instance_valid(p) and not (p as Node).is_in_group("remote_player"):
			return p as Node2D
	return null


func _on_area_entered(area: Area2D) -> void:
	if collected:
		return
	var p = area.get_parent()
	# Only the local real player collects — a teammate's puppet shouldn't vacuum
	# coins that belong to this peer.
	if p and p.is_in_group("player") and not p.is_in_group("remote_player"):
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
