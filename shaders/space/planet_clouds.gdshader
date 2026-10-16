// Cloud shell for the intro cutscene planet (docs/specs/cutscene-intro-space.md, "Planet
// upgrade"): a sphere just above the surface, child of the planet so it turns with it. Flat cel
// clouds from the shared cloud_field (planet_earth.gdshaderinc), hard edges, one shadow step on
// the side away from the relief light, painted patches, stepped sun light like the surface.
// Storm (docs/specs/cutscene-intro-space.md, "Storm eye rebuild"): the layers cloud_layers() reports
// get their own tones, higher layers cast hard shadows on lower ones, and the eye is a shaded pit.
// Lightning: flashes light the storm's own cloud shapes from inside, big ones throw crawler veins,
// from the flash list intro_space.gd writes every frame.
shader_type spatial;
render_mode cull_back, shadows_disabled, specular_disabled, depth_draw_never, blend_mix;

#include "res://shaders/space/space_noise.gdshaderinc"
#include "res://shaders/space/planet_earth.gdshaderinc"
#include "res://shaders/cel/includes/painted.gdshaderinc"
#include "res://shaders/cel/includes/scatter.gdshaderinc"

group_uniforms CloudLook;
uniform vec3 cloud_color : source_color = vec3(0.95, 0.97, 1.0);
uniform vec3 cloud_shade_color : source_color = vec3(0.68, 0.76, 0.86);
// Width (unit sphere) of the shadow band along the edges away from the light.
uniform float cloud_shade_width : hint_range(0.0, 0.03) = 0.005;
// Whole-shell opacity: 1 = solid cel clouds, lower lets the ground show through.
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.75;
// Same direction as the surface shader's relief_light_dir. World space.
uniform vec3 relief_light_dir = vec3(-0.75, 0.6, 0.3);
uniform float paint_planet_scale = 30.0;
uniform float paint_planet_amount : hint_range(0.0, 1.0) = 0.6;
uniform float scatter_planet_scale = 1.4;
group_uniforms;

group_uniforms Storm;
// The low deck under the bands, and its shadowed side.
uniform vec3 storm_deck_color : source_color = vec3(0.47, 0.54, 0.66);
uniform vec3 storm_deck_shadow_color : source_color = vec3(0.29, 0.34, 0.46);
// Shaded side of the bands and eyewall (darker than the ordinary cloud shade).
uniform vec3 storm_shade_color : source_color = vec3(0.56, 0.63, 0.76);
// Eye: the inner wall face lit / in shadow, the floor, and the floor under the eyewall's shadow.
uniform vec3 eye_wall_lit_color : source_color = vec3(0.6, 0.67, 0.79);
uniform vec3 eye_wall_dark_color : source_color = vec3(0.24, 0.28, 0.39);
uniform vec3 eye_floor_color : source_color = vec3(0.26, 0.31, 0.43);
uniform vec3 eye_floor_shadow_color : source_color = vec3(0.06, 0.07, 0.12);
// Inner wall face width (fraction of the eye radius) and the eyewall shadow's reach across the
// floor (fraction of storm_radius_deg).
uniform float eye_wall_step : hint_range(0.0, 0.8) = 0.3;
uniform float eye_shadow_reach : hint_range(0.0, 0.5) = 0.11;
// How far (unit sphere) a higher layer throws its shadow onto a lower one.
uniform float storm_cast_offset : hint_range(0.0, 0.03) = 0.006;
// Opacity inside the storm: denser than the ordinary clouds; the pit is fully solid.
uniform float storm_opacity : hint_range(0.0, 1.0) = 0.95;
group_uniforms;

