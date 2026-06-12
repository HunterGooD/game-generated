extends Node2D

## Тёмный, ПРИВЯЗАННЫЙ К МИРУ задник, заполняющий пространство за пределами играбельной
## карты, чтобы дефолтный clear-цвет движка не просвечивал за границами арены или в вогнутых
## зазорах граф-данжа. Привязан к миру (не к камере), поэтому стоит на месте, пока игрок
## движется — камера просто открывает разные его части. Тонируется по биому (никогда не
## чисто-чёрный) с мягким затемнением К КРАЯМ. Виньетка считается от КОРОТКОЙ оси и
## ограничена по толщине — на длинных (вытянутых) картах рамки больше не заливают весь
## задник цветом края, скрывая биомный тон. Плюс мягкие пылинки у камеры. Целиком в коде.

var _rect: Rect2 = Rect2(0, 0, 4096, 4096)
var _color: Color = Color(0.10, 0.10, 0.14)
var _edge: Color = Color(0.05, 0.05, 0.08)


func _ready() -> void:
	# Глубоко позади всего, в абсолютном Z, чтобы ничто в мире не отрисовалось под ним.
	z_index = -4000
	z_as_relative = false


# Размер + тема задника из лимитов активной камеры и биома. Вызывать ПОСЛЕ установки
# лимитов камеры (т.е. когда данж/арена достроены).
func setup(bounds: Rect2, biome: String) -> void:
	# Щедрый запас, чтобы перелёт сглаживания камеры за лимиты всё равно был закрыт.
	_rect = bounds.grow(1600.0)
	_color = DungeonBiome.backdrop_color(biome)
	_edge = DungeonBiome.backdrop_edge_color(biome)
	queue_redraw()


func setup_from_camera(camera: Node, biome: String) -> void:
	var bounds := Rect2(0, 0, 4096, 4096)
	if camera and camera.get("limit_left") != null:
		var l: float = float(camera.get("limit_left"))
		var t: float = float(camera.get("limit_top"))
		var r: float = float(camera.get("limit_right"))
		var b: float = float(camera.get("limit_bottom"))
		bounds = Rect2(l, t, maxf(64.0, r - l), maxf(64.0, b - t))
	setup(bounds, biome)
	_build_motes(camera, biome)


func _draw() -> void:
	# Базовая заливка всего расширенного прямоугольника — биомный тон.
	draw_rect(_rect, _color, true)
	# Мягкая виньетка: вложенные ЗАЛИТЫЕ рамки вдоль границы, темнеющие наружу.
	# Толщина — от короткой оси и с жёстким потолком, поэтому форма карты
	# (длинная «кишка» или квадрат) на неё не влияет.
	var band: float = clampf(minf(_rect.size.x, _rect.size.y) * 0.22, 240.0, 1100.0)
	var steps: int = 6
	var th: float = band / float(steps)
	for j in steps:
		# j = 0 — внешняя (самая тёмная) рамка, дальше — светлее и глубже внутрь.
		var inset: float = th * float(j)
		var a: float = 0.34 * (1.0 - float(j) / float(steps))
		var col := Color(_edge.r, _edge.g, _edge.b, a)
		var r: Rect2 = _rect.grow(-inset)
		if r.size.x <= th * 2.0 or r.size.y <= th * 2.0:
			break
		# Рамка из четырёх залитых полос (верх / низ / лево / право).
		draw_rect(Rect2(r.position, Vector2(r.size.x, th)), col, true)
		draw_rect(Rect2(Vector2(r.position.x, r.end.y - th), Vector2(r.size.x, th)), col, true)
		draw_rect(
			Rect2(Vector2(r.position.x, r.position.y + th), Vector2(th, r.size.y - th * 2.0)),
			col,
			true
		)
		draw_rect(
			Rect2(Vector2(r.end.x - th, r.position.y + th), Vector2(th, r.size.y - th * 2.0)),
			col,
			true
		)


# Мягкие круглые пылинки, привязанные к КАМЕРЕ: эмиттер всегда в кадре, поэтому его
# никогда не отсекает culling (старая версия висела в центре карты и на длинных картах
# пропадала целиком — visibility_rect по умолчанию ±100 px). Частицы рождаются в
# мировых координатах (local_coords = false), так что при движении камеры они «висят»
# в мире, а не едут приклеенными к экрану. Текстура — процедурная мягкая точка вместо
# спрайта вспышки, который выглядел странно.
func _build_motes(camera: Node, biome: String) -> void:
	if camera == null or not (camera is Node2D):
		return
	var existing := camera.get_node_or_null("BackdropMotes")
	if existing:
		existing.queue_free()
	var motes := GPUParticles2D.new()
	motes.name = "BackdropMotes"
	motes.amount = 48
	motes.lifetime = 9.0
	motes.preprocess = 5.0
	motes.local_coords = false
	motes.z_index = -3900  # над задником, под полом
	motes.z_as_relative = false
	# Эмиттер по центру экрана; запас покрывает уже выпущенные частицы,
	# оставшиеся позади при движении камеры.
	motes.visibility_rect = Rect2(-2200, -1600, 4400, 3200)

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.4, -1, 0)
	pm.spread = 70.0
	pm.gravity = Vector3(0, -2, 0)
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 16.0
	pm.scale_min = 0.10
	pm.scale_max = 0.30
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 2.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1150, 700, 1)
	# Плавное появление/угасание — частицы не «вспыхивают» при спавне в кадре.
	var tint: Color = DungeonBiome.light_color(biome).lightened(0.35)
	var grad := Gradient.new()
	grad.set_color(0, Color(tint.r, tint.g, tint.b, 0.0))
	grad.add_point(0.25, Color(tint.r, tint.g, tint.b, 0.30))
	grad.add_point(0.7, Color(tint.r, tint.g, tint.b, 0.22))
	grad.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	motes.process_material = pm

	# Процедурная мягкая круглая точка — без внешних ассетов.
	var dot_grad := Gradient.new()
	dot_grad.set_color(0, Color(1, 1, 1, 1))
	dot_grad.add_point(0.45, Color(1, 1, 1, 0.5))
	dot_grad.set_color(1, Color(1, 1, 1, 0.0))
	var dot := GradientTexture2D.new()
	dot.gradient = dot_grad
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	dot.width = 64
	dot.height = 64
	motes.texture = dot
	camera.add_child(motes)
