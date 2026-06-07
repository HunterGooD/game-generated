shader_type canvas_item;

// Adds a soft outer glow whose color is set per-item from the rarity table.
// Cheap — single radial falloff applied around any non-transparent pixel.

uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float glow_strength : hint_range(0.0, 2.0) = 0.9;
uniform float glow_radius : hint_range(0.0, 8.0) = 3.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 ts = TEXTURE_PIXEL_SIZE * glow_radius;
	float a = 0.0;
	a += texture(TEXTURE, UV + vec2( ts.x, 0.0)).a;
	a += texture(TEXTURE, UV + vec2(-ts.x, 0.0)).a;
	a += texture(TEXTURE, UV + vec2(0.0,  ts.y)).a;
	a += texture(TEXTURE, UV + vec2(0.0, -ts.y)).a;
	a *= 0.25;
	float glow = clamp(a - base.a, 0.0, 1.0) * glow_strength;
	vec4 result = base;
	result.rgb += glow_color.rgb * glow;
	result.a = max(result.a, glow * glow_color.a);
	COLOR = result * COLOR;
}
