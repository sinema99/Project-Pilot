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

uniform int mapping = 0;
// Metres per mesh unit for mapping 1 and 2 (an FBX in centimetres is 0.01). Set by JetpackLook.
uniform float object_scale = 1.0;
uniform float texels_per_metre = 16.0;

uniform float shade_count = 4.0;
uniform float shade_dark = 0.85;
uniform float shade_light = 1.10;
uniform float clump_texels = 3.0;
uniform float jitter_chance = 0.12;

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

void fragment() {
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
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * v_lambert / PI;
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) / PI;
	}
}
