extends Node2D

# Rescue Step — Conductor transform of Storm Step. Dash to the nearest ally, shield
# them on arrival and shove enemies away from the landing.

const MAX_DASH: float = 420.0
const SHIELD_FRAC: float = 0.15
const SHOVE_RADIUS: float = 130.0

var damage: int = 16
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
	var dest: Vector2 = origin + direction * 200.0
	var ally: Node2D = _nearest_ally(origin)
	if ally:
		dest = (ally as Node2D).global_position
	if caster and is_instance_valid(caster):
		var tw := (caster as Node2D).create_tween()
		tw.tween_property(caster, "global_position", dest, 0.16).set_trans(Tween.TRANS_QUAD)
	if VfxManager:
		VfxManager.spawn_hit_sparks(dest, Color(0.6, 0.85, 1.0, 1), 10)
	if not visual_only:
		var max_hp: float = float(GameManager.player_max_hp) if GameManager else 100.0
		if ally and ally.has_method("add_shield"):
			ally.call("add_shield", max_hp * SHIELD_FRAC, -1.0)
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				var ep: Vector2 = (e as Node2D).global_position
				if dest.distance_to(ep) > SHOVE_RADIUS:
					continue
				if e.has_method("take_damage"):
					e.call("take_damage", damage, dest)
				if e.has_method("set"):
					(e as Node2D).set("velocity", (ep - dest).normalized() * 260.0)
	var t := get_tree().create_timer(0.3)
	t.timeout.connect(queue_free)


func _nearest_ally(from: Vector2) -> Node2D:
	var best: Node2D = null
	var bd: float = MAX_DASH
	for rp in get_tree().get_nodes_in_group("remote_player"):
		if not is_instance_valid(rp) or not (rp is Node2D):
			continue
		var d: float = from.distance_to((rp as Node2D).global_position)
		if d < bd:
			bd = d
			best = rp
	return best
