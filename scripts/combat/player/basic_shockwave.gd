extends Node2D

# Cleaving Shockwave — Barbarian basic-attack replacement. A traveling wave
# that passes through every enemy in a forward line for 50% normal damage.

const SPEED: float = 600.0
const RANGE: float = 220.0
const HIT_RADIUS: float = 70.0

var damage: int = 12
var direction: Vector2 = Vector2.RIGHT
var travelled: float = 0.0
var hit_ids: Dictionary = {}
var sprite: Sprite2D = null


func setup(dir: Vector2, dmg: int) -> void:
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	# 50% of the passed-in damage per spec.
	damage = max(1, int(round(float(dmg) * 0.5)))
	rotation = direction.angle()


func setup_with_mods(dir: Vector2, dmg: int, _mods: Dictionary) -> void:
	setup(dir, dmg)


func _ready() -> void:
	z_index = 55
	sprite = Sprite2D.new()
	var path: String = "res://assets/sprites/effects/shockwave_basic.png"
	if ResourceLoader.exists(path):
		sprite.texture = load(path) as Texture2D
	sprite.modulate = Color(1.0, 0.65, 0.35, 0.95)
	if sprite.texture:
		var src_h: float = float(sprite.texture.get_size().y)
		if src_h > 1.0:
			var s: float = clamp(110.0 / src_h, 0.08, 0.7)
			sprite.scale = Vector2(s, s)
	add_child(sprite)
	if AudioManager:
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/player/player_basic_shockwave.mp3", -10.0
		)


func _physics_process(delta: float) -> void:
	var step: Vector2 = direction * SPEED * delta
	position += step
	travelled += step.length()
	# Damage every enemy near the leading edge.
	var tree := get_tree()
	if tree:
		for e in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(e):
				continue
			if e.get("dead") == true:
				continue
			var id: int = e.get_instance_id()
			if hit_ids.has(id):
				continue
			if global_position.distance_to((e as Node2D).global_position) <= HIT_RADIUS:
				hit_ids[id] = true
				if e.has_method("take_damage"):
					e.take_damage(damage, global_position)
	if travelled >= RANGE:
		_finish()


func _finish() -> void:
	if sprite:
		var tw := sprite.create_tween()
		tw.tween_property(sprite, "modulate:a", 0.0, 0.15)
		tw.tween_callback(queue_free)
	else:
		queue_free()
