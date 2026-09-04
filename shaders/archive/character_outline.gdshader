shader_type spatial;

// Inverted-hull outline, meant to be hung on a MeshInstance3D as material_overlay
// (or a next_pass). The base material renders normally; this pass re-draws the
// mesh grown along its normals with front faces culled, so only the sliver of
// shell that pokes past the real silhouette is visible -- a solid line around
// the object.
//
// test3 uses this instead of the Moebius compositor: that pass is full-screen
// and would ink the desert terrain too. This is per-mesh, so only what it is
// applied to gets a line.
render_mode unshaded, cull_front, shadows_disabled, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Line weight in pixels, authored against `reference_height`. Held roughly
// constant on screen with distance, so it does not swell up close or thin out
// far away.
uniform float outline_size : hint_range(0.0, 16.0) = 3.0;
uniform float reference_height = 1080.0;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 clip = PROJECTION_MATRIX * view;

	// pixels -> vertical NDC units -> view-space units at this depth.
	float ndc_per_px = 2.0 / reference_height;
	float view_per_ndc = clip.w / PROJECTION_MATRIX[1][1];
	view.xyz += view_normal * outline_size * ndc_per_px * view_per_ndc;

	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
