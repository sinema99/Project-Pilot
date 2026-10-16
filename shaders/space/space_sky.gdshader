// Space backdrop for the intro cutscene (docs/specs/cutscene-intro-space.md; cinema look in
// docs/specs/cinema-post.md): a navy-to-teal gradient wash with a touch of violet, a nebula, a
// diagonal Milky Way band with dark dust lanes, and stars in several colours and sizes. Bright and
// hero stars twinkle slowly; hero stars are bright enough (HDR) for the lens streak to catch them.
// All held darker than the planet's night side. The twinkle runs on `twinkle_time`, which
// intro_space.gd sets from the shot time so seeking shows the same frame.
shader_type sky;

#include "res://shaders/space/space_noise.gdshaderinc"

uniform float twinkle_time = 0.0;

group_uniforms Wash;
// Gradient along wash_axis: low end, high end.
uniform vec3 wash_low : source_color = vec3(0.006, 0.009, 0.026);
uniform vec3 wash_high : source_color = vec3(0.006, 0.03, 0.04);
uniform vec3 wash_axis = vec3(0.3, 1.0, 0.0);
uniform float wash_strength : hint_range(0.0, 2.0) = 1.0;
group_uniforms;

group_uniforms Stars;
// Cells per unit of direction. Higher = more, smaller-spaced stars.
uniform float small_density = 140.0;
uniform float small_chance : hint_range(0.0, 1.0) = 0.07;
uniform float small_size = 0.0011;
uniform float small_brightness = 0.4;
uniform float big_density = 38.0;
uniform float big_chance : hint_range(0.0, 1.0) = 0.05;
uniform float big_size = 0.0019;
uniform float big_brightness = 1.2;
// A few hero stars: big, coloured, above the streak threshold.
uniform float hero_density = 11.0;
uniform float hero_chance : hint_range(0.0, 1.0) = 0.3;
uniform float hero_size = 0.0032;
uniform float hero_brightness = 3.2;
// Star colours: most blue-white or white, some warm, a few red.
uniform vec3 star_blue : source_color = vec3(0.72, 0.84, 1.0);
uniform vec3 star_white : source_color = vec3(0.95, 0.96, 1.0);
uniform vec3 star_warm : source_color = vec3(1.0, 0.86, 0.66);
uniform vec3 star_red : source_color = vec3(1.0, 0.55, 0.45);
group_uniforms;

group_uniforms Twinkle;
// Bright and hero stars only. Period range in seconds and the swing (+- fraction).
uniform vec2 twinkle_period = vec2(2.0, 4.0);
uniform float twinkle_amount : hint_range(0.0, 1.0) = 0.3;
group_uniforms;

group_uniforms Nebula;
uniform vec3 nebula_a : source_color = vec3(0.05, 0.16, 0.3);
uniform vec3 nebula_b : source_color = vec3(0.22, 0.08, 0.34);
uniform float nebula_strength : hint_range(0.0, 1.0) = 0.22;
uniform float nebula_scale = 1.8;
group_uniforms;

group_uniforms Band;
// The band is the great circle around this normal. Set so it crosses the shot's sky strip
// diagonally, from the top right corner down behind the planet's limb.
uniform vec3 band_normal = vec3(-0.854, 0.215, -0.474);
// Half width, in direction units (about radians).
uniform float band_width = 0.07;
uniform vec3 band_color : source_color = vec3(0.07, 0.1, 0.14);
uniform vec3 band_core : source_color = vec3(0.12, 0.11, 0.15);
uniform float band_strength : hint_range(0.0, 2.0) = 0.7;
// Dust lanes: dark streaks along the band's middle.
uniform float dust_scale = 22.0;
uniform float dust_amount : hint_range(0.0, 1.0) = 0.8;
// The band also packs in extra faint stars.
uniform float band_star_density = 240.0;
uniform float band_star_chance : hint_range(0.0, 1.0) = 0.09;
uniform float band_star_brightness = 0.22;
group_uniforms;

float band_at(vec3 dir) {
	float d = dot(dir, normalize(band_normal)) / band_width;
	return exp(-d * d);
}

vec3 star_tint(float h) {
	if (h < 0.4) {
		return star_blue;
	} else if (h < 0.8) {
		return star_white;
	} else if (h < 0.95) {
		return star_warm;
	}
	return star_red;
}

// One layer of stars: one possible star per grid cell around the view direction. chance_band
// adds extra chance inside the band; twinkle 1 makes this layer's stars twinkle.
vec3 star_layer(vec3 dir, float density, float chance, float chance_band, float size, float seed,
		float twinkle) {
	vec3 p = dir * density;
	vec3 cell = floor(p);
	vec3 best = vec3(0.0);
	float best_b = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 c = cell + vec3(float(x), float(y), float(z));
				vec3 h = space_hash3(c + seed);
				vec3 star = normalize(c + 0.2 + 0.6 * space_hash3(c + seed + 3.3));
				if (h.x > chance + chance_band * band_at(star)) {
					continue;
				}
				float dist = length(dir - star);
				// Size jitter, so not every star is the same point.
				float s = size * (0.6 + 0.8 * h.y);
				float b = (1.0 - smoothstep(s * 0.4, s, dist)) * (0.4 + 0.6 * h.z);
				vec3 h2 = space_hash3(c + seed + 9.1);
				float period = mix(twinkle_period.x, twinkle_period.y, h2.y);
				b *= 1.0 + twinkle * twinkle_amount * sin(TAU * (twinkle_time / period + h2.z));
				if (b > best_b) {
					best_b = b;
					best = star_tint(h2.x) * b;
				}
			}
		}
	}
	return best;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float g = smoothstep(-0.6, 0.6, dot(dir, normalize(wash_axis)));
	vec3 col = mix(wash_low, wash_high, g) * wash_strength;

	float neb = space_fbm(dir * nebula_scale + vec3(2.3, 5.1, 0.7), 5);
	float neb_mix = space_fbm(dir * nebula_scale * 0.7 + vec3(9.4, 1.2, 4.4), 3);
	float neb_amount = smoothstep(0.4, 0.8, neb) * nebula_strength;
	col += mix(nebula_a, nebula_b, smoothstep(0.35, 0.65, neb_mix)) * neb_amount;

	// Milky Way: soft glow, a brighter core, clumped along its length, cut by dust lanes.
	float band = band_at(dir);
	float clump = space_fbm(dir * 7.0 + vec3(3.1, 0.4, 8.8), 4);
	float dust = space_fbm(dir * dust_scale + vec3(5.5, 2.2, 1.1), 4);
	float lanes = smoothstep(0.45, 0.62, dust) * smoothstep(0.25, 0.9, band) * dust_amount;
	vec3 glow = band_color * band + band_core * band * band * band;
	col += glow * (0.55 + 0.9 * clump) * (1.0 - lanes) * band_strength;

	vec3 stars = star_layer(dir, small_density, small_chance, 0.0, small_size, 0.0, 0.0) * small_brightness;
	stars = max(stars, star_layer(dir, band_star_density, 0.0, band_star_chance, small_size * 0.7, 31.0, 0.0)
			* band_star_brightness * (1.0 - lanes));
	stars = max(stars, star_layer(dir, big_density, big_chance, 0.0, big_size, 17.0, 1.0) * big_brightness);
	stars = max(stars, star_layer(dir, hero_density, hero_chance, 0.0, hero_size, 53.0, 1.0) * hero_brightness);
	COLOR = col + stars;
}
