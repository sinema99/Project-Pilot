shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, shadows_disabled;

// Snow on the inside of the cockpit's screen sphere: the outside feed as the ship flies out of the
// descent's calm into the storm. Pale lavender calm with light snow that darkens into slate-violet
// storm cloud with grey-teal streaks (both sampled from the descent shot). The ship's speed never
// changes: the storm is more snow, cloud bands and gust turbulence, never longer streaks. Anime cel:
// flat bands, hard edged flakes, no gradients. See docs/specs/cutscene-cockpit-storm.md.
//
// The ship flies toward `source_dir` (sphere space, behind the camera), so the snow streams away
// from it and recedes into its antipode, the vanishing point dead behind his head. Flakes live in
// log-polar cells round that point (angle round it, log of the angle from it): cells are square in
// angle everywhere and shrink toward the point, so flakes get smaller and slower as they recede, as
// in real perspective. A wind field (S-lanes, gusts, eddies) warps those cells so flakes stream on
// curved paths, and big near "skimmers" hit the glass, cling, slide round it and peel off. Every
// input is a uniform from CockpitSnow, so a frame is pure in shot time.

uniform vec3 source_dir = vec3(0.0, 0.1, 1.0);
// 0 = calm light snow, 1 = full storm.
uniform float storm : hint_range(0.0, 1.0) = 0.0;
// How far the snow has streamed, in log-angle units: the cruise speed times shot time.
uniform float travel = 0.0;
// Shot time, seconds: the flakes' wobble, the gusts' turbulence and the cloud bands' churn.
uniform float shot_time = 0.0;
// 0..1 gusts: denser snow, cloud bands and turbulence. Already scaled by the storm.
uniform float gust : hint_range(0.0, 1.0) = 0.0;
// 0..1 lightning.
uniform float flash : hint_range(0.0, 1.0) = 0.0;

// Calm sky, top to the horizon: the descent's pale lavender.
uniform vec3 calm_top : source_color = vec3(0.82, 0.8, 0.89);
uniform vec3 calm_high : source_color = vec3(0.85, 0.82, 0.9);
uniform vec3 calm_low : source_color = vec3(0.87, 0.85, 0.92);
uniform vec3 calm_deck : source_color = vec3(0.9, 0.9, 0.94);
// Storm sky, the same four bands: dark slate-violet overhead, lighter grey-teal low.
uniform vec3 storm_top : source_color = vec3(0.36, 0.37, 0.45);
uniform vec3 storm_high : source_color = vec3(0.44, 0.46, 0.53);
uniform vec3 storm_low : source_color = vec3(0.52, 0.56, 0.6);
uniform vec3 storm_deck : source_color = vec3(0.6, 0.66, 0.69);
// The storm's cloud bands: dark violet masses and the grey-teal streaks between them.
uniform vec3 cloud_dark : source_color = vec3(0.39, 0.38, 0.46);
uniform vec3 cloud_teal : source_color = vec3(0.68, 0.76, 0.77);
// Flakes: pure white, no rim. Far layers fade toward the sky.
uniform vec3 flake_core : source_color = vec3(0.97, 0.98, 1.0);
// A thin shade on each flake's leading edge, so white still reads on the pale calm sky. It fades
// back into the sky as the storm darkens it.
uniform vec3 flake_shade : source_color = vec3(0.58, 0.6, 0.74);
// The wind: how far the S-lanes bend the stream off its line, radians of angle round the vanishing
// point (log-polar, so the bend shrinks with perspective).
uniform float lane_bend = 0.22;
// How far a full gust shoves the flakes sideways, the same units.
uniform float turbulence = 0.12;
// Eddies: the curl at an eddy's heart, radians, and the chance a patch of stream holds one (calm,
// storm). They drift down the stream slower than the snow, so flakes pass through them.
uniform float eddy_curl = 1.7;
uniform vec2 eddy_chance = vec2(0.3, 0.7);
uniform float eddy_drift = 0.45;
// Skimmers: near flakes that hit the glass, cling, slide and peel off. Mean count alive (calm,
// storm), and the radius on the glass, radians of the sphere.
uniform vec2 skimmer_count = vec2(5.0, 15.0);
uniform float skimmer_size = 0.03;
// The storm ramp (StormBeats), so a skimmer's life is decided by the storm when it was born.
uniform vec2 ramp = vec2(3.0, 7.0);
uniform vec3 lightning : source_color = vec3(0.95, 0.98, 1.0);

varying vec3 sphere_dir;

void vertex() {
	sphere_dir = VERTEX;
}

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), u.x),
			mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Seamless round the circle: x is wrapped every `period` cells.
