extends CanvasLayer

## Crypt-biome atmosphere: a screen-space darkness vignette that limits how far the player
## sees. The camera keeps the player roughly centred, so the lit pocket stays around them.
## Purely visual (no damage). Built in code with a tiny inline radial shader.

const SHADER_CODE := """
shader_type canvas_item;
uniform float clear_radius = 0.30;
uniform float softness = 0.30;
uniform vec4 fog_color : source_color = vec4(0.015, 0.02, 0.04, 1.0);
void fragment() {
	// Aspect-corrected distance from screen centre.
	vec2 uv = UV - vec2(0.5);
	uv.x *= 1.7;
	float d = length(uv);
	float a = smoothstep(clear_radius, clear_radius + softness, d);
	COLOR = vec4(fog_color.rgb, a * fog_color.a);
}
"""


func _ready() -> void:
	layer = 8  # above the world, below the HUD/overlays
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	add_child(rect)
