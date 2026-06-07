extends Node2D

# Static Discharge — 320 px nova around the caster that consumes all current
# Static Charges, dealing damage proportional to stacks consumed.
# Capacitor Core unique: 6+ stacks consumed refunds half the cooldown.

const RADIUS: float = 320.0
const REFUND_THRESHOLD: int = 6

var damage: int = 28
var visual_only: bool = false
var caster: Node = null


func setup_with_mods(_dir: Vector2, dmg: int, mods: Dictionary) -> void:
	damage = dmg
	visual_only = bool(mods.get("visual_only", false))
	if visual_only:
		set_meta("visual_only", true)
	caster = mods.get("caster", null)


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
		# Capacitor Core refund.
		if (
			stacks >= REFUND_THRESHOLD
			and InventorySystem
			and InventorySystem.has_method("has_unique")
			and bool(InventorySystem.call("has_unique", "storm_capacitor_core"))
		):
			var ss = caster.get_node_or_null("SkillSystem")
			if ss and ss.cooldowns.size() > 3:
				ss.cooldowns[3] = ss.cooldowns[3] * 0.5
	var done := get_tree().create_timer(0.7)
	done.timeout.connect(queue_free)