group_uniforms Lightning;
// Up to 8 live flashes: x, y = storm-local degrees (earth_storm_local), z = radius in degrees,
// w = brightness (0 = dark, 1 = a full flash, more for the final sting).
uniform vec4 flashes[8];
uniform vec3 flash_color : source_color = vec3(0.55, 0.86, 1.0);
uniform vec3 flash_core_color : source_color = vec3(0.95, 0.99, 1.0);
// HDR multiplier: above 1 so the glow picks the flashes up.
uniform float flash_energy = 2.0;
// Below this brightness a flash shows nothing; above flash_core_level it gets the white centre.
uniform float flash_level : hint_range(0.0, 1.0) = 0.12;
uniform float flash_core_level : hint_range(0.0, 1.0) = 0.45;
// How much the flash edge wobbles.
uniform float flash_edge_noise : hint_range(0.0, 1.0) = 0.5;
// How much light the deck catches (the bands and eyewall catch all of it): the deck only lights
// near the strike, so the lit shape follows the bands' own torn edges.
uniform float flash_deck_catch : hint_range(0.0, 1.0) = 0.35;
// Crawlers: thin branching veins on flashes brighter than crawler_level, reaching crawler_reach
// flash radii out, crawler_width wide (noise units).
uniform float crawler_level : hint_range(0.0, 2.0) = 0.6;
uniform float crawler_reach = 2.4;
uniform float crawler_width : hint_range(0.0, 0.1) = 0.022;
uniform float crawler_energy = 3.0;
group_uniforms;

group_uniforms Light;
uniform float exposure : hint_range(0.0, 1.0) = 0.33;
uniform float lit_edge : hint_range(-1.0, 1.0) = 0.22;
uniform float dark_edge : hint_range(-1.0, 1.0) = -0.04;
uniform float mid_tone : hint_range(0.0, 1.0) = 0.62;
uniform float shadow_tone : hint_range(0.0, 1.0) = 0.22;
uniform float step_softness : hint_range(0.0, 0.2) = 0.015;
group_uniforms;

varying vec3 sphere_dir;
varying float terminator_shift;

void vertex() {
	sphere_dir = normalize(VERTEX);
}

// The flashes at storm-local `sl` for a pixel catching `catch_` of their light: x = glow tone,
// y = white core, z = crawler vein.
vec3 lightning_at(vec2 sl, float catch_) {
	vec3 lit = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		vec4 f = flashes[i];
		if (f.w <= flash_level || f.z <= 0.0) {
			continue;
		}
		vec2 q = (sl - f.xy) / f.z;
		float r = length(q);
		float wob = 1.0 + (space_noise(vec3(sl * 2.2, float(i) * 7.3)) - 0.5) * flash_edge_noise * 2.0;
		float reach = (0.6 + 0.7 * min(f.w, 1.6)) * wob;
		float l = clamp(1.0 - r / reach, 0.0, 1.0) * catch_;
		float laa = max(fwidth(l), 1e-4);
		lit.x = max(lit.x, smoothstep(flash_level - laa, flash_level + laa, l));
		if (f.w > flash_core_level) {
			lit.y = max(lit.y, smoothstep(0.55 - laa, 0.55 + laa, l));
		}
		if (f.w > crawler_level && catch_ > 0.2 && r < crawler_reach) {
			// Veins: a ridge of noise seeded by where the flash is (stable while it flickers), and
			// finer branches only near it. Both thin out toward the tips.
			vec2 seed = fract(f.xy * vec2(0.731, 0.517)) * 40.0;
			float taper = 1.0 - r / crawler_reach;
			// Fine jitter so the veins zig-zag instead of curling.
			vec2 qj = q + (vec2(space_noise(vec3(q * 9.0, seed.x)), space_noise(vec3(q * 9.0, seed.y))) - 0.5) * 0.18;
			float main_ = abs(space_fbm(vec3(qj * 1.3 + seed, seed.x), 2) - 0.5);
			float twig = abs(space_fbm(vec3(qj * 3.4 + seed.yx, seed.y), 2) - 0.5);
			float wm = crawler_width * taper;
			float ma = max(fwidth(main_), 1e-4);
			float ta = max(fwidth(twig), 1e-4);
			float v = 1.0 - smoothstep(wm - ma, wm + ma, main_);
			float near_main = 1.0 - smoothstep(0.04, 0.09, main_);
			v = max(v, (1.0 - smoothstep(wm * 0.6 - ta, wm * 0.6 + ta, twig)) * near_main * taper);
			lit.z = max(lit.z, v * clamp((f.w - crawler_level) * 4.0, 0.0, 1.0));
		}
	}
	return lit;
}

