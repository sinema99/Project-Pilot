// The boss arena's 2D backdrop (docs/specs/boss-arena.md): everything past ~3 km of the arrival
// world, baked by tools/bake_boss_backdrop.gd as six 90 deg views from the arena's centre.
//
// Face convention (the bake tool's FACES, the same order and vectors): for a face looking along F
// with up U and right R = F x U, a view direction d lands at x = d.R / d.F, y = d.U / d.F, both
// -1..1, and the image's uv is (0.5 + 0.5 x, 0.5 - 0.5 y).
//
// The images are what the screen showed: already through the bake's tonemap (Godot's filmic at
// `exposure`, white `white`). The arena tonemaps its sky again, so each texel is put back through
// the inverse of that curve first and the arena's own tonemap lands on the baked colour.
shader_type sky;

uniform sampler2D face_px : source_color, filter_linear, repeat_disable;
uniform sampler2D face_nx : source_color, filter_linear, repeat_disable;
uniform sampler2D face_py : source_color, filter_linear, repeat_disable;
uniform sampler2D face_ny : source_color, filter_linear, repeat_disable;
uniform sampler2D face_pz : source_color, filter_linear, repeat_disable;
uniform sampler2D face_nz : source_color, filter_linear, repeat_disable;
// A step of dither (of 255), so the overcast's long soft gradients do not band.
uniform float dither = 1.0;
// The bake's (and the arena's) tonemap: exposure and white.
uniform float exposure = 0.85;
uniform float white = 1.0;
// Off: the texels as they are (for checking the bake).
uniform bool untonemap = true;

vec2 face_uv(vec3 d, vec3 f, vec3 u) {
	vec3 r = cross(f, u);
	float k = dot(d, f);
	return vec2(0.5 + 0.5 * dot(d, r) / k, 0.5 - 0.5 * dot(d, u) / k);
}

// Godot's filmic curve (exposure bias 2), per channel.
const float F_A = 0.22 * 4.0;
const float F_B = 0.30 * 2.0;
const float F_C = 0.10;
const float F_D = 0.20;
const float F_E = 0.01;
const float F_F = 0.30;

float filmic(float x) {
	return (x * (F_A * x + F_C * F_B) + F_D * F_E) / (x * (F_A * x + F_B) + F_D * F_F) - F_E / F_F;
}

// The x >= 0 with filmic(x) / filmic(white) = y.
float unfilmic(float y) {
	float t = clamp(y, 0.0, 0.999) * filmic(white) + F_E / F_F;
	// F_A (t - 1) x^2 + F_B (t - F_C) x + F_D (F_F t - F_E) = 0
	float a = F_A * (t - 1.0);
	float b = F_B * (t - F_C);
	float c = F_D * (F_F * t - F_E);
	float disc = max(b * b - 4.0 * a * c, 0.0);
	return max((-b - sqrt(disc)) / (2.0 * a), 0.0);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 a = abs(d);
	vec3 col;
	if (a.x >= a.y && a.x >= a.z) {
		col = d.x > 0.0 ? texture(face_px, face_uv(d, vec3(1, 0, 0), vec3(0, 1, 0))).rgb
				: texture(face_nx, face_uv(d, vec3(-1, 0, 0), vec3(0, 1, 0))).rgb;
	} else if (a.y >= a.z) {
		col = d.y > 0.0 ? texture(face_py, face_uv(d, vec3(0, 1, 0), vec3(0, 0, 1))).rgb
				: texture(face_ny, face_uv(d, vec3(0, -1, 0), vec3(0, 0, -1))).rgb;
	} else {
		col = d.z > 0.0 ? texture(face_pz, face_uv(d, vec3(0, 0, 1), vec3(0, 1, 0))).rgb
				: texture(face_nz, face_uv(d, vec3(0, 0, -1), vec3(0, 1, 0))).rgb;
	}
	vec3 grain = fract(52.9829189 * fract(vec3(0.06711056, 0.0583715, 0.0749123) * FRAGCOORD.x
			+ vec3(0.00583715, 0.0749123, 0.06711056) * FRAGCOORD.y));
	col += (grain - 0.5) * dither / 255.0;
	if (untonemap) {
		col = vec3(unfilmic(col.r), unfilmic(col.g), unfilmic(col.b)) / exposure;
	}
	COLOR = col;
}
