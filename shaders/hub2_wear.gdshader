// hub2's industrial surface. See docs/specs/hub2-industrial.md.
//
// No UVs and no textures: the world position is cut into texels_per_metre square pixels (16, the
// Jetpack grid), projected along the dominant axis of the face normal. What a face looks like
// depends on which way it points:
//   walls   - big steel / concrete panels (6 x 3 m) with seams, rivets, plate lines and grime
//             streaks hanging below each horizontal seam;
//   floors  - diamond-tread deck plating in 3 m plates, worn lighter along walkways;
//   ceilings / undersides - dark ribbed steel, the dirtiest.
// Where the wear goes comes from the mesh, baked offline by tools/bake_hub2_wear.gd: CUSTOM0 is the
// signed distance in metres to four lines near the face and CUSTOM1 what each is (1 convex edge,
// 2 concave crease, 3 seam where one piece of the map goes into another).
//   convex  - dark band along the edge with ragged chips of dull bare metal and a few bigger bites;
//   concave - stepped dark grime in the crease and rust creeping out of it;
//   corner  - extra dark where two lines are near at once.
// Low parts of the structure rust and darken (ground_y up).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled, fog_disabled;

#include "res://shaders/hub2_ps1.gdshaderinc"

uniform float detail_fade_begin = 2.5;
uniform float detail_fade_end = 6.0;
uniform float texels_per_metre = 16.0;
// World height of the structure's lowest point; grime and rust fade out over grime_height above it.
uniform float ground_y = 0.0;
uniform float grime_height = 14.0;

uniform vec3 steel_color : source_color = vec3(0.50, 0.46, 0.41);
uniform vec3 concrete_color : source_color = vec3(0.55, 0.50, 0.43);
uniform vec3 paint_teal : source_color = vec3(0.30, 0.42, 0.37);
uniform vec3 paint_oxide : source_color = vec3(0.45, 0.22, 0.16);
uniform vec3 deck_color : source_color = vec3(0.47, 0.43, 0.39);
uniform vec3 under_color : source_color = vec3(0.33, 0.30, 0.27);
uniform vec3 bare_metal : source_color = vec3(0.34, 0.35, 0.37);
uniform vec3 grime_color : source_color = vec3(0.045, 0.045, 0.05);
uniform vec3 rust_dark : source_color = vec3(0.22, 0.10, 0.05);
uniform vec3 rust_light : source_color = vec3(0.40, 0.19, 0.08);
// 0 = clean, 1 = as filthy as designed.
uniform float wear : hint_range(0.0, 1.5) = 1.0;
// Props only (the map keeps the defaults): force_paint 1 = wall faces take oxide below force_split_y and teal
// above, tone multiplies the base colour (a door leaf a shade darker than the wall round it).
uniform int force_paint = 0;
// Props only: 1 = wall faces are always the plain grey steel (no zone paint), e.g. the control-room door + frame.
uniform int force_steel = 0;
uniform float force_split_y = 45.0;
uniform float tone : hint_range(0.0, 1.5) = 1.0;

// Moving props (the sliding door leaf): world-space shift of the prop since it was at rest, subtracted so
// the pattern rides with the mesh instead of sliding across it.
uniform vec3 pos_offset = vec3(0.0);

varying vec3 v_pos;
varying vec3 v_norm;
varying vec4 v_d;
varying vec4 v_c;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - pos_offset;
	v_norm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_d = CUSTOM0;
	v_c = CUSTOM1;
}

float cell_hash(ivec2 c, int axis, uint salt) {
	uint h = uint(c.x) * 1597334677u ^ uint(c.y) * 3812015801u ^ uint(axis + 1) * 2654435769u ^ salt;
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return float(h) / 4294967295.0;
}

float vnoise(vec2 texel_centre, vec2 size, int axis, uint salt) {
	vec2 q = texel_centre / size;
	vec2 i = floor(q);
	vec2 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	ivec2 c = ivec2(i);
	float a = cell_hash(c, axis, salt);
	float b = cell_hash(c + ivec2(1, 0), axis, salt);
	float d = cell_hash(c + ivec2(0, 1), axis, salt);
	float e = cell_hash(c + ivec2(1, 1), axis, salt);
	return mix(mix(a, b, f.x), mix(d, e, f.x), f.y);
}

// n shades between lo and hi from a 0..1 value.
float stepped(float f, float n, float lo, float hi) {
	float idx = clamp(floor(clamp(f, 0.0, 0.999) * n), 0.0, n - 1.0);
	return mix(lo, hi, idx / (n - 1.0));
}

