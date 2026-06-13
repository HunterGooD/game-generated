shader_type canvas_item;

// Full-disc hurricane vortex for the barbarian Whirlwind. Spins continuously on
// its own (driven by TIME, not a node tween — so it can never "stick"), churns
// like a storm, and is dense enough to mostly OCCLUDE the hero underneath, so it
// uses normal (mix) blending — NOT additive — and is drawn above the player.
// Purely procedural from UV (a blank quad supplies the canvas); web-safe.

uniform vec4 body_color : source_color = vec4(0.85, 0.10, 0.07, 1.0);  // deep rage red
uniform vec4 hot_color : source_color = vec4(1.0, 0.80, 0.45, 1.0);    // hot arm/eye highlight
uniform float spin_speed = 3.2;   // radians/sec of swirl rotation
uniform float arms = 5.0;         // number of spiral arms
uniform float twist = 9.0;        // how much the arms curl with radius
uniform float opacity = 0.92;     // how strongly it hides the hero (0..1)
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;          // 0 centre … 1 at the disc edge
	float a = atan(p.y, p.x);

	// Spiral arms that curl inward and rotate over time.
	float swirl = a * arms + r * twist - TIME * spin_speed;
	float arm = 0.5 + 0.5 * sin(swirl);
	// Turbulence so it boils like a storm instead of a clean pinwheel.
	float n = noise(vec2(a * 2.5 + seed, r * 4.0 - TIME * 1.6));
	float dens = clamp(mix(arm, n, 0.45) * 1.2, 0.0, 1.0);

	// Solid spinning disc that fades only at the very rim → covers the hero.
	float disc = smoothstep(1.0, 0.62, r);
	// A small brighter "eye" pull at the centre.
	float eye = 1.0 - smoothstep(0.0, 0.22, r);

	float alpha = disc * opacity * mix(0.7, 1.0, dens);

	// Deep red body, hot highlights along the arms and at the eye.
	vec3 col = mix(body_color.rgb, hot_color.rgb, clamp(dens * 0.55 + eye * 0.6, 0.0, 1.0));

	if (alpha <= 0.004) {
		discard;
	}
	COLOR = vec4(col, alpha) * COLOR;
}
