shader_type sky;

// The flyover's sky. Above the horizon it is the old overcast gradient (ProceduralSkyMaterial's
// curve). Below it, the eye ray is run down to a flat plane at `ground_y` and that spot is painted
// as snow (flyover_ground.gdshaderinc) seen through the storm's fog, so the ground seems to go on
// past OP_1's edge. The fog quad leaves sky pixels alone, so the fog is applied here. Being the
// sky, the ship's hull outline (which writes no depth) still draws over it.
// See docs/specs/cutscene-flyover.md.

#include "res://shaders/storm/storm_fog.gdshaderinc"
#include "res://shaders/cutscene/flyover_ground.gdshaderinc"

uniform vec3 sky_top_color : source_color = vec3(0.55, 0.6, 0.7);
uniform vec3 sky_horizon_color : source_color = vec3(0.8, 0.77, 0.86);
uniform float sky_curve = 0.5;

uniform float ground_y = 0.0;
uniform vec3 ground_color : source_color = vec3(0.6, 0.62, 0.68);
uniform float mottle = 0.04;
uniform float mottle_size = 120.0;

void sky() {
	if (EYEDIR.y >= 0.0) {
		float c = 1.0 - acos(clamp(EYEDIR.y, -1.0, 1.0)) / (PI * 0.5);
		COLOR = mix(sky_horizon_color, sky_top_color, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	} else if (AT_CUBEMAP_PASS || POSITION.y <= ground_y) {
		// The radiance cubemap only lights things; it doesn't need the ground's detail.
		COLOR = sky_horizon_color;
	} else {
		float dist = (ground_y - POSITION.y) / EYEDIR.y;
		vec3 p = POSITION + EYEDIR * dist;
		vec4 fog = storm_fog_at(dist, TIME);
		COLOR = mix(flyover_ground(p.xz, ground_color, mottle, mottle_size), fog.rgb, fog.a);
	}
}
