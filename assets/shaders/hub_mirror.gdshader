shader_type canvas_item;

// Hub "Mirror" prop surface. Applied to the mirror's body ColorRect so the meta-tree
// portal reads as a tall pane of enchanted glass: a vertical tint gradient, a gentle
// wavy distortion, faint vertical reflection streaks, and a slow diagonal sheen sweeping
// across it. Purely cosmetic. Tint defaults to the mirror's violet.

uniform vec4 tint : source_color = vec4(0.62, 0.45, 0.92, 1.0);
uniform float wave_speed = 1.4;
uniform float sheen_speed = 0.6;

void fragment() {
	vec2 uv = UV;
	// Wavy mirror distortion — bends the streaks/sheen like rippled glass.
	float wave = sin(uv.y * 16.0 + TIME * wave_speed) * 0.010;
	uv.x += wave;

	// Vertical gradient: luminous near the top, deeper toward the base.
	float grad = mix(1.05, 0.40, UV.y);
	vec3 col = tint.rgb * grad;

	// Faint vertical reflection streaks.
	float streak = sin(uv.x * 46.0) * 0.05;
	col += streak;

	// Slow diagonal sheen band sweeping across the pane.
	float band = sin((uv.x + uv.y) * 3.14159 - TIME * sheen_speed);
	float sheen = smoothstep(0.86, 1.0, band);
	col += vec3(0.85, 0.80, 1.0) * sheen * 0.55;

	// Soft inner edge darkening so the pane has a glassy rim.
	float edge = smoothstep(0.0, 0.06, UV.x) * smoothstep(1.0, 0.94, UV.x);
	col *= mix(0.7, 1.0, edge);

	COLOR = vec4(col, tint.a * 0.94);
}
