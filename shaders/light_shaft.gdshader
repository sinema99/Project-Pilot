shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// The visible shaft of a ceiling lamp. Soft on every side: it fades where it meets a surface (so
// it never draws a hard ring on the floor), thins toward its edge (so no cone outline), and
// keeps its glow when the camera is inside it.

uniform vec4 tint : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform float strength = 0.06;
uniform float height = 30.0;
uniform float surface_fade = 3.0;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

varying float v_h;

void vertex() {
	// 0 at the bottom of the cone, 1 at the lamp
	v_h = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float face = pow(abs(dot(n, v)), 1.5);

	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 p = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -p.z / p.w;
	float gap = clamp((scene_z - (-VERTEX.z)) / surface_fade, 0.0, 1.0);
	gap = gap * gap * (3.0 - 2.0 * gap);

	// brightest near the lamp, dying out well before the floor
	float along = pow(v_h, 1.3);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * strength * face * gap * along;
}
