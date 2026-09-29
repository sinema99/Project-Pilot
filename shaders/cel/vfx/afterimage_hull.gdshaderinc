// Shared by afterimage_outline.gdshader and afterimage_outline_depth.gdshader: outline.gdshader's
// inverted-hull push, so the ink's depth pass lands on exactly the depth its colour pass tests.
global uniform float outline_width;

void vertex() {
	vec4 clip_position =
			PROJECTION_MATRIX *
			(MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 clip_normal =
			mat3(PROJECTION_MATRIX) *
			(mat3(MODELVIEW_MATRIX) * NORMAL);
	clip_position.xy +=
			normalize(clip_normal.xy) /
			VIEWPORT_SIZE *
			clip_position.w *
			outline_width;
	POSITION = clip_position;
}
