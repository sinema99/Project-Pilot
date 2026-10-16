// The Earth for the intro cutscene planet (docs/specs/cutscene-intro-space.md, "Planet upgrade"):
// lat / lon on the unit sphere, the baked ETOPO1 crop, and the cloud field. Shared by
// planet_snow.gdshader (surface + cloud shadows) and planet_clouds.gdshader (the cloud shell) so
// a shadow always matches its cloud. Needs space_noise.gdshaderinc included first.
//
// The sphere's object space IS Earth space: +y = north (the spin axis), x = cos(lat) cos(lon),
// z = -cos(lat) sin(lon), longitude east-positive. tools/gen_planet_earth_frame.gd turns the
// planet so Florida sits under the ship.

// The crop tools/gen_planet_earth.gd baked: cell centres, north row first. Must match its input.
// 8 S-86 N / 180 W-32 W: widened north and west 2026-10-16 for the opening pan, which tilts down
// past Alaska, the Canadian Arctic and Greenland.
const float EARTH_LON_WEST = -180.0;
const float EARTH_LAT_NORTH = 86.0;
const float EARTH_CELL = 0.05;
const vec2 EARTH_TEXELS = vec2(2961.0, 1881.0);
const float EARTH_OCEAN_DEPTH = 6000.0;
const float EARTH_LAND_HEIGHT = 4500.0;

uniform sampler2D earth_map : filter_linear_mipmap, repeat_disable;

group_uniforms Clouds;
// Cloud edge: field values above this are cloud.
uniform float cloud_level : hint_range(0.0, 1.0) = 0.56;
// Noise frequency per degree. Higher = smaller clouds.
uniform float cloud_freq = 0.17;
// How much tighter the noise runs north-south than east-west: >1 lays the clouds out in streaks
// along the wind, which is what reads as cloud rather than more land from orbit.
uniform float cloud_stretch : hint_range(1.0, 4.0) = 2.4;
uniform float cloud_warp : hint_range(0.0, 4.0) = 1.6;
// Added to the whole field: lower = less cloud everywhere. The storm and bands sit on top.
uniform float cloud_cover : hint_range(-0.5, 0.5) = -0.055;
// Degrees of eastward drift; intro_space.gd sets it from the shot time.
uniform float cloud_drift = 0.0;
// Fine noise on the field so the cel edges chip instead of running smooth.
uniform float cloud_edge_noise : hint_range(0.0, 0.3) = 0.06;
// Atlantic bands: streaks running SW -> NE off the East Coast.
uniform float band_strength : hint_range(0.0, 1.0) = 0.38;
uniform float band_angle_deg = 32.0;
// Storm comma over Florida: the ship's dive ends inside it.
uniform vec2 storm_lat_lon = vec2(27.8, -81.7);
uniform float storm_radius_deg = 7.5;
uniform float storm_twist : hint_range(0.0, 12.0) = 5.0;
uniform float storm_strength : hint_range(0.0, 1.0) = 0.36;
group_uniforms;

// Storm layers (docs/specs/cutscene-intro-space.md, "Storm eye rebuild"), outside in: outer bands
// (the twirled arms above), inner rain bands, the moat, the eyewall and the eye. Radii are
// fractions of storm_radius_deg; every edge is torn by the same twirled noise as the clouds.
group_uniforms StormLayers;
uniform float storm_eye_radius : hint_range(0.0, 0.5) = 0.2;
uniform float storm_wall_radius : hint_range(0.0, 1.0) = 0.45;
// Inner rain bands start past the moat and fade out by storm_band_outer.
uniform float storm_band_inner : hint_range(0.0, 1.0) = 0.56;
uniform float storm_band_outer : hint_range(0.0, 1.5) = 1.05;
// Radians of turn per unit of log radius; 2.6 matches the outer arm.
uniform float storm_band_pitch = 2.6;
// How wide the bands are (0 = threads, 1 = solid) and how much the noise tears them.
uniform float storm_band_fill : hint_range(0.0, 1.0) = 0.55;
uniform float storm_band_tear : hint_range(0.0, 2.0) = 0.9;
// The low grey deck everything else sits on.
uniform float storm_deck_radius : hint_range(0.0, 1.5) = 0.9;
// Degrees the eyewall and the inner bands have turned counter-clockwise from above; intro_space.gd
// sets them from shot time. The outer bands never turn.
uniform float storm_spin_wall = 0.0;
uniform float storm_spin_band = 0.0;
group_uniforms;

