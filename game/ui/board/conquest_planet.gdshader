shader_type canvas_item;
render_mode unshaded;

uniform vec4 terrain : source_color = vec4(0.36, 0.58, 0.78, 1.0);
uniform float seed = 1.0;

void fragment() {
	vec2 uv = UV - vec2(0.72, 0.82);
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 sphere = uv / 0.58;
	float d = length(sphere);
	float ring = exp(-abs(d - 0.995) * 75.0) * 0.4;
	float z = sqrt(max(0.0, 1.0 - d * d));
	float continents = sin(sphere.x * 7.0 + cos(sphere.y * 11.0 + seed) * 2.0 + seed)
		+ sin(sphere.y * 14.0 + sphere.x * 8.0 + z * 5.0 + seed);
	float shade = clamp(dot(vec3(sphere, z), normalize(vec3(-0.6, -0.7, 0.6))), 0.05, 0.92);
	vec3 ground = mix(terrain.rgb * 0.43, terrain.rgb, smoothstep(-0.24, 0.2, continents));
	float planet = 1.0 - smoothstep(0.993, 1.005, d);
	COLOR = vec4(ground * shade + terrain.rgb * ring, max(planet * 0.88, ring));
}
