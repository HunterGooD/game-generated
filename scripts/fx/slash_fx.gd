class_name SlashFx
extends RefCounted

## Procedural melee-slash material factory. Pairs with melee_slash.gdshader to
## replace the flat PNG swing arc with a bright, class-themed energy crescent.
## Same static-factory + shared-cached-texture shape as SoftLight / BlobShadow.
##
## A slash is just a Sprite2D wearing a ShaderMaterial: the sprite supplies a
## blank white quad (so the shader has UVs to draw into), the shader does the
## rest. Drive the reveal by tweening the material's "shader_parameter/progress"
## from 0→1 over the swing's lifetime.
##
## Usage:
##   var mat := SlashFx.apply_to(sprite, "mage")          # class id …
##   var mat := SlashFx.apply_to(sprite, "fire")          # … or skill element
##   create_tween().tween_property(mat, "shader_parameter/progress", 1.0, life)

const SLASH_SHADER: Shader = preload("res://assets/shaders/melee_slash.gdshader")
const QUAD_SIZE: int = 256

# Default angular sweep (radians, ~137°). A theme's "span" overrides it.
const DEFAULT_SPAN: float = 2.4
# Global reach multiplier — every swing tip extends a bit further from the caster.
const REACH: float = 1.18

# One shared blank white quad backs every slash (built lazily).
static var _quad_tex: Texture2D = null

# Neutral fallback — a clean white blade — for unknown themes.
const NEUTRAL: Dictionary = {"core": Color(1, 1, 1), "glow": Color(0.7, 0.8, 1.0), "style": 0}

# Weapon-themed palette. Keyed by class id AND by skill "element" so a skill can
# theme its slash by what it IS (fire/blood/…) rather than by the caster's class.
# style: 0 clean blade · 1 fire (ragged + flicker) · 2 claw (3 rakes) · 3 electric.
const PALETTE: Dictionary = {
	# Per-class basic-swing palettes folded into ClassDefinition.slash_style;
	# palette_for() routes a class theme through the registry. Only element
	# themes (caster-agnostic skill slashes) live here now.
	# ── per element (skill slashes, caster-agnostic) ──
	"fire": {"core": Color(1.0, 0.45, 0.12), "glow": Color(1.00, 0.75, 0.25), "style": 1},
	"blood": {"core": Color(0.95, 0.13, 0.20), "glow": Color(0.45, 0.00, 0.06), "style": 1},
	"nature": {"core": Color(0.55, 0.90, 0.40), "glow": Color(0.80, 0.95, 0.50), "style": 2},
	"storm": {"core": Color(0.50, 0.85, 1.00), "glow": Color(0.85, 0.95, 1.00), "style": 3},
	"stone": {"core": Color(0.85, 0.70, 0.50), "glow": Color(0.60, 0.45, 0.30), "style": 0},
	"white": {"core": Color(1, 1, 1), "glow": Color(0.7, 0.8, 1.0), "style": 0},
}


## A blank white square — only needed so the Sprite2D has a size and UV 0..1 for
## the shader to draw into. Shared by every slash, built once.
static func quad_texture() -> Texture2D:
	if _quad_tex != null:
		return _quad_tex
	var img := Image.create(QUAD_SIZE, QUAD_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	_quad_tex = ImageTexture.create_from_image(img)
	return _quad_tex


## Palette entry for a theme (class id or element). Unknown → neutral white blade.
static func palette_for(theme: String) -> Dictionary:
	# Class themes (the basic melee swing) come from ClassDefinition.slash_style;
	# element themes (fire/blood/…) stay in PALETTE. Unknown → neutral white blade.
	if GameManager != null and GameManager.has_class(theme):
		var style: Dictionary = GameManager.class_def(theme).slash_style
		if not style.is_empty():
			return style
	return PALETTE.get(theme, NEUTRAL)


## Build a fresh slash ShaderMaterial for `theme`. `core_override` (a Color)
## replaces the core hue while keeping the theme's glow + style — for basic-attack
## uniques that recolour the swing.
static func make_material(theme: String, core_override = null, seed_val: float = 0.0) -> ShaderMaterial:
	var p: Dictionary = palette_for(theme)
	var mat := ShaderMaterial.new()
	mat.shader = SLASH_SHADER
	var core: Color = core_override if core_override is Color else p["core"]
	mat.set_shader_parameter("slash_color", core)
	mat.set_shader_parameter("glow_color", p["glow"])
	mat.set_shader_parameter("style", int(p["style"]))
	mat.set_shader_parameter("arc_span", float(p.get("span", DEFAULT_SPAN)))
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("seed", seed_val)
	return mat


## Dress `sprite` as a slash: give it the quad texture (if it has none) and a
## themed ShaderMaterial. Returns the material so the caller can tween `progress`.
static func apply_to(sprite: Sprite2D, theme: String, core_override = null) -> ShaderMaterial:
	if sprite == null:
		return null
	if sprite.texture == null:
		sprite.texture = quad_texture()
	sprite.centered = true
	# Per-instance noise offset so simultaneous swings don't flicker in lockstep.
	var seed_val: float = float(absi(int(sprite.get_instance_id())) % 997) * 0.013
	var mat := make_material(theme, core_override, seed_val)
	sprite.material = mat
	return mat


## One-shot themed slash under `parent`: spawn a Sprite2D at local `pos`, sweep
## it over `life` seconds (shader fades itself out), self-frees on completion.
## For skill swing visuals replacing the old PNG-arc + modulate + alpha-fade.
## The quad is 256px (radius reach ≈ 97px·scale); pass the skill's prior arc scale.
static func spawn(
	parent: Node, theme: String, pos: Vector2, scale: float, life: float, core_override = null
) -> Sprite2D:
	if parent == null:
		return null
	var spr := Sprite2D.new()
	spr.position = pos
	spr.scale = Vector2(scale, scale) * REACH
	var mat := apply_to(spr, theme, core_override)
	parent.add_child(spr)
	var tw := spr.create_tween().set_parallel(true)
	(
		tw
		. tween_property(spr, "scale", spr.scale * 1.35, life)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	if mat:
		(
			tw
			. tween_property(mat, "shader_parameter/progress", 1.0, life)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
	# Free a hair after the sweep ends (parent may outlive the visual).
	tw.chain().tween_callback(spr.queue_free)
	return spr
