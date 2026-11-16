shader_type spatial;
render_mode unshaded, cull_back, fog_disabled, shadows_disabled;

// A powered display in hub2's crane control room (docs/specs/hub2-control-room.md): a drawn low-res
// image (crane status, yard map, power...) with scanlines and a flicker, or, with no image, a plain
// lamp. `blink` > 0 is a square-wave blink in Hz (phase shifts it); `flick` > 0 drops the light out
// at random moments (a tired fluorescent tube). Unshaded so AIRFRAME leaves it alone.

uniform sampler2D img : source_color, filter_nearest, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float brightness = 1.15;
uniform float scan = 1.0;
uniform float blink = 0.0;
uniform float phase = 0.0;
uniform float flick = 0.0;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(img, UV).rgb * tint * brightness;
	if (scan > 0.5) {
		float lines = 0.8 + 0.2 * step(0.5, fract(UV.y * 80.0));
		float f = 0.93 + 0.07 * step(0.5, h(vec2(floor(TIME * 10.0), phase)));
		c *= lines * f;
	}
	if (blink > 0.0) {
		c *= 0.12 + 0.88 * step(0.5, fract(TIME * blink + phase));
	}
	if (flick > 0.0) {
		float k = h(vec2(floor(TIME * 7.0 + phase * 13.0), phase));
		c *= 1.0 - flick * step(0.82, k);
	}
	ALBEDO = c;
}