void fragment() {
	vec3 d = normalize(sphere_dir);
	int layer;
	vec4 storm;
	float field = cloud_layers(d, layer, storm);
	// Antialiased hard edge: one pixel wide whatever the distance.
	float aa = max(fwidth(field), 1e-4);
	float a = smoothstep(cloud_level - aa, cloud_level + aa, field);
	if (a <= 0.0) {
		discard;
	}
	vec2 ll = earth_lat_lon(d);
	terminator_shift = scatter_shift_at(scatter_stroke(ll * scatter_planet_scale));
	vec3 lr = normalize(transpose(mat3(MODEL_MATRIX)) * normalize(relief_light_dir));
	vec3 away = -earth_toward(d, lr);
	// One sample on the side away from the light (is this a shaded edge?) and one toward it (is a
	// higher layer throwing its shadow here?).
	int layer_b;
	int layer_c;
	vec4 storm_b;
	float behind = cloud_layers(normalize(d + away * cloud_shade_width), layer_b, storm_b);
	cloud_layers(normalize(d - away * storm_cast_offset), layer_c, storm_b);
	float h = storm_height(layer);
	bool edge = storm_height(layer_b) < h
			|| (layer == STORM_CLOUD && behind < cloud_level + terminator_shift * 0.5);
	bool cast = storm_height(layer_c) > h;
	bool in_storm = storm.z > 0.5 || layer == STORM_WALL || layer == STORM_EYE;

	vec2 dl = ll;
	dl.y -= cloud_drift;
	vec2 sl = earth_storm_local(dl);
	vec3 col;
	if (layer == STORM_EYE) {
		// The pit: the inner wall face steps down to the floor; the face toward the light is lit,
		// and the eyewall's shadow falls across the floor on the light side.
		vec2 dl2 = earth_lat_lon(normalize(d + away * 0.001));
		dl2.y -= cloud_drift;
		vec2 away2 = normalize(earth_storm_local(dl2) - sl);
		vec2 sn = sl / storm_radius_deg;
		if (storm.x > storm.y * (1.0 - eye_wall_step)) {
			col = dot(normalize(sn), away2) > 0.1 ? eye_wall_lit_color : eye_wall_dark_color;
		} else {
			col = length(sn - away2 * eye_shadow_reach) > storm.y ? eye_floor_shadow_color : eye_floor_color;
		}
	} else if (layer == STORM_DECK) {
		col = edge || cast ? storm_deck_shadow_color : storm_deck_color;
	} else {
		vec3 shade = in_storm ? storm_shade_color : cloud_shade_color;
		col = edge || cast ? shade : cloud_color;
	}
	if (layer != STORM_EYE) {
		col = mix(col, paint_apply(col, paint_level(paint_noise_triplanar(d * paint_planet_scale, d))),
				paint_planet_amount);
	}
	ALBEDO = col;
	ALPHA = a * (in_storm ? (layer == STORM_EYE ? 1.0 : storm_opacity) : cloud_opacity);

	// Lightning lights the cloud it is in: dense layers catch it wide, the deck only near the
	// strike, the pit barely at all.
	float catch_ = layer == STORM_DECK ? flash_deck_catch : (layer == STORM_EYE ? 0.15 : 1.0);
	// Denser cloud catches more, so the lit patch is torn like the cloud it is in.
	catch_ *= clamp(0.5 + storm.w * 2.5, 0.0, 1.0);
	vec3 lit = lightning_at(sl, catch_);
	if (lit.x > 0.0 || lit.z > 0.0) {
		vec3 fc = mix(flash_color, flash_core_color, max(lit.y, lit.z));
		float on = max(lit.x, lit.z);
		ALBEDO = mix(ALBEDO, fc, on);
		// The glow tone stays below the glow threshold; the white core and the veins bloom.
		EMISSION = fc * flash_energy * on * mix(0.35, 1.0, lit.y) + fc * crawler_energy * lit.z;
		ALPHA = mix(ALPHA, a, on);
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) + terminator_shift;
	float mid = smoothstep(dark_edge - step_softness, dark_edge + step_softness, ndl);
	float lit = smoothstep(lit_edge - step_softness, lit_edge + step_softness, ndl);
	float tone = mix(mix(shadow_tone, mid_tone, mid), 1.0, lit);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * exposure * tone;
}
