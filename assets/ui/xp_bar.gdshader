shader_type canvas_item;

// Animated XP bar shader — adds a scrolling shine + pulse to the filled portion.
// Apply on a ColorRect over the filled area.

uniform vec4 base_color : source_color = vec4(0.90, 0.18, 0.22, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 0.78, 0.32, 1.0);
uniform float shine_speed : hint_range(0.0, 4.0) = 1.4;
uniform float shine_width : hint_range(0.01, 0.6) = 0.18;
uniform float pulse_strength : hint_range(0.0, 0.6) = 0.18;
uniform float pulse_speed : hint_range(0.0, 8.0) = 3.5;

void fragment() {
	float u = UV.x;
	// Scrolling shine highlight.
	float t = mod(TIME * shine_speed, 1.6) - 0.3;
	float d = abs(u - t);
	float shine = smoothstep(shine_width, 0.0, d);
	// Gentle vertical gradient — darker at edges, brighter in middle.
	float gradient = 1.0 - 0.55 * abs(UV.y - 0.5) * 2.0;
	// Pulse.
	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_strength;
	vec3 col = mix(base_color.rgb, highlight_color.rgb, shine * 0.85);
	col *= gradient * pulse;
	COLOR = vec4(col, 1.0);
}
