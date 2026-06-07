shader_type canvas_item;

// Animated lava-pulse overlay for the dungeon floor. Multiplies the floor
// tile texture by a slow scrolling noise + warm pulsing color, biasing the
// arena toward a hellish ember glow without hiding the underlying tiling.

uniform vec4 warm_color : source_color = vec4(1.0, 0.45, 0.22, 1.0);
uniform vec4 cool_color : source_color = vec4(0.55, 0.12, 0.16, 1.0);
uniform float pulse_speed : hint_range(0.0, 4.0) = 0.45;
uniform float scroll_speed : hint_range(0.0, 2.0) = 0.18;
uniform float intensity : hint_range(0.0, 1.0) = 0.55;

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
	vec4 base = texture(TEXTURE, UV);
	vec2 scroll = UV + vec2(0.0, -TIME * scroll_speed);
	float n = noise(scroll * 3.5);
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed + n * 6.28);
	vec3 lava = mix(cool_color.rgb, warm_color.rgb, pulse * n);
	base.rgb = mix(base.rgb, base.rgb * lava * 1.7, intensity);
	COLOR = base * COLOR;
}
