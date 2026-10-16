shader_type sky;

// The flyover's sky. Above the horizon a dark storm gradient (never in frame; it lights the
// radiance cubemap). Below it, the eye ray is run down to a flat plane at `ground_y` and that spot
// is painted as snow (flyover_ground.gdshaderinc), with the dead city's buried streets, seen
// through the storm's fog. The fog quad leaves sky pixels alone, so the fog is applied here, and
// the lightning floods it here too (`flash`). Being the sky, the ship's hull outline (which writes
// no depth) still draws over it. See docs/specs/cutscene-flyover.md.

#include "res://shaders/storm/storm_fog.gdshaderinc"
#include "res://shaders/cutscene/flyover_ground.gdshaderinc"

uniform vec3 sky_top_color : source_color = vec3(0.2, 0.21, 0.27);
uniform vec3 sky_horizon_color : source_color = vec3(0.36, 0.37, 0.45);
uniform float sky_curve = 0.5;

uniform float ground_y = 0.0;
uniform vec3 ground_color : source_color = vec3(0.6, 0.62, 0.68);
uniform float mottle = 0.04;
uniform float mottle_size = 120.0;

// Buried streets: see flyover_streets(). `street_dark` is how much darker a trough is.
uniform vec2 street_origin = vec2(0.0, 210.0);
uniform float street_angle = 0.0;
uniform vec2 street_block = vec2(110.0, 130.0);
uniform float street_width = 16.0;
uniform float street_radius = 700.0;
uniform float street_dark = 0.12;

// Lightning, 0..1 (FlyoverShot.flash_at): lifts the ground toward `flash_color`.
uniform float flash = 0.0;
uniform vec3 flash_color : source_color = vec3(0.55, 0.9, 1.0);
uniform float flash_lift = 0.45;

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
		vec3 ground = flyover_ground(p.xz, ground_color, mottle, mottle_size);
		ground *= 1.0 - street_dark * flyover_streets(p.xz, street_origin, street_angle, street_block, street_width, street_radius);
		ground = mix(ground, flash_color, flash * flash_lift);
		vec4 fog = storm_fog_at(dist, TIME);
		COLOR = mix(ground, fog.rgb, fog.a);
	}
}
