shader_type canvas_item;

void fragment() {
	vec3 pixel = texture(TEXTURE, UV).rgb;
	vec3 difference = abs(pixel - vec3(95.0 / 255.0));
	float separation = max(difference.r, max(difference.g, difference.b));
	COLOR.a *= smoothstep(0.004, 0.075, separation);
}
