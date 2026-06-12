extends Area2D

# Bone Spear — fast piercing projectile (talent transform of Raise Skeleton).
# The "Bone Spear" unique weapon makes it shatter into splinters when spent.

const SPEED: float = 900.0
const LIFETIME: float = 1.2
const MAX_PIERCE: int = 3

var direction: Vector2 = Vector2.RIGHT
var damage: int = 18
var travelled: float = 0.0
var hit_ids: Dictionary = {}
var pierced: int = 0
var visual_only: bool = false
var _is_splinter: bool = false


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	damage = dmg
	visual_only = ctx.is_visual_only
	_is_splinter = bool(ctx.get_mod("splinter", false))
	if visual_only:
		set_meta("visual_only", true)
	rotation = direction.angle()
	if _is_splinter:
		scale = Vector2(0.55, 0.55)


func _ready() -> void:
	collision_layer = 4
	collision_mask = 17  # walls + enemy hurtbox
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	# Build the spear sprite.
	var s := Sprite2D.new()
	var path := "res://assets/sprites/effects/bone_spear_projectile.png"
	if ResourceLoader.exists(path):
		s.texture = load(path) as Texture2D
	s.modulate = Color(0.95, 0.85, 1.0, 1)
	# Normalize size — typical projectile ~64 px tall.
	if s.texture:
		var src_h: float = float(s.texture.get_size().y)
		if src_h > 1.0:
			var sc: float = clamp(64.0 / src_h, 0.05, 0.5)
			s.scale = Vector2(sc, sc)
	add_child(s)
	# Add a small collision shape so the Area2D actually overlaps.
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 22.0
	cs.shape = shape
	add_child(cs)
	# Life timer.
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
	if travelled > 1400.0:
		_die()


func _on_area_entered(area: Area2D) -> void:
	if visual_only:
		return
	if not area.is_in_group("enemy_hit"):
		return
	var enemy := area.get_parent()
	if enemy == null:
		return
	var id: int = enemy.get_instance_id()
	if hit_ids.has(id):
		return
	hit_ids[id] = true
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage, global_position)
	if VfxManager:
		VfxManager.spawn_hit_sparks(global_position, Color(0.85, 0.5, 1.0, 1), 5)
	pierced += 1
	if pierced >= MAX_PIERCE:
		_die()


func _on_body_entered(body: Node) -> void:
	if body is StaticBody2D:
		_die()


func _die() -> void:
	# Bone Spear unique — shatter into a 3-splinter fan once spent (only when
	# the spear actually pierced something; whiffs into a wall don't shatter).
	if (
		not _is_splinter
		and not visual_only
		and pierced > 0
		and InventorySystem
		and InventorySystem.has_unique("bone_spear_splinters")
	):
		_spawn_splinters()
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	queue_free()


func _spawn_splinters() -> void:
	if not is_inside_tree():
		return
	var packed: PackedScene = load(scene_file_path) as PackedScene
	var parent := get_tree().current_scene
	if packed == null or parent == null:
		return
	for angle in [-PI / 4.0, 0.0, PI / 4.0]:
		var child: Node2D = packed.instantiate()
		child.position = global_position
		var mods: Dictionary = {"splinter": true, "visual_only": visual_only}
		var ctx := SkillContext.from_mods(
			direction.rotated(float(angle)), int(round(float(damage) * 0.5)), mods
		)
		SkillContext.apply(child, ctx)
		parent.add_child(child)
