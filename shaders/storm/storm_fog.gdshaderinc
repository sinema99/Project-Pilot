// The Ichi storm's fog as a function of view distance, for anything that has to fog itself: the
// fog quad, and the ink passes the quad cannot reach (the hull outline drawn over sky pixels, the
// crease ink that draws after it). Driven by globals that Storm sets (project.godot
// [shader_globals]); storm_fog is 0 outside the storm, so every other scene is untouched.
// See docs/specs/ichi-snowstorm.md.

#include "res://shaders/storm/storm_gust.gdshaderinc"

global uniform float storm_fog;
global uniform float storm_visibility;
global uniform float storm_gust_visibility;
global uniform float storm_gust_period;
global uniform vec4 storm_near_color;
global uniform vec4 storm_far_color;
// Ink keeps at least this much of its darkness however deep in the fog, so far silhouettes
// linger as faint ghosts instead of vanishing.
global uniform float storm_ink_floor;

// rgb = the fog's colour at `dist` metres, a = how much of the scene it hides (0..1).
vec4 storm_fog_at(float dist, float time) {
	float vis = storm_gust_wall(time, storm_gust_period, storm_visibility, storm_gust_visibility);
	float t = clamp(dist / vis, 0.0, 1.0);
	// 98% gone at the visibility distance, squared so the near field stays clear.
	float fog = 1.0 - exp(-3.9 * t * t);
	return vec4(mix(storm_near_color.rgb, storm_far_color.rgb, smoothstep(0.05, 1.0, t)), fog * storm_fog);
}

// Ink colour `ink` seen through the storm at `dist` metres.
vec3 storm_fog_ink(vec3 ink, float dist, float time) {
	vec4 f = storm_fog_at(dist, time);
	return mix(ink, f.rgb, min(f.a, 1.0 - storm_ink_floor));
}
