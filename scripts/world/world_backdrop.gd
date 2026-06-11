extends Node2D

## A dark, WORLD-ANCHORED backdrop that fills the space beyond the playable map, so the engine's
## default clear-colour never shows through arena borders or the concave gaps of a graph-built
## dungeon. Anchored to the world (not the camera) so it stays put as the player moves — the
## camera simply reveals different parts of it. Tinted per biome (never pure black) with a soft
## radial darkening toward the edges, plus slow world-space dust. Built entirely in code.

var _rect: Rect2 = Rect2(0, 0, 4096, 4096)
var _color: Color = Color(0.10, 0.10, 0.14)
var _edge: Color = Color(0.05, 0.05, 0.08)


func _ready() -> void:
	# Sit far behind everything, in absolute (non-relative) Z so nothing in the world can draw
	# under it.
	z_index = -4000
	z_as_relative = false


# Size + theme the backdrop from the active camera's limits and biome. Call AFTER the camera
# limits are set (i.e. after the dungeon/arena finishes building).
func setup(bounds: Rect2, biome: String) -> void:
	# Pad generously so camera smoothing overshoot past the limits is still covered.
	_rect = bounds.grow(1600.0)
	_color = DungeonBiome.backdrop_color(biome)
	_edge = DungeonBiome.backdrop_edge_color(biome)
	queue_redraw()
	_build_dust()


func setup_from_camera(camera: Node, biome: String) -> void:
	var bounds := Rect2(0, 0, 4096, 4096)
	if camera and camera.get("limit_left") != null:
		var l: float = float(camera.get("limit_left"))
		var t: float = float(camera.get("limit_top"))
		var r: float = float(camera.get("limit_right"))
		var b: float = float(camera.get("limit_bottom"))
		bounds = Rect2(l, t, maxf(64.0, r - l), maxf(64.0, b - t))
	setup(bounds, biome)


func _draw() -> void:
	# Base fill across the whole padded rect.
	draw_rect(_rect, _color, true)
	# Soft vignette: concentric translucent edge-coloured frames thickening toward the border,
	# so the transition from lit map to dark surround is gradual rather than a hard line.
	var steps: int = 6
	var center: Vector2 = _rect.position + _rect.size * 0.5
	for i in steps:
		var f: float = float(i + 1) / float(steps)
		var inset: float = (1.0 - f) * 0.5
		var r := Rect2(
			center - _rect.size * (0.5 - inset),
			_rect.size * (2.0 * (0.5 - inset))
		)
		var a: float = 0.10 * f
		# Draw a frame (outer rect minus inner) by stroking with growing width.
		draw_rect(r, Color(_edge.r, _edge.g, _edge.b, a), false, _rect.size.x * 0.08 * f)


func _build_dust() -> void:
	var existing := get_node_or_null("Dust")
	if existing:
		existing.queue_free()
	# World-space dust drifting over the surround. Parented to this world node so the motes hang
	# in the world (not glued to the screen). Emission box spans the visible bounds.
	var dust := GPUParticles2D.new()
	dust.name = "Dust"
	dust.amount = 90
	dust.lifetime = 12.0
	dust.preprocess = 7.0
	dust.local_coords = false
	dust.position = _rect.position + _rect.size * 0.5
	dust.modulate = Color(0.7, 0.74, 0.85, 0.22)

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1, 0.15, 0)
	pm.spread = 40.0
	pm.gravity = Vector3(0, 3, 0)
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 14.0
	pm.scale_min = 0.5
	pm.scale_max = 1.8
	pm.angular_velocity_min = -10.0
	pm.angular_velocity_max = 10.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(maxf(600.0, _rect.size.x * 0.5), maxf(400.0, _rect.size.y * 0.5), 1)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 0.85, 0.95, 0.0))
	grad.add_point(0.5, Color(0.8, 0.85, 0.95, 0.5))
	grad.set_color(1, Color(0.8, 0.85, 0.95, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	dust.process_material = pm

	var tex_path := "res://assets/sprites/effects/cast_flash.png"
	if ResourceLoader.exists(tex_path):
		dust.texture = load(tex_path) as Texture2D
	add_child(dust)
