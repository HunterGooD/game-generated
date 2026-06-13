extends Node2D

# Fire wall — a line of flames perpendicular to cast direction.
# Damages enemies entering its hurt area.

const LIFETIME: float = 3.0
const WIDTH: float = 220.0
const DAMAGE_TICK_INTERVAL: float = 0.4

@export var hurt_area: Area2D
@export var hit_box: HitBoxComponent

var damage: int = 8
var direction: Vector2 = Vector2.RIGHT
var tick_t: float = 0.0
var life: float = LIFETIME
var enemies_inside: Array = []
var is_ice: bool = false
var width_mult: float = 1.0
var tick_interval: float = DAMAGE_TICK_INTERVAL
var caster_ref: Node = null


func setup(dir: Vector2, dmg: int) -> void:
	setup_context(SkillContext.from_mods(dir, dmg, {}))


var _ctx: SkillContext = null


func setup_context(ctx: SkillContext) -> void:
	_ctx = ctx
	var dir := ctx.direction
	var dmg := ctx.damage
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	damage = dmg
	caster_ref = ctx.caster
	rotation = direction.angle() + PI / 2.0
	var dur_stacks: int = int(ctx.get_mod("duration_stacks", 0))
	var rad_stacks: int = int(ctx.get_mod("radius_stacks", 0))
	life = LIFETIME + 1.5 * float(dur_stacks)
	tick_interval = max(0.15, DAMAGE_TICK_INTERVAL - 0.08 * float(dur_stacks))
	width_mult = 1.0 + 0.35 * float(rad_stacks)
	is_ice = ctx.transform == "ice_wall"


func _ready() -> void:
	if hit_box:
		hit_box.monitoring = false
		hit_box.monitorable = false
		hit_box.payload = _build_damage_payload()
	if hurt_area:
		hurt_area.collision_layer = 0
		hurt_area.collision_mask = 16  # bit 5 — enemy hurtboxes
		hurt_area.area_entered.connect(_on_area_entered)
		hurt_area.area_exited.connect(_on_area_exited)

	# Resize collision shape per radius modifier.
	if hurt_area:
		var sh: CollisionShape2D = hurt_area.get_node_or_null("HurtShape") as CollisionShape2D
		if sh and sh.shape is RectangleShape2D:
			var rs: RectangleShape2D = sh.shape.duplicate() as RectangleShape2D
			rs.size = Vector2(rs.size.x * width_mult, rs.size.y)
			sh.shape = rs
	_spawn_flames()
	# Light flash + shake on spawn.
	if VfxManager:
		var col: Color = Color(0.55, 0.85, 1.4, 1) if is_ice else Color(1.0, 0.6, 0.25, 1)
		VfxManager.spawn_explosion(global_position, 0.8, col)


func _spawn_flames() -> void:
	# Spawn 8 flame sprites along the wall.
	var tex: Texture2D = null
	var path := "res://assets/sprites/effects/fire_flame.png"
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		return
	var effective_width: float = WIDTH * width_mult
	var hot: Color = Color(0.55, 0.85, 1.4, 1.0) if is_ice else Color(1.4, 1.0, 0.6, 1.0)
	var cool: Color = Color(0.35, 0.65, 1.1, 1.0) if is_ice else Color(0.9, 0.5, 0.3, 1.0)
	for i in 9:
		var s := Sprite2D.new()
		s.texture = tex
		var t: float = float(i) / 8.0
		var x: float = lerp(-effective_width / 2.0, effective_width / 2.0, t)
		s.position = Vector2(x, randf_range(-6.0, 6.0))
		var sc: float = randf_range(0.45, 0.7)
		s.scale = Vector2(sc, sc)
		s.modulate = hot
		s.z_index = 60
		add_child(s)
		var tw := create_tween().set_loops()
		tw.tween_property(s, "modulate", hot, randf_range(0.1, 0.25))
		tw.tween_property(s, "modulate", cool, randf_range(0.1, 0.25))

	# Glow light.
	var light := PointLight2D.new()
	var grad := GradientTexture2D.new()
	grad.width = 384
	grad.height = 256
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	if is_ice:
		g.colors = PackedColorArray([Color(0.55, 0.85, 1.4, 1.0), Color(0.55, 0.85, 1.4, 0.0)])
		light.color = Color(0.55, 0.85, 1.4, 1.0)
	else:
		g.colors = PackedColorArray([Color(1.0, 0.7, 0.3, 1.0), Color(1.0, 0.5, 0.1, 0.0)])
		light.color = Color(1.0, 0.7, 0.3, 1.0)
	grad.gradient = g
	light.texture = grad
	light.energy = 1.8
	light.texture_scale = 1.8 * width_mult
	light.z_index = 55
	add_child(light)


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		_extinguish()
		return
	tick_t -= delta
	if tick_t <= 0.0:
		tick_t = tick_interval
		for area in enemies_inside:
			if is_instance_valid(area):
				var enemy = area.get_parent()
				if area is HurtBoxComponent and hit_box:
					hit_box.payload = _build_damage_payload()
					(area as HurtBoxComponent).receive_hit(hit_box)
				else:
					if enemy and enemy.has_method("take_damage"):
						enemy.take_damage(damage, global_position)
				if _ctx != null:
					_ctx.apply_on_hit(enemy)
				if is_ice and enemy and enemy.has_method("apply_slow"):
					enemy.apply_slow(1.2, 0.4)
					if enemy.has_method("mark_element"):
						enemy.call("mark_element", "frost")
				elif enemy and enemy.has_method("mark_element"):
					enemy.call("mark_element", "fire")


func _on_area_entered(area: Area2D) -> void:
	if not enemies_inside.has(area):
		enemies_inside.append(area)


func _on_area_exited(area: Area2D) -> void:
	enemies_inside.erase(area)


func _extinguish() -> void:
	if hurt_area:
		hurt_area.set_deferred("monitoring", false)
	# Fade smoke and remove.
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)


func _build_damage_payload() -> DamageInstance:
	var tags: Array[StringName] = [&"player", &"skill", &"fire_wall"]
	if is_ice:
		tags.append(&"ice_wall")
	else:
		tags.append(&"fire")
	return DamageInstance.new(float(damage), _resolve_damage_source(), self, tags, [])


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
