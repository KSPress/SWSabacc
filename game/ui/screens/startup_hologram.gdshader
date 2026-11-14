shader_type canvas_item;
render_mode unshaded;

uniform bool animated = true;
uniform float elapsed = 0.0;

float noise(float seed) {
	return fract(sin(seed * 127.1 + 311.7) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float glow = 0.0;
	float signal_level = 1.0;
	float raster = 0.0;
	float sweep = 0.0;
	float reveal = 1.0;
	if (animated) {
		float tick = floor(elapsed * 27.0);
		float glitch = step(0.84, noise(tick));
		float strip = floor(uv.y * 24.0);
		float dropout = step(0.78, noise(tick + strip * 3.0));
		uv.x += (noise(tick + strip) - 0.5) * 0.032 * glitch * dropout;
		signal_level = 0.92 + 0.08 * noise(tick) - 0.30 * glitch * dropout;
		raster = 0.5 + 0.5 * cos(uv.y * 440.0 + elapsed * 9.0);
		sweep = exp(-abs(uv.y - fract(elapsed * 0.62)) * 26.0);
		float leading_edge = mix(0.12, 1.06, clamp(elapsed * 2.45, 0.0, 1.0));
		reveal = (1.0 - smoothstep(leading_edge - 0.08, leading_edge, uv.y))
			* smoothstep(0.0, 0.14, elapsed);
		glow += texture(TEXTURE, uv + vec2(0.012, 0.0)).a;
		glow += texture(TEXTURE, uv - vec2(0.012, 0.0)).a;
		glow += texture(TEXTURE, uv + vec2(0.0, 0.012)).a;
		glow += texture(TEXTURE, uv - vec2(0.0, 0.012)).a;
		glow *= 0.12;
	}
	float mark = texture(TEXTURE, uv).a;
	float clarity = clamp(0.50 + 0.30 * raster + 0.55 * sweep, 0.0, 1.0);
	vec3 light = mix(vec3(0.18, 0.65, 0.98), vec3(0.76, 0.96, 1.0), mark * clarity);
	float halo = exp(-dot(UV - 0.5, UV - 0.5) * 17.0);
	float edges = smoothstep(0.0, 0.13, min(min(UV.x, UV.y), min(1.0 - UV.x, 1.0 - UV.y)));
	COLOR = vec4(light, max(halo * 0.07, max(mark, glow) * signal_level * reveal) * edges);
}
