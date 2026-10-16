// Engine glow in a nozzle (docs/specs/cutscene-flyover.md): a flat disc across the nozzle mouth,
// three hard cel rings in the trails' colours (white-hot core, cyan, dark blue edge). Only the
// core is HDR, so the environment glow catches it the way it catches the trail's core.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 mid_color : source_color = vec3(0.3, 0.85, 1.0);
uniform vec3 edge_color : source_color = vec3(0.1, 0.28, 0.75);
uniform float core_energy = 1.6;
// Ring radii as fractions of the disc's radius.
uniform float core_radius : hint_range(0.0, 1.0) = 0.3;
uniform float mid_radius : hint_range(0.0, 1.0) = 0.72;
uniform float opacity : hint_range(0.0, 1.0) = 0.95;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float aa = max(fwidth(r), 1e-4);
	float in_disc = 1.0 - smoothstep(1.0 - aa, 1.0, r);
	if (in_disc <= 0.0) {
		discard;
	}
	float in_mid = 1.0 - smoothstep(mid_radius - aa, mid_radius + aa, r);
	float in_core = 1.0 - smoothstep(core_radius - aa, core_radius + aa, r);
	vec3 col = mix(edge_color, mid_color, in_mid);
	col = mix(col, core_color * core_energy, in_core);
	ALBEDO = col;
	ALPHA = opacity * in_disc;
}
