extends Node2D

const LEAP_TIME: float = 0.55
const BLAST_RADIUS: float = 160.0
const MAX_LEAP_DISTANCE: float = 400.0

var damage: int = 24
var direction: Vector2 = Vector2.RIGHT
var target_pos: Vector2 = Vector2.ZERO
var visual_only: bool = false
var _caster: Node = null


func setup_context(ctx: SkillContext) -> void:
	var dir := ctx.direction
	var dmg := ctx.damage
	damage = dmg
	direction = dir
	visual_only = ctx.is_visual_only
	_caster = ctx.caster
	if visual_only:
		set_meta("visual_only", true)
	var caster = _caster
	if caster:
		var to_mouse: Vector2 = caster.get_global_mouse_position() - caster.global_position
		var dist: float = min(to_mouse.length(), MAX_LEAP_DISTANCE)
		target_pos = caster.global_position + direction * dist
	elif visual_only:
		target_pos = global_position + direction * 200.0


func _ready() -> void:
	if target_pos == Vector2.ZERO:
		target_pos = global_position + direction * 200.0
	var tel := Sprite2D.new()
	var path := "res://assets/sprites/effects/meteor_telegraph.png"
	if ResourceLoader.exists(path):
		tel.texture = load(path) as Texture2D
	tel.modulate = Color(1, 0.5, 0.4, 0.7)
	tel.scale = Vector2(1.4, 1.4)
	tel.global_position = target_pos
	tel.z_index = 50
	get_tree().current_scene.add_child(tel)

	var pulse := tel.create_tween().set_loops(int(LEAP_TIME / 0.18) + 1)
	pulse.tween_property(tel, "scale", Vector2(1.55, 1.55), 0.09)
	pulse.tween_property(tel, "scale", Vector2(1.35, 1.35), 0.09)

	if not visual_only:
		var caster := _resolve_caster()
		if caster:
			var visual = caster.get_node_or_null("Visual")
			if visual:
				var t := caster.create_tween()
				(
					t
					. tween_property(
						visual, "position:y", visual.position.y - 60.0, LEAP_TIME * 0.5
					)
					. set_trans(Tween.TRANS_QUAD)
					. set_ease(Tween.EASE_OUT)
				)
				(
					t
					. tween_property(visual, "position:y", visual.position.y, LEAP_TIME * 0.5)
					. set_trans(Tween.TRANS_QUAD)
					. set_ease(Tween.EASE_IN)
				)
			var t2 := caster.create_tween()
			t2.tween_property(caster, "global_position", target_pos, LEAP_TIME).set_trans(
				Tween.TRANS_QUAD
			)

	var timer := get_tree().create_timer(LEAP_TIME)
	timer.timeout.connect(_on_slam.bind(tel))


func _on_slam(tel: Sprite2D) -> void:
	if is_instance_valid(tel):
		tel.queue_free()
	if VfxManager:
		VfxManager.spawn_explosion(target_pos, 1.4, Color(1, 0.5, 0.25, 1))
		VfxManager.screen_shake(10.0, 0.35)
		VfxManager.screen_flash(Color(1, 0.45, 0.25, 0.2), 0.2)
		VfxManager.hit_stop(0.05)
	if AudioManager:
		AudioManager.play_sfx_path("res://assets/audio/sfx/player/player_spell_leap.mp3", -6.0)
	if not visual_only:
		var tree := get_tree()
		if tree:
			for e in tree.get_nodes_in_group("enemy"):
				if not is_instance_valid(e):
					continue
				var d: float = target_pos.distance_to((e as Node2D).global_position)
				if d <= BLAST_RADIUS:
					if e.has_method("take_damage"):
						e.take_damage(damage, target_pos)
		if InventorySystem and InventorySystem.has_unique("worldcleaver"):
			_worldcleaver_quake()
	queue_free()


func _worldcleaver_quake() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for i in 3:
		var step: int = i
		var timer := get_tree().create_timer(0.18 * float(step))
		timer.timeout.connect(_quake_ring.bind(step))


func _quake_ring(step: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var ring_radius: float = 90.0 + 70.0 * float(step)
	var dmg: int = int(round(float(damage) * 0.4))
	for e in tree.get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var d: float = target_pos.distance_to((e as Node2D).global_position)
		if d <= ring_radius and d > ring_radius - 80.0:
			if e.has_method("take_damage"):
				e.take_damage(dmg, target_pos)
	if VfxManager:
		VfxManager.spawn_hit_sparks(
			(
				target_pos
				+ Vector2(
					randf_range(-ring_radius, ring_radius), randf_range(-ring_radius, ring_radius)
				)
			),
			Color(1, 0.6, 0.25, 1),
			8
		)
		VfxManager.screen_shake(2.0, 0.1)


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
