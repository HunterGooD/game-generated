shader_type canvas_item;

// Diablo-style resource globe: a glass orb filled with animated liquid.
// Used for the HUD health globe (bright red) and the class resource globe
// (mana blue / barbarian dark rage / rogue amber / druid green / hexen violet).
//   fill        — liquid level 0..1
//   liquid_color— base liquid tint
//   darkness    — murky variant (rage): darkens body, thickens depth shading
//   shield_frac — pale glassy layer drawn OVER the liquid from the bottom up
//                 (shield_hp / max_hp), so an active shield visibly sheathes
//                 the health globe.
uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform vec4 liquid_color : source_color = vec4(0.85, 0.08, 0.1, 1.0);
uniform float darkness : hint_range(0.0, 1.0) = 0.0;
uniform float shield_frac : hint_range(0.0, 1.0) = 0.0;
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

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float t = TIME + seed_offset;

	// Liquid surface: fill=1 → top (-1), fill=0 → bottom (+1), with two
	// overlapping waves so the liquid feels alive.
	float level = 1.0 - 2.0 * fill;
	float wave = (sin(uv.x * 4.0 + t * 2.2) + sin(uv.x * 7.3 - t * 3.1) * 0.5) * 0.04;
	float surf = level + wave;
	float in_liquid = step(surf, uv.y);

	// Liquid body: murkier with `darkness`, shaded deeper toward the bottom,
	// glowing line at the surface, faint internal churn.
	vec3 liq = liquid_color.rgb * mix(1.0, 0.45, darkness);
	float depth_shade = mix(1.0, mix(0.55, 0.3, darkness), clamp((uv.y - surf) / 1.6, 0.0, 1.0));
	liq *= depth_shade;
	liq += liquid_color.rgb * exp(-abs(uv.y - surf) * 14.0) * 0.55;
	liq += vec3(vnoise(uv * 3.0 + vec2(t * 0.3, -t * 0.45))) * 0.06 * (1.0 - darkness * 0.5);

	// Empty space above the liquid: dark glass interior.
	vec3 col = mix(vec3(0.05, 0.045, 0.06), liq, in_liquid);

	// Shield sheath: pale translucent layer over everything below its level.
	if (shield_frac > 0.001) {
		float sh_level = 1.0 - 2.0 * clamp(shield_frac, 0.0, 1.0);
		float in_shield = step(sh_level, uv.y);
		col = mix(col, vec3(0.75, 0.85, 1.0), in_shield * 0.38);
		col += vec3(0.8, 0.9, 1.0) * exp(-abs(uv.y - sh_level) * 20.0) * 0.5;
	}

	// Glass: darkened rim, upper-left specular, thin metallic ring.
	col *= mix(1.0, 0.35, smoothstep(0.72, 1.0, r));
	col += vec3(1.0) * exp(-distance(uv, vec2(-0.45, -0.5)) * 2.4) * 0.16;
	float ring = smoothstep(0.99, 0.94, r) - smoothstep(0.92, 0.86, r);
	col += vec3(0.6, 0.55, 0.45) * ring * 0.4;

	float alpha = smoothstep(1.0, 0.965, r);
	COLOR = vec4(col, alpha);
}
