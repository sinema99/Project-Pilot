// The intro cutscene planet: a desolate ice-age Earth (docs/specs/cutscene-intro-space.md,
// "Planet upgrade"). Inside the baked ETOPO1 crop (the only part the camera sees): real coasts
// roughed by noise, stepped ocean shelf bands, sea ice, every continent frozen white,
// mild shaded mountains showing through the snow, cloud shadows, a cheated sun glint, painted patches and
// chipped terminator, and the mega sky city over the USA (planet_city.gdshaderinc). Outside the crop: the old flat noise planet, which is never on camera.
// Flat cel colour regions and stepped light throughout.
shader_type spatial;
render_mode cull_back, shadows_disabled, specular_disabled;

#include "res://shaders/space/space_noise.gdshaderinc"
#include "res://shaders/space/planet_earth.gdshaderinc"
#include "res://shaders/space/planet_city.gdshaderinc"
#include "res://shaders/space/planet_grade.gdshaderinc"
#include "res://shaders/cel/includes/painted.gdshaderinc"
#include "res://shaders/cel/includes/scatter.gdshaderinc"

group_uniforms Surface;
uniform vec3 snow_color : source_color = vec3(0.86, 0.9, 0.95);
uniform vec3 ice_color : source_color = vec3(0.55, 0.74, 0.82);
uniform vec3 deep_color : source_color = vec3(0.2, 0.42, 0.56);
uniform vec3 rock_color : source_color = vec3(0.76, 0.6, 0.53);
// Fallback noise planet (outside the crop).
uniform float noise_scale = 6.0;
uniform vec3 noise_offset = vec3(4.1, 1.3, 7.7);
uniform float deep_level : hint_range(0.0, 1.0) = 0.38;
uniform float ice_level : hint_range(0.0, 1.0) = 0.5;
uniform float rock_level : hint_range(0.0, 1.0) = 0.66;
uniform float rock_scale = 14.0;
uniform float polar_snow : hint_range(0.0, 1.0) = 0.12;
group_uniforms;

group_uniforms Earth;
// Metres of noise added to the elevation before the coast and shelf cuts: roughs the coastline.
uniform float coast_jitter_m = 10.0;
uniform float coast_noise_scale = 90.0;
// All land is snow (the Earth has frozen over); the mountains still read through the relief light.
// North of this latitude the shallow shelf is frozen too (flat, no relief), lobed along its edge.
uniform float ice_shelf_lat = 39.0;
uniform float ice_lobe_deg = 2.5;
// Sea ice on the open ocean, from loose floes at sea_ice_lat to packed sea_ice_full_lat.
uniform float sea_ice_lat = 41.0;
uniform float sea_ice_full_lat = 50.0;
uniform float floe_scale = 140.0;
// Ocean bands by depth (metres).
uniform vec3 abyss_color : source_color = vec3(0.11, 0.28, 0.44);
uniform vec3 shelf_color : source_color = vec3(0.24, 0.56, 0.62);
uniform vec3 coast_color : source_color = vec3(0.5, 0.78, 0.78);
uniform float shelf_depth = 190.0;
uniform float coast_depth = 28.0;
group_uniforms;

group_uniforms Mountains;
// Upper left, from the camera's side: rakes across ranges the head-on sun would flatten. Also
// sets which way clouds shade and cast. World space.
uniform vec3 relief_light_dir = vec3(-0.75, 0.6, 0.3);
// How much steeper than real the masked ranges are drawn.
uniform float relief_exaggeration = 40.0;
uniform float relief_step : hint_range(0.0, 0.5) = 0.1;
uniform float relief_shadow_tone : hint_range(0.0, 1.0) = 0.68;
uniform float relief_light_tone : hint_range(1.0, 1.5) = 1.07;
group_uniforms;

