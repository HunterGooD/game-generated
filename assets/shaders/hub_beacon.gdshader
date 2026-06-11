shader_type canvas_item;

// Hub "Beacon" (co-op) prop — a wavy vertical aurora of green light. Applied to the beacon's
// body ColorRect: a glowing column wobbles side-to-side with height and time, with rising
// shimmer bands and a bright top, fading toward the rim. Pairs with small green spark
// particles spawned in hub.gd. Purely cosmetic.

uniform vec4 tint : source_color = vec4(0.5, 0.85, 0.6, 1.0);
uniform float wave_speed = 1.0;

void fragment() {
	// Column wobble: a horizontal offset that varies with height and time (aurora sway).
	float wob = sin(UV.y * 8.0 + TIME * wave_speed * 2.0) * 0.06
		+ sin(UV.y * 3.0 - TIME * wave_speed) * 0.04;
	float col_d = abs((UV.x - 0.5) + wob);
	float beam = smoothstep(0.32, 0.0, col_d);     // bright near the column
	float band = 0.6 + 0.4 * sin(UV.y * 14.0 - TIME * wave_speed * 3.0);  // rising shimmer
	float grad = mix(1.25, 0.4, UV.y);             // brighter at the top
	vec3 col = tint.rgb * beam * band * grad;
	col += vec3(0.7, 1.0, 0.8) * beam * beam * 0.35;  // bright inner core
	COLOR = vec4(col, tint.a * beam);
}
