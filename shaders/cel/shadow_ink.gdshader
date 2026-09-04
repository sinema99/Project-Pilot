shader_type spatial;

// Screen-space shadow ink. Used only as a next_pass on ground-type materials.
// The base pass has already shaded the ground: bright where the sun reaches it,
// flat cool ambient where a cast shadow falls. We trace that lit/shadow border
// as a solid black pen line.
//
// How it stays a SOLID line, not a grey sketch:
//   * `shadow_amt()` is a soft 0..1 classification (smoothstep, not step) so the
//     border position is sub-pixel stable instead of flickering in the penumbra.
//   * The 8-tap ring accumulates how much the neighbourhood disagrees with the
//     centre, then `ink_gain` blows that up so ANY real border signal clamps to
//     1.0. Result: uniform opaque black wherever the border passes within
//     `line_width` px, with only a ~1px anti-aliased shoulder. No partial-grey
//     stretches on shallow-angle edges.
//   * Line thickness == `line_width` px and is fully decoupled from the shadow
//     map's penumbra width, so `shadow_blur` can be raised to round off the
//     shadow-map stair-steps without fattening the line.
//
// The cut is an absolute luminance, so it must sit in the gap between any cast
// shadow (~0.73 here) and lit ground (~0.95).
//
// GATED TO NEAR-HORIZONTAL SURFACES. cel_ground.tres is applied to the whole
// platform GLB -- ground, walls, floating spheres. On a flat surface the
// lit/shadow terminator is one clean line; on a curved sphere it sweeps across
// the surface at a grazing angle and the cel bands / specular wobble across
// `ink_cut`, so screen-space edge detection hatches the whole terminator band
// into a moire mess. Cast-shadow ink is a ground effect, so we only draw it
// where the fragment normal points roughly up.

render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
// The scene-wide ink colour, set in project.godot (shared with outline.gdshader).
global uniform vec4 outline_color;

// Ring radius in screen pixels == drawn line half-width.
uniform float line_width : hint_range(0.25, 3.0) = 0.9;
// Luminance splitting lit ground from any cast shadow.
uniform float ink_cut : hint_range(0.0, 1.0) = 0.82;
// Softness of the classification crossing (keep small).
uniform float ink_feather : hint_range(0.005, 0.15) = 0.03;
// How hard the accumulated border signal is pushed to full opacity. Higher =
// more of the line is dead solid black, less AA shoulder.
uniform float ink_gain : hint_range(1.0, 16.0) = 6.0;
// Master opacity for the inked line.
uniform float ink_strength : hint_range(0.0, 1.0) = 1.0;
// Below this |world normal.y| the surface is treated as wall/prop and gets no
// ink. abs() so a flipped ground normal still passes. Flat ground/platform-top
// read ~1.0; sphere sides and walls read ~0.
uniform float ground_min_up : hint_range(0.0, 1.0) = 0.7;

varying vec3 world_normal;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// 1.0 fully in shadow, 0.0 fully lit, smooth across the crossing.
float shadow_amt(vec2 uv) {
	float l = luma(texture(screen_tex, uv).rgb);
	return 1.0 - smoothstep(ink_cut - ink_feather, ink_cut + ink_feather, l);
}

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	// Reject anything that isn't roughly a floor.
	float up = abs(normalize(world_normal).y);
	float ground = smoothstep(ground_min_up, min(ground_min_up + 0.1, 1.0), up);
	if (ground <= 0.0) {
		ALPHA = 0.0;
	} else {
	vec2 o = (1.0 / VIEWPORT_SIZE) * line_width;
	float c = shadow_amt(SCREEN_UV);

	float acc = 0.0;
	acc += abs(c - shadow_amt(SCREEN_UV + vec2( o.x,  0.0)));
	acc += abs(c - shadow_amt(SCREEN_UV + vec2(-o.x,  0.0)));
	acc += abs(c - shadow_amt(SCREEN_UV + vec2( 0.0,  o.y)));
	acc += abs(c - shadow_amt(SCREEN_UV + vec2( 0.0, -o.y)));
	acc += abs(c - shadow_amt(SCREEN_UV + vec2( o.x * 0.707,  o.y * 0.707)));
	acc += abs(c - shadow_amt(SCREEN_UV + vec2(-o.x * 0.707,  o.y * 0.707)));
	acc += abs(c - shadow_amt(SCREEN_UV + vec2( o.x * 0.707, -o.y * 0.707)));
	acc += abs(c - shadow_amt(SCREEN_UV + vec2(-o.x * 0.707, -o.y * 0.707)));

	float ink = clamp(acc * ink_gain, 0.0, 1.0) * ink_strength * ground;

	ALBEDO = outline_color.rgb;
	ALPHA = ink * outline_color.a;
	}
}
