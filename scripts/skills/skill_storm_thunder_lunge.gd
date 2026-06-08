extends Node2D

# Thunder Lunge — Thunderblade transform of Storm Step. A dashing lunge that damages
# and statics everything along the dash line.

const MAX_DASH: float = 320.0
const WIDTH: float = 64.0

var damage: int = 20
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
	z_index = 50
	var origin: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	var dest: Vector2 = origin
	if caster and is_instance_valid(caster):
		var to_m: Vector2 = caster.get_global_mouse_position() - origin
		dest = origin + direction * min(to_m.length(), MAX_DASH)
		var tw := (caster as Node2D).create_tween()
		tw.tween_property(caster, "global_position", dest, 0.15).set_trans(Tween.TRANS_QUAD)
	if VfxManager:
		VfxManager.spawn_hit_sparks(dest, Color(0.7, 0.85, 1.0, 1), 10)
	if not visual_only:
		var ndir: Vector2 = (dest - origin)
		var seg_len: float = max(ndir.length(), 1.0)
		ndir /= seg_len
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				var rel: Vector2 = (e as Node2D).global_position - origin
				var along: float = rel.dot(ndir)
				if along < -30.0 or along > seg_len + 30.0:
					continue
				if abs(rel.dot(Vector2(-ndir.y, ndir.x))) > WIDTH:
					continue
				if e.has_method("take_damage"):
					e.call("take_damage", damage, origin)
				if e.has_method("mark_element"):
					e.call("mark_element", "storm")
	var t := get_tree().create_timer(0.3)
	t.timeout.connect(queue_free)
