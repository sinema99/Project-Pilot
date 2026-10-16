// The dark snow curtain under the storm wall in the descent shot (scripts/cutscene/descent_land.gd,
// docs/specs/cutscene-descent.md row 35). A vertical strip far behind the city; UV.x = sketch x as
// a fraction of the frame, UV.y = 0 at the top, 1 at the ground. Falling-snow streaks in two hard
// alpha tones, thinning out toward the centre of the frame. Drawn after the Storm's fog quad, so
// it fogs itself. Bolts behind it light it from within (glows, from descent.gd).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/space/space_noise.gdshaderinc"
#include "res://shaders/storm/storm_fog.gdshaderinc"

uniform vec3 color : source_color = vec3(0.10, 0.13, 0.15);
uniform vec3 glow_color : source_color = vec3(0.5, 0.85, 1.0);
// Alpha of the thick and thin tones.
uniform float density : hint_range(0.0, 1.0) = 0.475;
uniform float thin_density : hint_range(0.0, 1.0) = 0.4;
// Sketch-x fractions: full strength left of thin_start, gone by thin_end.
uniform float thin_start = 0.22;
uniform float thin_end = 0.55;
// Streak width (fraction of the frame), slant, and fall speed (frame heights per second).
uniform float streak_size = 0.003;
uniform float slant = 0.03;
uniform float fall_speed = 0.02;
// How much of the storm fog it takes (the rest of the fog is behind it).
uniform float haze : hint_range(0.0, 1.0) = 0.4;
// Shot time (s), pushed by descent.gd.
uniform float cloud_time = 0.0;
// x = sketch-x fraction, w = brightness. Dark entries have w = 0.
uniform vec4 glows[4];

varying float v_dist;

void vertex() {
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec2 p = vec2(UV.x + UV.y * slant, UV.y);
	// Streaks: noise stretched tall, drifting down; a broad layer modulating them in patches.
	float streak = space_noise(vec3(p.x / streak_size, p.y * 3.0 - cloud_time * fall_speed * 3.0, 1.7));
	float patch = space_fbm(vec3(p.x * 9.0, p.y * 1.5 - cloud_time * fall_speed, 5.3), 3);
	// Thins toward the centre, raggedly.
	float edge = smoothstep(thin_start, thin_end, UV.x + (patch - 0.5) * 0.12);
	float body = 0.55 + (streak - 0.5) * 0.5 + (patch - 0.5) * 0.6 - edge;
	float a = body > 0.45 ? density : body > 0.2 ? thin_density : 0.0;
	if (a <= 0.0) {
		discard;
	}
	vec3 col = color;
	float g = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 f = glows[i];
		if (f.w <= 0.0) {
			continue;
		}
		float d = abs(UV.x - f.x) / 0.05 + UV.y * 0.6 - (patch - 0.5) * 0.4;
		float ring = d < 0.5 ? 0.8 : d < 1.0 ? 0.45 : d < 1.6 ? 0.2 : 0.0;
		g = max(g, ring * f.w);
	}
	col = mix(col, glow_color, clamp(g, 0.0, 1.0) * 0.6);
	vec4 fog = storm_fog_at(v_dist, TIME);
	ALBEDO = mix(col, fog.rgb, fog.a * haze);
	ALPHA = a;
}
