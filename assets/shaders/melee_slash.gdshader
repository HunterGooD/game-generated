shader_type canvas_item;
render_mode blend_add;

// Procedural melee slash. Draws a bright crescent arc straight from UV — no
// texture art — that sweeps across as `progress` runs 0→1 (driven by a Tween,
// like flash_amount in hit_flash.gdshader). Additive (blend_add) so it reads as
// a hot energy swoosh on the dark combat canvas and never darkens what's behind
// it. Color comes from uniforms (set per class/element by SlashFx), `style`
// switches the shape preset. Web-safe: no derivatives, no texture sampling.
//
// Drawn on a blank square quad: UV 0..1, the arc points along +X (the sprite is
// rotated to the attack direction by the spawner).

uniform vec4 slash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.7, 0.8, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;   // sweep + fade driver
uniform float arc_span : hint_range(0.5, 3.1) = 2.4;   // angular width (radians)
uniform float radius : hint_range(0.1, 0.5) = 0.38;    // band centre radius (UV)
uniform float thickness : hint_range(0.02, 0.3) = 0.12;// band half-width
uniform float softness : hint_range(0.0, 0.2) = 0.05;  // edge feather
uniform float core_white : hint_range(0.0, 2.0) = 1.1; // hot leading-edge boost
uniform float intensity : hint_range(0.0, 3.0) = 1.4;  // overall brightness
uniform int style : hint_range(0, 3) = 0;              // 0 blade 1 fire 2 claw 3 electric
uniform float hold : hint_range(0.0, 1.0) = 0.0;       // 1 = steady full crescent (spinning skills)
uniform float seed = 0.0;

// Cheap 2D hash → pseudo-noise (matches dissolve.gdshader's web-safe approach).
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

// Soft radial band mask around `r0` with half-width `half_w`, feathered by softness.
float band(float r, float r0, float half_w) {
	return 1.0 - smoothstep(half_w, half_w + softness + 0.001, abs(r - r0));
}

void fragment() {
	// Centre the quad; +X is the swing direction.
	vec2 p = UV - vec2(0.5);
	float r = length(p);
	float a = atan(p.y, p.x);              // -PI..PI, 0 along +X

	// Outside the sector → nothing.
	float half_span = arc_span * 0.5;
	// Normalised position along the arc, 0 (one tip) → 1 (other tip).
	float t = clamp((a + half_span) / arc_span, 0.0, 1.0);

	float eff_r = r;
	float thick = thickness;
	float flick = 1.0;

	// ---- style-specific distortion of the band geometry ----
	if (style == 1) {
		// Fire: warp the radius with animated noise → ragged, licking edge.
		float n = noise(vec2(t * 9.0 + seed, TIME * 3.0));
		eff_r += (n - 0.5) * 0.10;
		flick = 0.8 + 0.2 * noise(vec2(t * 20.0, TIME * 11.0 + seed));
	} else if (style == 3) {
		// Electric: jagged angular jitter + fast flicker.
		float n = noise(vec2(t * 26.0 + seed, TIME * 14.0));
		eff_r += (n - 0.5) * 0.05;
		thick = thickness * 0.65;
		flick = step(0.25, noise(vec2(t * 40.0, TIME * 30.0))) * 0.6 + 0.4;
	} else if (style == 2) {
		// Claw: thinner band (the 3 rakes are summed below).
		thick = thickness * 0.34;
	} else {
		// Blade: crisp, slightly thinner core for a clean edge.
		thick = thickness * 0.85;
	}

	// ---- radial silhouette ----
	float rad;
	float core_band;
	if (style == 2) {
		// Three parallel rakes straddling the centre radius.
		float sep = thickness * 0.7;
		float r1 = band(eff_r, radius - sep, thick);
		float r2 = band(eff_r, radius, thick);
		float r3 = band(eff_r, radius + sep, thick);
		rad = max(r1, max(r2, r3));
		core_band = rad;
	} else {
		rad = band(eff_r, radius, thick);
		core_band = 1.0 - smoothstep(0.0, thick * 0.7 + 0.001, abs(eff_r - radius));
	}

	// ---- angular sector mask (feathered tips) ----
	float ang = smoothstep(half_span, half_span - 0.18, abs(a));

	float shape = rad * ang;

	// ---- sweep: a bright front runs across the arc, revealing behind it,
	// the far tail dims (motion-blur feel), and the whole thing fades out.
	// In hold mode the front instead orbits forever via TIME and nothing fades —
	// a steady full crescent for spinning skills (whirlwind). ----
	bool held = hold > 0.5;
	float front = held ? fract(TIME * 0.6) : mix(-0.15, 1.15, progress);
	float reveal = 1.0 - smoothstep(front, front + 0.10, t);     // drawn behind front
	float tail = smoothstep(front - 0.85, front, t);             // far back dims
	float lead = smoothstep(0.14, 0.0, abs(t - front));          // hot leading edge
	float body_fade = 1.0 - smoothstep(0.55, 1.0, progress);     // overall fade-out

	float alpha;
	if (held) {
		alpha = shape * flick * intensity;
	} else {
		alpha = shape * reveal * mix(0.45, 1.0, tail) * body_fade * flick;
		// Leading edge stays bright even where reveal is transitioning.
		alpha = max(alpha, shape * lead * body_fade * flick);
		alpha *= intensity;
	}

	// ---- colour: glow at the band edges, core hue at the centre, white-hot
	// at the sweeping front. ----
	vec3 rgb = mix(glow_color.rgb, slash_color.rgb, core_band);
	rgb += vec3(core_white) * lead * shape;

	if (alpha <= 0.001) {
		discard;
	}
	COLOR = vec4(rgb, clamp(alpha, 0.0, 1.0)) * COLOR;
}