group_uniforms CloudShadow;
// How far (unit sphere) a cloud's shadow lands from it, away from the relief light.
uniform float cloud_shadow_offset : hint_range(0.0, 0.05) = 0.009;
uniform float cloud_shadow_tone : hint_range(0.0, 1.0) = 0.68;
group_uniforms;

group_uniforms Glint;
// Cheated onto the Gulf near Florida (a true reflection would sit over the ice / land).
uniform vec2 glint_lat_lon = vec2(26.6, -84.6);
uniform vec3 glint_color : source_color = vec3(0.85, 0.97, 1.0);
uniform float glint_size_deg = 2.2;
uniform float glint_core_deg = 0.9;
uniform float glint_strength : hint_range(0.0, 2.0) = 0.55;
group_uniforms;

group_uniforms Style;
// Painted patches: patches per unit sphere (30 = ~2 deg, ~200 km on Earth).
uniform float paint_planet_scale = 30.0;
uniform float paint_planet_amount : hint_range(0.0, 1.0) = 0.6;
uniform float scatter_planet_scale = 1.4;
group_uniforms;

group_uniforms Light;
// LIGHT_COLOR arrives with the sun's energy and a factor of PI in it; this brings the snow back
// under white without dimming the sun the ship is lit by.
uniform float exposure : hint_range(0.0, 1.0) = 0.33;
uniform float lit_edge : hint_range(-1.0, 1.0) = 0.22;
uniform float dark_edge : hint_range(-1.0, 1.0) = -0.04;
uniform float mid_tone : hint_range(0.0, 1.0) = 0.62;
uniform float shadow_tone : hint_range(0.0, 1.0) = 0.22;
uniform float step_softness : hint_range(0.0, 0.2) = 0.015;
group_uniforms;

