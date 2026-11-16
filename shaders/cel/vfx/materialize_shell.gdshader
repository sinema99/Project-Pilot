shader_type spatial;

// The uniform materialize's glow - see docs/specs/pilot9-revolver.md.
//
// A copy of each of the item's meshes, pushed a hair out along its normals, drawn over it while it
// grows out of his grip: it forms glowing cyan and cools to its own colour as the glow fades.
// Brightest at the silhouette, so the edges read. Flat, additive and above 1.0 like the staff's
// bands (materialize_edge.gdshader).
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 edge_color : source_color = vec3(0.35, 0.95, 1.0);
uniform float energy = 2.5;
// 0..1, set by equip_anim.gd every frame.
uniform float fade = 1.0;
// Metres out along the normal, whatever the item's scale.
uniform float inflate = 0.002;
// The face-on share of the glow; the silhouette is always full.
uniform float core = 0.35;

void vertex() {
	float scale = max(length(MODEL_MATRIX[0].xyz), 0.00001);
	VERTEX += NORMAL * inflate / scale;
}

void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = edge_color * energy * fade * mix(core, 1.0, rim * rim);
}
