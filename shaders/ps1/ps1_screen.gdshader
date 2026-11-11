// The Jetpack look's screen filter: CRT vertical stripes, a light red/blue fringe, a saturated
// grade. Drawn by a full-screen ColorRect on a CanvasLayer below the HUD. See
// docs/specs/jetpack-look.md.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

// Darkening of the stripe column, 0 = no stripes.
uniform float stripe_strength : hint_range(0.0, 1.0) = 0.14;
// Stripe period in screen pixels at 1080p; scales with the screen height.
uniform float stripe_period : hint_range(2.0, 8.0) = 3.0;
// Red/blue offset in pixels at 1080p, growing toward the screen edges.
uniform float fringe_px : hint_range(0.0, 6.0) = 1.0;
uniform float fringe_edge_boost : hint_range(0.0, 4.0) = 1.5;

uniform float saturation : hint_range(0.0, 2.5) = 1.2;
uniform float contrast : hint_range(0.5, 2.0) = 1.12;
uniform vec3 lift = vec3(0.0, 0.0, 0.02);
uniform vec3 gain = vec3(1.02, 1.0, 1.04);

void fragment() {
	vec2 uv = SCREEN_UV;
	float scale = (1.0 / SCREEN_PIXEL_SIZE.y) / 1080.0;

	vec2 from_centre = uv - 0.5;
	float edge = length(from_centre) * 2.0;
	float off = fringe_px * scale * (1.0 + fringe_edge_boost * edge * edge) * SCREEN_PIXEL_SIZE.x;
	vec3 c;
	c.r = texture(screen_tex, uv + vec2(off, 0.0)).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - vec2(off, 0.0)).b;

	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c = c * gain + lift;

	float period = max(stripe_period * scale, 2.0);
	float column = mod(floor(FRAGCOORD.x), floor(period + 0.5));
	if (column < 0.5) {
		c *= 1.0 - stripe_strength;
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
