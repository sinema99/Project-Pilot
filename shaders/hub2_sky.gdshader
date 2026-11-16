// hub2's sky (docs/specs/hub2-ps1-mood.md): a stepped dusk gradient, sodium orange at the horizon
// through teal to deep blue overhead, a few single-pixel stars. Flat bands, no smooth blend.
shader_type sky;

uniform vec3 horizon_color : source_color = vec3(0.95, 0.5, 0.2);
uniform vec3 mid_color : source_color = vec3(0.1, 0.34, 0.42);
uniform vec3 zenith_color : source_color = vec3(0.03, 0.07, 0.17);
uniform float bands = 8.0;
uniform float star_density = 0.0016;

float h31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	float up = EYEDIR.y;
	float t = clamp(up / 0.7, 0.0, 1.0);
	t = pow(t, 0.55);
	t = floor(t * bands) / bands;
	vec3 col = t < 0.5 ? mix(horizon_color, mid_color, t * 2.0) : mix(mid_color, zenith_color, (t - 0.5) * 2.0);
	if (up < 0.0) {
		col = horizon_color * 0.35;
	}
	if (up > 0.25 && h31(floor(EYEDIR * 160.0)) > 1.0 - star_density) {
		col = vec3(0.9, 0.95, 1.0);
	}
	COLOR = col;
}
