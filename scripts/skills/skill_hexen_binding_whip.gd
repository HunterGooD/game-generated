extends Node2D

# Binding Whip — Coven Mother transform of Blood Whip. A lashing pull: damages
# enemies in front and drags them toward the caster (peeling them off allies).

const RANGE: float = 220.0
const ARC_DOT: float = 0.2
const PULL: float = 280.0

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
	var origin: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	if VfxManager:
		VfxManager.spawn_hit_sparks(origin + direction * 120.0, Color(0.7, 0.1, 0.2, 1), 8)
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				var rel: Vector2 = (e as Node2D).global_position - origin
				if rel.length() > RANGE or direction.dot(rel.normalized()) < ARC_DOT:
					continue
				if e.has_method("take_damage"):
					e.call("take_damage", damage, origin)
				if e.has_method("set"):
					(e as Node2D).set("velocity", (origin - (e as Node2D).global_position).normalized() * PULL)
	var t := get_tree().create_timer(0.3)
	t.timeout.connect(queue_free)