float noise_wrap(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float i0 = mod(i.x, period);
	float i1 = mod(i.x + 1.0, period);
	return mix(mix(hash1(vec2(i0, i.y)), hash1(vec2(i1, i.y)), u.x),
			mix(hash1(vec2(i0, i.y + 1.0)), hash1(vec2(i1, i.y + 1.0)), u.x), u.y);
}

float smooth01(float x) {
	x = clamp(x, 0.0, 1.0);
	return x * x * (3.0 - 2.0 * x);
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// The wind, as an offset to (phi, log angle). A flow field fixed on the sphere (it changes slowly in
// time but does not stream), so a flake streaming through it follows a curved path, not a line.
vec2 wind(vec2 p, float gusts) {
	float pk = 4.0 / TAU;
	// S-lanes: the stream wanders sideways (mostly) and a little along itself.
	vec2 off = vec2(noise_wrap(vec2(p.x * pk, p.y * 1.1 + shot_time * 0.08), 4.0) - 0.5,
			(noise_wrap(vec2(p.x * pk + 2.7, p.y * 1.1 - shot_time * 0.06), 4.0) - 0.5) * 0.35);
	off *= 2.0 * lane_bend;
	// Gust turbulence: a quicker, finer sideways shove.
	off.x += (noise_wrap(vec2(p.x * 6.0 / TAU, p.y * 2.2 + shot_time * 1.3), 6.0) - 0.5)
			* 2.0 * turbulence * gusts;
	// Eddies: small curls drifting down the stream. Each turns the field round its heart, most at the
	// middle and none at its edge, so flakes passing by swing part-way round it and carry on.
	float e = TAU / 9.0;
	vec2 q = vec2(p.x / e, (p.y + travel * eddy_drift) / e);
	vec2 base = floor(q);
	float chance = mix(eddy_chance.x, eddy_chance.y, storm);
	float strength = mix(0.6, 1.2, storm) * (1.0 + 0.6 * gusts);
	vec2 curl = vec2(0.0);
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			vec2 cell = base + vec2(float(i), float(j));
			vec2 id = vec2(mod(cell.x, 9.0), cell.y) + 41.0;
			if (hash1(id) > chance) {
				continue;
			}
			vec2 dv = q - (cell + 0.2 + 0.6 * hash2(id + 1.3));
			float reach = 0.3 + 0.25 * hash1(id + 2.9);
			float fall = 1.0 - smooth01(length(dv) / reach);
			float turn = (hash1(id + 4.4) < 0.5 ? -1.0 : 1.0) * (0.5 + 0.5 * hash1(id + 6.1));
			turn *= 0.7 + 0.3 * sin(shot_time * (0.8 + hash1(id + 7.7)) + hash1(id + 8.8) * TAU);
			curl += rot(dv, turn * eddy_curl * strength * fall * fall) - dv;
		}
	}
	return off + curl * e;
}

// One layer of flakes in the (wind-warped) log-polar field. `cells` round the circle; `rate` scales
// the layer's share of the travel (nearer layers stream faster); `size` the flake width in cells;
// `tail` how far it smears behind itself, in widths; `tufts` 1 lets big tufts appear (near only).
// Returns the flake's brightness, 0 where there is none.
float flakes(vec2 p, float cells, float rate, float size, float tail, float tufts, float density,
		float seed) {
	float k = cells / TAU;
	vec2 g = vec2(p.x * k, (p.y + travel * rate) * k);
	for (int dy = -2; dy <= 2; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 cell = floor(g) + vec2(float(dx), float(dy));
			vec2 id = vec2(mod(cell.x, cells), cell.y) + seed * 17.0;
			if (hash1(id + 3.1) > density) {
				continue;
			}
			vec2 c = cell + 0.25 + 0.5 * hash2(id);
			// Flutter: each flake wobbles on its own beat and amount, never in step with its neighbours.
			float amp = 0.08 + 0.2 * hash1(id + 5.0);
			c += vec2(sin(shot_time * (1.4 + 2.6 * hash1(id + 9.0)) + hash1(id + 5.5) * TAU),
					sin(shot_time * (1.1 + 2.0 * hash1(id + 9.4)) + hash1(id + 6.5) * TAU) * 0.6) * amp;
			vec2 d = g - c;
			// Specks, lumpy clumps, and (near layer only) a few big tufts.
			float kind = hash1(id + 7.7);
			float s = size * (0.55 + 0.35 * hash1(id + 1.7));
			float lump = 0.0;
			if (kind > 0.84) {
				s = size * (0.9 + 0.35 * hash1(id + 1.7));
				lump = 0.16;
			}
			if (kind > 1.0 - 0.06 * tufts) {
				s = size * (1.8 + 0.6 * hash1(id + 1.7));
				lump = 0.3;
			}
			// Each smears along its own path: the tail trails up the stream, leaning its own way.
			d.x -= max(d.y, 0.0) * (hash1(id + 2.2) - 0.5) * 0.5;
			float t = tail * (0.6 + 0.8 * hash1(id + 3.7));
			d.y = d.y < 0.0 ? d.y : d.y / t;
			float r = length(d) / s;
			if (lump > 0.0) {
				// Lumpy edge, tumbling.
				float a = atan(d.y, d.x) + shot_time * (hash1(id + 4.2) - 0.5) * 6.0;
				r *= 1.0 + lump * (0.6 * sin(a * 3.0 + hash1(id + 0.9) * TAU)
						+ 0.4 * sin(a * 5.0 + hash1(id + 1.1) * TAU));
			}
			if (r < 1.0) {
				// Leading edge (toward the vanishing point) in shade: negative.
				vec2 back = d - vec2(0.0, 0.3 * s);
				float lit = 0.75 + 0.25 * hash1(id + 8.1);
				return length(back) / s * (r / max(length(d) / s, 1e-4)) < 1.0 ? lit : -lit;
			}
		}
	}
	return 0.0;
}

