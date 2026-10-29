// The arrival shot's clear sky (docs/specs/cutscene-arrival.md): deep blue at the zenith to a pale
// haze at the horizon, a few thin high cloud streaks with hard cel edges, and a soft lift toward the
// sun. Below the horizon it is the haze colour (the land covers it anyway).
//
// The camera only ever sees a few degrees above the horizon, so the streaks are laid out by heading
// and elevation, not projected onto a cloud plane: a plane seen that close to edge-on smeared into
// vertical streaks (spec R2-6).
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.16, 0.36, 0.64);
uniform vec3 horizon : source_color = vec3(0.7, 0.79, 0.9);
uniform vec3 cloud : source_color = vec3(0.95, 0.96, 0.98);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.97, 0.9);
uniform sampler2D cloud_tex : repeat_enable, filter_linear_mipmap;
uniform float cloud_amount = 0.5;
// Tiles per radian of heading, and per radian of elevation: long and thin along the horizon.
uniform vec2 cloud_scale = vec2(0.8, 9.0);
// Elevations (radians) the streaks live between: thin near the haze, gone higher up.
uniform vec2 cloud_band = vec2(0.012, 0.09);

void sky() {
	float e = max(EYEDIR.y, 0.0);
	vec3 col = mix(horizon, zenith, pow(smoothstep(0.0, 0.25, e), 0.5));
	float el = asin(clamp(EYEDIR.y, -1.0, 1.0));
	vec2 p = vec2(atan(EYEDIR.x, -EYEDIR.z), el) * cloud_scale;
	float c = texture(cloud_tex, p).r;
	c = smoothstep(0.64, 0.66, c) * 0.6 + smoothstep(0.72, 0.74, c) * 0.4;
	c *= smoothstep(cloud_band.x, cloud_band.x * 2.5, el) * (1.0 - smoothstep(cloud_band.y * 0.6, cloud_band.y, el));
	col = mix(col, cloud, c * cloud_amount);
	float s = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
	col += sun_glow * pow(s, 6.0) * 0.3;
	if (EYEDIR.y < 0.0) {
		col = horizon;
	}
	COLOR = col;
}
