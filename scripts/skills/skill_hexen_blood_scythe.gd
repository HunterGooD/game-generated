extends Node2D

# Blood Scythe — Blood Witch transform of Blood Whip. A wide melee sweep that hits
# harder against cursed / hex-marked foes.

const RADIUS: float = 170.0
const ARC_DOT: float = -0.2
const CURSE_BONUS: float = 0.4

var damage: int = 24
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false


func setup_with_mods(dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)
	rotation = direction.angle()


func _ready() -> void:
	z_index = 50
	var flash := Sprite2D.new()
	var path := "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		flash.texture = load(path) as Texture2D
	flash.modulate = Color(0.8, 0.1, 0.15, 0.9)
	flash.position = Vector2(90, 0)
	add_child(flash)
	var tw := flash.create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector2(1.6, 1.6), 0.3)
	tw.tween_property(flash, "modulate:a", 0.0, 0.3)
	if not visual_only:
		_hit()
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)


func _hit() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var rel: Vector2 = (e as Node2D).global_position - global_position
		if rel.length() > RADIUS or direction.dot(rel.normalized()) < ARC_DOT:
			continue
		var dmg: int = damage
		if (e.has_meta("hex_marked")) or int(e.get("curse_stacks")) > 0:
			dmg = int(round(float(dmg) * (1.0 + CURSE_BONUS)))
		if e.has_method("take_damage"):
			e.call("take_damage", dmg, global_position)
		if e.has_method("apply_bleed"):
			e.call("apply_bleed", 3.0, float(damage) * 0.3)