// Layers cloud_layers() reports. Heights are in storm_height().
const int STORM_NONE = 0;
const int STORM_DECK = 1;
const int STORM_CLOUD = 2;
const int STORM_WALL = 3;
const int STORM_EYE = 4;

// How high a layer sits: a layer casts a shadow on anything lower. The eye is the bottom of the pit.
float storm_height(int layer) {
	return layer == STORM_EYE ? 0.5 : float(layer);
}

vec2 earth_lat_lon(vec3 e) {
	e = normalize(e);
	return degrees(vec2(asin(clamp(e.y, -1.0, 1.0)), atan(-e.z, e.x)));
}

vec3 earth_dir(vec2 lat_lon) {
	vec2 r = radians(lat_lon);
	return vec3(cos(r.x) * cos(r.y), sin(r.x), -cos(r.x) * sin(r.y));
}

// Texture coordinate of a lat / lon in the crop. Outside 0..1 = off the crop.
vec2 earth_uv(vec2 ll) {
	vec2 cell = vec2(ll.y - EARTH_LON_WEST, EARTH_LAT_NORTH - ll.x) / EARTH_CELL;
	return (cell + 0.5) / EARTH_TEXELS;
}

bool earth_in_crop(vec2 uv) {
	return all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)));
}

// Metres above (+) or below (-) sea level, from the signed square root in R.
float earth_elevation(vec4 texel) {
	float s = texel.r * 2.0 - 1.0;
	return s >= 0.0 ? s * s * EARTH_LAND_HEIGHT : -s * s * EARTH_OCEAN_DEPTH;
}

// Angular distance in degrees, good enough at these sizes (x shrunk by cos(lat)).
vec2 earth_local_deg(vec2 ll, vec2 centre) {
	return vec2((ll.y - centre.y) * cos(radians(centre.x)), ll.x - centre.x);
}

// Position in the storm's frame (degrees east / north of the eye), from a drifted lat / lon. The
// frame never turns; the eyewall and inner bands turn inside it (storm_spin_*). The lightning
// flashes live in this frame. Must match intro_space.gd::storm_local().
vec2 earth_storm_local(vec2 ll) {
	return earth_local_deg(ll, storm_lat_lon);
}

