// The storm's cloud deck in the descent shot, seen from below (docs/specs/cutscene-descent.md).
// A flat mesh at the deck's base (scripts/cutscene/descent_land.gd); billows hang down from it in
// the vertex shader. Cel: three hard tones from the billows, lowest = lightest (it catches the
// light off the snow). Lightning: up to 8 flashes from descent.gd, each lighting a disc of the
// deck cyan in hard steps, at flash_opacity. Opaque, so the Storm's fog quad fogs it like the land.
// Storm wall (left of frame): the mesh's COLOR says how much wall a vertex is (r), whether it is
// on a riser (g) and how near a band's lip (b); there the tones turn teal-grey.
// Motion: the billow pattern turns slowly around the eye and churns in place, both on the shot
// clock (cloud_time, from descent.gd), so seeking shows the same frame.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

#include "res://shaders/space/space_noise.gdshaderinc"

group_uniforms Billows;
// How far (m) the billows hang below the base, and their size (m).
uniform float billow_depth = 35.0;
uniform float billow_size = 170.0;
group_uniforms;

group_uniforms Motion;
// Shot time (s), pushed every frame by descent.gd.
uniform float cloud_time = 0.0;
// The eye (world XZ) the pattern turns around, and how fast (rad/s).
uniform vec2 eye_center = vec2(0.0);
uniform float spin_rate = 0.0;
// How fast the billows reshape in place (noise units/s; 0.1 is a full reshape every ~10 s).
uniform float churn_rate = 0.0;
group_uniforms;

group_uniforms Tones;
uniform vec3 dark_color : source_color = vec3(0.13, 0.14, 0.18);
uniform vec3 mid_color : source_color = vec3(0.20, 0.21, 0.26);
uniform vec3 light_color : source_color = vec3(0.29, 0.30, 0.36);
// Billow amount (0..1) where the mid and light tones start.
uniform float mid_step : hint_range(0.0, 1.0) = 0.42;
uniform float light_step : hint_range(0.0, 1.0) = 0.64;
group_uniforms;

group_uniforms Edge;
// The front edge melts into the sky: toward it the tones fade to edge_color (the sky's horizon)
// over edge_fade of the deck's depth (UV.y: 0 at the edge, 1 nearest the camera), ragged by the
// billows so the fade follows the cloud's shape instead of a straight band.
uniform vec3 edge_color : source_color = vec3(0.725, 0.71, 0.805);
uniform float edge_fade : hint_range(0.0, 1.0) = 0.55;
uniform float edge_ragged : hint_range(0.0, 1.0) = 0.35;
// The same mist over the whole deck: wisps of edge_color, up to mist_amount, in patches mist_size
// (m) across that churn with the billows. Thin cloud (low b) takes more.
uniform float mist_amount : hint_range(0.0, 1.0) = 0.6;
uniform float mist_size = 260.0;
group_uniforms;

group_uniforms Lightning;
// xy = world x / z, z = radius (m), w = brightness. Dark entries have w = 0.
uniform vec4 flashes[8];
uniform vec3 flash_color : source_color = vec3(0.55, 0.9, 1.0);
uniform vec3 flash_core_color : source_color = vec3(0.92, 0.98, 1.0);
uniform float flash_energy = 1.4;
// How strongly the rings show over the cloud (1 = the old full strength).
uniform float flash_opacity : hint_range(0.0, 1.0) = 0.5;
group_uniforms;

group_uniforms Wall;
// The storm wall's teal-grey tones: undersides, risers, and the pale lip of each band.
uniform vec3 wall_dark : source_color = vec3(0.12, 0.16, 0.17);
uniform vec3 wall_mid : source_color = vec3(0.21, 0.29, 0.30);
uniform vec3 wall_light : source_color = vec3(0.36, 0.48, 0.48);
uniform vec3 wall_lip : source_color = vec3(0.56, 0.68, 0.67);
// The edge mist on the wall is this much of the flat deck's, so the wall reads as a solid face.
uniform float wall_edge_fade : hint_range(0.0, 1.0) = 0.35;
group_uniforms;

varying vec3 v_world;
varying vec2 v_cloud;
varying float v_billow;

// Where world `xz` sits in the turning pattern.
vec2 cloud_xz(vec2 xz) {
	float a = -spin_rate * cloud_time;
	vec2 d = xz - eye_center;
	return eye_center + vec2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a));
}

float billow(vec2 xz) {
	vec3 p = vec3(xz / billow_size, 0.3 + churn_rate * cloud_time);
	float n = space_fbm(p, 4);
	// Rounded lumps: push the noise up into puffs with sharp creases between.
	return smoothstep(0.3, 0.75, n);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_cloud = cloud_xz(world.xz);
	float b = billow(v_cloud);
	VERTEX.y -= b * billow_depth;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_billow = b;
}

void fragment() {
	// Detail inside each billow so the tone edges are not just the mesh's contour.
	float detail = space_noise(vec3(v_cloud / (billow_size * 0.35), 4.1 + churn_rate * 1.3 * cloud_time)) - 0.5;
	float b = v_billow + detail * 0.25;
	vec3 col = dark_color;
	col = mix(col, mid_color, step(mid_step, b));
	col = mix(col, light_color, step(light_step, b));
	// The storm wall: darker undersides, lighter risers, a pale lip at the foot of each riser.
	float wall = COLOR.r;
	// The bands follow the smooth billows, not the fine detail, so their edges sweep instead of saw.
	float bw = v_billow;
	vec3 wcol = wall_dark;
	wcol = mix(wcol, wall_mid, step(mid_step, b));
	wcol = mix(wcol, wall_light, step(light_step - 0.3 * COLOR.g, bw) * COLOR.g);
	wcol = mix(wcol, wall_lip, step(0.55, COLOR.b + (bw - 0.5) * 0.3));
	col = mix(col, wcol, wall);
	// Thicker lumps (high b) keep their tone further out; thin wisps fade first.
	float edge = UV.y / max(edge_fade, 1e-4) + (b - 0.5) * edge_ragged;
	float fade = (1.0 - smoothstep(0.0, 1.0, edge)) * mix(1.0, wall_edge_fade, wall);
	float wisp = smoothstep(0.25, 0.75, space_fbm(vec3(v_cloud / mist_size, 7.3 + churn_rate * cloud_time), 3));
	float mist = mist_amount * mix(0.15, 1.0, wisp) * (1.15 - 0.5 * clamp(b, 0.0, 1.0));
	mist *= mix(1.0, 0.45, wall);
	col = mix(col, edge_color, clamp(max(fade, mist), 0.0, 1.0));

	float lit = 0.0;
	float core = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 f = flashes[i];
		if (f.w <= 0.0) {
			continue;
		}
		float d = distance(v_world.xz, f.xy) / max(f.z, 1.0);
		// Hard rings, ragged by the billows so the light follows the cloud's shape.
		d -= (b - 0.5) * 0.35;
		float ring = d < 0.4 ? 1.0 : d < 0.75 ? 0.6 : d < 1.2 ? 0.3 : 0.0;
		lit = max(lit, ring * f.w);
		core = max(core, (d < 0.22 ? 1.0 : 0.0) * f.w);
	}
	col = mix(col, flash_color * flash_energy, clamp(lit, 0.0, 1.0) * flash_opacity);
	col = mix(col, flash_core_color * flash_energy * 1.4, clamp(core, 0.0, 1.0) * flash_opacity);
	ALBEDO = col;
}
