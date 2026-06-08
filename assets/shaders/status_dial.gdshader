shader_type canvas_item;

// Status icon with a "clock dial" countdown. Drawn on a ColorRect (placeholder
// black/tinted square) OR a TextureRect (real icon later) — the radial wipe is the
// same either way, so art can be dropped in without touching this shader.
//
// `progress` is TIME REMAINING (1.0 = just applied, 0.0 = expired). The dial
// DEPLETES: a bright wedge starts full at 12 o'clock and unwinds clockwise as the
// status runs out; the elapsed slice is dimmed.

uniform vec4 tint : source_color = vec4(0.05, 0.05, 0.06, 1.0); // square fill (placeholder)
uniform float progress : hint_range(0.0, 1.0) = 1.0;            // time remaining
uniform vec4 dim_color : source_color = vec4(0.0, 0.0, 0.0, 0.66); // overlay on elapsed slice
uniform float use_icon = 0.0;  // 0 = solid tint square, 1 = sample TEXTURE (real art)
uniform vec4 border_color : source_color = vec4(0.85, 0.85, 0.9, 1.0);
uniform float border = 0.07;

void fragment() {
	vec2 uv = UV;
	// Base: solid tint placeholder, or the supplied texture once art exists.
	vec4 base = mix(tint, texture(TEXTURE, uv) * tint, use_icon);
	vec3 col = base.rgb;

	// Clock dial: angle measured from 12 o'clock, increasing clockwise.
	vec2 d = uv - vec2(0.5);
	float ang = atan(d.x, -d.y);
	if (ang < 0.0) {
		ang += TAU;
	}
	float remaining = progress * TAU;
	// Pixels past the remaining wedge are the elapsed slice → dim them.
	if (ang > remaining) {
		col = mix(col, dim_color.rgb, dim_color.a);
	}

	// Inner frame for definition (also works under a transparent art layer).
	float inside =
		step(border, uv.x) * step(border, 1.0 - uv.x)
		* step(border, uv.y) * step(border, 1.0 - uv.y);
	col = mix(border_color.rgb, col, inside);

	COLOR = vec4(col, base.a);
}
