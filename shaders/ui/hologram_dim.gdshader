shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix;
// Pilot's meshes write stencil 1 while the menu is up; the world is dimmed everywhere else.
stencil_mode read, compare_not_equal, 1;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float darken = 0.35;
uniform float desaturate = 0.3;
uniform float vignette = 0.3;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desaturate * amount);
	c *= 1.0 - darken * amount;
	float v = smoothstep(0.35, 0.95, length(SCREEN_UV - 0.5) * 1.3);
	c *= 1.0 - vignette * v * amount;
	ALBEDO = c;
}
