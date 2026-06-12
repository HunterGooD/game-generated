class_name SoftLight
extends PointLight2D

## A soft additive PointLight2D for atmospheric glows (campfire, portal, jeweler).
## ADD blend with NO global darkening pass — it only brightens its halo, so it
## never hurts readability and never fights the hit-flash/`modulate` tinting on
## sprites. One shared radial-gradient texture backs every glow.
##
## Usage:  SoftLight.attach(host, color, radius_px, energy, y_offset)

const TEX_SIZE: int = 128

static var _tex: Texture2D = null


static func _light_texture() -> Texture2D:
	if _tex != null:
		return _tex
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	grad.set_offset(0, 0.0)
	grad.set_offset(1, 1.0)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = TEX_SIZE
	gt.height = TEX_SIZE
	_tex = gt
	return _tex


static func _build(color: Color, radius_px: float, energy: float) -> SoftLight:
	var l := SoftLight.new()
	l.texture = _light_texture()
	l.color = color
	l.energy = energy
	l.blend_mode = Light2D.BLEND_MODE_ADD
	l.texture_scale = (2.0 * radius_px) / float(TEX_SIZE)
	return l


## Add an additive glow under `host` at local (0, y). `radius_px` is the lit
## radius; `energy` scales brightness (keep ≲1.0 so it stays a glow). Returns it.
static func attach(
	host: Node2D, color: Color, radius_px: float, energy: float = 0.8, y: float = -20.0
) -> SoftLight:
	if host == null:
		return null
	var l := _build(color, radius_px, energy)
	l.position = Vector2(0, y)
	host.add_child(l)
	return l


## Place a glow at an explicit world/local `pos` under `parent` — for scattering
## ambient lights through a level (e.g. dungeon room centres).
static func at(
	parent: Node, pos: Vector2, color: Color, radius_px: float, energy: float = 0.7
) -> SoftLight:
	if parent == null:
		return null
	var l := _build(color, radius_px, energy)
	l.position = pos
	parent.add_child(l)
	return l
