// The Jetpack look's surface: Airframe Ultra / PS1. See docs/specs/jetpack-look.md.
//
// - Colour pixels (texture pass 2): no textures. The material's albedo colour is cut into
//   texels_per_metre square pixels, each one of shade_count stepped brightness levels between
//   shade_dark and shade_light. Shades come in clumps (two octaves of cell noise, clump_texels
//   across) with a few lone texels nudged one shade (jitter_chance). Minecraft-style.
// - No UVs: the pixel grid is projected along the dominant axis of the normal, one axis per face.
//   mapping 0 = world space (the level: neighbouring boxes line up), 1 = object space (static
//   models), 2 = rest pose (skinned models: CUSTOM0 = mesh-space rest position, CUSTOM1 = rest
//   normal, baked by JetpackLook, so the pixels ride the body as it animates).
// - Light: the sun's lambert is worked out PER VERTEX (Gouraud); its shadow is per pixel. No
//   specular. Ambient comes from the environment as usual.
// - Vertex snapping: clip-space xy rounded to a snap_lines-high grid at full render res.
// - Affine warping: the pixel grid interpolated in screen space (the PS1's missing perspective
//   correction), by the p*w / w trick.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
// Drop back faces. Two-sided stays the default (the level's thin quads); the trench coat turns this
// on so its leather's inside never z-fights the lining 6 mm behind it.
uniform bool cull_back = false;
// Ignore shadow maps on this surface (the sun still shades it per face). The trench coat's folds
// otherwise shadow each other in stepped dark wedges. It still casts onto the ground.
uniform bool ignore_shadows = false;

// A character (pilot, mech, speeder, anything alive or driven), set by AirframeLook. It is lit PER
// FACE (flat: the face normal from screen-space derivatives, so the shading steps from facet to
// facet like the PS1 reference), and, while PixelWorld's CharView is up, drawn in its own coarser
// block grid. See docs/specs/airframe-character-pixels.md.
uniform bool is_character = false;
// 1 while AIRFRAME is showing (AirframeLook sets it): characters are lit flat per face.
global uniform float airframe_char_flat;
// PixelWorld's CharView width in texels, 0 while it is off. A pass whose viewport is much wider
// than that is the 2X world pass.
global uniform float pixel_char_view_w;

uniform int mapping = 0;
// Metres per mesh unit for mapping 1 and 2 (an FBX in centimetres is 0.01). Set by JetpackLook.
uniform float object_scale = 1.0;
uniform float texels_per_metre = 16.0;

uniform float shade_count = 4.0;
uniform float shade_dark = 0.85;
uniform float shade_light = 1.10;
uniform float clump_texels = 3.0;
uniform float jitter_chance = 0.12;

// Worn leather (the trench coat, set by JetpackLook; 0 = off). The shade is picked from where the
// texel sits on the coat's REST shape (metres, model space: +X his left, +Y up, +Z front) instead
// of plain clumps: lighter where leather rubs (shoulders, elbows, front edges, collar rim, hem
// edge), darker where grime and folds gather (underarms, sleeve undersides, waist crease, lower
// back, a band above the hem, hanging fold streaks). wear_strength scales it (1 leather, ~0.5 lining).
uniform float wear_strength = 0.0;
uniform vec3 wear_elbow = vec3(0.4, 1.3, 0.0);

// Pilot grime (docs/specs/pilot9-grime.md; set by JetpackLook on pilot9's body, 0 = off). Placed
// dirt from the REST position (metres, +Y up, feet at 0, T-pose arms along X, +Z front) blended
// toward grime_color, weighted by how light the base colour is; plus a per-material detail layer
// (grime_material 1 main scuffs + scratches, 2 vest blotches + stains, 3 scarf fading, 0 none).
// grime_amount 0.5 = the specced look, 1 = twice as dirty.
uniform float grime_amount = 0.0;
uniform int grime_material = 0;
uniform vec3 grime_color : source_color = vec3(0.37, 0.33, 0.28);
uniform float grime_ankle_y = 0.12;
uniform float grime_knee_y = 0.50;
uniform float grime_hip_y = 0.95;
uniform float grime_hand_x = 0.85;

// The coat's dirty hem (docs/specs/pilot9-coat-drape.md; set by JetpackLook on the coat's leather,
// 0 = off): the pilot grime's dirt (grime_color, the same clumps and 3 steps) on a band from the
// hem (coat_dirt_hem_y, rest height) up coat_dirt_height, heaviest at the edge. Uses grime_amount.
uniform bool coat_dirt = false;
uniform float coat_dirt_hem_y = 0.30;
uniform float coat_dirt_height = 0.20;

