shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

// A cockpit hologram panel: shows its SubViewport (the drawn UI, transparent where empty) as
// translucent green glass. On a jolt `glitch` tears bands of it sideways and flickers it for a
// frame or two. See docs/specs/cutscene-cockpit.md, "Atmosphere pass".

uniform sampler2D screen_tex : source_color, filter_linear;
uniform float opacity : hint_range(0.0, 1.0) = 0.92;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
// Different per panel, so they do not tear in step.
uniform float seed = 0.0;

float hash(float n) {
	return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float frame = floor(TIME * 40.0);
	if (glitch > 0.0) {
		float band = floor(uv.y * 11.0 + hash(frame) * 5.0);
		float h = hash(band + frame * 3.1);
		if (h > 0.5) {
			uv.x += (h - 0.5) * 0.3 * glitch * sign(hash(band + 7.0) - 0.5);
		}
	}
	vec4 c = texture(screen_tex, uv);
	if (uv.x < 0.0 || uv.x > 1.0) {
		c = vec4(0.0);
	}
	float flick = 1.0 - glitch * 0.45 * step(0.5, hash(frame + 13.0));
	ALBEDO = c.rgb;
	ALPHA = c.a * opacity * flick;
}
