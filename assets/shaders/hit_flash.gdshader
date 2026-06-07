shader_type canvas_item;

// Cheap hit-flash. flash_amount in [0..1] mixes the sprite toward flash_color.
// Designed for the Compatibility (WebGL2) renderer.

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(2.0, 0.45, 0.45, 1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.rgb = mix(c.rgb, flash_color.rgb, flash_amount);
	COLOR = c * COLOR;
}
