extends Node2D

# Stone Grinder — Titanbreaker transform of Whirlwind (slot 0). A grinding spin that
# drags lighter enemies inward (control → Seismic Momentum) while dealing reduced
# damage. Follows the caster (attached_to_caster).

const LIFETIME: float = 1.8
const RADIUS: float = 190.0
const TICK_INTERVAL: float = 0.18
const DMG_SCALE: float = 0.4  # -60% damage
const PULL_SPEED: float = 140.0
const SMALL_ENEMY_HP: int = 120  # only lighter foes get dragged

var damage: int = 14
var visual_only: bool = false
var caster: Node2D = null
var _life: float = LIFETIME
var _tick_t: float = 0.0


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = int(round(float(dmg) * DMG_SCALE))
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 40
	var blade := Sprite2D.new()
	var path := "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		blade.texture = load(path) as Texture2D
	blade.modulate = Color(0.7, 0.55, 0.4, 0.85)
	blade.scale = Vector2(1.8, 1.8)
	add_child(blade)
	var tw := blade.create_tween().set_loops()
	tw.tween_property(blade, "rotation", blade.rotation + TAU, 0.32)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if visual_only:
		return
	var tree := get_tree()
	if tree == null:
		return
	# Drag lighter enemies toward the center every frame.
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var ep: Vector2 = (e as Node2D).global_position
		var d: float = global_position.distance_to(ep)
		if d > RADIUS or d < 12.0:
			continue
		if int(e.get("max_hp")) <= SMALL_ENEMY_HP:
			var pull: Vector2 = (global_position - ep).normalized() * PULL_SPEED * delta
			(e as Node2D).global_position = ep + pull
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = TICK_INTERVAL
		_tick_damage()


func _tick_damage() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if global_position.distance_to((e as Node2D).global_position) > RADIUS:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", damage, global_position)
		if caster and caster.has_method("notify_control_applied"):
			caster.call("notify_control_applied")
