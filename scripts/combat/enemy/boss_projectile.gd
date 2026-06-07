extends Area2D

# Boss-fired projectile. Supports straight (Hellbolt), homing (Lava Hunter),
# and dark beam (Shadewitch). Damages players on contact.

const STRAIGHT_SPEED: float = 360.0
const HOMING_SPEED: float = 220.0
const LIFETIME: float = 6.0

@export var sprite: Sprite2D
@export var hit_box: HitBoxComponent

var direction: Vector2 = Vector2.RIGHT
var damage: int = 15
var homing: bool = false
var target: Node2D = null
var travelled: float = 0.0
var t_alive: float = 0.0
var tint_color: Color = Color(1.0, 0.5, 0.25, 1)


func setup(
	dir: Vector2,
	dmg: int,
	homing_in: bool = false,
	tex_path: String = "res://assets/sprites/effects/hellbolt_projectile.png",
	tint_in: Color = Color(1.0, 0.5, 0.25, 1)
) -> void:
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	damage = dmg
	homing = homing_in
	rotation = direction.angle()
	tint_color = tint_in
	if sprite:
		if ResourceLoader.exists(tex_path):
			sprite.texture = load(tex_path) as Texture2D
		sprite.modulate = tint_color
		sprite.scale = Vector2(0.5, 0.5)
	if hit_box:
		hit_box.payload = DamageInstance.new(float(damage), null, self, [&"boss", &"projectile"], [])


func set_homing_target(target_in: Node2D) -> void:
	target = target_in


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player hurtbox
	monitoring = true
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if hit_box:
		hit_box.collision_layer = 0
		hit_box.collision_mask = 2
		hit_box.hit.connect(_on_hit_hurtbox)
	# Self-destruct after lifetime.
	var t := get_tree().create_timer(LIFETIME)
	t.timeout.connect(_die)


func _physics_process(delta: float) -> void:
	t_alive += delta
	if homing and target == null:
		target = _find_nearest_player()
	if homing and is_instance_valid(target):
		var to_target: Vector2 = (target.global_position - global_position).normalized()
		# Lerp direction so the projectile curves rather than snaps.
		direction = direction.lerp(to_target, clamp(2.4 * delta, 0.0, 1.0)).normalized()
		rotation = direction.angle()
	var speed: float = HOMING_SPEED if homing else STRAIGHT_SPEED
	var step: Vector2 = direction * speed * delta
	position += step
	travelled += step.length()
	if travelled > 1600.0:
		_die()


func _find_nearest_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d: float = INF
	for p in tree.get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		var d: float = global_position.distance_to((p as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = p as Node2D
	return best


func _on_area_entered(area: Area2D) -> void:
	if area is HurtBoxComponent:
		return
	var p = area.get_parent()
	if p and p.is_in_group("player") and p.has_method("take_damage"):
		p.take_damage(damage)
		if VfxManager:
			VfxManager.spawn_hit_sparks(global_position, tint_color, 8)
		_die()


func _on_hit_hurtbox(_area: Area2D) -> void:
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, tint_color, 8)
	_die()


func _on_body_entered(body: Node) -> void:
	if body is StaticBody2D or body is TileMap:
		_die()


func _die() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	queue_free()
