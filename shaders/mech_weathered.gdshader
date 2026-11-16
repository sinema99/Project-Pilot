// EXIA's weathered factory paint. See docs/specs/mech-weathering.md ("Placement pass").
//
// One shader, two roles (is_frame):
// - SHELL: chipped paint (paint_color) over rust.
// - FRAME: oily dark metal, worn the same way, with sparse flecks of the paint colour.
// `paint_left` is the share still in its original finish; 1 or more = no rust and no chips at all.
//
// WHERE the wear goes is physical, not random noise:
//   chips   - ragged bare metal along the convex edges, heaviest on bottom edges and outer corners;
//             bigger bites have rust in their core.
//   rust    - grows in from the edges, the seams (concave creases and where another part meets this
//             one), the under-faces and the lower body; noise only roughens its border. A few lone
//             spots on the flat faces.
//   streaks - orange-brown washes that hang below the edges and seams above, 0.3-1 m long, fading.
//   grime   - rises from the ground to mid-shin; under-faces darker than tops.
//   scratches - few, shell only, flat faces away from the edges.
// The edge / seam / drop / corner distances come from the mesh: CUSTOM2, baked offline by
// tools/bake_mech_wear.gd (has_wear_map). The back boxes are true boxes: box_half > 0 works the same
// four distances out of the box's own position instead.
// Everything is cut into texels_per_metre square pixels like the AIRFRAME look (no UVs, no textures),
// projected along the dominant axis of the normal from the mesh-space rest position (CUSTOM0/1 when
// use_rest), so it rides the body through every animation.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 paint_color : source_color = vec3(0.78, 0.6, 0.12);
uniform vec3 frame_color : source_color = vec3(0.09, 0.09, 0.1);
uniform vec3 rust_dark : source_color = vec3(0.20, 0.09, 0.05);
uniform vec3 rust_light : source_color = vec3(0.42, 0.20, 0.09);
uniform vec3 bare_metal : source_color = vec3(0.45, 0.45, 0.47);
uniform vec3 grime_color : source_color = vec3(0.07, 0.05, 0.04);
uniform vec3 hazard_black : source_color = vec3(0.07, 0.07, 0.07);

uniform bool is_frame = false;
// Share of the surface still in its original finish (paint for a shell, dark metal for a frame).
uniform float paint_left : hint_range(0.0, 1.1) = 0.85;
uniform float seed = 0.0;
uniform bool use_rest = false;
uniform float texels_per_metre = 16.0;
uniform bool hazard = false;
// CUSTOM2 holds the baked distances (chip, seam, drop, corner).
uniform bool has_wear_map = false;
// > 0: this is a box of these half extents (local space, y up); the distances come from it.
uniform vec3 box_half = vec3(0.0);
// Grime from the ground up: off for parts whose local y is not the body's height (the back boxes).
uniform bool ground_grime = true;
// Mesh-space height where the ground grime has faded out (mid-shin).
uniform float grime_top = 2.9;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.6;

global uniform float pixel_char_view_w;
global uniform float airframe_char_flat;

varying vec3 v_pos;
varying vec3 v_norm;
varying vec4 v_wear;

