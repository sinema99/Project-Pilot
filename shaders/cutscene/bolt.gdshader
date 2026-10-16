// One background lightning bolt in the descent shot (scripts/cutscene/descent_bolts.gd): a flat
// strip facing the camera, UV.x across it. Cel: a white-hot core over two hard steps of cyan glow.
// Drawn after the Storm's fog quad, so it fogs itself, but only by `haze` of the fog: a bolt is
// light and cuts through the haze. Two-sided, since the strip's winding follows the bolt's turns.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/storm/storm_fog.gdshaderinc"

// 0..1 and over, pushed every frame by descent_bolts.gd.
uniform float brightness = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform vec3 glow_color : source_color = vec3(0.45, 0.85, 1.0);
uniform vec3 core_color : source_color = vec3(0.92, 0.98, 1.0);
// Over 1 so the core blooms.
uniform float core_energy = 2.0;
uniform float haze : hint_range(0.0, 1.0) = 0.4;

varying float v_dist;

void vertex() {
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float u = abs(UV.x * 2.0 - 1.0);
	float core = step(u, 0.3);
	float glow = u < 0.6 ? 0.75 : 0.35;
	vec3 col = mix(glow_color, core_color * core_energy, core);
	float a = max(core, glow) * brightness * opacity * COLOR.a;
	if (a <= 0.002) {
		discard;
	}
	vec4 fog = storm_fog_at(v_dist, TIME);
	ALBEDO = mix(col, fog.rgb, fog.a * haze);
	ALPHA = clamp(a, 0.0, 1.0);
}
