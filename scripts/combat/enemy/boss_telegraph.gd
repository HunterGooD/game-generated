extends Node2D

# Boss telegraph — visible warning area that ticks down, then "fires" by
# emitting `triggered` for the boss to read overlapping enemies/players.

signal triggered(center: Vector2, params: Dictionary)

@export var sprite: Sprite2D

var shape: String = "circle"  # "circle" | "cone" | "line" | "cross"
var radius: float = 120.0
var duration: float = 1.2
var rotation_deg: float = 0.0
var t: float = 0.0
var damage: int = 20
var fired: bool = false
var attacker: Node = null


func setup(
	shape_in: String,
	center: Vector2,
	radius_in: float,
	duration_in: float,
	damage_in: int = 20,
	rotation_in: float = 0.0,
	attacker_in: Node = null
) -> void:
	shape = shape_in
	radius = radius_in
	duration = duration_in
	damage = damage_in
	rotation_deg = rotation_in
	attacker = attacker_in
	global_position = center


func _ready() -> void:
	z_index = 40
	var tex_path: String = ""
	match shape:
		"circle":
			tex_path = "res://assets/sprites/effects/boss_telegraph_circle.png"
		"cone":
			tex_path = "res://assets/sprites/effects/boss_telegraph_cone.png"
		"line":
			tex_path = "res://assets/sprites/effects/boss_telegraph_line.png"
		"cross":
			tex_path = "res://assets/sprites/effects/boss_telegraph_circle.png"
		_:
			tex_path = "res://assets/sprites/effects/boss_telegraph_circle.png"
	if sprite and ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path) as Texture2D
	if sprite:
		# Scale sprite so radius matches in world coords.
		var src: Vector2 = sprite.texture.get_size() if sprite.texture else Vector2(256, 256)
		var target_diam: float = radius * 2.0
		var sc: float = target_diam / max(src.x, src.y)
		# Cone elongates forward; line stretches narrow.
		if shape == "cone":
			sprite.scale = Vector2(sc * 1.4, sc * 0.6)
		elif shape == "line":
			sprite.scale = Vector2(sc * 1.7, sc * 0.18)
		else:
			sprite.scale = Vector2(sc, sc)
		sprite.modulate = Color(1.0, 0.3, 0.25, 0.55)
		sprite.rotation_degrees = rotation_deg
	# Pulse the warning.
	if sprite:
		var tw := sprite.create_tween().set_loops()
		tw.tween_property(sprite, "modulate", Color(1.0, 0.45, 0.3, 0.85), 0.18)
		tw.tween_property(sprite, "modulate", Color(1.0, 0.25, 0.2, 0.45), 0.18)
	if AudioManager:
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/enemy/enemy_boss_telegraph_warn.mp3", -14.0
		)


func _process(delta: float) -> void:
	if fired:
		return
	t += delta
	if t >= duration:
		_fire()


func _fire() -> void:
	fired = true
	# Flash brighter and emit triggered for the spawner to apply damage.
	if sprite:
		sprite.modulate = Color(1.4, 0.65, 0.45, 0.95)
	# Damage players inside the affected area.
	_damage_players()
	# Tween fade-out then free.
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
	triggered.emit(
		global_position, {"shape": shape, "radius": radius, "damage": damage, "rot": rotation_deg}
	)


func _damage_players() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for p in tree.get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		var pos: Vector2 = (p as Node2D).global_position
		if _is_inside_shape(pos):
			if p.has_method("receive_damage_payload"):
				p.call(
					"receive_damage_payload",
					DamageInstance.new(float(damage), attacker, self, [&"boss", &"telegraph", StringName(shape)], [])
				)
			elif p.has_method("take_damage"):
				p.take_damage(damage)


func _is_inside_shape(pos: Vector2) -> bool:
	var rel: Vector2 = pos - global_position
	match shape:
		"circle", "cross":
			return rel.length() <= radius
		"cone":
			# Cone is a 90° wedge centered on rotation_deg, length = radius * 1.4
			var dist: float = rel.length()
			if dist > radius * 1.4:
				return false
			var ang: float = rad_to_deg(rel.angle())
			var diff: float = wrapf(ang - rotation_deg, -180.0, 180.0)
			return abs(diff) <= 50.0
		"line":
			# Line is a thin strip along rotation_deg.
			var perp_angle: float = deg_to_rad(rotation_deg + 90.0)
			var perp: Vector2 = Vector2(cos(perp_angle), sin(perp_angle))
			var perp_dist: float = abs(rel.dot(perp))
			var along_angle: float = deg_to_rad(rotation_deg)
			var along: Vector2 = Vector2(cos(along_angle), sin(along_angle))
			var along_dist: float = abs(rel.dot(along))
			return perp_dist <= 40.0 and along_dist <= radius * 1.7
	return false