void vertex() {
	if (use_rest) {
		v_pos = CUSTOM0.xyz;
		v_norm = CUSTOM1.xyz;
	} else {
		v_pos = VERTEX;
		v_norm = NORMAL;
	}
	v_wear = has_wear_map ? CUSTOM2 : vec4(1.0, 1.0, 3.0, 1.0);
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

// Smooth value noise, cells `size` texels across (x and y stretched separately).
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

// Bottom edges count nearer (wear more), top edges farther. Same weights as the bake.
float edge_w(float outward_y) {
	return 1.0 + 0.6 * max(-outward_y, 0.0) - 0.4 * max(outward_y, 0.0);
}

// The four distances for a point p on a box of half extents h, on the face along `face_axis`.
vec4 box_wear(vec3 p, vec3 h, int face_axis) {
	vec3 gap = h - abs(p);
	float chip = 9.0;
	float drop = 3.0;
	float g_a = 9.0;
	float g_b = 9.0;
	for (int k = 0; k < 3; k++) {
		if (k == face_axis) {
			continue;
		}
		float w = k == 1 ? edge_w(sign(p.y) * 0.7) : 1.0;
		chip = min(chip, gap[k] / w);
		if (g_a > 8.0) {
			g_a = gap[k];
		} else {
			g_b = gap[k];
		}
	}
	if (face_axis != 1) {
		drop = gap.y;
	}
	return vec4(chip, 1.0, drop, length(vec2(g_a, g_b)));
}

void fragment() {
	vec3 nn = normalize(v_norm);
	vec3 n = abs(nn);
	vec2 coord;
	int axis;
	if (n.y >= n.x && n.y >= n.z) {
		coord = v_pos.xz;
		axis = 1;
	} else if (n.x >= n.z) {
		coord = vec2(v_pos.z, -v_pos.y);
		axis = 0;
	} else {
		coord = vec2(v_pos.x, -v_pos.y);
		axis = 2;
	}
	// Each mesh gets its own patches: shift the sampled plane by the seed.
	coord = coord * texels_per_metre + vec2(seed * 37.0, seed * 91.0);
	vec2 texel = floor(coord);
	vec2 centre = texel + 0.5;
	ivec2 ti = ivec2(texel);

	vec4 wear_d = box_half.x > 0.0 ? box_wear(v_pos, box_half, axis) : v_wear;
	float d_chip = wear_d.x;
	float d_seam = wear_d.y;
	float drop = wear_d.z;
	float corner = 1.0 - smoothstep(0.0, 0.35, wear_d.w);
	float under = smoothstep(0.35, 0.9, -nn.y);
	float h = v_pos.y;
	float wear = paint_left >= 1.0 ? 0.0 : 1.0 - paint_left;

	// Base finish in clumped stepped shades.
	float clump = 0.65 * vnoise(centre, vec2(3.0), axis, 0x9e37u) + 0.35 * vnoise(centre, vec2(1.5), axis, 0x51edu);
	clump = clamp((clump - 0.5) * 2.2 + 0.5, 0.0, 0.999);
	float shade = stepped(clump, 4.0, 0.82, 1.1);
	if (cell_hash(ti, axis, 0x2c1bu) < 0.1) {
		shade *= cell_hash(ti, axis, 0x7f4au) < 0.5 ? 0.92 : 1.06;
	}
	vec3 base = is_frame ? frame_color : paint_color;
	if (hazard) {
		// Diagonal bars, 8 texels wide, paint colour and black.
		float bar = fract((coord.x + coord.y) / 16.0);
		base = bar < 0.5 ? paint_color : hazard_black;
	}
	vec3 col = base * shade;

	// Rust: a potential from where rust starts (edges, seams, under-faces, low down), roughened by
	// noise, cut at a threshold that the wear share sets.
	float rough = 0.5 * vnoise(centre, vec2(6.0), axis, 0xa51du) + 0.3 * vnoise(centre, vec2(2.5), axis, 0x3b7du)
		+ 0.2 * cell_hash(ti, axis, 0x6d21u);
	float edge_p = 1.0 - smoothstep(0.0, 0.3, d_chip);
	float seam_p = 1.0 - smoothstep(0.0, 0.4, d_seam);
	float low_p = ground_grime ? 1.0 - smoothstep(0.4, grime_top, h) : 0.0;
	float pot = max(max(edge_p * 0.6, seam_p * 0.9), max(under * 0.6, low_p * 0.3));
	pot = max(pot, corner * 0.75);
	float rust_v = pot + (rough - 0.5) * 0.8;
	// A few lone spots on the open faces.
	float spot = vnoise(centre, vec2(4.0), axis, 0x1d9au) * 0.7 + rough * 0.3;
	float rust = 0.0;
	// Where the rust starts: the more worn, the lower the cut.
	float rust_cut = 1.2 - wear * 1.6;
	if (wear > 0.0) {
		rust = step(rust_cut, rust_v);
		rust = max(rust, step(0.97 - wear * 0.15, spot));
	}
	float rust_tone = vnoise(centre, vec2(4.0), axis, 0x1e5fu) * 0.7 + cell_hash(ti, axis, 0x4c3bu) * 0.3;
	vec3 rust_col = mix(rust_dark, rust_light, stepped(rust_tone, 4.0, 0.0, 1.0));
	col = mix(col, rust_col, rust);

	// Chips: ragged bare metal on the convex edges, 1-3 texels, gappy, wider at corners. Bigger
	// bites here and there with rust in their core.
	if (wear > 0.0) {
		// The dark frame shows its worn edges narrower, as duller steel.
		float chip_amt = smoothstep(0.0, 0.1, wear) * (0.85 + wear) * (is_frame ? 0.6 : 1.0);
		vec3 metal = is_frame ? bare_metal * 0.7 : bare_metal;
		float px = 1.0 / texels_per_metre;
		float width = px * (0.5 + 1.8 * vnoise(centre, vec2(3.0), axis, 0x44c1u)) * (1.0 + 1.5 * corner) * chip_amt;
		width *= 0.7 + 0.6 * cell_hash(ti, axis, 0x91f3u);
		float gap = vnoise(centre, vec2(2.0, 2.0), axis, 0x0b17u);
		if (d_chip < width && gap > 0.5) {
			col = metal * (0.8 + 0.4 * cell_hash(ti, axis, 0x88a1u));
		}
		float bite_n = vnoise(centre, vec2(5.0), axis, 0x7e23u) + corner * 0.25;
		float bite = px * 6.0 * smoothstep(0.7, 0.95, bite_n) * chip_amt;
		bite *= 0.8 + 0.4 * cell_hash(ti, axis, 0x33d7u);
		if (d_chip < bite) {
			col = d_chip < bite * 0.55 ? rust_col : metal * (0.8 + 0.3 * cell_hash(ti, axis, 0x5e1bu));
		}
		// A thin broken ring of metal where the paint meets the rust.
		float ring = 1.0 - smoothstep(0.0, 0.06, abs(rust_v - rust_cut));
		if (rust > 0.5 && ring > 0.0 && cell_hash(ti, axis, 0xc417u) < 0.3 * ring) {
			col = metal * (0.8 + 0.4 * cell_hash(ti, axis, 0x88a1u));
		}
		// Scratches: thin diagonal runs on the open shell faces only.
		vec2 sc = vec2(centre.x + centre.y * 0.5, centre.y - centre.x * 0.2);
		if (!is_frame && rust < 0.5 && d_chip > 0.3 && vnoise(sc, vec2(18.0, 1.4), axis, 0x5ca7u) > 0.93) {
			col = metal * 0.9;
		}
		// Rare lone flecks.
		if (rust < 0.5 && cell_hash(ti, axis, 0xf1ecu) > 0.994) {
			col = bare_metal;
		}
	}
	// A frame keeps sparse flecks of the paint it once wore.
	if (is_frame && rust < 0.5 && cell_hash(ti, axis, 0x7a17u) > 0.995) {
		col = paint_color * shade * 0.9;
	}

	// Rust streaks: 1-texel columns hanging below an edge or seam, each its own length, fading out.
	if (wear > 0.0 && n.y < 0.6) {
		ivec2 column = ivec2(int(texel.x), 0);
		float on = cell_hash(column, axis, 0x2f61u);
		float len = 0.3 + 0.7 * cell_hash(column, axis, 0x6a5bu);
		float s = 1.0 - drop / len;
		if (on > 0.86 - wear * 0.6 && s > 0.0) {
			float wash = s * (0.35 + 0.25 * cell_hash(ti, axis, 0x13c9u));
			col = mix(col, rust_light * 0.85, wash);
		}
	}

	// Grime: from the ground up to grime_top, and on the under-faces.
	if (wear > 0.0) {
		float g = low_p * (0.55 + 0.45 * vnoise(centre, vec2(3.0, 5.0), axis, 0xd21fu));
		col = mix(col, grime_color, g * grime_strength);
		col = mix(col, grime_color, under * 0.3);
	}

	ALBEDO = col;
	// AIRFRAME's character look (docs/specs/airframe-character-pixels.md; same as ps1_surface for
	// characters): lit flat per face, and a flat marker in the 2X world pass where CharView draws
	// the mech in its own coarser grid. Both are off outside AIRFRAME (the globals are 0).
	if (airframe_char_flat > 0.5) {
		vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		NORMAL = dot(fn, VERTEX) > 0.0 ? -fn : fn;
	}
	if (pixel_char_view_w > 0.5 && VIEWPORT_SIZE.x > pixel_char_view_w * 1.5 && length(VERTEX) < 50.0) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(1.0, 0.0, 1.0);
	}
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
