shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, shadows_disabled;

// Re-entry fire on the inside of the cockpit's screen sphere: the outside feed of the plasma round
// the ship's nose. Anime cel fire, hard bands, no gradients. See docs/specs/cutscene-cockpit.md.
//
// Airflow over a ball: the flames are born at a hot point (`source_dir`, sphere space) and stream
// along the great circles from it to its antipode, so they fan out, curve round the sphere and meet
// again behind. All noise is sampled in (azimuth round the source, angle from the source), so the
// flow follows the sphere for free.
//
// Front-heavy: a white-hot core with a ragged shock front at the nose, and the fire cooling hard
// toward the tail, where it tears open on the wake (space and stars). `swallow` closes
// the wake again. On top, `drops` knock single panels of the wire grid out for a few frames.

uniform vec3 source_dir = vec3(-0.3, -0.3, 1.0);
// Radians of flow per second along the great circles.
uniform float flow_speed = 0.8;
// Radians the flow has travelled, integrated by ReentryFire so a change of speed never jumps it.
// Negative = not driven: fall back to TIME * flow_speed.
uniform float flow_phase = -1.0;
// Noise cells round the source (across the flow) and per radian along it. Across > along stretches
// the tongues along the flow.
uniform float across_scale = 9.0;
uniform float along_scale = 0.9;
// How much the fire cools from the hot point to the far side, in heat units at PI radians. The
// falloff goes with the angle squared, so the front stays hot and the tail drops away.
uniform float cooling = 1.0;
// Extra heat round the nose, fading out by `front_reach` radians.
uniform float front_heat = 0.12;
uniform float front_reach = 0.9;
// The white-hot core: radius in radians, and how ragged its edge is (share of the radius).
uniform float core_radius = 0.2;
uniform float core_ragged = 0.35;
// 1.0 = steady; driven by ReentryFire so the fill light flickers with the screen.
uniform float flicker = 1.0;
// Band thresholds, hot to cold. Below the last one is the dark gap colour, or space on the wake.
uniform vec4 thresholds = vec4(0.80, 0.62, 0.45, 0.30);
uniform vec3 white_hot : source_color = vec3(1.0, 0.96, 0.72);
uniform vec3 orange : source_color = vec3(1.0, 0.56, 0.12);
uniform vec3 red : source_color = vec3(0.82, 0.16, 0.05);
uniform vec3 dark_red : source_color = vec3(0.32, 0.04, 0.03);
uniform vec3 gap : source_color = vec3(0.09, 0.015, 0.015);

// The wake: from this angle off the source the gaps start showing space, fully by `wake_full`.
uniform float wake_start = 1.7;
uniform float wake_full = 2.2;
// 0..1, driven from the shot: the ship answering the push. The core spreads, the fire stops cooling
// and the wake closes.
uniform float swallow = 0.0;
uniform float swallow_core = 0.5;
// Heat the swallow adds, ramping in from `swallow_from` radians off the source to full on the wake,
// so it fills the tail without washing the front out.
uniform float swallow_heat = 0.35;
uniform float swallow_from = 1.0;

// Space behind the ship.
uniform vec3 space : source_color = vec3(0.008, 0.01, 0.025);
// Star cells per sphere radius, and the share of cells holding one.
uniform float star_scale = 70.0;
uniform float star_density = 0.012;

// Panel dropouts: one panel of the wire grid (segments x rings) each. x = segment, y = ring (0 at the
// top pole), z = kind (0 black, 1 no signal, 2 shifted), w = seconds it lasts. `drop_age` is the
// seconds since the event that threw them.
uniform int segments = 32;
uniform int rings = 16;
uniform vec4 drops[8];
uniform int drop_count = 0;
uniform float drop_age = -1.0;
uniform vec3 no_signal : source_color = vec3(0.25, 0.85, 0.95);

varying vec3 sphere_dir;

void vertex() {
	sphere_dir = VERTEX;
}

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)),
			dot(p, vec3(113.5, 271.9, 124.6)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

// Gradient noise, roughly -1..1.
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(dot(hash3(i + vec3(0, 0, 0)), f - vec3(0, 0, 0)),
						dot(hash3(i + vec3(1, 0, 0)), f - vec3(1, 0, 0)), u.x),
					mix(dot(hash3(i + vec3(0, 1, 0)), f - vec3(0, 1, 0)),
						dot(hash3(i + vec3(1, 1, 0)), f - vec3(1, 1, 0)), u.x), u.y),
			mix(mix(dot(hash3(i + vec3(0, 0, 1)), f - vec3(0, 0, 1)),
						dot(hash3(i + vec3(1, 0, 1)), f - vec3(1, 0, 1)), u.x),
					mix(dot(hash3(i + vec3(0, 1, 1)), f - vec3(0, 1, 1)),
						dot(hash3(i + vec3(1, 1, 1)), f - vec3(1, 1, 1)), u.x), u.y), u.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 4.1);
		a *= 0.5;
	}
	return v;
}

