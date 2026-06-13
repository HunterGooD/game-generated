extends Node2D

# Static Discharge — 320 px nova around the caster that consumes all current
# Static Charges, dealing damage proportional to stacks consumed.
# Capacitor Core unique: 6+ stacks consumed refunds half the cooldown.

const RADIUS: float = 320.0
const REFUND_THRESHOLD: int = 6

var damage: int = 28
var visual_only: bool = false
var caster: Node = null
var capacitor_core: bool = false

var _ctx: SkillContext = null


func setup_context(ctx: SkillContext) -> void:
	_ctx = ctx
	var dmg := ctx.damage
	damage = dmg
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)
	caster = ctx.caster
	# Capacitor Core — block variant (ctx.transform) or the unique.
	capacitor_core = ctx.transform == "storm_capacitor_core"


func _ready() -> void:
	z_index = 60
	# Visual nova.
	var s := Sprite2D.new()
	var path := "res://assets/sprites/effects/static_discharge_nova.png"
	if ResourceLoader.exists(path):
		s.texture = load(path) as Texture2D
	s.modulate = Color(0.7, 0.95, 1.6, 1)
	s.scale = Vector2(0.4, 0.4)
	add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector2(2.4, 2.4), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	tw.tween_property(s, "modulate:a", 0.0, 0.55)
	if VfxManager:
		VfxManager.screen_shake(5.0, 0.2)
		VfxManager.screen_flash(Color(0.7, 0.95, 1.5, 0.18), 0.25)
	if caster and is_instance_valid(caster) and caster.has_method("camera_punch"):
		caster.call("camera_punch", 0.10, 0.3)
	if not visual_only and caster and is_instance_valid(caster):
		var stacks: int = 0
		if caster.has_method("consume_static_charge"):
			stacks = int(caster.call("consume_static_charge"))
		# Total damage = base × (1.0 + stacks × 1.0). 0 stacks still deals base.
		var burst_dmg: int = int(round(float(damage) * (1.0 + float(stacks))))
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e):
					continue
				if e.get("dead") == true:
					continue
				if global_position.distance_to((e as Node2D).global_position) <= RADIUS:
					if e.has_method("take_damage"):
						e.call("take_damage", burst_dmg, global_position)
						if _ctx != null:
							_ctx.apply_on_hit(e)
		# Capacitor Core refund.
		if (
			stacks >= REFUND_THRESHOLD
			and (
				capacitor_core
				or (
					InventorySystem
					and InventorySystem.has_method("has_unique")
					and bool(InventorySystem.call("has_unique", "storm_capacitor_core"))
				)
			)
		):
			var ss = caster.get_node_or_null("SkillSystem")
			if ss and ss.cooldowns.size() > 3:
				ss.cooldowns[3] = ss.cooldowns[3] * 0.5
		# Stormcage Array 5pc — a big discharge calls a free Sky Strike on the
		# nearest enemy (no mana, no cooldown).
		if (
			stacks >= REFUND_THRESHOLD
			and InventorySystem
			and InventorySystem.has_method("has_set_effect")
			and InventorySystem.has_set_effect("storm_overcharge")
		):
			_fire_overcharge_sky_strike()
	var done := get_tree().create_timer(0.7)
	done.timeout.connect(queue_free)


func _fire_overcharge_sky_strike() -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var def: SkillDefinition = SkillCatalog.get_def("storm_sky_strike")
	if def == null:
		return
	# Nearest live enemy anywhere on screen-ish range.
	var best: Node2D = null
	var best_d: float = 900.0
	var tree := get_tree()
	if tree == null:
		return
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e.get("dead") == true:
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e as Node2D
	if best == null:
		return
	SkillCaster.spawn(def, caster as Node2D, best.global_position, damage, {"caster": caster})
