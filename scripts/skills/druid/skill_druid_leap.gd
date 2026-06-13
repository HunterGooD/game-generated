extends Node2D

# Hunting Leap — wolf-druid leaps to mouse target, lands with a small bite-AOE.

const LEAP_TIME: float = 0.42
const MAX_DISTANCE: float = 360.0
const BLAST_RADIUS: float = 110.0

var damage: int = 24
var direction: Vector2 = Vector2.RIGHT
var target_pos: Vector2 = Vector2.ZERO
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
	var caster = _caster
	if caster:
		var to_mouse: Vector2 = caster.get_global_mouse_position() - caster.global_position
		var dist: float = min(to_mouse.length(), MAX_DISTANCE)
		target_pos = caster.global_position + direction * dist
	elif visual_only:
		target_pos = global_position + direction * 200.0


func _ready() -> void:
	z_index = 60
	if target_pos == Vector2.ZERO:
		target_pos = global_position + direction * 200.0
	# Landing marker.
	var marker := Sprite2D.new()
	var path: String = "res://assets/sprites/effects/meteor_telegraph.png"
	if ResourceLoader.exists(path):
		marker.texture = load(path) as Texture2D
	marker.modulate = Color(1.0, 0.5, 0.4, 0.7)
	marker.scale = Vector2(0.9, 0.9)
	marker.global_position = target_pos
	marker.z_index = 50
	get_tree().current_scene.add_child(marker)
	var pulse := marker.create_tween().set_loops(int(LEAP_TIME / 0.14) + 1)
	pulse.tween_property(marker, "scale", Vector2(1.0, 1.0), 0.07)
	pulse.tween_property(marker, "scale", Vector2(0.85, 0.85), 0.07)
	# Move caster on host/local only.
	if not visual_only:
		var caster := _resolve_caster()
		if caster:
			var t := caster.create_tween()
			t.tween_property(caster, "global_position", target_pos, LEAP_TIME).set_trans(
				Tween.TRANS_QUAD
			)
			var visual = caster.get_node_or_null("Visual")
			if visual:
				var ht := caster.create_tween()
				(
					ht
					. tween_property(
						visual, "position:y", visual.position.y - 50.0, LEAP_TIME * 0.5
					)
					. set_trans(Tween.TRANS_QUAD)
					. set_ease(Tween.EASE_OUT)
				)
				(
					ht
					. tween_property(visual, "position:y", visual.position.y, LEAP_TIME * 0.5)
					. set_trans(Tween.TRANS_QUAD)
					. set_ease(Tween.EASE_IN)
				)
	# Trigger impact after leap.
	var timer := get_tree().create_timer(LEAP_TIME)
	timer.timeout.connect(_on_land.bind(marker))


func _on_land(marker: Sprite2D) -> void:
	if is_instance_valid(marker):
		marker.queue_free()
	if VfxManager:
		VfxManager.spawn_explosion(target_pos, 0.9, Color(1.0, 0.55, 0.4, 1))
		VfxManager.screen_shake(5.0, 0.18)
		VfxManager.hit_stop(0.05)
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in SkillTargeting.in_radius(tree, target_pos, BLAST_RADIUS):
				if e.has_method("take_damage"):
					e.take_damage(damage, target_pos)
	queue_free()


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
