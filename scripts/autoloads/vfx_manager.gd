extends Node

# VFX Manager — central spawn point for combat visual effects.
# Owns: damage numbers, hit sparks, death bursts, explosions, screen shake,
# screen flashes, and hit-stop. Designed to be cheap on the GL Compatibility renderer.

# Cached textures.
var _tex_explosion: Texture2D
var _tex_smoke: Texture2D
var _tex_soul: Texture2D
var _tex_bone: Texture2D
var _tex_dark: Texture2D
var _tex_ice: Texture2D
var _tex_flame: Texture2D
var _tex_lightning: Texture2D

var _shake_amount: float = 0.0
var _shake_timer: float = 0.0
var _shake_seed: Vector2 = Vector2.ZERO

var _screen_flash_layer: CanvasLayer = null
var _screen_flash_rect: ColorRect = null

var _hit_stop_until: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_textures()


func _load_textures() -> void:
	_tex_explosion = _safe_load("res://assets/sprites/effects/explosion_orange.png")
	_tex_smoke = _safe_load("res://assets/sprites/effects/smoke_puff_purple.png")
	_tex_soul = _safe_load("res://assets/sprites/effects/soul_wisp.png")
	_tex_bone = _safe_load("res://assets/sprites/effects/bone_shard.png")
	_tex_dark = _safe_load("res://assets/sprites/effects/dark_bolt.png")
	_tex_ice = _safe_load("res://assets/sprites/effects/ice_shard.png")
	_tex_flame = _safe_load("res://assets/sprites/effects/fire_flame.png")
	_tex_lightning = _safe_load("res://assets/sprites/effects/lightning_zap.png")


func _safe_load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


# ─────────────────────────────────────────────────────────────────────────────
# Hit stop — briefly freezes everything (use sparingly).
func hit_stop(duration: float = 0.05) -> void:
	_hit_stop_until = max(_hit_stop_until, Time.get_ticks_msec() / 1000.0 + duration)
	Engine.time_scale = 0.05


# ─────────────────────────────────────────────────────────────────────────────
# Screen shake — Camera2D offset jitter.
func screen_shake(amount: float, duration: float) -> void:
	_shake_amount = max(_shake_amount, amount)
	_shake_timer = max(_shake_timer, duration)


