shader_type canvas_item;

// Animated card panel for the ascension choice. Each card passes a `tint` (its
// role colour) and `grey` (1.0 for the "Remain Mortal" card → desaturated/cold).
// `intensity` is bumped on hover. Drawn on a ColorRect behind each card's text.

uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.2, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float grey : hint_range(0.0, 1.0) = 0.0;

// cheap hash noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;

	// Vertical base gradient (brighter toward the top).
	float grad = mix(0.18, 0.7, 1.0 - uv.y);

	// Rising energy: scrolling noise that drifts upward.
	float energy = noise(vec2(uv.x * 4.0, uv.y * 6.0 - t * 0.8));
	energy = pow(energy, 2.0) * 0.5;

	// Diagonal sheen sweeping across.
	float sheen = sin((uv.x + uv.y) * 5.0 - t * 1.6) * 0.5 + 0.5;
	sheen = pow(sheen, 3.0) * 0.3;

	// Gentle breathing pulse.
	float pulse = 0.85 + 0.15 * sin(t * 2.2);

	vec3 col = tint.rgb * (grad + energy + sheen) * intensity * pulse;

	// Inner border glow — bright frame, darker centre fill.
	float bx = smoothstep(0.0, 0.06, uv.x) * smoothstep(0.0, 0.06, 1.0 - uv.x);
	float by = smoothstep(0.0, 0.05, uv.y) * smoothstep(0.0, 0.05, 1.0 - uv.y);
	float frame = 1.0 - bx * by;
	col += tint.rgb * frame * 0.6 * intensity;

	// "Remain Mortal": desaturate and cool it down.
	float g = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(g) * vec3(0.55, 0.58, 0.66), grey);

	COLOR = vec4(col, 0.93);
}
