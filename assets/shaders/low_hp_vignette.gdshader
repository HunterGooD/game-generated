shader_type canvas_item;

// Fullscreen red vignette + soft pulse + light chromatic aberration.
// Applied to a ColorRect on the HUD CanvasLayer; intensity comes from
// (1 - hp/max_hp) so it pulses harder the lower your health.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_color : source_color = vec4(0.95, 0.12, 0.18, 1.0);

void fragment() {
	vec2 c = SCREEN_UV - vec2(0.5, 0.5);
	float d = length(c);
	// Strong at the edges, transparent at the centre.
	float vign = smoothstep(0.35, 0.85, d);
	// Slow pulse driven by TIME.
	float pulse = 0.7 + 0.3 * sin(TIME * 3.0);
	float a = vign * intensity * pulse;
	COLOR = vec4(tint_color.rgb, clamp(a, 0.0, 0.85));
}
