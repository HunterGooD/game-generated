extends Node2D

# Ally Tether — Coven Mother transform of Soul Tether. Bonds the nearest ally to the
# nearest enemy: damages the enemy and shields the ally (sharing the harm).

const RANGE: float = 280.0

var damage: int = 20
var visual_only: bool = false
var caster: Node2D = null


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	var origin: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	if not visual_only:
		var enemy: Node2D = _nearest("enemy", origin)
		var ally: Node2D = _nearest("remote_player", origin)
		if ally == null and caster is Node2D:
			ally = caster as Node2D
		if enemy:
			if enemy.has_method("take_damage"):
				enemy.call("take_damage", damage, origin)
			if enemy.has_method("add_curse_stack"):
				enemy.call("add_curse_stack")
		if ally and ally.has_method("add_shield"):
			ally.call("add_shield", float(damage) * 0.6, -1.0)
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)


func _nearest(grp: String, from: Vector2) -> Node2D:
	var best: Node2D = null
	var bd: float = RANGE
	for n in get_tree().get_nodes_in_group(grp):
		if not is_instance_valid(n) or not (n is Node2D) or bool(n.get("dead")):
			continue
		var d: float = from.distance_to((n as Node2D).global_position)
		if d < bd:
			bd = d
			best = n
	return best
