// Painted shading: stepped low-contrast patches inside each cel tone, so a flat colour reads as
// hand-painted. Applied to ALBEDO before light(), so the two-band diffuse curve is untouched and
// light and shadow get the same mottling. See docs/specs/painted-shading.md.
//
// Not part of the upstream eldskald shader; this file is the project's own.

global uniform float paint_strength;
global uniform float paint_value;
global uniform float paint_warmth;
global uniform float paint_steps;
global uniform float paint_softness;
global uniform float paint_world_size;
global uniform float paint_world_detail_size;
global uniform float paint_world_detail_weight;
global uniform float paint_uv_size;
global uniform float paint_angularity;

// How hard the noise is pushed away from 0.5 before it is stepped. Two octaves of value noise
// sit mostly between 0.3 and 0.7, so without this the outer levels would almost never show.
const float PAINT_CONTRAST = 2.2;

// Hash without sin(): sin() of a large argument loses precision on some GPUs, and world
// coordinates here reach the hundreds (the habitat sits at x = 330).
float paint_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float paint_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
			mix(paint_hash(i), paint_hash(i + vec2(1.0, 0.0)), u.x),
			mix(paint_hash(i + vec2(0.0, 1.0)), paint_hash(i + vec2(1.0, 1.0)), u.x),
			u.y);
}

// Two octaves of cloud: the big patch shapes, plus a smaller one that breaks up their outlines
// so they read as laid-down paint rather than round blobs.
float paint_cloud(vec2 p) {
	return 0.68 * paint_value_noise(p) + 0.32 * paint_value_noise(p * 2.07 + vec2(17.1, 5.3));
}

// Voronoi with one flat random value per cell, so a step edge that lands between two cells is a
// straight cut at whatever angle the cell border runs. Feature points are fully jittered, which
// gives irregular polygons rather than a grid.
float paint_voronoi(vec2 p) {
	vec2 i = floor(p);
	float best = 9.0;
	float value = 0.5;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = i + vec2(float(x), float(y));
			vec2 site = cell + vec2(paint_hash(cell), paint_hash(cell + vec2(19.19, 47.73)));
			vec2 d = site - p;
			float dist = dot(d, d);
			if (dist < best) {
				best = dist;
				value = paint_hash(cell + vec2(71.3, 29.1));
			}
		}
	}
	return value;
}

// Voronoi cell values are uniform 0..1 (std 0.29); the cloud sits around 0.5 (std 0.16).
// Scaling the cells down to the cloud's spread keeps the two mixable without one swamping
// the other.
const float PAINT_VORONOI_SPREAD = 0.56;

// Mixes two centred noises and restores the spread the mix loses (two independent values
// averaged are flatter than either), so the dark / base / light split stays about a third each
// whatever the weights are. Returns 0..1 around 0.5.
float paint_blend(float a, float b, float weight_b) {
	float wa = 1.0 - weight_b;
	float mixed = wa * (a - 0.5) + weight_b * (b - 0.5);
	return 0.5 + mixed / max(length(vec2(wa, weight_b)), 1e-3);
}

// The patch shape: straight-edged Voronoi polygons with cloud mixed in, so most edges are cut
// straight and some bend. paint_angularity 0 = pure cloud, 1 = pure polygons.
float paint_noise(vec2 p) {
	float cells = 0.5 + (paint_voronoi(p) - 0.5) * PAINT_VORONOI_SPREAD;
	return paint_blend(paint_cloud(p), cells, clamp(paint_angularity, 0.0, 1.0));
}

// World-space triplanar. Each plane gets its own offset so a box corner does not mirror the
// same patch onto three faces. Planes with no weight are skipped: on axis-aligned level boxes
// that is two of the three, and the Voronoi is the expensive part.
float paint_noise_triplanar(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 1e-5);
	float total = 0.0;
	if (w.x > 0.001) {
		total += w.x * paint_noise(p.zy);
	}
	if (w.y > 0.001) {
		total += w.y * paint_noise(p.xz + vec2(31.7, 11.9));
	}
	if (w.z > 0.001) {
		total += w.z * paint_noise(p.xy + vec2(63.1, 47.3));
	}
	return total;
}

// Level geometry: a big layer so large surfaces get broad patches in proportion, plus a fainter
// small one so crates and pillars smaller than a big patch are not left flat. Added before the
// steps, so there are still only paint_steps tones.
float paint_noise_world(vec3 world_pos, vec3 n) {
	float big = paint_noise_triplanar(world_pos / max(paint_world_size, 1e-3), n);
	float detail = paint_noise_triplanar(
			world_pos / max(paint_world_detail_size, 1e-3) + vec3(13.7, 41.3, 7.9), n);
	return paint_blend(big, detail, clamp(paint_world_detail_weight, 0.0, 1.0));
}

// Cuts the noise into paint_steps flat levels and returns the level in -1..1 (3 steps: dark /
// base / light). paint_softness is the blend width at each step edge, 0 = hard.
float paint_level(float n) {
	float steps = max(paint_steps, 2.0);
	float c = clamp((n - 0.5) * PAINT_CONTRAST + 0.5, 0.0, 0.9999);
	float t = c * steps;
	float i = floor(t);
	float w = max(paint_softness, 1e-4);
	float edge = smoothstep(0.0, 1.0, clamp((fract(t) - 1.0 + w) / w, 0.0, 1.0));
	return clamp((i + edge) / (steps - 1.0), 0.0, 1.0) * 2.0 - 1.0;
}

// Lighter levels lean warm, darker lean cool. A temperature tint rather than a hue rotation:
// rotating the hue of a white or grey does nothing, and pilot9 is mostly white and grey.
vec3 paint_apply(vec3 albedo, float level) {
	float v = level * paint_strength;
	return albedo * (1.0 + v * paint_value)
			* vec3(1.0 + v * paint_warmth, 1.0, 1.0 - v * paint_warmth);
}
