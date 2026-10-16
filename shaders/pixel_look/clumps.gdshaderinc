// PIXEL look surface clumps: every surface splits into hard-edged patches of three tones built
// from its own colour - a darker, cooler shade, the base, a lighter, warmer tint - the way the
// flower-field reference breaks up. See docs/specs/pixel-look.md, "Reference pass".
//
// Its own copy of the hash on purpose - the pixel look does not include the cel files.

// 0 is flat colour, 1 the full three tones.
global uniform float look_clump_strength;
// How far the shade and tint sit from the base, in brightness.
global uniform float look_clump_value;
// How far they lean cool (shade) and warm (tint).
global uniform float look_clump_hue;
// The big clump, in metres, on level geometry.
global uniform float look_clump_world_size;
// The big clump, in UV units, on characters.
global uniform float look_clump_uv_size;

const float CLUMP_DETAIL_SCALE = 2.9;

// Hash without sin(): world coordinates reach the hundreds (the habitat sits at x = 330).
float clump_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float clump_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
			mix(clump_hash(i), clump_hash(i + vec2(1.0, 0.0)), u.x),
			mix(clump_hash(i + vec2(0.0, 1.0)), clump_hash(i + vec2(1.0, 1.0)), u.x),
			u.y);
}

// The detail octave is this much smaller than the clump, and the far layer this much bigger.
const float CLUMP_FAR_SCALE = 4.0;

// One layer of blobby, uneven patches, 0..1: a lightly domain-warped octave plus a detail octave
// that rags the edges. The detail fades back to 0.5 (no effect) once its cells are under ~2
// blocks on screen, so it never flickers whole blocks. `footprint` is how much of `p` one
// rendered pixel covers (half a block at the 2x supersample).
float clump_layer(vec2 p, float footprint) {
	vec2 warp = vec2(clump_value_noise(p * 0.5 + vec2(5.2, 1.3)),
			clump_value_noise(p * 0.5 + vec2(8.3, 2.8))) - 0.5;
	float big = clump_value_noise(p + warp * 0.6);
	float detail = clump_value_noise(p * CLUMP_DETAIL_SCALE + vec2(17.3, 41.7));
	float detail_fade = 1.0 - smoothstep(0.1, 0.25, footprint * CLUMP_DETAIL_SCALE);
	return big + (detail - 0.5) * 0.6 * detail_fade;
}

// Near, the clumps are look_clump_*_size; once those shrink under ~2 blocks a layer
// CLUMP_FAR_SCALE times bigger takes over, so the texture carries on into the middle distance
// (smaller on screen with distance, as in the reference) instead of stopping in a ring round the
// camera. The far layer fades to flat in its turn, where the haze has the picture anyway.
float clump_field(vec2 p, float footprint) {
	float to_far = smoothstep(0.2, 0.4, footprint);
	float near = clump_layer(p, footprint);
	float far_fp = footprint / CLUMP_FAR_SCALE;
	float far = mix(clump_layer(p / CLUMP_FAR_SCALE + vec2(91.7, 23.1), far_fp), 0.5,
			smoothstep(0.25, 0.6, far_fp));
	float n = mix(near, far, to_far);
	// Value noise bunches around 0.5; stretch it so all three tones get a fair share.
	return clamp((n - 0.5) * 2.2 + 0.5, 0.0, 1.0);
}

// The field cut into three hard tones: -1 shade, 0 base, +1 tint.
float clump_tone(float n) {
	return n < 0.36 ? -1.0 : (n > 0.64 ? 1.0 : 0.0);
}

// World-space triplanar, picking the dominant plane rather than blending: blended stepped
// tones would put a fourth and fifth tone along every bevel.
float clump_world(vec3 world_pos, vec3 n) {
	vec3 p = world_pos / max(look_clump_world_size, 1e-3);
	float footprint = length(fwidth(p));
	vec3 a = abs(n);
	vec2 q;
	if (a.y >= a.x && a.y >= a.z) {
		q = p.xz + vec2(31.7, 11.9);
	} else if (a.x >= a.z) {
		q = p.zy;
	} else {
		q = p.xy + vec2(63.1, 47.3);
	}
	return clump_tone(clump_field(q, footprint));
}

float clump_uv(vec2 uv, float seed) {
	vec2 p = uv / max(look_clump_uv_size, 1e-4) + vec2(seed * 7.13, seed * 3.71);
	return clump_tone(clump_field(p, length(fwidth(p))));
}

// Shade is darker and leans cool; tint moves toward a warm cream and leans warm. Toward a colour,
// not a multiply, so white surfaces (the mech) still get a visible third tone instead of clipping,
// and a hue rotation would do nothing on pilot9's whites and greys anyway.
const vec3 CLUMP_WARM = vec3(1.0, 0.92, 0.72);

vec3 clump_apply(vec3 albedo, float tone) {
	float v = tone * look_clump_strength;
	if (v < 0.0) {
		vec3 cool = vec3(1.0 - look_clump_hue, 1.0, 1.0 + look_clump_hue);
		return albedo * (1.0 + v * look_clump_value) * mix(vec3(1.0), cool, -v);
	}
	vec3 warm = vec3(1.0 + look_clump_hue, 1.0, 1.0 - look_clump_hue);
	return mix(albedo, mix(albedo, CLUMP_WARM, look_clump_value) * warm, v);
}
