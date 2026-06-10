shader_type canvas_item;

// Empowerment-pillar glow. Applied to the pillar's body/glow ColorRects so each column
// reads as a colored, pulsing beacon: red = empower enemies, green = aid allies,
// purple = rare. A vertical gradient + time pulse makes it feel like rising energy.

uniform vec4 tint : source_color = vec4(1.0, 0.3, 0.25, 1.0);
uniform float pulse_speed = 3.0;
uniform float brightness = 1.3;

void fragment() {
	float pulse = 0.7 + 0.3 * sin(TIME * pulse_speed);
	// Brighter toward the top of the rect (UV.y 0 = top).
	float grad = mix(1.15, 0.55, UV.y);
	vec3 col = tint.rgb * brightness * grad * pulse;
	COLOR = vec4(col, tint.a * (0.85 + 0.15 * pulse));
}