float storm_at(float t) {
	return smooth01((t - ramp.x) / (ramp.y - ramp.x));
}

vec3 on_sphere(float r, float phi, vec3 u, vec3 w, vec3 v) {
	return cos(r) * v + sin(r) * (cos(phi) * u + sin(phi) * w);
}

// The skimmers: big near flakes that hit the glass, squash flat for a beat, slide along the sphere
// on a curve (speeding up, stretching), and peel off toward the vanishing point, shrinking away. Some
// break into bits mid-slide. Each slot lives one flake after another; whether a life is lived is
// decided by the storm at its birth, so a flake never pops in halfway. Returns 1 where one covers.
float skimmers(vec3 n, vec3 u, vec3 w, vec3 v) {
	for (int i = 0; i < 20; i++) {
		float fi = float(i);
		float period = 1.3 + 0.9 * hash1(vec2(fi, 0.37));
		float phase = hash1(vec2(fi, 0.71)) * period;
		float life = floor((shot_time + phase) / period);
		float age = fract((shot_time + phase) / period);
		vec2 id = vec2(fi, life) + 61.0;
		float alive = mix(skimmer_count.x, skimmer_count.y, storm_at(life * period - phase)) / 20.0;
		if (hash1(id) > alive) {
			continue;
		}
		float r0 = 1.0 + 0.4 * hash1(id + 1.1);
		float r1 = r0 * 0.3;
		float phi0 = hash1(id + 2.3) * TAU;
		float bend = (hash1(id + 3.5) - 0.5) * 1.2;
		// How far along its path, 0..1: a creep while it clings, then an accelerating slide.
		float s = 0.03 * smooth01(age / 0.2);
		if (age > 0.2) {
			float k = (age - 0.2) / 0.8;
			s = 0.03 + 0.97 * k * k;
		}
		vec3 p = on_sphere(mix(r0, r1, s), phi0 + bend * sin(s * 2.5), u, w, v);
		if (dot(n, p) < 0.95) {
			continue;
		}
		vec3 next = on_sphere(mix(r0, r1, s + 0.01), phi0 + bend * sin((s + 0.01) * 2.5), u, w, v);
		vec3 fwd = normalize(next - p - dot(next - p, p) * p);
		vec3 side_dir = cross(p, fwd);
		// Shape over its life: grows in on the hit, squashes flat as it clings, stretches as it
		// slides, shrinks as it peels away.
		float size = skimmer_size * (0.7 + 0.6 * hash1(id + 4.7));
		float along = 1.0;
		float across = 1.0;
		if (age < 0.06) {
			size *= smooth01(age / 0.06);
		} else if (age < 0.22) {
			float q = sin((age - 0.06) / 0.16 * PI);
			along = 1.0 - 0.45 * q;
			across = 1.0 + 0.55 * q;
		} else {
			float q = smooth01((age - 0.22) / 0.5);
			along = 1.0 + 1.3 * q;
			across = 1.0 - 0.25 * q;
		}
		size *= 1.0 - smooth01((age - 0.75) / 0.25);
		if (size <= 1e-4) {
			continue;
		}
		// Some break into three bits partway through the slide, drifting apart.
		int bits = hash1(id + 5.9) < 0.3 && age > 0.5 ? 3 : 1;
		float spread = (age - 0.5) * 0.25;
		vec3 delta = n - p;
		for (int b = 0; b < bits; b++) {
			float fb = float(b) - float(bits - 1) * 0.5;
			float x = dot(delta, side_dir) - fb * spread;
			float y = dot(delta, fwd) + abs(fb) * spread * 0.6;
			float bs = bits > 1 ? size * 0.6 : size;
			// The tail trails behind, against its travel.
			float yy = y > 0.0 ? y / along : y / (along * 1.6);
			float lump = 1.0 + 0.15 * sin(atan(yy, x) * 3.0 + hash1(id + 6.3 + fb) * TAU);
			if (length(vec2(x / across, yy)) / bs * lump < 1.0) {
				return 1.0;
			}
		}
	}
	return 0.0;
}

