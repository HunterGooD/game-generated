extends Node2D

# Ritual of Doom — Curseweaver transform of Crimson Ritual. Enemies inside gain a
# Doom timer; when it expires the zone erupts, hitting everyone still inside.

const FUSE: float = 2.5
const RADIUS: float = 200.0

var damage: int = 30
var visual_only: bool = false
var _t: float = FUSE


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 4
	var spr := Sprite2D.new()
	var path := "res://assets/sprites/effects/fire_ring.png"
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		spr.texture = load(path) as Texture2D
		var w: float = float(spr.texture.get_width())
		if w > 0.0:
			spr.scale = Vector2.ONE * (RADIUS * 2.0 / w)
	spr.modulate = Color(0.5, 0.05, 0.5, 0.45)
	add_child(spr)
	var tw := spr.create_tween().set_loops()
	tw.tween_property(spr, "modulate:a", 0.2, 0.3)
	tw.tween_property(spr, "modulate:a", 0.5, 0.3)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_detonate()
		queue_free()


func _detonate() -> void:
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 2.0, Color(0.7, 0.1, 0.7, 1))
		VfxManager.screen_shake(7.0, 0.3)
	if visual_only:
		return
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) <= RADIUS and e.has_method("take_damage"):
			e.call("take_damage", damage, global_position)