group_uniforms Atmosphere;
uniform vec3 rim_color : source_color = vec3(0.45, 0.85, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.7;
uniform float rim_power : hint_range(0.5, 16.0) = 3.5;
group_uniforms;

varying vec3 sphere_dir;
varying float terminator_shift;
// 1 on open ocean (planet_grade: the ocean gradient), 0 elsewhere.
varying float grade_water;

void vertex() {
	sphere_dir = normalize(VERTEX);
}

vec3 fallback_surface(vec3 d) {
	float n = space_fbm(d * noise_scale + noise_offset, 5);
	n += abs(d.y) * polar_snow;
	if (n < deep_level) {
		return deep_color;
	} else if (n < ice_level) {
		return ice_color;
	}
	float r = space_fbm(d * rock_scale + noise_offset * 1.7, 4);
	return r > rock_level ? rock_color : snow_color;
}

// Height of the smoothed land (G) in metres.
float land_height(vec2 uv) {
	return texture(earth_map, uv).g * EARTH_LAND_HEIGHT;
}

void fragment() {
	vec3 d = normalize(sphere_dir);
	vec2 ll = earth_lat_lon(d);
	vec2 uv = earth_uv(ll);
	float stroke = scatter_stroke(ll * scatter_planet_scale);
	terminator_shift = scatter_shift_at(stroke);
	vec3 col;
	float glint = 0.0;
	grade_water = 0.0;
	if (!earth_in_crop(uv)) {
		col = fallback_surface(d);
	} else {
		vec4 tx = texture(earth_map, uv);
		float elev = earth_elevation(tx)
				+ (space_fbm(d * coast_noise_scale, 3) - 0.5) * 2.0 * coast_jitter_m;
		float front = ice_shelf_lat
				+ (space_fbm(vec3(ll.y * 0.11, 1.7, 5.3), 3) - 0.5) * 4.0 * ice_lobe_deg
				+ (space_noise(d * 90.0) - 0.5) * 0.6;
		bool water = elev < 0.0;
		bool sheet = water && ll.x > front && elev > -shelf_depth;
		bool painted = true;
		if (sheet) {
			col = snow_color;
		} else if (water) {
			float depth = -elev;
			col = depth < coast_depth ? coast_color : (depth < shelf_depth ? shelf_color : abyss_color);
			// Sea ice: floes thicken northward until the pack is solid.
			float pack = smoothstep(sea_ice_lat, sea_ice_full_lat, ll.x);
			float floe = space_fbm(d * floe_scale, 3);
			if (pack > 0.0 && floe < pack * 1.15 - 0.05) {
				col = floe < pack * 0.8 ? snow_color : ice_color;
			} else {
				painted = false;
				grade_water = 1.0;
				// Sun glint, stepped: core and halo, chipped by the same strokes as the terminator.
				float ang = degrees(acos(clamp(dot(d, earth_dir(glint_lat_lon)), -1.0, 1.0)))
						+ (stroke - 0.5) * 0.35;
				glint = ang < glint_core_deg ? 1.0 : (ang < glint_size_deg ? 0.35 : 0.0);
			}
		} else {
			col = snow_color;
		}

		vec3 lr = normalize(transpose(mat3(MODEL_MATRIX)) * normalize(relief_light_dir));
		vec3 toward = earth_toward(d, lr);
		// The mega sky city covers whatever is under it; its shadow falls on what is not.
		bool city;
		vec3 city_col = city_surface(d, toward, city);
		if (city) {
			col = city_col;
			grade_water = 0.0;
			painted = true;
			glint = 0.0;
		}

		// Mild mountains: the masked height tilts a normal that only the raking relief light sees.
		// Only real ranges: low relief (plains, plateaus) and the smooth ice sheet stay flat.
		float mask = smoothstep(0.2, 0.65, tx.b);
		if (mask > 0.01 && !water && !sheet && !city) {
			vec2 du = vec2(1.5 / EARTH_TEXELS.x, 0.0);
			vec2 dv = vec2(0.0, 1.5 / EARTH_TEXELS.y);
			float cell_m = EARTH_CELL * 111320.0 * 3.0;
			float se = (land_height(uv + du) - land_height(uv - du)) / (cell_m * max(cos(radians(ll.x)), 0.2));
			float sn = (land_height(uv - dv) - land_height(uv + dv)) / cell_m;
			vec3 east = normalize(cross(vec3(0.0, 1.0, 0.0), d));
			vec3 north = cross(d, east);
			vec3 n = normalize(d - (se * east + sn * north) * relief_exaggeration * mask);
			float r = dot(n, lr) - dot(d, lr);
			col *= r < -relief_step ? relief_shadow_tone : (r > relief_step ? relief_light_tone : 1.0);
		}

		if (painted) {
			col = mix(col, paint_apply(col, paint_level(paint_noise_triplanar(d * paint_planet_scale, d))),
					paint_planet_amount);
		}

		if (!city && city_shadow_at(d, toward)) {
			col *= city_shadow_tone;
			glint = 0.0;
		}

		// Cloud shadows: the cloud up-light of this point casts here.
		float shade = cloud_field(normalize(d + toward * cloud_shadow_offset));
		if (shade > cloud_level + terminator_shift * 0.5) {
			col *= cloud_shadow_tone;
			glint = 0.0;
		}
	}
	ALBEDO = col;
	EMISSION = glint_color * glint * glint_strength;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) + terminator_shift;
	float mid = smoothstep(dark_edge - step_softness, dark_edge + step_softness, ndl);
	float lit = smoothstep(lit_edge - step_softness, lit_edge + step_softness, ndl);
	float tone = mix(mix(shadow_tone, mid_tone, mid), 1.0, lit);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 albedo = grade_albedo(ALBEDO, ndl, dark_edge, facing, grade_water);
	DIFFUSE_LIGHT += grade_light(albedo * LIGHT_COLOR * exposure * tone, LIGHT_COLOR * exposure, ndl,
			dark_edge, step_softness, facing, tone);
	// Atmosphere rim: fresnel, only where the sun reaches.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	DIFFUSE_LIGHT += rim_color * LIGHT_COLOR * exposure * fres * rim_strength * mid;
}
