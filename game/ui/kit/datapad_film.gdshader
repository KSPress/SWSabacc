shader_type canvas_item;
render_mode unshaded;

uniform bool animated = true;
uniform float blur_amount : hint_range(0.0, 1.0) = 0.10;

void fragment() {
	vec2 dx = dFdx(UV) * 4.0;
	vec2 dy = dFdy(UV) * 4.0;
	vec3 sharp = texture(TEXTURE, UV).rgb;
	vec3 soft = (texture(TEXTURE, UV + dx).rgb + texture(TEXTURE, UV - dx).rgb
		+ texture(TEXTURE, UV + dy).rgb + texture(TEXTURE, UV - dy).rgb) * 0.25;
	vec3 photo = mix(sharp, soft, blur_amount);
	float scan = 1.0 - smoothstep(0.0, 0.32, fract(FRAGCOORD.y / 4.0));
	float phase = animated ? TIME * 0.16 : 0.28;
	float sweep = 1.0 - smoothstep(0.0, 0.11, abs(fract(SCREEN_UV.y - phase) - 0.5));
	float corners = smoothstep(0.25, 0.76, length((SCREEN_UV - 0.5) * vec2(0.95, 1.12)));
	float grain_frame = animated ? floor(TIME * 12.0) : 0.0;
	vec2 pixel = floor(FRAGCOORD.xy * 0.5) + mod(grain_frame, 97.0) * vec2(13.0, 23.0);
	float grain = fract(sin(dot(pixel, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	float flicker = animated ? sin(TIME * 10.0) * 0.009 + sin(TIME * 19.0) * 0.006 : 0.0;
	vec3 film = mix(photo, vec3(0.031, 0.067, 0.11), 0.27);
	film *= 1.0 - scan * 0.13 - corners * 0.24 + flicker;
	film += sweep * vec3(0.011, 0.029, 0.034) + grain * 0.035;
	COLOR = vec4(clamp(film, vec3(0.0), vec3(1.0)), 1.0);
}
