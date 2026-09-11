shader_type spatial;
render_mode unshaded, cull_back;

// World-space triplanar metre grid, for the jump grid platform's generated boxes.
// See docs/specs/pilot9-jump-grid-platform.md and scripts/jump_grid.gd.
//
// Lines are drawn against WORLD coordinates, not UVs, so they stay square no matter how a
// box is sized: put this on a 6 m pillar and the pillar counts itself, six squares tall,
// from across the map and with no label. A UV grid would stretch with the box and every
// surface would have to be re-scaled by hand to keep a metre a metre - which is the same
// class of silent lie the platform exists to avoid.
//
// Deliberately `unshaded` and outside the cel pipeline. This wants legibility, not art
// direction, and trial.tscn's ApplyCelGround only targets ../TrainingV and ../Mission1, so
// staying out of it costs nothing.
//
// Line colour is DERIVED from `base_color` rather than dialled in: a darkened version of
// whatever tint the box carries. That way one shader reads correctly on a near-black slab,
// a cyan grab strip and a red 18 m lane without a per-box colour decision that could be
// got wrong.

uniform vec4 base_color : source_color = vec4(0.46, 0.48, 0.52, 1.0);

// 1 m minor lines with a heavier line every 5 m. Both are metres, both are read by
// tests/test_pilot9_jump_grid_platform.gd - the whole claim of the surface is that one
// square is one metre, so the spacing is not a look knob.
uniform float minor_spacing = 1.0;
uniform float major_spacing = 5.0;

// Half-widths, in metres. Held constant in world space rather than screen space so a line
// cannot quietly grow into a measurable fraction of a short gap when the camera pulls back.
uniform float minor_width = 0.015;
uniform float major_width = 0.045;

// How far toward black each line pulls the base tint. 1.0 leaves the base untouched.
uniform float minor_darken = 0.66;
uniform float major_darken = 0.34;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	// MODEL_MATRIX and not the view matrix: the grid has to be nailed to the world, so
	// that two boxes meeting at an edge continue each other's lines.
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

// Coverage of the nearest line on one axis. `fract(v/s - 0.5) - 0.5` is the signed distance
// to the nearest multiple of `s` in units of `s`; scaling back up puts it in metres.
float line_axis(float v, float spacing, float width) {
	float d = abs(fract(v / spacing - 0.5) - 0.5) * spacing;
	// One pixel of antialiasing, so a line viewed edge-on does not shimmer into a moire.
	float aa = fwidth(v) * 0.75 + 0.0001;
	return 1.0 - smoothstep(width - aa, width + aa, d);
}

float line_plane(vec2 p, float spacing, float width) {
	return max(line_axis(p.x, spacing, width), line_axis(p.y, spacing, width));
}

void fragment() {
	// Triplanar: each face takes its two world axes from the two the normal is NOT along,
	// weighted so a chamfer or a rotated box blends instead of popping.
	vec3 w = abs(world_normal);
	w /= max(w.x + w.y + w.z, 0.0001);

	float minor = w.x * line_plane(world_pos.yz, minor_spacing, minor_width)
		+ w.y * line_plane(world_pos.xz, minor_spacing, minor_width)
		+ w.z * line_plane(world_pos.xy, minor_spacing, minor_width);
	float major = w.x * line_plane(world_pos.yz, major_spacing, major_width)
		+ w.y * line_plane(world_pos.xz, major_spacing, major_width)
		+ w.z * line_plane(world_pos.xy, major_spacing, major_width);

	// Major last so a 5 m line wins where it lands on top of a 1 m one.
	vec3 col = base_color.rgb;
	col = mix(col, base_color.rgb * minor_darken, minor);
	col = mix(col, base_color.rgb * major_darken, major);
	ALBEDO = col;
}
