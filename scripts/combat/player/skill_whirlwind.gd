extends Node2D

# Whirlwind — spins around the caster, ticking damage to nearby enemies.

const LIFETIME: float = 1.6
const RADIUS: float = 150.0
const TICK_INTERVAL: float = 0.18

@export var hurt_area: Area2D
@export var sprite: Sprite2D
@export var hit_box: HitBoxComponent

var damage: int = 12
var life: float = LIFETIME
var tick_t: float = 0.0
var _spin_tween: Tween = null
var caster_ref: Node = null

var _ctx: SkillContext = null


func setup_context(ctx: SkillContext) -> void:
	_ctx = ctx
	var dmg := ctx.damage
	damage = dmg
	caster_ref = ctx.caster


func _ready() -> void:
	if hit_box:
		hit_box.monitoring = false
		hit_box.monitorable = false
		hit_box.payload = _build_damage_payload()
	if hurt_area:
		hurt_area.collision_layer = 0
		hurt_area.collision_mask = 16
		var sh: CollisionShape2D = hurt_area.get_node_or_null("HurtShape") as CollisionShape2D
		if sh and sh.shape is CircleShape2D:
			var cs: CircleShape2D = sh.shape.duplicate() as CircleShape2D
			cs.radius = RADIUS
			sh.shape = cs
	if sprite:
		# Bind the loop tween to the SPRITE (not the tree) so it auto-dies on free.
		_spin_tween = sprite.create_tween().set_loops()
		_spin_tween.tween_property(sprite, "rotation", sprite.rotation + TAU, 0.35)
	if VfxManager:
		VfxManager.screen_shake(1.5, 0.15)


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		_finish()
		return
	tick_t -= delta
	if tick_t <= 0.0:
		tick_t = TICK_INTERVAL
		_tick_damage()


func _tick_damage() -> void:
	if hurt_area == null:
		return
	for area in hurt_area.get_overlapping_areas():
		if not area.is_in_group("enemy_hit"):
			continue
		var enemy = area.get_parent()
		if area is HurtBoxComponent and hit_box:
			hit_box.payload = _build_damage_payload()
			(area as HurtBoxComponent).receive_hit(hit_box)
			if enemy and _ctx != null:
				_ctx.apply_on_hit(enemy)
		elif enemy and enemy.has_method("take_damage"):
			enemy.take_damage(damage, global_position)
			if _ctx != null:
				_ctx.apply_on_hit(enemy)
		if enemy and VfxManager and randi() % 3 == 0:
			VfxManager.spawn_hit_sparks(enemy.global_position, Color(1, 0.7, 0.4, 1), 4)


func _finish() -> void:
	if hurt_area:
		hurt_area.set_deferred("monitoring", false)
		hurt_area.set_deferred("monitorable", false)
	# Kill the spin tween FIRST so it can't keep mutating a freed sprite
	# and hold a phantom reference. Hide the blade explicitly the same frame.
	if _spin_tween and _spin_tween.is_valid():
		_spin_tween.kill()
	_spin_tween = null
	if sprite:
		sprite.visible = false
	# Worldcleaver unique: leave a ring of fire after Whirlwind ends.
	_maybe_leave_fire_ring()
	queue_free()


func _maybe_leave_fire_ring() -> void:
	# Inventory unique "berserkers_halo" leaves a fire ring on Whirlwind end.
	if InventorySystem == null:
		return
	if not InventorySystem.has_unique("berserkers_halo"):
		return
	if not is_inside_tree():
		return
	var ring_scene_path: String = "res://scenes/combat/player/fire_ring.tscn"
	if not ResourceLoader.exists(ring_scene_path):
		return
	var ring_packed: PackedScene = load(ring_scene_path) as PackedScene
	if ring_packed == null:
		return
	var ring: Node2D = ring_packed.instantiate()
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position
	if ring.has_method("setup"):
		ring.call("setup", damage)


func _build_damage_payload() -> DamageInstance:
	return DamageInstance.new(
		float(damage), _resolve_damage_source(), self, [&"player", &"skill", &"whirlwind"], []
	)


func _resolve_damage_source() -> Node:
	if is_instance_valid(caster_ref):
		return caster_ref
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("player"):
		if node is Node and not node.is_in_group("remote_player"):
			return node
	return null
