// Gradients inside the intro planet's cel bands (docs/specs/cinema-post.md, decision 5). The light
// steps stay hard; inside them the ocean deepens toward the limb and lightens toward the sun, snow
// (and the sky city) cools toward the shadow side, a blue haze thickens toward the limb, and a thin
// warm band rides the terminator. Used from light() by planet_snow and planet_clouds, which pass
// in their own ndl (with the chipped terminator shift) and dark edge.

group_uniforms Grade;
// Ocean: multiplier at the limb / far from the sun, and facing the sun.
uniform vec3 grade_ocean_limb : source_color = vec3(0.62, 0.7, 0.9);
uniform vec3 grade_ocean_sun : source_color = vec3(1.0, 1.18, 1.15);
// Snow, ice, clouds, city: multiplier on the shadow side of the lit band (white = none).
uniform vec3 grade_cool : source_color = vec3(0.8, 0.88, 1.0);
// ndl range the cool tint fades out over (from the dark edge up to this).
uniform float grade_cool_reach : hint_range(0.0, 1.0) = 0.75;
// Haze: colour, how much of the surface it covers at the limb, and how fast it thickens.
uniform vec3 grade_haze : source_color = vec3(0.42, 0.66, 0.95);
uniform float grade_haze_strength : hint_range(0.0, 1.0) = 0.45;
uniform float grade_haze_power : hint_range(0.5, 8.0) = 2.2;
// Terminator: a thin stepped warm band just inside the dark edge.
uniform vec3 grade_warm : source_color = vec3(1.25, 0.82, 0.55);
uniform float grade_warm_width : hint_range(0.0, 0.3) = 0.06;
uniform float grade_warm_strength : hint_range(0.0, 1.0) = 0.8;
group_uniforms;

// The albedo with the in-band gradient. water: 1 for open ocean, 0 for everything else.
vec3 grade_albedo(vec3 albedo, float ndl, float dark_edge, float facing, float water) {
	float sun = smoothstep(dark_edge, 1.0, ndl);
	vec3 ocean = mix(grade_ocean_limb, grade_ocean_sun, sun * smoothstep(0.0, 0.6, facing));
	vec3 cool = mix(grade_cool, vec3(1.0), smoothstep(dark_edge, grade_cool_reach, ndl));
	return albedo * mix(cool, ocean, water);
}

// The lit colour after the band tone: the warm terminator band, then the limb haze (lit by the
// same light so it follows the bands). lit = albedo * light * tone already applied.
vec3 grade_light(vec3 lit, vec3 light, float ndl, float dark_edge, float softness, float facing,
		float tone) {
	float warm = smoothstep(dark_edge - softness, dark_edge + softness, ndl)
			* (1.0 - smoothstep(dark_edge + grade_warm_width - softness,
					dark_edge + grade_warm_width + softness, ndl));
	lit *= mix(vec3(1.0), grade_warm, warm * grade_warm_strength);
	float haze = pow(1.0 - facing, grade_haze_power) * grade_haze_strength;
	return mix(lit, grade_haze * light * tone, haze);
}
