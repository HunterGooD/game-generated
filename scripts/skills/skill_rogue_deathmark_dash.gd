extends Node2D

# Deathmark Dash — Assassin (Rogue) R. Blink through the aim point, striking every
# enemy along the line. Heavy execute on low-HP targets; opens the Backstab Window.

const MAX_DASH: float = 360.0
const WIDTH: float = 70.0
const EXECUTE_HP_FRAC: float = 0.25

var damage: int = 30
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false
var caster: Node2D = null


func setup_with_mods(dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = bool(mods.get("visual_only", false))
	caster = mods.get("caster", null)
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	z_index = 55
	var origin: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	var dest: Vector2 = origin
	if caster and is_instance_valid(caster):
		var to_m: Vector2 = caster.get_global_mouse_position() - origin
		dest = origin + direction * min(to_m.length(), MAX_DASH)
		var tw := (caster as Node2D).create_tween()
		tw.tween_property(caster, "global_position", dest, 0.16).set_trans(Tween.TRANS_QUAD)
		if caster.has_method("start_backstab"):
			caster.call("start_backstab", 2.0)
	if VfxManager:
		VfxManager.spawn_hit_sparks(origin, Color(0.8, 0.2, 0.3, 1), 10)
		VfxManager.spawn_hit_sparks(dest, Color(0.8, 0.2, 0.3, 1), 10)
	if not visual_only:
		_strike(origin, dest)
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)


func _strike(a: Vector2, b: Vector2) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var seg: Vector2 = b - a
	var seg_len: float = max(seg.length(), 1.0)
	var ndir: Vector2 = seg / seg_len
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var rel: Vector2 = (e as Node2D).global_position - a
		var along: float = rel.dot(ndir)
		if along < -40.0 or along > seg_len + 40.0:
			continue
		if abs(rel.dot(Vector2(-ndir.y, ndir.x))) > WIDTH:
			continue
		var dmg: int = damage
		var ehp: float = float(e.get("hp"))
		var emax: float = float(e.get("max_hp"))
		if emax > 0.0 and ehp / emax <= EXECUTE_HP_FRAC:
			dmg = int(round(float(dmg) * (1.8 if emax >= 600 else 4.0) / 2.2))  # softer on elites
		if e.has_method("take_damage"):
			e.call("take_damage", dmg, a)
