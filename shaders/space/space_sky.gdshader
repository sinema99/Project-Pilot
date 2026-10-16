// Space backdrop for the intro cutscene (docs/specs/cutscene-intro-space.md): simple stars (sharp
// points, two layers, no twinkle) on near-black, plus a very faint blue-violet nebula haze.
shader_type sky;

#include "res://shaders/space/space_noise.gdshaderinc"

uniform vec3 space_color : source_color = vec3(0.004, 0.006, 0.014);

group_uniforms Stars;
uniform vec3 star_color : source_color = vec3(0.9, 0.94, 1.0);
// Cells per unit of direction. Higher = more, smaller-spaced stars.
uniform float small_density = 140.0;
uniform float small_chance : hint_range(0.0, 1.0) = 0.07;
uniform float small_size = 0.0011;
uniform float small_brightness = 0.4;
uniform float big_density = 38.0;
uniform float big_chance : hint_range(0.0, 1.0) = 0.05;
uniform float big_size = 0.0019;
uniform float big_brightness = 1.2;
group_uniforms;

group_uniforms Nebula;
uniform vec3 nebula_a : source_color = vec3(0.05, 0.12, 0.35);
uniform vec3 nebula_b : source_color = vec3(0.25, 0.08, 0.35);
uniform float nebula_strength : hint_range(0.0, 1.0) = 0.12;
uniform float nebula_scale = 1.8;
group_uniforms;

// One layer of stars: one possible star per grid cell around the view direction.
float star_layer(vec3 dir, float density, float chance, float size, float seed) {
	vec3 p = dir * density;
	vec3 cell = floor(p);
	float best = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 c = cell + vec3(float(x), float(y), float(z));
				vec3 h = space_hash3(c + seed);
				if (h.x > chance) {
					continue;
				}
				vec3 star = normalize(c + 0.2 + 0.6 * space_hash3(c + seed + 3.3));
				float dist = length(dir - star);
				// Size jitter, so not every star is the same point.
				float s = size * (0.6 + 0.8 * h.y);
				float b = (1.0 - smoothstep(s * 0.4, s, dist)) * (0.4 + 0.6 * h.z);
				best = max(best, b);
			}
		}
	}
	return best;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float neb = space_fbm(dir * nebula_scale + vec3(2.3, 5.1, 0.7), 5);
	float neb_mix = space_fbm(dir * nebula_scale * 0.7 + vec3(9.4, 1.2, 4.4), 3);
	float neb_amount = smoothstep(0.45, 0.8, neb) * nebula_strength;
	vec3 col = space_color + mix(nebula_a, nebula_b, smoothstep(0.35, 0.65, neb_mix)) * neb_amount;
	float stars = star_layer(dir, small_density, small_chance, small_size, 0.0) * small_brightness;
	stars = max(stars, star_layer(dir, big_density, big_chance, big_size, 17.0) * big_brightness);
	COLOR = col + star_color * stars;
}
