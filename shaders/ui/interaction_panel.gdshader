// The interaction panel: a PS1 prompt floating beside whoever the camera follows.
// See docs/specs/interaction-panel.md.
//
// The quad is 1 x 1 and centred; InteractionPrompt scales it to the face's texel aspect and to a
// constant on-screen size, and squashes its height for the unfold.
//
// - face: the keycap and the word, drawn into a tiny SubViewport (face_texels across), sampled
//   nearest and cut at alpha 0.5, so the font has no antialiasing - chunky texels only.
// - plate: everything else inside the edge, a dark ORDERED-DITHER checker instead of alpha - how
//   the PS1 faked transparency. One texel cyan ring around it.
// - vertex snap: clip-space xy rounded to a snap_lines-high grid, the world's own ps1_surface
//   numbers, so the corners jitter with the level.
// - affine: the UVs interpolated in screen space (the p*w / w trick), so the yawed quad kinks
//   along its diagonal.
// - 15-bit colour: every channel cut to 32 levels through a 4x4 Bayer matrix on the texel grid.
// - unlit, no fog, no depth test: nothing in the world covers it.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix;

uniform sampler2D face : source_color, filter_nearest, repeat_disable;
uniform vec2 face_texels = vec2(64.0, 16.0);

uniform vec4 plate_color : source_color = vec4(0.02, 0.055, 0.065, 1.0);
uniform vec4 edge_color : source_color = vec4(0.251, 0.949, 0.902, 1.0);
// 0 = no plate (default since 2026-11-12: the checker made the word hard to read), 0.5 =
// checker, 1 = solid. Steps of 1/16 through the Bayer matrix.
uniform float plate_coverage = 0.0;

uniform bool snap_enabled = true;
uniform float snap_lines = 720.0;
uniform bool affine_enabled = true;
uniform bool colour_15bit = true;

varying vec3 v_affine;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (snap_enabled && clip.w > 0.0) {
		float aspect = PROJECTION_MATRIX[1][1] / PROJECTION_MATRIX[0][0];
		vec2 grid = vec2(snap_lines * aspect, snap_lines) * 0.5;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;
	v_affine = vec3(UV * clip.w, clip.w);
}

void fragment() {
	vec2 uv = affine_enabled ? v_affine.xy / v_affine.z : UV;
	uv = clamp(uv, vec2(0.0), vec2(0.99999));
	ivec2 texel = ivec2(floor(uv * face_texels));
	ivec2 last = ivec2(face_texels) - 1;
	float threshold = (BAYER[(texel.y & 3) * 4 + (texel.x & 3)] + 0.5) / 16.0;

	vec4 f = texture(face, (vec2(texel) + 0.5) / face_texels);
	vec3 col;
	if (f.a >= 0.5) {
		col = f.rgb;
	} else if (texel.x == 0 || texel.y == 0 || texel.x == last.x || texel.y == last.y) {
		col = edge_color.rgb;
	} else {
		if (threshold >= plate_coverage) {
			discard;
		}
		col = plate_color.rgb;
	}
	if (colour_15bit) {
		col = floor(col * 31.0 + threshold) / 31.0;
	}
	ALBEDO = col;
	ALPHA = 1.0;
}
