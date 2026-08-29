shader_type sky;
render_mode use_debanding;

// Banded posterised sky (Moebius / Sable art direction).
//
// Four hard colour bands stacked horizon -> zenith. The band edges are stepped,
// not smooth: `band_softness` is a razor-thin smoothstep that only exists to
// antialias the seam so it does not crawl when the camera turns.
//
// Colour defaults are the spec's placeholder palette, pre-converted to linear
// (shader-literal defaults are read as linear; the inspector converts for you).

group_uniforms bands;
uniform vec3 horizon_color : source_color = vec3(0.831, 0.694, 0.456); // #EBD9B4 warm haze
uniform vec3 mid_color : source_color = vec3(0.347, 0.651, 0.731);     // #9FD3DE pale cyan
uniform vec3 upper_color : source_color = vec3(0.188, 0.521, 0.638);   // #78BFD1
uniform vec3 zenith_color : source_color = vec3(0.078, 0.381, 0.552);  // #4FA6C4 cyan

// Split points as elevation above the horizon (0 = horizon, 1 = straight up).
uniform float horizon_height : hint_range(0.0, 1.0) = 0.06;
uniform float mid_height : hint_range(0.0, 1.0) = 0.22;
uniform float upper_height : hint_range(0.0, 1.0) = 0.50;
uniform float band_softness : hint_range(0.0, 0.1) = 0.004;

group_uniforms sun;
uniform bool sun_enabled = true;
uniform float sun_size : hint_range(0.0, 0.5) = 0.04;
uniform float sun_softness : hint_range(0.0, 0.5) = 0.02;
uniform vec3 sun_color : source_color = vec3(1.0, 0.888, 0.687);

// Hard step with a hair of antialiasing on the seam.
float band_step(float edge, float x) {
	return smoothstep(edge - band_softness, edge + band_softness, x);
}

void sky() {
	float elevation = EYEDIR.y;

	// Below the horizon the sky is never seen in normal play (terrain + fog
	// cover it), so clamp rather than mirror: keeps the horizon band solid.
	float t = max(elevation, 0.0);

	vec3 col = horizon_color;
	col = mix(col, mid_color, band_step(horizon_height, t));
	col = mix(col, upper_color, band_step(mid_height, t));
	col = mix(col, zenith_color, band_step(upper_height, t));

	if (sun_enabled && LIGHT0_ENABLED) {
		// Track the key light directly so the disk can never drift out of sync
		// with the DirectionalLight3D driving the cel bands.
		float d = distance(EYEDIR, -LIGHT0_DIRECTION);
		float disk = 1.0 - smoothstep(sun_size, sun_size + sun_softness, d);
		col = mix(col, sun_color, disk);
	}

	COLOR = col;
}
