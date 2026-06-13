extends Area2D

# Ice bolt — fast projectile with slow effect on impact.

const SPEED: float = 760.0
const LIFETIME: float = 1.4
const SLOW_DURATION: float = 3.0
const SLOW_MULT: float = 0.45

@export var sprite: Sprite2D
@export var hit_box: HitBoxComponent

var direction: Vector2 = Vector2.RIGHT
var damage: int = 14
var travelled: float = 0.0
var trail_t: float = 0.0
var pierce: bool = false
var pierced_set: Dictionary = {}
var slow_duration: float = SLOW_DURATION
var slow_mult: float = SLOW_MULT
var _caster: Node = null
var _ctx: SkillContext = null


func setup(dir: Vector2, dmg: int) -> void:
	setup_context(SkillContext.from_mods(dir, dmg, {}))


func setup_context(ctx: SkillContext) -> void:
	_ctx = ctx
	var dir := ctx.direction
	var dmg := ctx.damage
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	damage = dmg
	rotation = direction.angle()
	_caster = ctx.caster
	pierce = bool(ctx.get_mod("pierce", false))
	var slow_stacks: int = int(ctx.get_mod("slow_stacks", 0))
	slow_duration = SLOW_DURATION + 1.5 * float(slow_stacks)
	slow_mult = max(0.2, SLOW_MULT - 0.08 * float(slow_stacks))
	if hit_box:
		hit_box.payload = _build_damage_payload()


func _ready() -> void:
	collision_layer = 4
	collision_mask = 17  # 1 (walls) | 16 (enemy hurtbox)
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	if hit_box:
		hit_box.collision_layer = 4
		hit_box.collision_mask = 16
		hit_box.hit.connect(_on_hit_hurtbox)
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
	trail_t -= delta
	if trail_t <= 0.0:
		trail_t = 0.04
		_spawn_trail()


func _spawn_trail() -> void:
	var tex: Texture2D = null
	var path := "res://assets/sprites/effects/ice_shard.png"
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.modulate = Color(0.7, 0.9, 1.4, 0.9)
	s.scale = Vector2(0.18, 0.18)
	s.position = global_position
	s.rotation = randf() * TAU
	s.z_index = 140
	get_tree().current_scene.add_child(s)
	# Bind the fade tween to the TRAIL sprite, not the bolt: the bolt queue_free()s
	# on impact, which would kill a bolt-owned tween mid-fade and strand the trail
	# sprite (parented to the scene) frozen on the ground. Owned by `s`, the fade
	# always completes and frees itself.
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "modulate:a", 0.0, 0.3)
	tw.tween_property(s, "scale", Vector2(0.05, 0.05), 0.3)
	tw.chain().tween_callback(s.queue_free)


func _on_area_entered(area: Area2D) -> void:
	if area is HurtBoxComponent:
		return
	if not area.is_in_group("enemy_hit"):
		return
	var enemy = area.get_parent()
	if enemy == null:
		return
	var id: int = enemy.get_instance_id()
	if pierced_set.has(id):
		return
	pierced_set[id] = true
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage, global_position)
	if enemy.has_method("apply_slow"):
		enemy.apply_slow(slow_duration, slow_mult)
	if enemy.has_method("mark_element"):
		enemy.call("mark_element", "frost")
	if _ctx != null:
		_ctx.apply_on_hit(enemy)
	if VfxManager:
		VfxManager.spawn_hit_sparks(enemy.global_position, Color(0.7, 0.9, 1.4, 1.0), 8)
	if pierce:
		# Continue flying; slight damage decay per hit.
		damage = max(1, int(round(float(damage) * 0.75)))
		if hit_box:
			hit_box.payload = _build_damage_payload()
	else:
		_impact()


func _on_hit_hurtbox(area: Area2D) -> void:
	var enemy := area.get_parent()
	if enemy == null:
		return
	var id: int = enemy.get_instance_id()
	if pierced_set.has(id):
		return
	pierced_set[id] = true
	if enemy.has_method("apply_slow"):
		enemy.apply_slow(slow_duration, slow_mult)
	if _ctx != null:
		_ctx.apply_on_hit(enemy)
	if VfxManager:
		VfxManager.spawn_hit_sparks(enemy.global_position, Color(0.7, 0.9, 1.4, 1.0), 8)
	if pierce:
		damage = max(1, int(round(float(damage) * 0.75)))
		if hit_box:
			hit_box.payload = _build_damage_payload()
	else:
		_impact()


func _on_body_entered(body: Node) -> void:
	if body is StaticBody2D or body is TileMap:
		_impact()


func _impact() -> void:
	# Ice shatter burst.
	if VfxManager:
		var tex: Texture2D = null
		if ResourceLoader.exists("res://assets/sprites/effects/ice_shard.png"):
			tex = load("res://assets/sprites/effects/ice_shard.png") as Texture2D
		# Use the manager's helper-ish API by manually spawning sparks of blue.
		VfxManager.spawn_hit_sparks(global_position, Color(0.7, 0.9, 1.4, 1.0), 10)
		VfxManager._spawn_light_flash(global_position, Color(0.7, 0.9, 1.4, 1.0), 0.25, 1.8, 1.8)
	_die()


func _die() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	queue_free()


func _build_damage_payload() -> DamageInstance:
	# Prefer the caster passed in via ctx. Only scan the tree as a fallback,
	# and only when we're actually inside it (setup_context runs before the
	# projectile is added to the scene, so get_tree() would be null otherwise).
	var attacker: Node = _caster
	if attacker == null and is_inside_tree():
		attacker = _resolve_local_player()
	return DamageInstance.new(float(damage), attacker, self, [&"player", &"projectile", &"ice"], [])


func _resolve_local_player() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("player"):
		if node is Node and not node.is_in_group("remote_player"):
			return node
	return null