void fragment() {
	vec3 nn = normalize(v_norm);
	vec3 an = abs(nn);
	vec2 coord;
	int axis;
	if (an.y >= an.x && an.y >= an.z) {
		coord = v_pos.xz;
		axis = 1;
	} else if (an.x >= an.z) {
		coord = vec2(v_pos.z, -v_pos.y);
		axis = 0;
	} else {
		coord = vec2(v_pos.x, -v_pos.y);
		axis = 2;
	}
	coord *= texels_per_metre;
	vec2 texel = floor(coord);
	vec2 centre = texel + 0.5;
	ivec2 ti = ivec2(texel);
	float px = 1.0 / texels_per_metre;

	bool is_floor = nn.y > 0.6;
	bool is_ceil = nn.y < -0.6;
	float w = wear;

	// -- the lines the bake found near this face ----------------------------------------------
	float d_cx = 99.0;
	float d_cc = 99.0;
	float m1 = 99.0;
	float m2 = 99.0;
	for (int i = 0; i < 4; i++) {
		float c = floor(v_c[i] + 0.5);
		if (c < 0.5) {
			continue;
		}
		float d = v_d[i];
		if (c > 2.5) {
			d = abs(d);
		} else if (d < -0.2) {
			continue;
		}
		d = max(d, 0.0);
		if (c < 1.5) {
			d_cx = min(d_cx, d);
		} else {
			d_cc = min(d_cc, d);
		}
		if (d < m1) {
			m2 = m1;
			m1 = d;
		} else if (d < m2) {
			m2 = d;
		}
	}
	float corner = 1.0 - smoothstep(0.0, 0.7, m2);

	// -- base finish -------------------------------------------------------------------------
	float clump = 0.65 * vnoise(centre, vec2(3.0), axis, 0x9e37u) + 0.35 * vnoise(centre, vec2(1.5), axis, 0x51edu);
	clump = clamp((clump - 0.5) * 2.2 + 0.5, 0.0, 0.999);
	float shade = stepped(clump, 4.0, 0.9, 1.07);
	if (cell_hash(ti, axis, 0x2c1bu) < 0.08) {
		shade *= cell_hash(ti, axis, 0x7f4au) < 0.5 ? 0.94 : 1.05;
	}
	vec3 base;
	float streak_ly = -1.0;
	float streak_row = 0.0;
	float seam_hi = 1.0;
	if (is_floor) {
		vec2 plate = floor(coord / 48.0);
		vec2 l = coord - plate * 48.0;
		float ph = cell_hash(ivec2(plate), axis, 0x61a3u);
		base = deck_color * (0.93 + ph * 0.12);
		// Diamond tread: 8 texel cells, a tick along alternating diagonals.
		vec2 cl = mod(floor(l), 8.0);
		bool even = mod(floor(l.x / 8.0) + floor(l.y / 8.0), 2.0) < 0.5;
		bool tick = even ? abs(cl.x - cl.y) < 1.5 : abs(cl.x + cl.y - 7.0) < 1.5;
		if (tick) {
			shade *= 1.14;
		} else if ((even ? abs(cl.x - cl.y) : abs(cl.x + cl.y - 7.0)) < 2.5) {
			shade *= 0.9;
		}
		// Plate seams and corner bolts.
		if (l.x < 1.0 || l.y < 1.0) {
			shade *= 0.5;
		} else if (l.x < 2.0 || l.y < 2.0) {
			shade *= 1.1;
		}
		if (floor(l.x) == 3.0 && floor(l.y) == 3.0) {
			shade *= 1.3;
		}
		// Walkways wear lighter.
		float lane = vnoise(centre, vec2(70.0, 9.0), axis, 0x3a77u) * 0.6 + vnoise(centre, vec2(9.0, 70.0), axis, 0x1f43u) * 0.4;
		base *= 1.0 + 0.16 * smoothstep(0.55, 0.8, lane) * min(w, 1.0);
	} else if (is_ceil) {
		vec2 rib = floor(coord / 32.0);
		vec2 l = coord - rib * 32.0;
		base = under_color * (0.9 + 0.1 * cell_hash(ivec2(rib), axis, 0x4b1du));
		if (l.x < 2.0) {
			shade *= 0.55;
		} else if (l.x < 3.0) {
			shade *= 1.12;
		}
		if (l.y < 1.0) {
			shade *= 0.7;
		}
	} else {
		// Zones of steel and concrete, 30 x 15 m; panels 6 x 3 m inside.
		vec2 zone = floor(coord / vec2(480.0, 240.0));
		float zh = cell_hash(ivec2(zone), axis, 0x77c5u);
		vec3 mat = zh > 0.62 ? concrete_color : steel_color;
		// Some steel zones are painted: teal or oxide red, so the big walls stop being one colour.
		float zp = cell_hash(ivec2(zone), axis, 0x3d51u);
		if (zh <= 0.62) {
			mat = zp < 0.16 ? paint_oxide : (zp < 0.34 ? paint_teal : mat);
		}
		// A prop that has to read as part of one particular painted wall (the control-room bulkhead): fixed
		// oxide below force_split_y, teal above it, whatever zone the prop's own position falls in. Only on
		// faces that point east (+X, the corridor): the west face is the control-room stub, which keeps its own
		// zone paint, and the thin edge / reveal faces keep theirs too.
		if (force_steel > 0) {
			mat = steel_color;
		}
		if (force_paint > 0 && nn.x > 0.5) {
			mat = v_pos.y < force_split_y ? paint_oxide : paint_teal;
		}
		vec2 panel = floor(coord / vec2(96.0, 48.0));
		vec2 l = coord - panel * vec2(96.0, 48.0);
		float ph = cell_hash(ivec2(panel), axis, 0x2e19u);
		base = mat * (0.9 + ph * 0.18);
		// Seams: dark line, lit lip next to it.
		if (l.x < 1.0 || l.y < 1.0) {
			shade *= 0.5;
		} else if (l.x < 2.0 || l.y < 2.0) {
			shade *= 1.1;
		}
		// Plates: faint lines every 1.5 m.
		vec2 pl = mod(floor(l), 24.0);
		if (pl.x == 0.0 || pl.y == 0.0) {
			shade *= 0.93;
		}
		// Rivets along the seams, every 12 texels.
		bool rivet_v = (floor(l.x) == 3.0 || floor(l.x) == 92.0) && mod(floor(l.y), 12.0) == 6.0;
		bool rivet_h = floor(l.y) == 3.0 && mod(floor(l.x), 12.0) == 6.0;
		if (rivet_v || rivet_h) {
			shade *= 1.3;
		}
		streak_ly = l.y;
		streak_row = panel.y;
	}
	// Big soft mottling, 20 m blotches.
	float blotch = vnoise(centre, vec2(320.0), axis, 0x5d11u);
	base *= 0.88 + 0.2 * stepped(blotch, 3.0, 0.0, 1.0) * 0.6 + 0.04;
	base *= tone;
	vec3 col = base * shade;
	vec3 flat_col = base * 0.95;

	float rough = 0.5 * vnoise(centre, vec2(6.0), axis, 0xa51du) + 0.3 * vnoise(centre, vec2(2.5), axis, 0x3b7du)
		+ 0.2 * cell_hash(ti, axis, 0x6d21u);

	// -- height: the low parts of the structure are filthier ----------------------------------------
	float low = 1.0 - smoothstep(0.0, grime_height, v_pos.y - ground_y);

	// -- concave creases and seams: stepped dark grime, rust creeping out ---------------------------
	float cc_w = 0.9 + 0.6 * low;
	float crease = 1.0 - smoothstep(0.0, cc_w, d_cc + (0.5 - rough) * 0.5);
	crease = stepped(crease, 4.0, 0.0, 1.0) * min(w, 1.0);
	col = mix(col, grime_color, crease * 0.75);
	float rust_pot = crease * 0.4 + low * 0.35 + (is_ceil ? 0.25 : 0.0) + (rough - 0.5) * 0.9;
	float rust = step(0.88 - 0.25 * w, rust_pot) * min(w, 1.0);
	float rust_tone = vnoise(centre, vec2(4.0), axis, 0x1e5fu) * 0.7 + cell_hash(ti, axis, 0x4c3bu) * 0.3;
	col = mix(col, mix(rust_dark, rust_light, stepped(rust_tone, 4.0, 0.0, 1.0)), rust);

	// -- convex edges: dark band, ragged chips of bare metal, a few bigger bites ----------------------
	float band = 1.0 - smoothstep(0.0, 0.32, d_cx);
	band = stepped(band, 3.0, 0.0, 1.0) * min(w, 1.0);
	col *= mix(1.0, 0.55, band);
	if (w > 0.0) {
		float chip_w = px * (0.6 + 1.8 * vnoise(centre, vec2(3.0), axis, 0x44c1u)) * (1.0 + 1.5 * corner);
		chip_w *= 0.7 + 0.6 * cell_hash(ti, axis, 0x91f3u);
		float gap = vnoise(centre, vec2(2.0), axis, 0x0b17u);
		if (d_cx < chip_w && gap > 0.45) {
			col = bare_metal * (0.75 + 0.35 * cell_hash(ti, axis, 0x88a1u));
		}
		float bite_n = vnoise(centre, vec2(5.0), axis, 0x7e23u) + corner * 0.25;
		float bite = px * 6.0 * smoothstep(0.72, 0.95, bite_n) * min(w, 1.0);
		if (d_cx < bite) {
			col = d_cx < bite * 0.5 ? rust_dark : bare_metal * (0.7 + 0.3 * cell_hash(ti, axis, 0x5e1bu));
		}
	}
	// Corners where two lines meet: darker still.
	col *= 1.0 - 0.35 * stepped(corner, 3.0, 0.0, 1.0) * min(w, 1.0);

	// -- walls: grime streaks hanging below each horizontal seam ----------------------------------
	if (streak_ly >= 0.0 && w > 0.0) {
		ivec2 column = ivec2(int(texel.x), int(streak_row));
		float on = cell_hash(column, axis, 0x2f61u);
		float len = 5.0 + 34.0 * cell_hash(column, axis, 0x6a5bu);
		if (on > 0.84 - 0.1 * w && streak_ly < len && streak_ly > 1.5) {
			float k = 1.0 - streak_ly / len;
			col = mix(col, cell_hash(ti, axis, 0x13c9u) < 0.3 ? rust_dark : grime_color, 0.5 * k * min(w, 1.0));
		}
	}
	// Whole low-down grime on everything.
	col = mix(col, grime_color, low * 0.35 * (0.6 + 0.4 * rough) * min(w, 1.0));

	// Where a texel shrinks below a screen pixel, settle to the plain tone (no shimmer far off).
	// The two uniforms are texels per screen pixel: bigger = the pattern holds out further.
	vec2 fw = fwidth(coord);
	float tiny = smoothstep(detail_fade_begin, detail_fade_end, max(fw.x, fw.y));
	col = mix(col, flat_col * 0.8, tiny);

	// -- roof-door snow: white cover on what the open sky sees, broken at the edge, old finish through thin spots
	float snow = ps1_snow(v_pos, nn);
	if (snow > 0.0) {
		float edge_n = vnoise(centre, vec2(4.0), axis, 0x51a1u) * 0.7 + cell_hash(ti, axis, 0x77b3u) * 0.3;
		float amt = snow * 1.35 - edge_n * 0.55 + 0.05;
		bool thin = vnoise(centre, vec2(2.5), axis, 0x2d9fu) > 0.9;
		if (amt > 0.45 && !thin) {
			float lump = stepped(vnoise(centre, vec2(6.0), axis, 0x4e7bu), 3.0, 0.9, 1.0);
			col = snow_color * lump * (amt > 0.7 ? 1.0 : 0.86);
		}
	}
	// -- edge dusting (rev 1): a broken strip along drop edges that look out into the open shaft,
	// 30-60 cm wide, thinning into specks further in; the floor shows through the gaps.
	float ze = is_floor ? ps1_edge_snow_zone(v_pos) : 0.0;
	if (ze > 0.0) {
		float ed = ps1_edge_dist(v_pos);
		float ez = ze;
		if (ed < 1.4) {
			float width = (0.3 + 0.45 * vnoise(centre, vec2(18.0), axis, 0x6b2du)) * (0.7 + 0.3 * ez);
			float strip = 1.0 - ed / width;
			float patch = vnoise(centre, vec2(9.0), axis, 0x3c8fu) * 0.5 + vnoise(centre, vec2(3.0), axis, 0x7d21u) * 0.3 + cell_hash(ti, axis, 0x5a17u) * 0.2;
			float amt = strip * 0.85 + (patch - 0.5) * 1.8 + (ez - 1.0) * 0.3;
			bool speck = ed < width * 2.2 && cell_hash(ti, axis, 0x19e5u) < 0.2 * ez * (1.0 - ed / (width * 2.2));
			if (amt > 0.35 || speck) {
				float lump = stepped(vnoise(centre, vec2(6.0), axis, 0x4e7bu), 3.0, 0.9, 1.0);
				col = snow_color * lump * (amt > 0.65 ? 1.0 : 0.86);
			}
		}
	}

	// Light pools add to the surface's own colour (so they show in shadow too); the fog then takes
	// the lit result toward its tint in flat bands.
	vec3 pools = ps1_pools(v_pos, nn);
	float fog = ps1_fog(length(VERTEX));
	ALBEDO = col * (1.0 - fog);
	EMISSION = pools * (0.22 + col * 0.9) * (1.0 - fog) + fog_tint * fog;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
