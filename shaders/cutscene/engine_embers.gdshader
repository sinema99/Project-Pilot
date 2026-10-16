// Engine embers (docs/specs/cutscene-flyover.md, "Speed lines + engine heat"): streak quads built
// each frame by scripts/cutscene/flyover_embers.gd. Each leaves the nozzle white-hot, drops to the
// engine cyan (one hard cel step), then fades. HDR so the environment glow catches them.
//
// Mesh contract: UV.x across the streak (0..1), UV.y along it (1 = head), COLOR.r = age as a
// fraction of the ember's life, COLOR.a = its brightness.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 hot_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cool_color : source_color = vec3(0.55, 0.88, 1.0);
uniform float hot_energy = 3.0;
uniform float cool_energy = 1.6;
// Fraction of its life an ember stays white-hot.
uniform float hot_until : hint_range(0.0, 1.0) = 0.3;
// Fraction of its life it starts fading at.
uniform float fade_from : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	float u = COLOR.r;
	float across = abs(UV.x * 2.0 - 1.0);
	float shape = pow(1.0 - across, 1.5) * (0.15 + 0.85 * UV.y) * (1.0 - smoothstep(0.85, 1.0, UV.y));
	vec3 col = u < hot_until ? hot_color * hot_energy : cool_color * cool_energy;
	ALBEDO = col;
	ALPHA = clamp(shape * COLOR.a * (1.0 - smoothstep(fade_from, 1.0, u)), 0.0, 1.0);
}
