extends Node2D

# Grand Malediction — Curseweaver (Hexen) R. Curses every enemy in a wide radius
# (Armor Break + Bleed + a curse stack). Enemies that were already Hex-Marked
# detonate instantly for bonus damage.

const RADIUS: float = 300.0

var damage: int = 26
var visual_only: bool = false


func setup_context(ctx: SkillContext) -> void:
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)


func _ready() -> void:
	if VfxManager:
		VfxManager.spawn_explosion(global_position, 2.0, Color(0.6, 0.1, 0.7, 1))
		VfxManager.screen_shake(5.0, 0.25)
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or bool(e.get("dead")):
					continue
				if global_position.distance_to((e as Node2D).global_position) > RADIUS:
					continue
				_curse(e)
				# Already Hex-Marked → detonate now.
				if e.has_meta("hex_marked") and e.has_method("take_damage"):
					e.call("take_damage", int(round(float(damage) * 1.5)), global_position)
					e.set_meta("hex_marked", false)
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(queue_free)


# Roll 3 distinct mini-curses per the spec: Frailty (-armor → takes more),
# Misfortune (attacks whiff), Agony (DoT), Doom (corpse-burst). Power scales
# with the ability damage. Falls back to legacy vulnerable+stack for enemies
# without the named-curse API (bosses).
func _curse(e: Node) -> void:
	if not e.has_method("apply_curse"):
		if e.has_method("apply_vulnerable"):
			e.call("apply_vulnerable", 6.0, 0.25)
		if e.has_method("add_curse_stack"):
			e.call("add_curse_stack")
		return
	var pool: Array = ["frailty", "misfortune", "agony", "doom"]
	pool.shuffle()
	for i in 3:
		var id: String = String(pool[i])
		var power: float = 0.0
		match id:
			"agony":
				power = float(damage) * 0.35
			"doom":
				power = float(damage) * 1.5
		e.call("apply_curse", id, 6.0, power)
