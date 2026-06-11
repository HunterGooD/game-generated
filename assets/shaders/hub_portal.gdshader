shader_type canvas_item;

// Hub "Portal" prop — a swirling vortex of fire. Applied to the portal's body ColorRect:
// polar swirl bands spiral inward toward a hot core, fading to the tint at the rim and to
// transparent at the rect corners (so it reads as a glowing disc). Pairs with rising ember
// particles spawned in hub.gd. Purely cosmetic.

uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.35, 1.0);
uniform float swirl_speed = 3.0;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;          // 0 at centre … ~1 at edge
	float ang = atan(p.y, p.x);
	// Spiral the angle inward over time — the bands appear to pour into the core.
	float sw = ang + TIME * swirl_speed - r * 6.0;
	float bands = 0.5 + 0.5 * sin(sw * 4.0);
	float core = smoothstep(1.0, 0.0, r);   // hot toward the middle
	vec3 hot = vec3(1.0, 0.85, 0.45);
	vec3 col = mix(tint.rgb, hot, core * bands);
	col *= mix(0.6, 1.45, core);             // brighter centre
	// Circular fade so the square corners disappear.
	float edge = smoothstep(1.05, 0.55, r);
	COLOR = vec4(col, tint.a * edge);
}
