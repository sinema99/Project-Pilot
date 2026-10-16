shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix, shadows_disabled, fog_disabled;

// Melts OP_1's ragged edge into the painted ground the sky draws past it. A full-screen quad that
// reads depth: every terrain pixel within `edge_band` metres of the map's edge is blended toward
// the same ground colour and mottle as the sky (flyover_ground.gdshaderinc), fully so inside
// `edge_solid` metres (deeper than the ragged edge's deepest notch). Sky pixels below the horizon
// are repainted with exactly what the sky shows there, which wipes the terrain's outline hull off
// them (it writes no depth, so it sits on "sky"). Drawn after the storm's fog quad and the map's
// crease ink (FlyoverShot keeps it sorted between them and the snow), so it covers the ink and
// fogs itself.
//
// Anything that is not ground (the ship, the building) keeps its outline: a pixel with such a
// thing within `guard_px` pixels is left alone, since outlines over it carry its neighbour's depth.
// See docs/specs/cutscene-flyover.md.

#include "res://shaders/storm/storm_fog.gdshaderinc"
#include "res://shaders/cutscene/flyover_ground.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

// The map's outer rectangle in world x/z: (x0, z0, x1, z1). Its north side is not used: the canyon
// drops away first, and from above its lip is the edge you see. `lip_tex` holds the lip's world z
// across x0..x1.
uniform vec4 map_rect;
uniform sampler2D lip_tex : filter_linear, repeat_disable;
// The building's height span per cell over the rectangle (r = lowest, g = highest): a pixel inside
// it, or above `ship_height`, is not ground. (Testing "above the terrain" instead fails at the lip:
// depth read back off the canyon wall at a grazing angle lands tens of metres off.)
uniform sampler2D building_tex : filter_nearest, repeat_disable;
uniform float ship_height = 200.0;
// The sky's painted plane height (FlyoverShot.ground_y).
uniform float ground_y = 0.0;
uniform float edge_solid = 25.0;
uniform float edge_band = 80.0;
uniform float guard_px = 6.0;

uniform vec3 ground_color : source_color = vec3(0.6, 0.62, 0.68);
uniform float mottle = 0.04;
uniform float mottle_size = 120.0;

void vertex() {
	// Reversed-Z: z = 1 is the near plane, so the quad covers everything and is never clipped.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// World position under screen `uv`, or w = 0 for sky.
vec4 world_at(vec2 uv, mat4 inv_proj, mat4 inv_view) {
	float depth = texture(depth_tex, uv).x;
	if (depth < 0.0000001) {
		return vec4(0.0);
	}
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return vec4((inv_view * vec4(view.xyz / view.w, 1.0)).xyz, 1.0);
}

vec2 map_uv(vec2 xz) {
	return (xz - map_rect.xy) / (map_rect.zw - map_rect.xy);
}

// Something standing above the ground (not sky, not terrain).
bool is_solid(vec4 p) {
	vec2 span = texture(building_tex, map_uv(p.xz)).rg;
	return p.w != 0.0 && (p.y > ship_height || (p.y >= span.x && p.y <= span.y));
}

void fragment() {
	vec4 p = world_at(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	if (is_solid(p)) {
		discard;
	}
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 g;
	float mask = 1.0;
	if (p.w == 0.0) {
		// Sky: the plane point the sky shader paints here.
		vec4 far = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 0.5, 1.0);
		vec3 dir = (INV_VIEW_MATRIX * vec4(far.xyz / far.w, 0.0)).xyz;
		if (dir.y >= 0.0 || cam.y <= ground_y) {
			discard;
		}
		g = cam + dir * (ground_y - cam.y) / dir.y;
	} else {
		vec2 uv = map_uv(p.xz);
		float lip = texture(lip_tex, vec2(uv.x, 0.5)).r;
		float d = min(min(p.x - map_rect.x, map_rect.z - p.x), min(p.z - map_rect.y, lip - p.z));
		mask = 1.0 - smoothstep(edge_solid, edge_band, d);
		if (mask <= 0.0) {
			discard;
		}
		// Below the painted plane (the canyon walls): show the plane point the sky would, at the
		// plane's distance, so they fog the same and leave no paler ghost of the drop.
		g = p.xyz;
		if (g.y < ground_y) {
			g = cam + (g - cam) * (ground_y - cam.y) / (g.y - cam.y);
		}
	}
	vec2 px = guard_px / VIEWPORT_SIZE;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * TAU / 8.0;
		if (is_solid(world_at(SCREEN_UV + vec2(cos(a), sin(a)) * px, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX))) {
			discard;
		}
	}
	vec4 fog = storm_fog_at(distance(g, cam), TIME);
	ALBEDO = mix(flyover_ground(g.xz, ground_color, mottle, mottle_size), fog.rgb, fog.a);
	ALPHA = mask;
}