// What the gaps on the wake show: black space and still stars. (The ship flies at the planet, so
// Earth is ahead, under the fire, never behind.)
vec3 outside(vec3 n) {
	vec3 p = n * star_scale;
	vec3 cell = floor(p);
	vec3 h = hash3(cell) * 0.5 + 0.5;
	if (h.x < star_density) {
		vec3 centre = cell + 0.5 + (hash3(cell + 17.0) * 0.3);
		if (length(p - centre) < 0.12) return vec3(1.0);
	}
	return space;
}

// The whole feed in direction n (unit, sphere space).
vec3 feed(vec3 n) {
	vec3 s = normalize(source_dir);
	vec3 u = normalize(cross(s, abs(s.y) < 0.9 ? vec3(0, 1, 0) : vec3(1, 0, 0)));
	vec3 w = cross(s, u);
	float theta = acos(clamp(dot(n, s), -1.0, 1.0));
	float phi = atan(dot(n, w), dot(n, u));
	// The core: white inside a ragged edge that licks round the source.
	float rag = noise(vec3(cos(phi) * 4.0, sin(phi) * 4.0, TIME * 2.5));
	float core = core_radius * (1.0 + swallow_core * swallow) * (1.0 + core_ragged * rag);
	if (theta < core) return white_hot;
	// Round the source on a circle (seamless in phi), along the flow scrolling with time.
	float travelled = flow_phase >= 0.0 ? flow_phase : TIME * flow_speed;
	float along = theta * along_scale - travelled * along_scale;
	vec3 p = vec3(cos(phi) * across_scale, sin(phi) * across_scale, along);
	// Domain warp, itself scrolling a bit slower, so tongues lick and change shape as they travel.
	vec3 q = p + vec3(0.0, 0.0, TIME * 0.6);
	vec3 warp = vec3(fbm(q * 0.7), fbm(q * 0.7 + vec3(5.2, 1.3, 2.8)), 0.0) * 0.9;
	float tongues = fbm(p + warp);
	// Fine flicker on the edges: a small fast layer.
	float edge = noise(p * vec3(3.0, 3.0, 1.5) + vec3(0.0, 0.0, -TIME * 3.0)) * 0.08;
	float x = theta / PI;
	float heat = 0.66 + tongues * 0.85 + edge
			- cooling * x * x
			+ front_heat * (1.0 - smoothstep(0.0, front_reach, theta))
			+ swallow_heat * swallow * smoothstep(swallow_from, wake_full, theta);
	// Half strength on the screen: every band edge moves with it, so full strength pumps the whole field.
	heat += (flicker - 1.0) * 0.5;
	if (heat > thresholds.x) return white_hot;
	if (heat > thresholds.y) return orange;
	if (heat > thresholds.z) return red;
	if (heat > thresholds.w) return dark_red;
	float wake = smoothstep(wake_start, wake_full, theta) * (1.0 - swallow);
	// Only the coldest part of a gap tears through, and more of it the further down the wake.
	return wake > 0.0 && heat < thresholds.w - 0.12 - 0.25 * (1.0 - wake) ? outside(n) : gap;
}

void fragment() {
	vec3 n = normalize(sphere_dir);
	// Which panel of the wire grid this is (WireSphere's layout: longitude round +Y from +X toward +Z,
	// rings from the top pole).
	float lon = atan(n.z, n.x);
	if (lon < 0.0) lon += TAU;
	float lat = asin(clamp(n.y, -1.0, 1.0));
	float seg_w = TAU / float(segments);
	float ring_h = PI / float(rings);
	vec2 panel = vec2(floor(lon / seg_w), floor((PI * 0.5 - lat) / ring_h));
	int kind = -1;
	for (int i = 0; i < 8; i++) {
		if (i >= drop_count) break;
		if (drop_age >= 0.0 && drop_age < drops[i].w && panel == drops[i].xy) kind = int(drops[i].z);
	}
	vec3 col;
	if (kind == 0) {
		col = vec3(0.0);
	} else if (kind == 1) {
		col = no_signal;
	} else if (kind == 2) {
		// Its slice of the picture, slid most of a panel sideways and a little down.
		float lon2 = lon + seg_w * 0.6;
		float lat2 = lat - ring_h * 0.35;
		col = feed(vec3(cos(lat2) * cos(lon2), sin(lat2), cos(lat2) * sin(lon2)));
	} else {
		col = feed(n);
	}
	ALBEDO = col;
}
