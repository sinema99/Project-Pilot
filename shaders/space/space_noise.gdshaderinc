// Value noise and fbm for the space shots (planet surface, sky nebula). 3D, so it can be fed a
// direction or an object-space normal and wrap a sphere without a seam.

float space_hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 space_hash3(vec3 p) {
	return vec3(
			space_hash(p),
			space_hash(p + vec3(31.7, 11.3, 5.9)),
			space_hash(p + vec3(7.1, 47.9, 23.3)));
}

float space_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
			mix(mix(space_hash(i + vec3(0, 0, 0)), space_hash(i + vec3(1, 0, 0)), f.x),
				mix(space_hash(i + vec3(0, 1, 0)), space_hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(space_hash(i + vec3(0, 0, 1)), space_hash(i + vec3(1, 0, 1)), f.x),
				mix(space_hash(i + vec3(0, 1, 1)), space_hash(i + vec3(1, 1, 1)), f.x), f.y),
			f.z);
}

// 0..1, roughly centred on 0.5.
float space_fbm(vec3 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		sum += amp * space_noise(p);
		norm += amp;
		p = p * 2.03 + vec3(1.7, 9.2, 3.4);
		amp *= 0.5;
	}
	return sum / norm;
}