mat2 earth_rot(float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

// Degrees the storm has turned at storm radius `sr` (fraction of storm_radius_deg): the eyewall's
// turn inside the moat, the bands' turn out to the deck edge, none past the outer bands.
float storm_spin_at(float sr) {
	float wall = 1.0 - smoothstep(storm_wall_radius, storm_band_inner + 0.05, sr);
	return mix(storm_spin_band, storm_spin_wall, wall) * (1.0 - smoothstep(0.9, 1.3, sr));
}

// The cloud field at Earth direction `e`, about 0..1; cloud where it is above cloud_level.
// `layer` says which storm layer is on top there (STORM_*). `storm` = (radius as a fraction of
// storm_radius_deg, the torn eye edge, 1 inside the storm's deck else 0, the tear noise about
// -0.5..0.5).
// Clouds only live inside the crop (the only part the camera sees).
float cloud_layers(vec3 e, out int layer, out vec4 storm) {
	layer = STORM_NONE;
	storm = vec4(99.0, 0.0, 0.0, 0.0);
	vec2 ll = earth_lat_lon(e);
	ll.y -= cloud_drift;
	if (!earth_in_crop(earth_uv(ll))) {
		return 0.0;
	}

	// Storm comma: twirl the noise around the centre, tighter toward the eye, plus one spiral arm.
	// The inside turns (eyewall faster than the bands) by sampling everything at a turned-back point.
	vec2 s0 = earth_storm_local(ll);
	float sr = length(s0) / storm_radius_deg;
	vec2 s = earth_rot(-radians(storm_spin_at(sr))) * s0;
	float env = exp(-sr * sr * 1.6);
	float twirl = storm_twist * env;
	vec2 sw = earth_rot(twirl) * s;
	vec2 sll = vec2(storm_lat_lon.x + sw.y, storm_lat_lon.y + sw.x / cos(radians(storm_lat_lon.x)));
	vec3 p = vec3(sll.y * cloud_freq, sll.x * cloud_freq * cloud_stretch, 0.37);

	vec3 w = vec3(space_fbm(p + vec3(3.1, 7.7, 1.3), 3), space_fbm(p + vec3(9.2, 2.4, 5.8), 3),
			space_fbm(p + vec3(5.5, 4.1, 8.6), 3)) - 0.5;
	float n = space_fbm(p + w * cloud_warp, 5);
	float field = n + cloud_cover;

	float ang = atan(s.y, s.x);
	float lr = log(max(sr, 0.05));
	float arm = smoothstep(0.55, 0.95, cos(ang + lr * 2.6)) * smoothstep(1.6, 0.4, sr);
	// The old solid fill is gone from the inside: the deck, bands and eyewall own it now.
	float outer = smoothstep(storm_band_outer - 0.35, storm_band_outer + 0.1, sr);
	field += storm_strength * (env * outer + arm * 0.7 * outer);

	// Atlantic bands: noise stretched along a SW -> NE line, only over the western Atlantic.
	float ba = radians(band_angle_deg);
	vec2 b = earth_local_deg(ll, vec2(32.0, -68.0));
	vec2 bd = vec2(cos(ba) * b.x + sin(ba) * b.y, -sin(ba) * b.x + cos(ba) * b.y);
	float band = space_fbm(vec3(bd.x * 0.07, bd.y * 0.55, 3.7), 4);
	float atlantic = smoothstep(-79.0, -71.0, ll.y) * smoothstep(21.0, 27.0, ll.x);
	field += atlantic * (band - 0.45) * band_strength * 2.0;

	float fine = (space_noise(p * 9.0) - 0.5) * cloud_edge_noise;
	field += fine;
	layer = field > cloud_level ? STORM_CLOUD : STORM_NONE;
	if (sr > 1.6) {
		return field;
	}

	// The layers, each edge torn by the twirled noise plus a finer swirled octave of it.
	float tear = n - 0.5 + (space_fbm(p * 3.1 + w, 3) - 0.5) * 0.7 + fine;
	// Three rain bands, wound like the outer arm, widest in the middle of their run.
	float spiral = cos(3.0 * (ang + lr * storm_band_pitch)) * 0.5 + 0.5;
	float eye_edge = storm_eye_radius * (1.0 + tear * 0.45);
	// The bands feed into the eyewall, so its rim bulges out where each one meets it.
	float wall_edge = storm_wall_radius * (1.0 + tear * 0.9 + (spiral - 0.5) * 0.3);
	float deck_edge = storm_deck_radius * (1.0 + tear * 1.1);
	float inner_edge = storm_band_inner * (1.0 + tear * 0.4);
	float run = smoothstep(inner_edge, inner_edge + 0.1, sr) * smoothstep(storm_band_outer, storm_band_outer - 0.2, sr);
	bool rain_band = spiral * run + tear * storm_band_tear > 1.0 - storm_band_fill;
	storm = vec4(sr, eye_edge, sr < deck_edge ? 1.0 : 0.0, tear);
	if (sr < eye_edge) {
		layer = STORM_EYE;
	} else if (sr < wall_edge) {
		layer = STORM_WALL;
	} else if (sr > inner_edge && (rain_band || layer == STORM_CLOUD)) {
		layer = STORM_CLOUD;
	} else if (sr < deck_edge) {
		layer = STORM_DECK;
	}
	return max(field, cloud_level + (deck_edge - sr) * 0.5);
}

float cloud_field(vec3 e) {
	int layer;
	vec4 storm;
	return cloud_layers(e, layer, storm);
}

// Unit tangent on the sphere at `e` pointing toward light direction `l` (both object space).
vec3 earth_toward(vec3 e, vec3 l) {
	vec3 t = l - e * dot(l, e);
	return length(t) > 1e-5 ? normalize(t) : vec3(0.0);
}
