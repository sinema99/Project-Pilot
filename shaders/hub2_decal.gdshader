// hub2's decals: vents, stripes, plates, stencil labels, grime streaks, indicator lamps. One sheet
// (scripts/hub2_decal_atlas.gd), alpha cut out (no blending, so they sit in the same flat pixel
// style as the surface), lit like the surface under them. The sheet's glow layer lights the lamps.
// The quads float 3 cm off the face; the clip-space bias keeps them from z-fighting far away.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

uniform sampler2D sheet : source_color, filter_nearest, repeat_disable;
uniform sampler2D glow_sheet : source_color, filter_nearest, repeat_disable;
uniform float glow_strength = 1.8;
uniform float depth_bias = 0.0004;

void vertex() {
	bool ortho = PROJECTION_MATRIX[3][3] > 0.5;
	if (!ortho) {
		vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
		clip.z += depth_bias * clip.w;
		POSITION = clip;
	}
}

void fragment() {
	vec4 s = texture(sheet, UV);
	if (s.a < 0.5) {
		discard;
	}
	ALBEDO = s.rgb * COLOR.rgb;
	vec4 g = texture(glow_sheet, UV);
	EMISSION = g.rgb * g.a * glow_strength;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
