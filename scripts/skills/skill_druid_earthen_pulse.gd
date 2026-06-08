extends Node2D

# Earthen Pulse — Stormshaper transform of Stone Armor. Grants a one-hit stone ward
# and releases a stone shockwave that damages and knocks back nearby enemies.

const RADIUS: float = 170.0

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
	var pos: Vector2 = (caster as Node2D).global_position if caster is Node2D else global_position
	global_position = pos
	if VfxManager:
		VfxManager.spawn_explosion(pos, 1.2, Color(0.6, 0.5, 0.35, 1))
		VfxManager.screen_shake(4.0, 0.18)
	if not visual_only and caster:
		var cur: int = int(caster.get("stone_armor_charges")) if caster.has_method("get") else 0
		caster.set("stone_armor_charges", maxi(cur, 1))
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				var ep: Vector2 = (e as Node2D).global_position
				if pos.distance_to(ep) > RADIUS:
					continue
				if e.has_method("take_damage"):
					e.call("take_damage", damage, pos)
				if e.has_method("set"):
					(e as Node2D).set("velocity", (ep - pos).normalized() * 220.0)
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)
