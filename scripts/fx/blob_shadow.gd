class_name BlobShadow
extends Sprite2D

## Soft "blob" shadow — a radial-gradient black ellipse drawn at an object's feet.
## Cheap, art-agnostic, and renders behind its host (z_index = -1, first child).
## The chosen approach over a shadow shader: in a top-down 2D game a faked cast
## shadow ends up being a blob anyway, but costs a second draw per sprite and
## breaks on the many sprites that flash/tint via `modulate`. One shared texture
## backs every shadow.
##
## Usage:  BlobShadow.attach(host, width, height, y_offset)

const TEX_SIZE: int = 96

# One shared radial-gradient texture for every shadow (built lazily).
static var _tex: Texture2D = null


static func _shadow_texture() -> Texture2D:
	if _tex != null:
		return _tex
	var grad := Gradient.new()
	# Fairly dark centre so it still reads on floors dimmed by a CanvasModulate
	# (dungeon/combat worlds darken the whole canvas — a faint blob washes out).
	grad.set_color(0, Color(0, 0, 0, 0.62))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	grad.set_offset(0, 0.0)
	grad.set_offset(1, 1.0)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)  # radius = half the square → soft circle inscribed
	gt.width = TEX_SIZE
	gt.height = TEX_SIZE
	_tex = gt
	return _tex


## Create a blob shadow under `host`. `width`/`height` are the ellipse diameters
## in px (height defaults to a flat 0.42×width); `y` shifts it along the host's
## local Y to sit on the feet line (usually 0). Returns the shadow (so callers
## can keep a ref to resize/hide it). No-op-safe on a null host.
static func attach(host: Node2D, width: float, height: float = 0.0, y: float = 0.0) -> BlobShadow:
	if host == null:
		return null
	# Idempotent: a host that already owns a shadow keeps it (just re-sizes), so
	# double-applies — boss re-visual, pooled enemies, player respawn — never stack.
	var h: float = height if height > 0.0 else width * 0.42
	for c in host.get_children():
		if c is BlobShadow:
			(c as BlobShadow).scale = Vector2(width / float(TEX_SIZE), h / float(TEX_SIZE))
			(c as BlobShadow).position = Vector2(0, y)
			return c as BlobShadow
	var s := BlobShadow.new()
	s.texture = _shadow_texture()
	s.centered = true
	s.scale = Vector2(width / float(TEX_SIZE), h / float(TEX_SIZE))
	s.position = Vector2(0, y)
	s.z_index = -1  # behind siblings within the host (host's own floor sits at z≈-10)
	s.z_as_relative = true
	s.light_mask = 0  # a flat blob — never lit by 2D lights
	s.show_behind_parent = true
	host.add_child(s)
	host.move_child(s, 0)  # also first in tree order, so it draws first
	return s


## Like attach(), but auto-places the shadow at `sprite`'s BOTTOM edge (the feet)
## instead of the host origin. Sprites here are centred and shifted up so their
## origin is NOT the ground line — a shadow at y=0 would hide behind the body.
## Computes the feet from the sprite's texture × scale, so it's art-agnostic and
## survives re-skins (idempotent attach just repositions). Call it AFTER the
## sprite's texture/scale are set.
static func attach_at_feet(host: Node2D, sprite: Node2D, width: float, height: float = 0.0) -> BlobShadow:
	return attach(host, width, height, _sprite_bottom_y(sprite))


# Y (in the sprite's parent space) of a centred sprite's bottom edge, pulled up
# 8% for the transparent padding most character art carries under the feet.
static func _sprite_bottom_y(sprite: Node2D) -> float:
	if sprite == null:
		return 0.0
	var tex_h: float = 0.0
	if sprite is Sprite2D and (sprite as Sprite2D).texture != null:
		tex_h = (sprite as Sprite2D).texture.get_size().y
	elif sprite is AnimatedSprite2D:
		var asp := sprite as AnimatedSprite2D
		var frames: SpriteFrames = asp.sprite_frames
		var anim: StringName = asp.animation
		if frames != null and frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
			var t: Texture2D = frames.get_frame_texture(anim, 0)
			if t != null:
				tex_h = t.get_size().y
	if tex_h <= 0.0:
		return sprite.position.y
	return sprite.position.y + tex_h * 0.5 * absf(sprite.scale.y) * 0.92
