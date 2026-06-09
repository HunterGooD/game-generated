shader_type canvas_item;

// Elite aura — renders the sprite's silhouette in a flat affix colour, gently pulsing.
// Drawn on a slightly enlarged child sprite BEHIND the enemy, so the part that peeks
// beyond the main sprite reads as a coloured halo/outline (independent of whether the
// source texture has any transparent padding — unlike a sample-based outline shader).

uniform vec4 tint : source_color = vec4(1.0, 0.3, 0.2, 1.0);

void fragment() {
	float a = texture(TEXTURE, UV).a;
	float pulse = 0.72 + 0.28 * sin(TIME * 3.0);
	COLOR = vec4(tint.rgb, a * tint.a * pulse);
}
