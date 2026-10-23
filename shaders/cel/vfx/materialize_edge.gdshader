shader_type spatial;

// The staff materialize's leading edge - see docs/specs/pilot9-staff-materialize.md.
//
// A thin band riding each growing end of the staff while it forms in his hand (and collapsing
// back into it on a holster). Flat, additive and above 1.0, so it blooms like the rim light.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 edge_color : source_color = vec3(0.35, 0.95, 1.0);
uniform float energy = 2.5;
// 0..1, set by equip_anim.gd every frame: the bands fade out as the staff finishes forming.
uniform float fade = 1.0;

void fragment() {
	ALBEDO = edge_color * energy * fade;
}
