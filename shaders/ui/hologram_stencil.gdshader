shader_type spatial;
render_mode unshaded, depth_draw_never, blend_mix;
// Marks pilot's visible pixels so hologram_dim leaves them alone. Chained onto his meshes only
// while the hologram menu is up. Alpha is a hair above zero so it is not culled as invisible.
stencil_mode write, compare_always, 1;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.004;
}
