class_name DungeonShrine
extends Node2D

## "Echo of Power" affix pickup: a glowing shrine. Walk into it to claim a stacking
## buff that lasts the dungeon layer. The controller accumulates the running total and
## re-applies it (apply_buff keeps the strongest, so re-applying the growing total stacks).
## Proximity-activated (no key press) — built in code, like the other dungeon props.

signal claimed(node: DungeonShrine)

const PICKUP_RANGE: float = 64.0

var _claimed: bool = false
var _pulse: float = 0.0


func _ready() -> void:
	z_index = 20
	add_to_group("dungeon_shrine")
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if _claimed:
		return
	_pulse = fmod(_pulse + delta, TAU)
	queue_redraw()
	var p := _nearest_player()
	if p and p.global_position.distance_to(global_position) <= PICKUP_RANGE:
		_claim()


func _claim() -> void:
	if _claimed:
		return
	_claimed = true
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/pickup/pickup_gold_pickup.mp3", -8.0)
	claimed.emit(self)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)


func _draw() -> void:
	var glow: float = 0.5 + 0.3 * sin(_pulse * 2.5)
	var col := Color(0.45, 0.7, 1.0)
	draw_circle(Vector2.ZERO, 44.0, Color(col.r, col.g, col.b, 0.18 * glow))
	draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.9), 3.0, true)
	# Inner diamond.
	var pts := PackedVector2Array(
		[Vector2(0, -18), Vector2(13, 0), Vector2(0, 18), Vector2(-13, 0)]
	)
	draw_colored_polygon(pts, Color(0.7, 0.88, 1.0, 0.85 * glow + 0.15))


func _nearest_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = INF
	for p in tree.get_nodes_in_group("player"):
		if not is_instance_valid(p) or not (p is Node2D):
			continue
		var d: float = (p as Node2D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best
