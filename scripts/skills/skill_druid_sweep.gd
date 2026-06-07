extends Node2D

# Sweeping Maul — bear-form wide arc with heavy damage and knockback.

const LIFETIME: float = 0.35
const ARC_RADIUS: float = 180.0
const KNOCKBACK: float = 220.0

var damage: int = 30
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false
var hit_set: Dictionary = {}


func setup_with_mods(dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)
	rotation = direction.angle()


func _ready() -> void:
	z_index = 60
	var flash := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		flash.texture = load(path) as Texture2D
	flash.modulate = Color(0.85, 0.7, 0.4, 0.95)
	flash.scale = Vector2(1.0, 1.0)
	flash.position = Vector2(80, 0)
	add_child(flash)
	var tw := flash.create_tween().set_parallel(true)
	(
		tw
		. tween_property(flash, "scale", Vector2(1.6, 1.6), LIFETIME)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(flash, "modulate:a", 0.0, LIFETIME)
	if not visual_only:
		var t := get_tree().create_timer(0.1)
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
		# Wide 130-degree arc — dot threshold lower.
		var to_e: Vector2 = to_e_vec.normalized() if d > 0.001 else direction
		if direction.dot(to_e) < -0.3:
			continue
		var id: int = e.get_instance_id()
		if hit_set.has(id):
			continue
		hit_set[id] = true
		if e.has_method("take_damage"):
			e.take_damage(damage, origin)
		# Knockback.
		if (e as Node2D).has_method("set"):
			var kb: Vector2 = to_e * KNOCKBACK
			(e as Node2D).set("velocity", kb)
	if VfxManager:
		VfxManager.spawn_hit_sparks(origin + direction * 100.0, Color(1.0, 0.7, 0.4, 1), 12)
		VfxManager.screen_shake(4.0, 0.18)
		VfxManager.hit_stop(0.05)
