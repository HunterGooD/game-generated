shader_type canvas_item;

// Cheap single-pass outline using 8 neighbour samples on alpha.
// outline_color and outline_strength drive the result; enabled controls
// the whole effect so we can fade it in/out cleanly.

uniform vec4 outline_color : source_color = vec4(1.0, 0.2, 0.3, 1.0);
uniform float outline_width : hint_range(0.0, 6.0) = 1.5;
uniform float outline_strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	if (outline_strength <= 0.001) {
		COLOR = base * COLOR;
	} else {
		vec2 ts = TEXTURE_PIXEL_SIZE * outline_width;
		float a = 0.0;
		a += texture(TEXTURE, UV + vec2( ts.x,  0.0)).a;
		a += texture(TEXTURE, UV + vec2(-ts.x,  0.0)).a;
		a += texture(TEXTURE, UV + vec2( 0.0,  ts.y)).a;
		a += texture(TEXTURE, UV + vec2( 0.0, -ts.y)).a;
		a += texture(TEXTURE, UV + vec2( ts.x,  ts.y)).a * 0.5;
		a += texture(TEXTURE, UV + vec2(-ts.x,  ts.y)).a * 0.5;
		a += texture(TEXTURE, UV + vec2( ts.x, -ts.y)).a * 0.5;
		a += texture(TEXTURE, UV + vec2(-ts.x, -ts.y)).a * 0.5;
		float edge = clamp(a - base.a * 6.0, 0.0, 1.0) * outline_strength;
		vec4 result = base;
		if (edge > 0.001 && base.a < 0.05) {
			result = vec4(outline_color.rgb, edge);
		}
		COLOR = result * COLOR;
	}
}