# ─────────────────────────────────────────────────────────────────────────────
# Screen flash — full-viewport color tint.
func screen_flash(color: Color, duration: float = 0.15) -> void:
	_ensure_flash_layer()
	if _screen_flash_rect == null:
		return
	_screen_flash_rect.color = color
	_screen_flash_rect.modulate.a = color.a
	var tw := create_tween()
	(
		tw
		. tween_property(_screen_flash_rect, "modulate:a", 0.0, duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)


func _ensure_flash_layer() -> void:
	if is_instance_valid(_screen_flash_layer) and is_instance_valid(_screen_flash_rect):
		return
	_screen_flash_layer = CanvasLayer.new()
	_screen_flash_layer.layer = 100
	add_child(_screen_flash_layer)
	_screen_flash_rect = ColorRect.new()
	_screen_flash_rect.color = Color(1, 1, 1, 0)
	_screen_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_flash_layer.add_child(_screen_flash_rect)
	_screen_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_flash_rect.modulate.a = 0.0


func _process(delta: float) -> void:
	# Hit stop release.
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() / 1000.0 >= _hit_stop_until:
		Engine.time_scale = 1.0
	# Camera shake.
	if _shake_timer > 0.0:
		_shake_timer -= delta
		var cam: Camera2D = _get_current_camera()
		if cam:
			_shake_seed = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amount
			cam.offset = _shake_seed
		if _shake_timer <= 0.0:
			_shake_amount = 0.0
			if cam:
				cam.offset = Vector2.ZERO


func _get_current_camera() -> Camera2D:
	var tree := get_tree()
	if tree == null:
		return null
	var viewport := tree.root.get_viewport()
	if viewport == null:
		return null
	return viewport.get_camera_2d()


# ─────────────────────────────────────────────────────────────────────────────
# DAMAGE NUMBER — Label that floats up and fades.
func spawn_damage_number(
	world_pos: Vector2, amount: int, color: Color = Color(1, 0.85, 0.4, 1)
) -> void:
	var scene := _scene_root()
	if scene == null:
		return
	# Tier the visual by damage size — bigger hits read distinctly.
	var size_px: int = 24
	var outline: int = 6
	var tier_color: Color = color
	if amount >= 200:
		size_px = 38
		outline = 8
		tier_color = Color(1.0, 0.25, 0.25, 1.0)  # crimson for huge hits
	elif amount >= 80:
		size_px = 30
		outline = 7
		tier_color = Color(1.0, 0.85, 0.4, 1.0)  # gold for medium
	# Spawn with a small horizontal arc for cinematic readability.
	var arc_x: float = randf_range(-22.0, 22.0)
	var lbl := Label.new()
	lbl.text = str(amount)
	lbl.add_theme_color_override("font_color", tier_color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", outline)
	lbl.add_theme_font_size_override("font_size", size_px)
	lbl.position = world_pos + Vector2(-12.0 + randf_range(-6.0, 6.0), -22.0)
	lbl.z_index = 200
	# Initial pop-in scale.
	lbl.pivot_offset = Vector2(20, 14)
	lbl.scale = Vector2(1.6, 1.6)
	scene.add_child(lbl)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.14).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	(
		tw
		. tween_property(lbl, "position:y", lbl.position.y - 56.0, 0.8)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tw
		. tween_property(lbl, "position:x", lbl.position.x + arc_x, 0.8)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN
	)
	tw.chain().tween_callback(lbl.queue_free)


# ─────────────────────────────────────────────────────────────────────────────
# HIT SPARKS — small radial burst when something gets hit.
func spawn_hit_sparks(
	world_pos: Vector2, color: Color = Color(0.9, 0.5, 1.0, 1.0), count: int = 6
) -> void:
	if _tex_dark == null:
		return
	var scene := _scene_root()
	if scene == null:
		return
	# Polished: spawn 50% more particles than requested for a punchier feel.
	var effective_count: int = int(round(float(count) * 1.5))
	for i in effective_count:
		var s := Sprite2D.new()
		s.texture = _tex_dark
		s.modulate = color
		var sc: float = randf_range(0.14, 0.22)
		s.scale = Vector2(sc, sc)
		s.position = world_pos
		s.z_index = 150
		scene.add_child(s)
		var dir: Vector2 = Vector2.RIGHT.rotated(randf() * TAU)
		var dist: float = randf_range(28.0, 84.0)
		var dur: float = randf_range(0.32, 0.55)
		var tw := create_tween().set_parallel(true)
		(
			tw
			. tween_property(s, "position", world_pos + dir * dist, dur)
			. set_trans(Tween.TRANS_QUART)
			. set_ease(Tween.EASE_OUT)
		)
		tw.tween_property(s, "modulate:a", 0.0, dur)
		tw.tween_property(s, "scale", Vector2(sc * 0.25, sc * 0.25), dur)
		tw.chain().tween_callback(s.queue_free)

	# Quick PointLight2D flash.
	_spawn_light_flash(world_pos, color, 0.22)


func _spawn_light_flash(
	world_pos: Vector2,
	color: Color,
	duration: float = 0.18,
	energy: float = 1.6,
	scale: float = 1.5
) -> void:
	var scene := _scene_root()
	if scene == null:
		return
	var light := PointLight2D.new()
	var grad := GradientTexture2D.new()
	grad.width = 192
	grad.height = 192
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.colors = PackedColorArray(
		[Color(color.r, color.g, color.b, 1.0), Color(color.r, color.g, color.b, 0.0)]
	)
	grad.gradient = g
	light.texture = grad
	light.color = color
	light.energy = energy
	light.texture_scale = scale
	light.position = world_pos
	light.z_index = 180
	scene.add_child(light)
	var tw := create_tween()
	tw.tween_property(light, "energy", 0.0, duration)
	tw.tween_callback(light.queue_free)


# ─────────────────────────────────────────────────────────────────────────────
# DEATH BURST — big celebratory enemy-death VFX.
func spawn_death_burst(world_pos: Vector2, enemy_type: String) -> void:
	var scene := _scene_root()
	if scene == null:
		return
	# Big flash.
	var flash_color: Color = Color(0.9, 0.7, 1.0, 1.0)
	match enemy_type:
		"skeleton":
			flash_color = Color(1.0, 0.95, 0.85, 1.0)
		"cultist":
			flash_color = Color(1.0, 0.4, 0.5, 1.0)
		"wraith":
			flash_color = Color(0.5, 0.8, 1.0, 1.0)
	_spawn_light_flash(world_pos, flash_color, 0.35, 2.2, 2.5)

	# Smoke puff cloud.
	_spawn_smoke_cloud(world_pos, 12, flash_color)

	# Type-specific shards.
	match enemy_type:
		"skeleton":
			_spawn_shards(world_pos, _tex_bone, 10, Color(1, 1, 0.9, 1), 0.25, 90.0, 0.75)
		"cultist":
			_spawn_shards(world_pos, _tex_dark, 12, Color(1.0, 0.4, 0.6, 1), 0.3, 100.0, 0.7)
		"wraith":
			_spawn_shards(world_pos, _tex_soul, 8, Color(0.6, 0.85, 1.0, 1), 0.5, 80.0, 1.0)
		_:
			_spawn_shards(world_pos, _tex_dark, 10, Color(0.9, 0.5, 1.0, 1), 0.3, 90.0, 0.7)

	# Soul wisps floating up.
	_spawn_soul_wisps(world_pos, 4, flash_color)

	# Damage number-style XP popup is handled in enemy script directly.


func _spawn_smoke_cloud(world_pos: Vector2, count: int, tint: Color) -> void:
	if _tex_smoke == null:
		return
	var scene := _scene_root()
	if scene == null:
		return
	for i in count:
		var s := Sprite2D.new()
		s.texture = _tex_smoke
		var col: Color = tint.lerp(Color(0.3, 0.2, 0.4, 1.0), 0.5)
		col.a = 0.85
		s.modulate = col
		var sc0: float = randf_range(0.5, 0.8)
		s.scale = Vector2(sc0, sc0)
		s.position = world_pos + Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
		s.rotation = randf() * TAU
		s.z_index = 140
		scene.add_child(s)
		var end_pos: Vector2 = (
			s.position + Vector2(randf_range(-40.0, 40.0), randf_range(-50.0, -10.0))
		)
		var end_scale: float = sc0 * randf_range(2.5, 3.5)
		var dur: float = randf_range(0.55, 0.85)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(s, "position", end_pos, dur).set_trans(Tween.TRANS_QUAD).set_ease(
			Tween.EASE_OUT
		)
		tw.tween_property(s, "scale", Vector2(end_scale, end_scale), dur)
		tw.tween_property(s, "modulate:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(
			Tween.EASE_IN
		)
		tw.tween_property(s, "rotation", s.rotation + randf_range(-1.0, 1.0), dur)
		tw.chain().tween_callback(s.queue_free)


func _spawn_shards(
	world_pos: Vector2,
	tex: Texture2D,
	count: int,
	color: Color,
	base_scale: float,
	dist: float,
	dur: float
) -> void:
	if tex == null:
		return
	var scene := _scene_root()
	if scene == null:
		return
	for i in count:
		var s := Sprite2D.new()
		s.texture = tex
		s.modulate = color
		s.scale = Vector2(base_scale, base_scale)
		s.position = world_pos
		s.rotation = randf() * TAU
		s.z_index = 160
		scene.add_child(s)
		var dir: Vector2 = Vector2.RIGHT.rotated(randf() * TAU)
		var fly: float = dist * randf_range(0.6, 1.4)
		var end_pos: Vector2 = world_pos + dir * fly
		var tw := create_tween().set_parallel(true)
		tw.tween_property(s, "position", end_pos, dur).set_trans(Tween.TRANS_QUART).set_ease(
			Tween.EASE_OUT
		)
		tw.tween_property(s, "rotation", s.rotation + randf_range(-3.0, 3.0), dur)
		tw.tween_property(s, "modulate:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(
			Tween.EASE_IN
		)
		tw.chain().tween_callback(s.queue_free)


func _spawn_soul_wisps(world_pos: Vector2, count: int, color: Color) -> void:
	if _tex_soul == null:
		return
	var scene := _scene_root()
	if scene == null:
		return
	for i in count:
		var s := Sprite2D.new()
		s.texture = _tex_soul
		s.modulate = color.lerp(Color.WHITE, 0.4)
		var sc0: float = randf_range(0.35, 0.55)
		s.scale = Vector2(sc0, sc0)
		s.position = world_pos + Vector2(randf_range(-10.0, 10.0), randf_range(-8.0, 8.0))
		s.z_index = 170
		scene.add_child(s)
		var dx: float = randf_range(-18.0, 18.0)
		var end_pos: Vector2 = s.position + Vector2(dx, randf_range(-80.0, -120.0))
		var dur: float = randf_range(0.9, 1.4)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(s, "position", end_pos, dur).set_trans(Tween.TRANS_SINE).set_ease(
			Tween.EASE_OUT
		)
		tw.tween_property(s, "modulate:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(
			Tween.EASE_IN
		)
		tw.tween_property(s, "scale", Vector2(sc0 * 0.4, sc0 * 0.4), dur)
		tw.chain().tween_callback(s.queue_free)


# ─────────────────────────────────────────────────────────────────────────────
# EXPLOSION — generic burst with shockwave + shards + smoke.
func spawn_explosion(
	world_pos: Vector2, scale_mult: float = 1.0, color: Color = Color(1.0, 0.7, 0.3, 1.0)
) -> void:
	var scene := _scene_root()
	if scene == null:
		return
	# Core flash spite.
	if _tex_explosion:
		var s := Sprite2D.new()
		s.texture = _tex_explosion
		s.modulate = color
		var sc0: float = 0.6 * scale_mult
		s.scale = Vector2(sc0, sc0)
		s.position = world_pos
		s.rotation = randf() * TAU
		s.z_index = 170
		scene.add_child(s)
		var sc1: float = sc0 * 2.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(s, "scale", Vector2(sc1, sc1), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(
			Tween.EASE_OUT
		)
		tw.tween_property(s, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(
			Tween.EASE_IN
		)
		tw.chain().tween_callback(s.queue_free)

	# Light flash.
	_spawn_light_flash(world_pos, color, 0.32, 2.4, 2.6 * scale_mult)
	# Shockwave shards.
	_spawn_shards(world_pos, _tex_dark, 14, color, 0.22, 120.0 * scale_mult, 0.5)
	# Smoke.
	_spawn_smoke_cloud(world_pos, 10, color)
	# Shake + flash.
	screen_shake(8.0 * scale_mult, 0.25)
	screen_flash(Color(color.r, color.g, color.b, 0.18), 0.18)


func _scene_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.current_scene
