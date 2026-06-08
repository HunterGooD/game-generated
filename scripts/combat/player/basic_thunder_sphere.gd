extends Area2D

# Thunder Sphere — Druid basic-attack replacement. A slow projectile that
# arcs lightning to one nearby enemy on impact.

const SPEED: float = 620.0
const LIFETIME: float = 1.3
const ARC_RADIUS: float = 180.0

var damage: int = 14
var direction: Vector2 = Vector2.RIGHT
var travelled: float = 0.0


func setup(dir: Vector2, dmg: int) -> void:
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	damage = dmg


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	setup(dir, dmg)


func _ready() -> void:
	collision_layer = 4
	collision_mask = 17  # walls + enemy hurtbox
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	var s := Sprite2D.new()
	var path := "res://assets/sprites/effects/thunder_sphere.png"
	if ResourceLoader.exists(path):
		s.texture = load(path) as Texture2D
	s.modulate = Color(1.0, 0.95, 0.6, 1)
	if s.texture:
		var src_h: float = float(s.texture.get_size().y)
		if src_h > 1.0:
			var sc: float = clamp(64.0 / src_h, 0.05, 0.5)
			s.scale = Vector2(sc, sc)
	add_child(s)
	# Small collision sensor.
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 24.0
	cs.shape = shape
	add_child(cs)
	if AudioManager:
		AudioManager.play_sfx_path(
			"res://assets/audio/sfx/player/player_basic_thunder_sphere.mp3", -10.0
		)
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = LIFETIME
	t.timeout.connect(_die)
	add_child(t)
	t.start()


func _physics_process(delta: float) -> void:
	var step: Vector2 = direction * SPEED * delta
	position += step
	travelled += step.length()
	if travelled > 1300.0:
		_die()


func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group("enemy_hit"):
		return
	var enemy := area.get_parent()
	if enemy and enemy.has_method("take_damage"):
		enemy.take_damage(damage, global_position)
		# Arc to one nearby enemy.
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or e == enemy:
					continue
				if e.get("dead") == true:
					continue
				if (
					(enemy as Node2D).global_position.distance_to((e as Node2D).global_position)
					<= ARC_RADIUS
				):
					if e.has_method("take_damage"):
						e.take_damage(int(round(float(damage) * 0.6)), global_position)
					if VfxManager:
						VfxManager.spawn_hit_sparks(
							(e as Node2D).global_position, Color(1.0, 1.0, 0.5, 1), 5
						)
					break
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(1.0, 0.95, 0.5, 1), 6)
	_die()


func _on_body_entered(body: Node) -> void:
	if body is StaticBody2D:
		_die()


func _die() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	queue_free()
