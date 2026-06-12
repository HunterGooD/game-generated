shader_type canvas_item;

// Elemental orb — fire / storm / frost ball used by the Elementalist:
// banked orbs orbit the player (elem_orb_ring.gd) and the same look is fired
// by Elemental Orbit (R). Draw on a square ColorRect; everything outside the
// ball is transparent.
//   element: 0 = fire (turbulent flame), 1 = storm (crackling plasma),
//            2 = frost (faceted crystal).
uniform int element = 0;
uniform float seed_offset = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float t = TIME + seed_offset;
	vec3 col = vec3(0.0);
	float alpha = 0.0;

	if (element == 0) {
		// FIRE — flame licks rise through the ball, bright core.
		float n = fbm(uv * 2.6 + vec2(0.0, -t * 1.8));
		float body = smoothstep(0.95, 0.35, r + (n - 0.5) * 0.55);
		vec3 hot = vec3(1.0, 0.95, 0.55);
		vec3 mid = vec3(1.0, 0.5, 0.12);
		vec3 edge = vec3(0.75, 0.1, 0.02);
		col = mix(edge, mid, body);
		col = mix(col, hot, smoothstep(0.55, 0.0, r) * (0.6 + 0.4 * n));
		alpha = body;
	} else if (element == 1) {
		// STORM — thin shell + bright core with arcs crackling around it.
		float ang = atan(uv.y, uv.x);
		float arc = abs(sin(ang * 3.0 + t * 7.0 + fbm(uv * 3.0 + vec2(t)) * 6.0));
		float bolt = smoothstep(0.92, 1.0, arc) * smoothstep(1.0, 0.25, r);
		float core = smoothstep(0.45, 0.0, r);
		float shell = smoothstep(0.85, 0.6, r) - smoothstep(0.6, 0.3, r);
		float flicker = 0.75 + 0.25 * vnoise(vec2(t * 9.0, ang));
		col = vec3(0.45, 0.55, 1.0) * (shell * 0.8 + bolt * 1.4) * flicker;
		col += vec3(0.9, 0.95, 1.0) * core;
		alpha = clamp(core + shell * 0.7 + bolt, 0.0, 1.0) * smoothstep(1.0, 0.85, r);
	} else {
		// FROST — slow shimmering facets over a deep-blue ball.
		float n = fbm(uv * 3.0 + vec2(t * 0.25));
		float facets = abs(fract(n * 4.0) - 0.5) * 2.0;
		float body = smoothstep(0.9, 0.5, r);
		vec3 deep = vec3(0.15, 0.35, 0.7);
		vec3 icec = vec3(0.6, 0.85, 1.0);
		col = mix(deep, icec, facets * 0.7 + smoothstep(0.5, 0.0, r) * 0.5);
		col += vec3(1.0) * smoothstep(0.25, 0.0, r) * 0.35;
		alpha = body;
	}

	COLOR = vec4(col, alpha);
}
