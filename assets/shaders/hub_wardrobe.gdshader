shader_type canvas_item;

// Hub "Wardrobe" prop — an enchanted wardrobe whose two doors stand slightly ajar, a bright
// pulsing seam of light spilling out down the centre. Soft vertical wood-sheen panels, a
// slow light sweep rising up the doors, and a darker frame border. Cool arcane blue. Pairs
// with sparkle particles spawned in hub.gd. Purely cosmetic.

uniform vec4 tint : source_color = vec4(0.55, 0.7, 1.0, 1.0);
uniform float pulse_speed = 2.2;
uniform float sweep_speed = 0.18;

void fragment() {
	vec2 uv = UV;
	float dist = abs(uv.x - 0.5);             // 0 at the seam … 0.5 at the outer edges

	// Door panels: faint vertical wood-sheen grain, a touch darker toward the seam.
	float grain = 0.90 + 0.10 * sin(uv.x * 26.0);
	float panel = mix(0.45, 0.85, smoothstep(0.0, 0.5, dist));
	float grad = mix(1.05, 0.55, uv.y);       // brighter at the top
	vec3 col = tint.rgb * panel * grain * grad;

	// Glowing central seam (doors ajar), gently pulsing.
	float pulse = 0.78 + 0.22 * sin(TIME * pulse_speed);
	float seam = smoothstep(0.06, 0.0, dist);
	col += vec3(0.85, 0.92, 1.0) * seam * pulse * 1.4;

	// Soft light sweep rising up the doors.
	float sweep = smoothstep(0.12, 0.0, abs(fract(uv.y * 0.5 - TIME * sweep_speed) - 0.5));
	col += tint.rgb * sweep * 0.28;

	// Darker carved frame around the edges.
	float frame = smoothstep(0.0, 0.05, uv.x) * smoothstep(1.0, 0.95, uv.x)
		* smoothstep(0.0, 0.035, uv.y) * smoothstep(1.0, 0.985, uv.y);
	col *= mix(0.55, 1.0, frame);

	COLOR = vec4(col, tint.a);
}
