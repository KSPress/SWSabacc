shader_type canvas_item;

uniform bool animated = true;

void fragment() {
	float tick = animated ? floor(TIME * 9.0) : 0.0;
	vec2 pixel = TEXTURE_PIXEL_SIZE;
	float band = floor(UV.y * 29.0);
	float jitter = step(0.91, fract(sin(band * 19.7 + tick * 5.3) * 415.7));
	vec2 uv = UV + vec2(jitter * pixel.x * 16.0, 0.0);
	vec2 blur = pixel * 11.0;
	vec4 card = texture(TEXTURE, uv) * 0.4;
	card += (texture(TEXTURE, uv + vec2(blur.x, 0.0)) + texture(TEXTURE, uv - vec2(blur.x, 0.0))
		+ texture(TEXTURE, uv + vec2(0.0, blur.y)) + texture(TEXTURE, uv - vec2(0.0, blur.y))) * 0.15;
	float lines = mix(0.68, 1.0, step(0.28, fract(UV.y * 210.0)));
	float flicker = animated ? 0.9 + 0.08 * sin(TIME * 17.0) : 0.95;
	vec3 cyan = mix(card.rgb, vec3(0.27, 0.78, 1.0) * (0.5 + card.g * 0.6), 0.58);
	COLOR = vec4(cyan * lines, card.a * flicker * 0.65);
}
