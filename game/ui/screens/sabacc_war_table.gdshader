shader_type canvas_item;
render_mode unshaded;

float grain(vec2 xy) {
	return fract(sin(dot(xy, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - vec2(0.5, 0.5)) / vec2(0.49, 0.49);
	float rail = max(abs(p.y), abs(p.x) + 0.36 * abs(p.y));
	float mask = 1.0 - smoothstep(0.996, 1.0, rail);
	float light = 1.0 - clamp(length(p - vec2(-0.26, -0.72)) * 0.44, 0.0, 1.0);
	float texture_grain = grain(floor(UV * vec2(1100.0, 680.0))) - 0.5;
	vec3 field = mix(vec3(0.085, 0.048, 0.038), vec3(0.26, 0.16, 0.12), light);
	field += texture_grain * 0.042;
	float metal = smoothstep(0.901, 0.914, rail);
	vec3 edge = mix(vec3(0.073, 0.047, 0.037), vec3(0.46, 0.31, 0.19), light);
	edge += 0.044 * sin(rail * 480.0) + texture_grain * 0.046;
	vec3 color = mix(field, edge, metal);
	color += exp(-abs(rail - 0.936) * 145.0) * vec3(0.24, 0.16, 0.09);
	float shadow = (1.0 - smoothstep(0.94, 1.1, rail)) * 0.45;
	COLOR = vec4(color * mask, max(mask, shadow));
}
