extends Node2D

# Storm Step — short electric dash in cursor direction. Damages enemies in the
# path and adds Static Charge per hit. Stormveil unique slows enemies hit.

const STEP_TIME: float = 0.18
const MAX_DISTANCE: float = 240.0
const HIT_RADIUS: float = 70.0

var damage: int = 18
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false
var caster: Node = null
var start_pos: Vector2 = Vector2.ZERO
var end_pos: Vector2 = Vector2.ZERO
var stormveil: bool = false


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)
	caster = ctx.caster
	# Stormveil — block variant (ctx.transform) or the unique — slows enemies hit.
	stormveil = ctx.transform == "storm_stormveil"
	if caster:
		start_pos = (caster as Node2D).global_position
		var to_mouse: Vector2 = (caster as Node2D).get_global_mouse_position() - start_pos
		var dist: float = min(max(to_mouse.length(), 140.0), MAX_DISTANCE)
		end_pos = start_pos + direction * dist


func _ready() -> void:
	z_index = 60
	if start_pos == Vector2.ZERO:
		start_pos = global_position
		end_pos = start_pos + direction * 220.0
	if not visual_only and caster and is_instance_valid(caster):
		# Dash the caster.
		var tw := (caster as Node2D).create_tween()
		(
			tw
			. tween_property(caster, "global_position", end_pos, STEP_TIME)
			. set_trans(Tween.TRANS_QUART)
			. set_ease(Tween.EASE_OUT)
		)
		# Damage tick mid-dash.
		var t := get_tree().create_timer(STEP_TIME * 0.5)
		t.timeout.connect(_apply_damage)
		# Brief invuln on caster.
		if caster.get("invuln_t") != null:
			caster.set("invuln_t", max(float(caster.get("invuln_t")), STEP_TIME + 0.1))
	if VfxManager:
		VfxManager.spawn_hit_sparks(start_pos, Color(0.55, 0.85, 1.6, 1), 8)
	var done := get_tree().create_timer(STEP_TIME + 0.2)
	done.timeout.connect(queue_free)


func _apply_damage() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hit: Dictionary = {}
	if not stormveil:
		stormveil = (
			InventorySystem
			and InventorySystem.has_method("has_unique")
			and bool(InventorySystem.call("has_unique", "storm_stormveil"))
		)
	var steps: int = 5
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var p: Vector2 = start_pos.lerp(end_pos, t)
		for e in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(e):
				continue
			if e.get("dead") == true:
				continue
			var id: int = e.get_instance_id()
			if hit.has(id):
				continue
			if p.distance_to((e as Node2D).global_position) <= HIT_RADIUS:
				hit[id] = true
				if e.has_method("take_damage"):
					e.call("take_damage", damage, p)
				if stormveil and e.has_method("apply_slow"):
					e.call("apply_slow", 1.5, 0.5)
				if caster and caster.has_method("add_static_charge"):
					caster.call("add_static_charge", 1)
				if VfxManager:
					VfxManager.spawn_hit_sparks(
						(e as Node2D).global_position, Color(0.55, 0.85, 1.6, 1), 5
					)
