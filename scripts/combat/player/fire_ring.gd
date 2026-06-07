extends Node2D

# Persistent fire ring left by Whirlwind when Berserker's Halo is equipped.
# Ticks damage to any enemy in a 130px radius for 3 seconds.

const LIFETIME: float = 3.0
const TICK_INTERVAL: float = 0.3
const RADIUS: float = 140.0

var damage: int = 12
var life: float = LIFETIME
var tick_t: float = 0.0
var visual: Sprite2D = null


func setup(dmg: int) -> void:
	damage = max(1, int(round(float(dmg) * 0.45)))


func _ready() -> void:
	visual = Sprite2D.new()
	var path: String = "res://assets/sprites/effects/meteor_telegraph.png"
	if ResourceLoader.exists(path):
		visual.texture = load(path) as Texture2D
	visual.modulate = Color(1.0, 0.45, 0.18, 0.85)
	visual.scale = Vector2(1.5, 1.5)
	visual.z_index = 30
	add_child(visual)
	var tw := visual.create_tween().set_loops()
	tw.tween_property(visual, "modulate:a", 0.4, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(visual, "modulate:a", 0.85, 0.45).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		var tw := visual.create_tween() if visual else null
		if tw:
			tw.tween_property(visual, "modulate:a", 0.0, 0.25)
			tw.tween_callback(queue_free)
		else:
			queue_free()
		set_process(false)
		return
	tick_t -= delta
	if tick_t <= 0.0:
		tick_t = TICK_INTERVAL
		_tick_damage()


func _tick_damage() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if (e as Node2D).global_position.distance_to(global_position) <= RADIUS:
			if e.has_method("take_damage"):
				e.take_damage(damage, global_position)
