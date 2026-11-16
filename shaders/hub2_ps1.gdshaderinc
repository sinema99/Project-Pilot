// hub2's PS1 pass (docs/specs/hub2-ps1-mood.md): banded depth fog and static sodium light pools,
// shared by the surface and decal shaders. Both shaders use `fog_disabled` and add the fog and the
// pools themselves as EMISSION, so every step is a flat band and the two agree. The scene's own
// Environment fog (resources/hub2_environment.tres) carries the same colour and range for anything
// that is not one of these two materials (the characters, props).

uniform vec3 fog_tint : source_color = vec3(0.075, 0.14, 0.19);
uniform float fog_begin = 20.0;
uniform float fog_end = 95.0;
// How many flat bands the fog is cut into (PS1 depth cue is coarse).
uniform float fog_steps = 0.0;   // 0 = smooth gradient

// Light pools: one lamp may sit in each 26 m cell of the world, hashed, so pools scatter through the
// whole structure with nothing to author. Each is a stepped falloff on surfaces that face it.
uniform float pool_cell = 14.0;
uniform float pool_radius = 8.5;
uniform float pool_chance = 0.45;
uniform float pool_steps = 0.0;   // 0 = smooth gradient; >0 = that many flat bands
uniform float pool_strength = 0.0;   // OFF: floating lamps read as random discs on walls (2026-11-13)
uniform vec3 pool_sodium : source_color = vec3(1.0, 0.52, 0.16);
uniform vec3 pool_red : source_color = vec3(1.0, 0.16, 0.10);
uniform vec3 pool_cold : source_color = vec3(0.25, 0.75, 0.9);

// Fixture pools (docs/specs/hub2-storage.md): the dressing generator places lamp props and
// Hub2LampPools writes every lit one here, so these pools sit under real fixtures. xyz = lamp
// point, w = radius; colour rgb = tint, a = strength. Independent of pool_strength (the hashed pools).
#define LAMP_MAX 160
uniform int lamp_count = 0;
uniform vec4 lamp_pos[LAMP_MAX];
uniform vec4 lamp_col[LAMP_MAX];

// Roof-door snow (docs/specs/hub2-roof-door.md): Hub2RoofDoor bakes a top-down height map of what the
// open sky sees through the roof gap and hands it here. A surface that faces up and sits on that top
// surface, inside `snow_core` (world x0, z0, x1, z1: the sky gap) plus a fade of `snow_fade` metres,
// is under snow. snow_map_rect (x0, z0, x1, z1) is where the map sits; all zero = no snow anywhere.
uniform sampler2D snow_map : filter_nearest, repeat_disable;
uniform vec4 snow_map_rect = vec4(0.0);
uniform vec4 snow_core = vec4(0.0);
uniform float snow_fade = 4.0;
uniform vec3 snow_color : source_color = vec3(0.80, 0.86, 0.94);

// 0..1 how much snow lies on a surface at world point p facing n.
float ps1_snow(vec3 p, vec3 n) {
	if (snow_map_rect.z <= snow_map_rect.x) {
		return 0.0;
	}
	vec2 uv = (p.xz - snow_map_rect.xy) / (snow_map_rect.zw - snow_map_rect.xy);
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return 0.0;
	}
	float h = texture(snow_map, uv).r;
	float on_top = 1.0 - smoothstep(0.25, 0.6, abs(p.y - h));
	vec2 d = max(snow_core.xy - p.xz, p.xz - snow_core.zw);
	float outside = max(max(d.x, d.y), 0.0);
	return on_top * smoothstep(0.55, 0.85, n.y) * clamp(1.0 - outside / snow_fade, 0.0, 1.0);
}

// Edge dusting (docs/specs/hub2-roof-door.md rev 1): drop edges looking out into the open shaft get a
// patchy snow strip even where no sky is straight above. snow_edge_zone (world x0, z0, x1, z1) is where
// it is full; it thins out over snow_edge_fade (x, z) metres past that, and with depth below
// snow_edge_top down to snow_edge_deep (x = metres down, y = what is left there). All zero = off.
uniform vec4 snow_edge_zone = vec4(0.0);
uniform vec2 snow_edge_fade = vec2(2.0, 15.0);
uniform float snow_edge_top = 0.0;
uniform vec2 snow_edge_deep = vec2(150.0, 0.35);
// Where the real drops are: Hub2RoofDoor.bake_edges() finds up to four floor levels per cell over
// snow_edge_rect (world x0, z0, x1, z1): snow_edge_heights rgba = their heights (-1000 = none),
// snow_edge_dists rgba = metres from each to the nearest drop edge on that level (capped at 1.5).
uniform sampler2D snow_edge_heights : filter_nearest, repeat_disable;
uniform sampler2D snow_edge_dists : filter_nearest, repeat_disable;
uniform vec4 snow_edge_rect = vec4(0.0);

