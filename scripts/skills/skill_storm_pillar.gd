extends Node2D

# Storm Pillar — Tempest Lord transform of Sky Strike. The strike leaves a crackling
# pillar that zaps nearby enemies for a few seconds.

const TELEGRAPH: float = 0.5
const LIFETIME: float = 4.0
const RADIUS: float = 120.0
const TICK: float = 0.5

var damage: int = 24
var visual_only: bool = false
var _life: float = LIFETIME
var _t: float = 0.0
var _struck: bool = false


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 20
	var tel := Sprite2D.new()
	var path := "res://assets/sprites/effects/meteor_telegraph.png"
	if ResourceLoader.exists(path):
		tel.texture = load(path) as Texture2D
	tel.modulate = Color(0.6, 0.8, 1.0, 0.6)
	add_child(tel)
	var t := get_tree().create_timer(TELEGRAPH)
	t.timeout.connect(_strike)


func _strike() -> void:
	_struck = true
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 1.3, Color(0.7, 0.9, 1.0, 1))
		VfxManager.screen_shake(5.0, 0.2)


func _process(delta: float) -> void:
	if not _struck:
		return
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > RADIUS:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", int(round(float(damage) * 0.5)), global_position)
		if e.has_method("mark_element"):
			e.call("mark_element", "storm")
