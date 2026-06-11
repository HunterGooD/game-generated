shader_type canvas_item;

// Blue "energy shield" overlay drawn on top of a health bar. The left `shield_frac`
// fraction of the bar (shield / max_hp) glows a shimmering, semi-transparent blue with
// a bright leading edge, so it's instantly obvious a hero is shielded and how much.
// Driven per-instance by the shield_frac uniform; transparent when shield_frac == 0.

uniform float shield_frac : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	if (shield_frac <= 0.001 || UV.x > shield_frac) {
		COLOR = vec4(0.0);
	} else {
		// Travelling shimmer + vertical sheen.
		float shimmer = 0.5 + 0.5 * sin((UV.x * 16.0) - TIME * 5.0);
		float sheen = 1.0 - abs(UV.y - 0.5) * 1.4;
		vec3 blue = vec3(0.30, 0.62, 1.0) + shimmer * vec3(0.18, 0.16, 0.0);
		// Bright leading edge at the shield front.
		float edge = smoothstep(shield_frac - 0.05, shield_frac, UV.x);
		COLOR.rgb = mix(blue, vec3(0.7, 0.9, 1.0), edge);
		COLOR.a = clamp((0.40 + 0.30 * shimmer) * sheen + edge * 0.5, 0.0, 0.9);
	}
}
