extends Node2D

# Charged Slash — Thunderblade transform of Chain Bolt. Trades the ranged bolt for a
# short lightning arc in front, staticking what it hits.

const RANGE: float = 150.0
const ARC_DOT: float = 0.3

var damage: int = 22
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false
var caster: Node2D = null


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	var origin: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	if VfxManager:
		VfxManager.spawn_hit_sparks(origin + direction * 90.0, Color(0.7, 0.9, 1.0, 1), 10)
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
				if e.has_method("mark_element"):
					e.call("mark_element", "storm")
	var t := get_tree().create_timer(0.3)
	t.timeout.connect(queue_free)
