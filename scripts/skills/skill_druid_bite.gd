extends Node2D

# Savage Bite — short cone-arc in front of the wolf-druid. High burst damage.

const LIFETIME: float = 0.28
const ARC_RADIUS: float = 130.0

var damage: int = 24
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false
var hit_set: Dictionary = {}
# "Alpha Predator" unique (dire_wolf_rend): bites bleed while in Dire Wolf form.
var _rend: bool = false


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = ctx.is_visual_only
	if visual_only:
		set_meta("visual_only", true)
	rotation = direction.angle()
	# Rend is conditional: the unique must be worn AND the druid must actually
	# be in Dire Wolf form (the talent transform of Bear Form).
	if InventorySystem and InventorySystem.has_unique("dire_wolf_rend") and ctx.caster:
		var ss = ctx.caster.get("skill_system")
		if ss != null and String(ss.get("druid_form")) == "dire_wolf":
			_rend = true


func _ready() -> void:
	z_index = 60
	var flash := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		flash.texture = load(path) as Texture2D
	flash.modulate = Color(1.0, 0.5, 0.4, 0.95)
	flash.scale = Vector2(0.7, 0.7)
	flash.position = Vector2(60, 0)
	add_child(flash)
	var tw := flash.create_tween().set_parallel(true)
	(
		tw
		. tween_property(flash, "scale", Vector2(1.05, 1.05), LIFETIME)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(flash, "modulate:a", 0.0, LIFETIME)
	# Damage pass after a tiny wind-up.
	if not visual_only:
		var t := get_tree().create_timer(0.05)
		t.timeout.connect(_apply_damage)
	var dt := get_tree().create_timer(LIFETIME + 0.05)
	dt.timeout.connect(queue_free)


func _apply_damage() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var origin: Vector2 = global_position
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var d: float = origin.distance_to((e as Node2D).global_position)
		if d > ARC_RADIUS:
			continue
		# Forward cone — dot > 0.2.
		var to_e: Vector2 = ((e as Node2D).global_position - origin).normalized()
		if direction.dot(to_e) < 0.2:
			continue
		var id: int = e.get_instance_id()
		if hit_set.has(id):
			continue
		hit_set[id] = true
		if e.has_method("take_damage"):
			e.take_damage(damage, origin)
		# Alpha Predator rend — 60% of bite damage bleeding out over 3s.
		if _rend and e.has_method("apply_poison"):
			e.call("apply_poison", 1, 3.0, float(damage) * 0.2)
	if VfxManager:
		VfxManager.spawn_hit_sparks(origin + direction * 70.0, Color(1.0, 0.5, 0.4, 1), 8)
		VfxManager.hit_stop(0.04)
