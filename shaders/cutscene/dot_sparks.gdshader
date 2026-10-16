// Dot sparks around the flyover's engines (docs/specs/cutscene-flyover.md, "Nozzle propulsion"):
// camera-facing quads built each frame by scripts/cutscene/flyover_dot_sparks.gd, cut to hard
// round discs (cel: no soft falloff, just an anti-aliased edge). White-hot ones are HDR so the
// environment glow catches them; cyan ones stay just under it.
//
// Mesh contract: UV 0..1 across the quad, COLOR.r = 1 for a white-hot dot, 0 for cyan.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 hot_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cool_color : source_color = vec3(0.2, 0.85, 1.0);
uniform float hot_energy = 3.0;
uniform float cool_energy = 1.0;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float aa = max(fwidth(r), 1e-4);
	float in_disc = 1.0 - smoothstep(1.0 - aa, 1.0, r);
	if (in_disc <= 0.0) {
		discard;
	}
	ALBEDO = COLOR.r > 0.5 ? hot_color * hot_energy : cool_color * cool_energy;
	ALPHA = in_disc;
}
