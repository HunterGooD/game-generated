extends Node2D

# Lightning Overdrive — Thunderblade (Stormcaller) R. A 14s overload: empowers the
# caster (damage + attack speed) and, when it ends, releases a Static Burst that
# zaps and statics nearby foes.

const DURATION: float = 14.0
const BURST_RADIUS: float = 220.0

var damage: int = 24
var visual_only: bool = false
var caster: Node2D = null
var _t: float = DURATION


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	if caster and caster.has_method("apply_buff"):
		caster.call("apply_buff", DURATION, 1.3, 1.15)
	if caster and caster.has_method("add_static_charge"):
		caster.call("add_static_charge", 3)
	if VfxManager and caster is Node2D:
		VfxManager.spawn_hit_sparks((caster as Node2D).global_position, Color(0.7, 0.85, 1.0, 1), 18)


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_static_burst()
		queue_free()


func _static_burst() -> void:
	var pos: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	if VfxManager:
		VfxManager.spawn_explosion(pos, 1.5, Color(0.7, 0.85, 1.0, 1))
		VfxManager.screen_shake(5.0, 0.2)
	if visual_only:
		return
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		if pos.distance_to((e as Node2D).global_position) > BURST_RADIUS:
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", damage, pos)
		if e.has_method("mark_element"):
			e.call("mark_element", "storm")
