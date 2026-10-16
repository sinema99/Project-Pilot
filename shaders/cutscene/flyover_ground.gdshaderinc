// The flyover's painted ground: what lies past OP_1's edge. Not geometry. The sky paints it
// below the horizon (flyover_sky.gdshader, a flat plane the eye ray hits) and the edge pass fades
// the map's outer band into it (flyover_edge.gdshader), so both read the same colour and the same
// world-anchored mottle. See docs/specs/cutscene-flyover.md.

float flyover_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float flyover_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(flyover_hash(i), flyover_hash(i + vec2(1.0, 0.0)), f.x),
			mix(flyover_hash(i + vec2(0.0, 1.0)), flyover_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The ground's colour at world `xz`: `base` with soft patches `mottle` lighter or darker,
// about `size` metres across (plus a finer layer at a third of that).
vec3 flyover_ground(vec2 xz, vec3 base, float mottle, float size) {
	float n = 0.7 * flyover_noise(xz / size) + 0.3 * flyover_noise(xz / (size / 3.0) + 17.3);
	return base * (1.0 + mottle * (n - 0.5) * 2.0);
}
