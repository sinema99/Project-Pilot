// One soft smoke puff: a camera-facing quad whose edge is eroded by drifting noise so it reads as
// a billowing blob, dense and bright at birth, thinning to nothing as it grows. age/seed/tint are
// per-instance; the node's scale (set from gun_fx.gd) does the growing.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

instance uniform float age = 0.0;
instance uniform float seed = 0.0;
instance uniform vec4 tint : source_color = vec4(0.84, 0.87, 0.95, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 7.3) * 0.3 + vnoise(p * 4.3 + 3.1) * 0.15;
}

void vertex() {
	// Full billboard, keeping the node's scale.
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * sc.x, INV_VIEW_MATRIX[1] * sc.y, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float t = clamp(age, 0.0, 1.0);
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// Noise sampled in the puff's own space; it slowly rolls so the edge keeps billowing.
	vec2 q = p * 1.6 + vec2(seed * 31.0, seed * 17.0) + vec2(t * 0.6, -t * 0.9);
	float n = fbm(q);
	// Eroded disc: the noise bites the rim harder as the puff ages.
	float body = 1.0 - r - (n - 0.5) * (0.7 + t * 0.5);
	float a = smoothstep(0.0, 0.45, body);
	if (a <= 0.01) {
		discard;
	}
	// Quick fade-in so it doesn't pop, long soft fade-out.
	float fade = smoothstep(0.0, 0.08, t) * pow(1.0 - t, 1.6);
	// Brighter, denser core; the shaded underside is a touch cooler and darker.
	float shade = mix(0.78, 1.0, clamp(0.5 + p.y * 0.5 + (n - 0.5), 0.0, 1.0));
	ALBEDO = tint.rgb * shade;
	ALPHA = a * fade * tint.a * 0.7;
}
