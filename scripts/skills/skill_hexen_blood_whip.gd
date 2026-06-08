extends Node2D

# Blood Whip — long-range crimson energy whip. Yanks an enemy toward the
# Hexen, applies Hex Mark on hit, and detonates any existing Hex Mark on
# the target. If the target is a boss, the Hexen yanks HERSELF toward them
# (gap-closer).

const REACH: float = 480.0
const PULL_DISTANCE: float = 180.0
const LIFETIME: float = 0.4

var damage: int = 18
var direction: Vector2 = Vector2.RIGHT
var visual_only: bool = false
var _caster: Node = null


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	damage = dmg
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	visual_only = ctx.is_visual_only
	_caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)
	rotation = direction.angle()


func _ready() -> void:
	z_index = 60
	# Visual whip — a long thin red strip.
	var lash := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/melee_swing_arc.png"
	if ResourceLoader.exists(path):
		lash.texture = load(path) as Texture2D
	lash.modulate = Color(1.0, 0.2, 0.35, 0.95)
	lash.scale = Vector2(2.6, 0.5)
	lash.position = Vector2(REACH * 0.5, 0)
	add_child(lash)
	var tw := lash.create_tween().set_parallel(true)
	tw.tween_property(lash, "scale", Vector2(3.2, 0.7), LIFETIME).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(lash, "modulate:a", 0.0, LIFETIME)
	if not visual_only:
		_resolve_hit()
	var dt := get_tree().create_timer(LIFETIME + 0.05)
	dt.timeout.connect(queue_free)


func _resolve_hit() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var caster_pos: Vector2 = global_position
	# Walk along the whip line, first enemy hit gets yanked.
	var step: float = 36.0
	var hits: int = int(REACH / step)
	for i in hits + 1:
		var p: Vector2 = caster_pos + direction * (step * float(i))
		for e in tree.get_nodes_in_group("enemy"):
			if not is_instance_valid(e):
				continue
			if e.get("dead") == true:
				continue
			if p.distance_to((e as Node2D).global_position) <= 60.0:
				_apply_to(e, caster_pos)
				return  # stop on first hit


func _apply_to(target: Node, caster_pos: Vector2) -> void:
	# Detonate existing hex if present.
	if target.has_meta("hex_marked") and bool(target.get_meta("hex_marked", false)):
		var hex_node = target.get_meta("hex_mark_node", null)
		if hex_node and is_instance_valid(hex_node) and hex_node.has_method("detonate"):
			hex_node.call("detonate")
	# Damage + fresh mark.
	if target.has_method("take_damage"):
		target.call("take_damage", damage, caster_pos)
	target.set_meta("hex_marked", true)
	# Pull / dash.
	var to_target: Vector2 = (target as Node2D).global_position - caster_pos
	var dist: float = to_target.length()
	if dist <= 1.0:
		return
	var dir: Vector2 = to_target.normalized()
	var is_boss: bool = target.is_in_group("boss")
	if is_boss:
		var caster := _resolve_caster()
		if caster:
			var jump_dist: float = min(dist - 80.0, PULL_DISTANCE)
			var landing: Vector2 = caster.global_position + dir * jump_dist
			var t := caster.create_tween()
			t.tween_property(caster, "global_position", landing, 0.18).set_trans(Tween.TRANS_QUAD)
	else:
		# Pull target toward caster.
		var pulled_pos: Vector2 = (target as Node2D).global_position - dir * PULL_DISTANCE
		var tw := (target as Node2D).create_tween()
		tw.tween_property(target, "global_position", pulled_pos, 0.18).set_trans(Tween.TRANS_QUAD)
	if VfxManager:
		VfxManager.spawn_hit_sparks((target as Node2D).global_position, Color(1.0, 0.2, 0.35, 1), 7)


func _resolve_caster() -> Node2D:
	if _caster != null and is_instance_valid(_caster):
		return _caster as Node2D
	var tree := get_tree()
	if tree == null:
		return null
	for p in tree.get_nodes_in_group("player"):
		if not p.is_in_group("remote_player"):
			return p as Node2D
	return null
