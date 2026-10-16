// Engine trails for the intro cutscene ship (docs/specs/cutscene-intro-space.md, "Effects pass"):
// camera-facing ribbons intro_space_trail.gd rebuilds every frame from the ship's past positions.
// Cel ribbon, three hard tones across it (white-hot core, cyan, dark blue edge); only the core is
// bright enough to glow. With age it spreads and pales, the core goes first, and the old end breaks
// up in hard chunks instead of fading. Re-entry heat turns new segments from cyan to orange.
//
// Per vertex: UV.x = age 0..1 (of the trail's life), UV.y = across -1..1, UV2.x = emission time
// (seconds, so the chunks stay put on the trail), COLOR.r = heat 0..1 when it was emitted,
// COLOR.a = the nozzle's opacity multiplier (1 unless the trail's nozzle_opacities sets it).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/space/space_noise.gdshaderinc"

group_uniforms Engine;
uniform vec3 core_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 mid_color : source_color = vec3(0.3, 0.85, 1.0);
uniform vec3 edge_color : source_color = vec3(0.1, 0.28, 0.75);
// What the old trail pales to.
uniform vec3 old_color : source_color = vec3(0.62, 0.86, 0.96);
group_uniforms;

group_uniforms Heat;
uniform vec3 hot_core_color : source_color = vec3(1.0, 0.95, 0.75);
uniform vec3 hot_mid_color : source_color = vec3(1.0, 0.52, 0.12);
uniform vec3 hot_edge_color : source_color = vec3(0.6, 0.14, 0.05);
uniform vec3 hot_old_color : source_color = vec3(0.95, 0.7, 0.5);
group_uniforms;

group_uniforms Look;
// HDR multiplier on the core: above 1 so the glow catches it.
uniform float core_energy = 1.5;
// Core width (fraction of the ribbon) at the nozzle, and the age (fraction of life) it is gone by.
uniform float core_width : hint_range(0.0, 1.0) = 0.3;
uniform float core_life : hint_range(0.0, 1.0) = 0.075;
// Mid tone width (fraction of the ribbon).
uniform float mid_width : hint_range(0.0, 1.0) = 0.68;
// Opacity at the nozzle, and how many hard steps it drops in over the life.
uniform float opacity : hint_range(0.0, 1.0) = 0.95;
uniform float opacity_steps = 4.0;
// Age (fraction of life) the trail starts breaking up into chunks.
uniform float breakup_start : hint_range(0.0, 1.0) = 0.55;
// Chunk size: noise cells per second of emission time, and across the ribbon.
uniform float breakup_freq = 7.0;
uniform float breakup_across = 1.2;
// Near the camera the ribbon fades: gone closer than near_fade_gone metres, whole past
// near_fade_full, so it never slices the lens on a chase camera (shot 4). 0 switches it off.
uniform float near_fade_gone = 0.0;
uniform float near_fade_full = 0.0;
group_uniforms;

void fragment() {
	float age = clamp(UV.x, 0.0, 1.0);
	float across = abs(UV.y);
	float heat = clamp(COLOR.r, 0.0, 1.0);
	float aa = max(fwidth(across), 1e-4);

	// Hard chunks at the old end: noise on emission time, so a chunk stays where it was left.
	float n = space_noise(vec3(UV2.x * breakup_freq, UV.y * breakup_across, 1.7));
	float gone = smoothstep(breakup_start, 1.0, age);
	if (n < gone * 1.05 || age >= 1.0) {
		discard;
	}

	vec3 core_c = mix(core_color, hot_core_color, heat);
	vec3 mid_c = mix(mid_color, hot_mid_color, heat);
	vec3 edge_c = mix(edge_color, hot_edge_color, heat);
	vec3 old_c = mix(old_color, hot_old_color, heat);
	// Spreads and pales: the tones step toward the old colour as it ages.
	float pale = floor(clamp(age * 1.6, 0.0, 1.0) * 3.0) / 3.0;
	mid_c = mix(mid_c, old_c, pale);
	edge_c = mix(edge_c, old_c, pale * 0.7);

	float cw = core_width * (1.0 - smoothstep(core_life * 0.5, core_life, age));
	float in_core = 1.0 - smoothstep(cw - aa, cw + aa, across);
	float in_mid = 1.0 - smoothstep(mid_width - aa, mid_width + aa, across);
	vec3 col = mix(edge_c, mid_c, in_mid);
	col = mix(col, core_c * core_energy, in_core * step(1e-3, cw));
	ALBEDO = col;

	float o = ceil((1.0 - age) * opacity_steps) / opacity_steps;
	float edge_aa = 1.0 - smoothstep(1.0 - aa * 2.0, 1.0, across);
	float near = near_fade_full > 0.0 ? smoothstep(near_fade_gone, near_fade_full, length(VERTEX)) : 1.0;
	ALPHA = opacity * o * edge_aa * near * COLOR.a;
}
