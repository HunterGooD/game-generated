extends Node2D

# Wind Gust — wide forward cone that pushes enemies away and deals light damage.

const LIFETIME: float = 0.35
const ARC_RADIUS: float = 200.0
const KNOCKBACK: float = 320.0

var damage: int = 18
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false
var hit_set: Dictionary = {}


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)
	rotation = direction.angle()


func _ready() -> void:
	z_index = 60
	# Procedural clean pale-wind slash (replaces the flat PNG arc).
	SlashFx.spawn(self, "white", Vector2(90, 0), 1.1, LIFETIME, Color(0.8, 0.95, 1.0))
	if not visual_only:
		var t := get_tree().create_timer(0.06)
		t.timeout.connect(_apply_damage)
	var dt := get_tree().create_timer(LIFETIME + 0.05)
	dt.timeout.connect(queue_free)


func _apply_damage() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var origin: Vector2 = global_position
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var to_e_vec: Vector2 = (e as Node2D).global_position - origin
		var d: float = to_e_vec.length()
		if d > ARC_RADIUS:
			continue
		var to_e: Vector2 = to_e_vec.normalized() if d > 0.001 else direction
		if direction.dot(to_e) < -0.1:
			continue
		var id: int = e.get_instance_id()
		if hit_set.has(id):
			continue
		hit_set[id] = true
		if e.has_method("take_damage"):
			e.take_damage(damage, origin)
		# Knockback along the gust direction.
		if (e as Node2D).has_method("set"):
			(e as Node2D).set("velocity", direction * KNOCKBACK)
	if VfxManager:
		VfxManager.spawn_hit_sparks(origin + direction * 120.0, Color(0.85, 0.95, 1.0, 1), 14)
		VfxManager.screen_shake(2.0, 0.1)
