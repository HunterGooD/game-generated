extends Area2D

# Dark bolt fired by enemies at the player.

const SPEED: float = 380.0
const LIFETIME: float = 2.0

@export var sprite: Sprite2D
@export var hit_box: HitBoxComponent

var direction: Vector2 = Vector2.RIGHT
var damage: int = 6
var travelled: float = 0.0
# Scaled down by a Chronomancer Temporal Dome the bolt is flying through.
var speed_mult: float = 1.0


func setup(dir: Vector2, dmg: int) -> void:
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	damage = dmg
	rotation = direction.angle()
	if hit_box:
		hit_box.payload = DamageInstance.new(float(damage), null, self, [&"enemy", &"projectile"], [])


func _ready() -> void:
	add_to_group("enemy_projectile")
	collision_layer = 0
	collision_mask = 2  # bit 2 — player hurtbox
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	if hit_box:
		hit_box.collision_layer = 0
		hit_box.collision_mask = 2
		hit_box.hit.connect(_on_hit_hurtbox)
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = LIFETIME
	t.timeout.connect(_die)
	add_child(t)
	t.start()


func _physics_process(delta: float) -> void:
	var step: Vector2 = direction * SPEED * speed_mult * delta
	position += step
	travelled += step.length()
	# Dome only slows while the bolt is inside it — reset each frame; the dome
	# re-applies its multiplier in _process.
	speed_mult = 1.0
	if travelled > 1200.0:
		_die()


func _on_area_entered(area: Area2D) -> void:
	if area is HurtBoxComponent:
		return
	var p = area.get_parent()
	if p and p.has_method("take_damage") and p.is_in_group("player"):
		p.take_damage(damage)
		if VfxManager:
			VfxManager.spawn_hit_sparks(global_position, Color(1.0, 0.4, 0.5, 1), 6)
		_die()


func _on_hit_hurtbox(_area: Area2D) -> void:
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(1.0, 0.4, 0.5, 1), 6)
	_die()


func _on_body_entered(body: Node) -> void:
	if body is StaticBody2D or body is TileMap:
		_die()


func _die() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	queue_free()
