extends Node2D

# Flame Cleave — Battlemage transform of Fire Wall (slot 0). A wide fiery arc in
# front of the caster that ignites everything it hits. While Arcane Flameblade is
# active it strikes TWICE (a second, larger sweep a beat later).

const LIFETIME: float = 0.4
const ARC_RADIUS: float = 190.0
const KNOCKBACK: float = 140.0
const BURN_DURATION: float = 4.0

var damage: int = 24
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false
var caster: Node2D = null
var double_strike: bool = false
var hit_set: Dictionary = {}


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = ctx.is_visual_only
	caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)
	# Double sweep while Flameblade empowers the blade.
	if caster and caster.has_method("is_flameblade_active"):
		double_strike = bool(caster.call("is_flameblade_active"))
	rotation = direction.angle()


func _ready() -> void:
	z_index = 60
	_spawn_arc_visual(1.0)
	if not visual_only:
		var t := get_tree().create_timer(0.08)
		t.timeout.connect(_apply_damage.bind(1.0))
		if double_strike:
			var t2 := get_tree().create_timer(0.26)
			t2.timeout.connect(_apply_damage.bind(1.3))
			var tv := get_tree().create_timer(0.18)
			tv.timeout.connect(_spawn_arc_visual.bind(1.4))
	var dt := get_tree().create_timer((0.5 if double_strike else LIFETIME) + 0.1)
	dt.timeout.connect(queue_free)


func _spawn_arc_visual(scale_mult: float) -> void:
	var flash := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		flash.texture = load(path) as Texture2D
	flash.modulate = Color(1.0, 0.55, 0.2, 0.95)
	flash.position = Vector2(90, 0)
	flash.scale = Vector2(scale_mult, scale_mult)
	add_child(flash)
	var tw := flash.create_tween().set_parallel(true)
	(
		tw
		. tween_property(flash, "scale", flash.scale * 1.7, LIFETIME)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(flash, "modulate:a", 0.0, LIFETIME)


func _apply_damage(scale_mult: float) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var origin: Vector2 = global_position
	var radius: float = ARC_RADIUS * scale_mult
	var dps: float = float(damage) * 0.6
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var to_e_vec: Vector2 = (e as Node2D).global_position - origin
		var d: float = to_e_vec.length()
		if d > radius:
			continue
		var to_e: Vector2 = to_e_vec.normalized() if d > 0.001 else direction
		if direction.dot(to_e) < -0.3:
			continue
		var id: int = e.get_instance_id()
		if hit_set.has(id):
			continue
		hit_set[id] = true
		if e.has_method("take_damage"):
			e.take_damage(int(round(float(damage) * scale_mult)), origin)
		if e.has_method("apply_burn"):
			e.call("apply_burn", BURN_DURATION, dps)
		if e.has_method("set"):
			(e as Node2D).set("velocity", to_e * KNOCKBACK)
	if VfxManager:
		VfxManager.spawn_hit_sparks(origin + direction * 110.0, Color(1.0, 0.6, 0.2, 1), 12)
		VfxManager.screen_shake(3.0, 0.14)
		VfxManager.hit_stop(0.04)
