// The arrival shot's clouds (scripts/cutscene/arrival_clouds.gd), spec R2-6. Three ways to make the
// shape, one look: a few big, smooth cel tones, lit from the sun's side (up and to the left, behind),
// the belly in shade, no speckle inside. Faded softly where a card meets anything behind it, so towers
// and peaks stand *in* the cloud instead of being cut by a line.
//   mode 0, heap: a cumulus of round lobes melted together (metaballs) along a flat base.
//   mode 1, plume: lobes rising up a leaning column, growing and thinning as they climb (steam).
//   mode 2, streak: wind-stretched noise (spindrift), soft and thin.
//   mode 3, sea: a level layer seen from above, a broad noise field with a billowed edge, lit by
//      its thickness; peaks rise out of it through the soft fade.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

uniform int mode = 0;
uniform float shot_time = 0.0;
// Noise tiles across the card and how fast it slides (tiles per second): the edge wobble for heaps,
// the whole shape for streaks and the sea.
uniform vec2 scale = vec2(1.0, 1.0);
uniform vec2 drift = vec2(0.003, 0.0);
// Heaps and plumes: how many lobes, and how far the noise roughens their edge.
uniform float lobes = 9.0;
uniform float wobble = 0.12;
// Plumes: rise (column lengths per second) and lean (card widths across the column's height).
uniform float rise = 0.05;
uniform float lean = 0.35;
// Streaks and the sea: where the cloud starts in the noise, and how soft its edge is.
uniform float coverage = 0.45;
uniform float softness = 0.06;
uniform float opacity = 1.0;
uniform vec3 lit_color : source_color = vec3(0.97, 0.98, 1.0);
uniform vec3 mid_color : source_color = vec3(0.84, 0.88, 0.94);
uniform vec3 shade_color : source_color = vec3(0.62, 0.68, 0.78);
// Toward the sun in card space (x right, y up, z out of the card toward the camera): up-left, behind.
uniform vec3 light_dir = vec3(-0.55, 0.75, -0.25);
// Where the tones split (light, 0..1): shade below the first, lit above the second.
uniform vec2 steps = vec2(0.38, 0.62);
// Metres over which a card fades out in front of anything behind it.
uniform float soft_depth = 400.0;

instance uniform float seed = 0.0;
// Card width over height, so lobes stay round.
instance uniform float aspect = 2.0;

float hash(float n) {
	return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

float noise(vec2 p) {
	return texture(noise_tex, p).r;
}

// Toned light, 0 shade / 0.5 mid / 1 lit, with the step edges antialiased.
float tone(float l) {
	float w = fwidth(l) * 0.75 + 1e-4;
	return 0.5 * smoothstep(steps.x - w, steps.x + w, l) + 0.5 * smoothstep(steps.y - w, steps.y + w, l);
}

void fragment() {
	vec2 uv = UV;
	// Card space: x across in card heights, y up, 0 at the centre.
	vec2 p = vec2((uv.x - 0.5) * aspect, 0.5 - uv.y);
	float a = 0.0;
	float light = 0.5;
	if (mode == 0 || mode == 1) {
		vec2 q = p + (vec2(noise(uv * scale + seed + drift * shot_time),
				noise(uv * scale * 1.3 - seed + drift * shot_time)) - 0.5) * wobble;
		// Metaballs: every lobe adds (1 - d^2)^2 inside its radius, so neighbours melt into one mass,
		// and the field's slope gives one continuous surface to light (not a ball per lobe).
		float field = 0.0;
		vec2 grad = vec2(0.0);
		float spacing = aspect * 0.86 / lobes;
		for (float i = 0.0; i < lobes; i += 1.0) {
			vec2 c;
			float r;
			float weight = 1.0;
			if (mode == 0) {
				// Lobes along the base, the big ones in the middle, a few stacked on top.
				float x = (i + 0.5) / lobes - 0.5 + (hash(i) - 0.5) * 0.5 / lobes;
				float mid = 1.0 - abs(x) * 2.0;
				r = min(spacing * (1.0 + 0.9 * mid + 0.4 * hash(i + 7.0)), 0.36);
				float row = step(0.55, hash(i + 3.0)) * smoothstep(0.2, 0.7, mid);
				c = vec2(x * aspect * 0.78, -0.3 + r * 0.55 + row * r * 0.9);
				// Keep every lobe inside the card, so none is cut by its edge.
				r = min(r, min(aspect * 0.5 - abs(c.x), 0.48 - c.y) - 0.02);
			} else {
				float t = fract(i / lobes + shot_time * rise);
				r = 0.08 + 0.22 * t;
				c = vec2(lean * pow(t, 1.4) * aspect - aspect * 0.25, -0.4 + 0.75 * t);
				weight = 1.0 - smoothstep(0.45, 1.0, t);
			}
			vec2 d = (q - c) / r;
			float k = max(1.0 - dot(d, d), 0.0);
			field += k * k * weight;
			grad += -4.0 * k * d / r * weight;
		}
		// A flat base for a heap.
		float base = mode == 0 ? smoothstep(-0.32, -0.26, q.y) : 1.0;
		float edge = 0.18;
		float w = fwidth(field) * 1.5 + 1e-4;
		a = smoothstep(edge - w, edge + w, field) * base;
		vec3 n = normalize(vec3(-grad * 0.12, 1.0));
		light = clamp(dot(n, normalize(light_dir)) * 0.9 + 0.5, 0.0, 1.0);
		// Thin rims glow (backlit); the belly sits in shade.
		light = max(light, 1.0 - smoothstep(edge, edge + 0.04, field));
		light *= smoothstep(-0.34, -0.1, q.y) * 0.45 + 0.55;
	} else {
		vec2 s = uv * scale + vec2(seed * 0.37, seed * 0.71) + drift * shot_time;
		float n = noise(s) * 0.7 + noise(s * 2.1 + 0.5) * 0.3;
		float shape = 1.0;
		if (mode == 2) {
			vec2 c = (uv - 0.5) * 2.0;
			shape = 1.0 - smoothstep(0.3, 1.0, length(c));
		} else {
			// The sea thins out toward the card's near edge and its sides.
			shape = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x) * smoothstep(1.0, 0.75, uv.y);
		}
		float d = n * shape;
		a = smoothstep(coverage, coverage + softness, d);
		if (mode == 2) {
			// Thin streaks and mist: lit, a mid tone where they thin out.
			light = clamp((d - coverage) * 4.0 + 0.55, 0.0, 1.0);
		} else {
			// The sea: thicker reads brighter (its tops catch the sun), troughs between billows in shade.
			light = clamp((n - 0.5) * 2.4 + 0.55, 0.0, 1.0) * smoothstep(coverage, coverage + 0.12, d) + 0.1;
		}
	}
	float t = tone(light);
	ALBEDO = t < 0.5 ? mix(shade_color, mid_color, t * 2.0) : mix(mid_color, lit_color, t * 2.0 - 1.0);

	float scene = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene, 1.0);
	float behind = -view.z / view.w - (-VERTEX.z);
	ALPHA = a * opacity * clamp(behind / soft_depth, 0.0, 1.0);
}