void fragment() {
	vec3 n = normalize(sphere_dir);
	vec3 v = -normalize(source_dir);
	vec3 u = normalize(cross(v, abs(v.y) < 0.9 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
	vec3 w = cross(v, u);
	float r = acos(clamp(dot(n, v), -1.0, 1.0));
	float phi = atan(dot(n, w), dot(n, u));
	float lr = log(max(r, 1e-3));

	// Sky: four cel bands by height, their edges wobbling a little, calm darkening into storm.
	float h = n.y + (noise(vec2(phi * 3.0, n.y * 4.0) + vec2(shot_time * 0.05, 0.0)) - 0.5) * 0.12;
	vec3 top = mix(calm_top, storm_top, storm);
	vec3 high = mix(calm_high, storm_high, storm);
	vec3 low = mix(calm_low, storm_low, storm);
	vec3 deck = mix(calm_deck, storm_deck, storm);
	vec3 col = top;
	if (h < 0.4) col = high;
	if (h < 0.05) col = low;
	if (h < -0.3) col = deck;

	// Storm cloud bands streaming into the vanishing point at the ship's speed: dark violet masses,
	// grey-teal streaks between them. They thicken in with the storm and with the gusts.
	float hk = 7.0 / TAU;
	vec2 hp = vec2(phi * hk, (lr + travel * 0.5) * hk * 0.35);
	float band = noise_wrap(hp + vec2(0.0, shot_time * 0.1), 7.0) * 0.6
			+ noise_wrap(hp * vec2(2.0, 1.0) + vec2(3.7, 1.3), 14.0) * 0.4;
	float streak = noise_wrap(hp * vec2(2.0, 1.4) + vec2(9.1, shot_time * 0.07), 14.0);
	float thick = storm * (0.6 + 0.4 * gust);
	if (band > 1.0 - thick * 0.6) col = mix(col, cloud_dark, 0.6);
	if (band > 1.0 - thick * 0.35) col = cloud_dark;
	if (streak > 1.0 - thick * 0.3 && band < 1.0 - thick * 0.35) col = cloud_teal;

	// Flakes, carried by the wind, nearest layer last so it wins. Thinned out right at the vanishing
	// point, where the cells get too small to read. The snow comes in patches: thick clumps and thin
	// gaps drifting with the stream, gusts pushing thicker ones through.
	vec2 p = vec2(phi, lr);
	p += wind(p, gust);
	float fade = smoothstep(0.08, 0.25, r);
	float drift = (p.y + travel * 0.8);
	float clump = noise_wrap(vec2(p.x * 5.0 / TAU, drift * 1.2 + shot_time * 0.05), 5.0) * 0.65
			+ noise_wrap(vec2(p.x * 11.0 / TAU, drift * 2.6), 11.0) * 0.35;
	float dens = mix(0.32, 0.6, storm) * mix(0.15, 1.9, smoothstep(0.25, 0.75, clump + 0.15 * gust));
	float lit = flakes(p, 140.0, 0.5, 0.11, 1.3, 0.0, dens * 0.9, 4.0) * 0.5 * step(0.6, fade);
	float f = flakes(p, 90.0, 0.6, 0.1, 1.5, 0.0, dens * 0.8, 3.0) * step(0.5, fade);
	if (f != 0.0) lit = f * 0.7;
	f = flakes(p, 54.0, 0.8, 0.09, 2.0, 0.0, dens * 0.7, 2.0) * step(0.3, fade);
	if (f != 0.0) lit = f * 0.85;
	f = flakes(p, 30.0, 1.0, 0.08, 3.2, 1.0, dens * 0.55, 1.0) * step(0.2, fade);
	if (f != 0.0) lit = f;
	if (skimmers(n, u, w, v) > 0.5) lit = 1.0;
	// Cel: a few flat steps between the sky and white, no gradients.
	if (lit > 0.0) col = mix(col, flake_core, floor(lit * 4.0 + 0.5) / 4.0);
	if (lit < 0.0) col = mix(col, flake_shade, floor(-lit * (1.0 - 0.6 * storm) * 4.0 + 0.5) / 4.0);

	// Lightning washes everything to white.
	col = mix(col, lightning, clamp(flash, 0.0, 1.0) * 0.85);
	ALBEDO = col;
}
