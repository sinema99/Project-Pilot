// hub2's decals: vents, stripes, plates, stencil labels, grime streaks, indicator lamps. One sheet
// (scripts/hub2_decal_atlas.gd), alpha cut out (no blending, so they sit in the same flat pixel
// style as the surface), lit like the surface under them. The sheet's glow layer lights the lamps.
// The quads float 3 cm off the face; the clip-space bias keeps them from z-fighting far away.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled, fog_disabled;

#include "res://shaders/hub2_ps1.gdshaderinc"

varying vec3 v_pos;
varying vec3 v_norm;

uniform sampler2D sheet : source_color, filter_nearest, repeat_disable;
uniform sampler2D glow_sheet : source_color, filter_nearest, repeat_disable;
uniform float glow_strength = 1.8;
uniform float depth_bias = 0.003;
// Decals thin out with a pixel dither between these view distances (metres) and are gone past the
// second, so none read through the fog on the far walls (the scene's depth fog runs 60 to 150 m).
uniform float fade_begin = 35.0;
uniform float fade_end = 90.0;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_norm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	bool ortho = PROJECTION_MATRIX[3][3] > 0.5;
	if (!ortho) {
		vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
		// Relative pull toward the camera (reverse-Z depth ~ 1/distance): ~0.3% of the distance, so a
		// decal wins over its own wall but never over a wall metres in front of it. The old constant
		// offset in depth grew to metres at range and let far decals show through nearer walls.
		clip.z *= 1.0 + depth_bias;
		POSITION = clip;
	}
}

float decal_vnoise(vec2 q, float salt) {
	vec2 i = floor(q);
	vec2 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	float a = ps1_hash(vec3(i.x, 0.0, i.y), salt);
	float b = ps1_hash(vec3(i.x + 1.0, 0.0, i.y), salt);
	float c = ps1_hash(vec3(i.x, 0.0, i.y + 1.0), salt);
	float e = ps1_hash(vec3(i.x + 1.0, 0.0, i.y + 1.0), salt);
	return mix(mix(a, b, f.x), mix(c, e, f.x), f.y);
}

void fragment() {
	vec4 s = texture(sheet, UV);
	if (s.a < 0.5) {
		discard;
	}
	float k = clamp((length(VERTEX) - fade_begin) / (fade_end - fade_begin), 0.0, 1.0);
	if (k > 0.0) {
		ivec2 px = ivec2(FRAGCOORD.xy);
		int i = (px.x % 4) + (px.y % 4) * 4;
		// 4x4 Bayer order, 0..15
		int bayer[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
		if (float(bayer[i]) / 16.0 < k) {
			discard;
		}
	}
	if (ps1_snow(v_pos, normalize(v_norm)) > 0.5) {
		discard;
	}
	vec3 col = s.rgb * COLOR.rgb;
	// Edge dusting (roof door rev 1): floor decals in the open-shaft zone (the hazard stripes on the
	// drop edges) get broken snow patches, so the stripe still reads through.
	if (v_norm.y > 0.6) {
		float ez = ps1_edge_snow_zone(v_pos);
		float ed = ez > 0.0 ? ps1_edge_dist(v_pos) : 99.0;
		if (ed < 1.4) {
			// Same strip rule as the floor under it (hub2_wear.gdshader), on the same 16/m texel grid.
			vec3 tx = floor(v_pos * 16.0);
			vec2 c = floor(v_pos.xz * 16.0) + 0.5;
			float width = (0.3 + 0.45 * decal_vnoise(c / 18.0, 21.0)) * (0.7 + 0.3 * ez);
			float strip = 1.0 - ed / width;
			float patch = decal_vnoise(c / 9.0, 22.0) * 0.5 + decal_vnoise(c / 3.0, 23.0) * 0.3 + ps1_hash(tx, 12.0) * 0.2;
			float amt = strip * 0.85 + (patch - 0.5) * 1.8 + (ez - 1.0) * 0.3;
			if (amt > 0.35) {
				col = snow_color * (amt > 0.65 ? 1.0 : 0.86);
			}
		}
	}
	float fog = ps1_fog(length(VERTEX));
	vec3 pools = ps1_pools(v_pos, normalize(v_norm));
	vec4 g = texture(glow_sheet, UV);
	ALBEDO = col * (1.0 - fog);
	EMISSION = (g.rgb * g.a * glow_strength + pools * (0.22 + col * 0.9)) * (1.0 - fog) + fog_tint * fog;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
