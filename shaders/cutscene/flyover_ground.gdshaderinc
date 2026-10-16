// The flyover's painted ground: the snow under the dead city. Not geometry. The sky paints it
// below the horizon (flyover_sky.gdshader, a flat plane the eye ray hits), so it goes on forever
// with no edge. See docs/specs/cutscene-flyover.md.

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

// How much of a buried street is under world `xz`, 0..1: shallow troughs on a grid of `block`
// metres turned `angle` radians about `origin`, `width` across, dying out past `radius`. Each
// stretch between crossings is a little wavy and fades in and out, so it reads as drifted over.
float flyover_streets(vec2 xz, vec2 origin, float angle, vec2 block, float width, float radius) {
	vec2 d = xz - origin;
	float c = cos(angle);
	float s = sin(angle);
	// Into the grid frame (x across, z along), the hero in the middle of a block.
	vec2 g = vec2(c * d.x - s * d.y, s * d.x + c * d.y) + block * 0.5;
	g += 3.0 * vec2(flyover_noise(g / 70.0 + 3.1), flyover_noise(g / 70.0 + 8.4)) - 1.5;
	vec2 to_line = abs(g - block * round(g / block));
	float half_w = width * 0.5;
	float on = max(1.0 - smoothstep(half_w * 0.6, half_w, to_line.x), 1.0 - smoothstep(half_w * 0.6, half_w, to_line.y));
	float patchy = smoothstep(0.25, 0.6, flyover_noise(g / 160.0 + 5.7));
	return on * patchy * (1.0 - smoothstep(radius * 0.6, radius, length(d)));
}
