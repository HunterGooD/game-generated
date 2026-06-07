shader_type canvas_item;

// Noise-based dissolve with a glowing burn edge. dissolve_amount 0 → 1
// chews the sprite away from random pixels; the band around the eaten
// frontier emits edge_color (set by script to the enemy's hue tint).

uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float edge_width : hint_range(0.0, 0.25) = 0.08;

// Cheap 2D hash → pseudo-noise. Web-safe (no derivatives, no textures).
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float n = noise(UV * 18.0);
	float threshold = dissolve_amount * 1.25;
	if (n < threshold - edge_width) {
		// Fully eaten — discard.
		c.a = 0.0;
	} else if (n < threshold) {
		// On the burn edge.
		c.rgb = mix(c.rgb, edge_color.rgb, 0.85);
		c.a = max(c.a, 0.95);
	}
	COLOR = c * COLOR;
}