uniform bool snap_enabled = true;
// Grid rows over the screen height; columns follow the aspect.
uniform float snap_lines = 240.0;
uniform bool affine_enabled = false;

// World direction TOWARDS the sun, set by JetpackLook from the scene's DirectionalLight3D.
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);

varying float v_lambert;
varying vec3 v_pos;
varying vec3 v_norm;
varying vec4 v_affine;

void vertex() {
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_lambert = max(dot(wn, normalize(sun_dir)), 0.0);

	if (mapping == 2) {
		v_pos = CUSTOM0.xyz * object_scale;
		v_norm = CUSTOM1.xyz;
	} else if (mapping == 1) {
		v_pos = VERTEX * object_scale;
		v_norm = NORMAL;
	} else {
		v_pos = wpos;
		v_norm = wn;
	}

	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// A directional shadow pass is orthographic: never snap the shadow casters.
	bool ortho = PROJECTION_MATRIX[3][3] > 0.5;
	if (snap_enabled && !ortho && clip.w > 0.0) {
		float aspect = PROJECTION_MATRIX[1][1] / PROJECTION_MATRIX[0][0];
		vec2 grid = vec2(snap_lines * aspect, snap_lines) * 0.5;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;

	v_affine = vec4(v_pos * clip.w, clip.w);
}

// Integer hash of a texel cell on one projection axis, 0..1.
float cell_hash(ivec2 c, int axis, uint salt) {
	uint h = uint(c.x) * 1597334677u ^ uint(c.y) * 3812015801u ^ uint(axis + 1) * 2654435769u ^ salt;
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return float(h) / 4294967295.0;
}

// Smooth value noise over cells `size` texels across, sampled at a texel centre.
float clump_noise(vec2 texel_centre, float size, int axis, uint salt) {
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

// x of the coat's front edge at height y (the rows of trench_coat_mesh.gd).
float coat_front_x(float y) {
	if (y <= 0.64) return mix(0.17, 0.15, clamp((y - 0.30) / 0.34, 0.0, 1.0));
	if (y <= 0.95) return mix(0.15, 0.12, (y - 0.64) / 0.31);
	if (y <= 1.12) return mix(0.12, 0.105, (y - 0.95) / 0.17);
	if (y <= 1.34) return mix(0.105, 0.085, (y - 1.12) / 0.22);
	return mix(0.085, 0.07, clamp((y - 1.34) / 0.131, 0.0, 1.0));
}

// Wear at a rest-pose point: -1 darkest .. +1 lightest, before the patchy noise.
float coat_wear(vec3 p, vec3 n, float noise) {
	vec3 q = vec3(abs(p.x), p.y, p.z);
	vec3 nq = vec3(n.x * sign(p.x == 0.0 ? 1.0 : p.x), n.y, n.z);
	bool sleeve = q.x > 0.265;
	float w = 0.0;
	// Light: shoulders and the top of the sleeve head.
	w += 0.8 * smoothstep(1.46, 1.57, q.y) * smoothstep(0.0, 0.5, nq.y) * smoothstep(0.08, 0.16, q.x);
	// Light: elbows (a rubbed knob), wherever the sleeve bends.
	vec3 e = vec3(abs(wear_elbow.x), wear_elbow.y, wear_elbow.z);
	w += 0.9 * (1.0 - smoothstep(0.03, 0.13, distance(q, e)));
	// Light: the front edges, from the collar down to the hem.
	float edge = q.x - coat_front_x(q.y);
	w += 0.8 * (1.0 - smoothstep(0.0, 0.05, abs(edge))) * smoothstep(0.02, 0.1, q.z) * (sleeve ? 0.0 : 1.0);
	// Light: the collar rim. (The hem's light rubbed edge went 2026-11-16: the dirty hem covers it.)
	w += 0.8 * smoothstep(1.585, 1.615, q.y);
	// Dark: a band of grime above the hem.
	w -= 0.55 * smoothstep(0.345, 0.40, q.y) * (1.0 - smoothstep(0.42, 0.62, q.y));
	// Dark: the underarm, and the underside of the sleeve.
	w -= 0.8 * smoothstep(1.25, 1.35, q.y) * (1.0 - smoothstep(1.40, 1.50, q.y))
		* smoothstep(0.17, 0.2, q.x) * (1.0 - smoothstep(0.26, 0.30, q.x));
	w -= 0.7 * smoothstep(0.1, -0.5, nq.y) * (sleeve ? 1.0 : 0.0);
	// Dark: the waist crease, a pull line across the belly and back.
	w -= 0.5 * (1.0 - smoothstep(0.0, 0.06, abs(q.y - 1.12))) * (sleeve ? 0.0 : 1.0);
	// Dark: the lower back, where the pack rubbed.
	w -= 0.6 * (1.0 - smoothstep(0.0, 0.16, abs(q.y - 0.95))) * smoothstep(-0.05, -0.15, q.z) * (sleeve ? 0.0 : 1.0);
	// Hanging fold streaks on the skirt: noise stretched along y, light ridge / dark valley.
	float skirt = (1.0 - smoothstep(0.95, 1.12, q.y)) * (sleeve ? 0.0 : 1.0);
	w += skirt * 0.55 * (noise - 0.5) * 2.0;
	return clamp(w, -1.0, 1.0);
}

// How dirty a rest-pose point is, 0..1, before the patch noise: boots and shins fading out by
// mid-thigh, knee fronts, hands/forearm ends, and a faint floor everywhere (less up top).
float grime_field(vec3 p, vec3 n) {
	float mid_thigh = mix(grime_knee_y, grime_hip_y, 0.5);
	float d = 0.85 * (1.0 - smoothstep(grime_ankle_y, mid_thigh, p.y));
	d = max(d, 0.95 * (1.0 - smoothstep(-0.02, grime_ankle_y, p.y)));
	// Knees: a scuffed patch on the front of the leg around knee height.
	float knee = (1.0 - smoothstep(0.04, 0.10, abs(p.y - grime_knee_y))) * smoothstep(-0.1, 0.4, n.z)
		* (1.0 - smoothstep(0.25, 0.32, abs(p.x)));
	d = max(d, 0.6 * knee);
	// Hands: what grabs ledges and rails, out at the end of the T-pose arms.
	d = max(d, 0.55 * smoothstep(grime_hand_x - 0.12, grime_hand_x, abs(p.x)));
	// The faint floor: dust everywhere, half as much on chest, shoulders and helmet.
	float floor_d = mix(0.16, 0.08, smoothstep(grime_hip_y + 0.15, grime_hip_y + 0.4, p.y));
	return max(d, floor_d);
}

// The per-material detail as a colour multiplier around 1 (scarf: >1 = faded).
vec3 grime_detail(vec3 c, vec2 centre, ivec2 ti, int axis) {
	if (grime_material == 1) {
		// Scuffs: soft darker patches. Scratches: one-texel lines, a few per 8x8 cell.
		float scuff = clump_noise(centre, 7.0, axis, 0x41a7u);
		float m = 1.0 - 0.07 * smoothstep(0.6, 0.8, scuff);
		ivec2 cell = ti / 8;
		ivec2 local = ti - cell * 8;
		if (cell_hash(cell, axis, 0x5c3du) < 0.35) {
			int dir = int(cell_hash(cell, axis, 0x1e9fu) * 4.0);
			int off = int(cell_hash(cell, axis, 0x77a1u) * 6.0) + 1;
			int len = int(cell_hash(cell, axis, 0x2b6du) * 4.0) + 3;
			int along = dir == 0 ? local.x : local.y;
			int across = dir == 0 ? local.y : (dir == 1 ? local.x : (dir == 2 ? local.x - local.y : local.x + local.y - 7));
			if (across == (dir >= 2 ? 0 : off) && along >= 1 && along <= len) {
				m = min(m, 0.86);
			}
		}
		return c * m;
	}
	if (grime_material == 2) {
		float blotch = clump_noise(centre, 6.0, axis, 0x6d2fu);
		float stain = clump_noise(centre, 11.0, axis, 0x13c5u);
		return c * mix(0.92, 1.05, blotch) * (1.0 - 0.18 * smoothstep(0.66, 0.74, stain));
	}
	if (grime_material == 3) {
		float fade = clump_noise(centre, 8.0, axis, 0x3f19u);
		float k = smoothstep(0.58, 0.7, fade);
		return mix(c, c * 1.45 + vec3(0.012), k);
	}
	return c;
}

void fragment() {
	if (cull_back && !FRONT_FACING) {
		discard;
	}
	vec3 p = affine_enabled ? v_affine.xyz / v_affine.w : v_pos;
	vec3 n = abs(v_norm);
	vec2 coord;
	int axis;
	if (n.y >= n.x && n.y >= n.z) {
		coord = p.xz;
		axis = 1;
	} else if (n.x >= n.z) {
		coord = vec2(p.z, -p.y);
		axis = 0;
	} else {
		coord = vec2(p.x, -p.y);
		axis = 2;
	}
	coord *= texels_per_metre;
	vec2 texel = floor(coord);
	vec2 centre = texel + 0.5;
	ivec2 ti = ivec2(texel);

	// Clumps: two octaves, stretched so every shade gets used, then stepped.
	float f = 0.65 * clump_noise(centre, clump_texels, axis, 0x9e37u)
		+ 0.35 * clump_noise(centre, clump_texels * 0.5, axis, 0x51edu);
	f = clamp((f - 0.5) * 2.2 + 0.5, 0.0, 0.999);
	if (wear_strength > 0.0) {
		// Folds hang: noise long in y, narrow around. Then wear picks the tone, the clump noise
		// breaks it into patches (about a third of the swing).
		vec2 fold_c = floor(vec2((p.x * 0.7 + p.z) * texels_per_metre, p.y * texels_per_metre * 0.12)) + 0.5;
		float fold = clump_noise(fold_c, clump_texels * 1.5, 3, 0x3b9du);
		float w = coat_wear(p / max(object_scale, 0.0001) * 1.0, v_norm, fold);
		f = clamp(0.5 + wear_strength * (0.62 * w + 0.38 * (f - 0.5)), 0.0, 0.999);
	}
	float steps = max(shade_count, 1.0);
	float idx = floor(f * steps);
	// A few lone texels one shade off.
	if (cell_hash(ti, axis, 0x2c1bu) < jitter_chance) {
		idx += cell_hash(ti, axis, 0x7f4au) < 0.5 ? -1.0 : 1.0;
	}
	idx = clamp(idx, 0.0, steps - 1.0);
	float shade = steps > 1.0 ? mix(shade_dark, shade_light, idx / (steps - 1.0)) : 1.0;

	// Where a texel shrinks below a screen pixel, settle to the mean shade (no shimmer far off).
	vec2 fw = fwidth(coord);
	float tiny = smoothstep(0.6, 1.4, max(fw.x, fw.y));
	shade = mix(shade, 0.5 * (shade_dark + shade_light), tiny);

	vec3 c = albedo_color.rgb * shade;
	if (grime_amount > 0.0 && !coat_dirt) {
		float k = clamp(grime_amount * 2.0, 0.0, 2.0) * (1.0 - tiny);
		vec3 detailed = grime_detail(c, centre, ti, axis);
		c = mix(c, detailed, clamp(k, 0.0, 1.0));
		// Dirt: the field broken into clumps, then stepped to three levels (clean / dusty / dirty).
		float field = grime_field(p, v_norm) * k;
		float patchy = 0.6 * clump_noise(centre, 4.0, axis, 0x58e1u) + 0.4 * cell_hash(ti, axis, 0x0d4bu);
		float dirt = clamp(field * 1.6 - (1.0 - patchy) * 0.9, 0.0, 1.0);
		dirt = floor(dirt * 3.0 + 0.35) / 3.0 * 0.85;
		// Dirt hardly shows on dark cloth: weight by how light the base colour is.
		float light_w = smoothstep(0.03, 0.25, dot(albedo_color.rgb, vec3(0.2126, 0.7152, 0.0722)));
		c = mix(c, grime_color * shade, dirt * light_w);
	}
	if (coat_dirt && grime_amount > 0.0) {
		// The same dirt as his shins, on a band above the hem (rest height), so the bottom of the
		// coat lines up with them.
		float k = clamp(grime_amount * 2.0, 0.0, 2.0) * (1.0 - tiny);
		float y = p.y / max(object_scale, 0.0001);
		float field = 0.95 * (1.0 - smoothstep(coat_dirt_hem_y, coat_dirt_hem_y + coat_dirt_height, y)) * k;
		float patchy = 0.6 * clump_noise(centre, 4.0, axis, 0x58e1u) + 0.4 * cell_hash(ti, axis, 0x0d4bu);
		float dirt = clamp(field * 1.6 - (1.0 - patchy) * 0.9, 0.0, 1.0);
		dirt = floor(dirt * 3.0 + 0.35) / 3.0 * 0.85;
		c = mix(c, grime_color * shade, dirt);
	}
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	if (is_character && airframe_char_flat > 0.5) {
		vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		NORMAL = dot(fn, VERTEX) > 0.0 ? -fn : fn;
	}
	// In the 2X world pass a character close enough to be drawn in CharView is painted a flat
	// marker colour (and no light: ALBEDO 0), which the composite reads as "the character is
	// visible here, not behind the level" and replaces with CharView's 4X pixels. Past 50 m
	// (fog begins at 60) there is no marker, so the far character stays in the 2X world.
	if (is_character && pixel_char_view_w > 0.5 && VIEWPORT_SIZE.x > pixel_char_view_w * 1.5
			&& length(VERTEX) < 50.0) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(1.0, 0.0, 1.0);
	}
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float lambert = (is_character && airframe_char_flat > 0.5) ? max(dot(NORMAL, LIGHT), 0.0) : v_lambert;
		DIFFUSE_LIGHT += LIGHT_COLOR * (ignore_shadows ? 1.0 : ATTENUATION) * lambert / PI;
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) / PI;
	}
}