// Metres from p to the nearest drop edge on its own level, or 99 when unknown.
float ps1_edge_dist(vec3 p) {
	if (snow_edge_rect.z <= snow_edge_rect.x) {
		return 99.0;
	}
	vec2 uv = (p.xz - snow_edge_rect.xy) / (snow_edge_rect.zw - snow_edge_rect.xy);
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return 99.0;
	}
	// Bilinear, but each texel only gives the level matching p, so a drop's low side never bleeds
	// into its lip.
	ivec2 sz = textureSize(snow_edge_heights, 0);
	vec2 f = uv * vec2(sz) - 0.5;
	ivec2 b = ivec2(floor(f));
	vec2 t = f - vec2(b);
	float sum = 0.0;
	float wsum = 0.0;
	for (int k = 0; k < 4; k++) {
		ivec2 o = ivec2(k & 1, k >> 1);
		ivec2 q = clamp(b + o, ivec2(0), sz - 1);
		vec4 hs = texelFetch(snow_edge_heights, q, 0);
		vec4 ds = texelFetch(snow_edge_dists, q, 0);
		vec4 match = step(abs(hs - vec4(p.y)), vec4(0.35));
		float m = max(max(match.x, match.y), max(match.z, match.w));
		if (m < 0.5) {
			continue;
		}
		float d = match.x > 0.5 ? ds.x : (match.y > 0.5 ? ds.y : (match.z > 0.5 ? ds.z : ds.w));
		float w = (o.x == 1 ? t.x : 1.0 - t.x) * (o.y == 1 ? t.y : 1.0 - t.y);
		sum += d * w;
		wsum += w;
	}
	return wsum > 0.0001 ? sum / wsum : 99.0;
}

// 0..1 how much edge dusting a point gets (before it is shaped into a strip by the edge distance).
float ps1_edge_snow_zone(vec3 p) {
	if (snow_edge_zone.z <= snow_edge_zone.x || p.y > snow_edge_top) {
		return 0.0;
	}
	vec2 d = max(snow_edge_zone.xy - p.xz, p.xz - snow_edge_zone.zw);
	d = max(d, vec2(0.0));
	vec2 r = clamp(d / snow_edge_fade, 0.0, 1.0);
	float k = (1.0 - r.x * r.x) * (1.0 - r.y * r.y);
	float deep = clamp((snow_edge_top - p.y) / snow_edge_deep.x, 0.0, 1.0);
	return k * mix(1.0, snow_edge_deep.y, deep);
}

float ps1_hash(vec3 c, float salt) {
	uvec3 q = uvec3(ivec3(c) + ivec3(4096));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u ^ q.z * 2654435769u ^ uint(salt * 7919.0);
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return float(h) / 4294967295.0;
}

// 0..1 banded fog amount at a view distance.
float ps1_fog(float dist) {
	float f = clamp((dist - fog_begin) / (fog_end - fog_begin), 0.0, 1.0);
	// fog_steps 0 = smooth gradient (2026-11-15, user); > 0 = that many flat bands.
	return fog_steps > 0.0 ? floor(f * fog_steps + 0.5) / fog_steps : f;
}

// Summed, stepped light from the fixture list at world point p on a surface facing n.
vec3 ps1_lamps(vec3 p, vec3 n) {
	vec3 total = vec3(0.0);
	for (int i = 0; i < lamp_count; i++) {
		vec3 to = lamp_pos[i].xyz - p;
		float d = length(to);
		float k = 1.0 - d / lamp_pos[i].w;
		if (k <= 0.0) {
			continue;
		}
		float facing = clamp(dot(n, to / max(d, 0.001)) * 0.6 + 0.4, 0.0, 1.0);
		// Fixtures shine down: nothing above the lamp (ceilings, upper walls) gets a pool.
		float below = clamp(to.y / max(d, 0.001) * 2.0 + 0.3, 0.0, 1.0);
		// Floors only (2026-11-14 review): pools on walls read as flat painted ovals.
		float up = smoothstep(0.55, 0.85, n.y);
		k = clamp(k * facing * below * up, 0.0, 1.0);
		// Smooth gradient (2026-11-15, user): eased falloff, no flat steps. pool_steps > 0 brings them back.
		k = pool_steps > 0.0 ? floor(k * pool_steps + 0.5) / pool_steps : k * k * (3.0 - 2.0 * k);
		total += lamp_col[i].rgb * lamp_col[i].a * k;
	}
	return min(total, vec3(1.0));
}

// Summed, stepped lamp colour at world point p on a surface facing n.
vec3 ps1_pools(vec3 p, vec3 n) {
	vec3 lamps = lamp_count > 0 ? ps1_lamps(p, n) : vec3(0.0);
	if (pool_strength <= 0.0) {
		return lamps;
	}
	vec3 base = floor(p / pool_cell);
	vec3 total = vec3(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 c = base + vec3(float(x), float(y), float(z));
				if (ps1_hash(c, 1.0) > pool_chance) {
					continue;
				}
				vec3 lamp = (c + vec3(0.2 + 0.6 * ps1_hash(c, 2.0), 0.2 + 0.6 * ps1_hash(c, 3.0), 0.2 + 0.6 * ps1_hash(c, 4.0))) * pool_cell;
				vec3 to = lamp - p;
				float d = length(to);
				float k = 1.0 - d / pool_radius;
				if (k <= 0.0) {
					continue;
				}
				float facing = clamp(dot(n, to / max(d, 0.001)) * 0.6 + 0.4, 0.0, 1.0);
				k = clamp(k * facing, 0.0, 1.0);
				k = pool_steps > 0.0 ? floor(k * pool_steps + 0.5) / pool_steps : k * k * (3.0 - 2.0 * k);
				float t = ps1_hash(c, 5.0);
				vec3 tint = t < 0.78 ? pool_sodium : (t < 0.9 ? pool_red : pool_cold);
				total += tint * k;
			}
		}
	}
	return min(total, vec3(1.0)) * pool_strength + lamps;
}
