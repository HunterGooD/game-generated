extends Node2D

# Tempest Communion — Stormshaper (Druid) R. A natural storm rages around the druid
# for 12s, striking nearby enemies. (The per-form storm flavour is a planned
# refinement; this is the working mixed storm.)

const LIFETIME: float = 12.0
const RADIUS: float = 220.0
const TICK: float = 0.6

var damage: int = 22
var visual_only: bool = false
var caster: Node2D = null
var _life: float = LIFETIME
var _t: float = 0.0


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 5
	var spr := Sprite2D.new()
	var path := "res://assets/sprites/effects/fire_ring.png"
	if not ResourceLoader.exists(path):
		path = "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		spr.texture = load(path) as Texture2D
		var w: float = float(spr.texture.get_width())
		if w > 0.0:
			spr.scale = Vector2.ONE * (RADIUS * 2.0 / w)
	spr.modulate = Color(0.5, 0.7, 0.9, 0.4)
	add_child(spr)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	if caster is Node2D:
		global_position = (caster as Node2D).global_position
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	var tree := get_tree()
	if tree == null:
		return
	var hit_any := false
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > RADIUS:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", int(round(float(damage) * 0.5)), global_position)
		hit_any = true
	if hit_any and VfxManager:
		VfxManager.spawn_hit_sparks(global_position + Vector2(randf_range(-RADIUS, RADIUS), randf_range(-RADIUS, RADIUS)), Color(0.6, 0.8, 1.0, 1), 4)
