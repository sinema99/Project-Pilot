shader_type spatial;
// unshaded: a screen emits its own light, so it must read the same in the sun and
// in the hub's interior shadow. Everything else on Setsuna goes through
// stylized.gdshader's cel bands; these quads deliberately do not.
// cull_back: a QuadMesh is one-sided, and there is nothing to see from behind a
// panel that is glued to a backpack.
render_mode blend_mix, unshaded, cull_back, depth_draw_opaque;

// Screen material for Setsuna's black `Highlights` regions. See
// docs/specs/setsuna-screens.md.
//
// The quads float 2mm proud of the pure-black panels; the panel underneath is
// the bezel. One rule covers all five screens because the three behaviours
// collapse into one bar:
//
//   health, stamina - `fill` is the fraction
//   dash            - binary, so `fill` is only ever 1.0 or 0.0
//   thighs          - solid state light, so `fill` stays pinned at 1.0
//
// which is why there is no mode uniform.

uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float fill : hint_range(0.0, 1.0) = 1.0;
// The unfilled part of a gauge cannot be black. These panels sit inside pure
// #000000 geometry, carry no outline (the compositor detects edges from depth
// and normals, and a 2mm step at 3m is far under its threshold) and get no
// bloom (glow is off scene-wide). An empty gauge drawn black would be
// indistinguishable from no screen at all. The track is what makes the panel's
// extent visible, and what makes it read as powered rather than as a hole.
uniform float track_level : hint_range(0.0, 1.0) = 0.12;

void fragment() {
	// QuadMesh UVs put V=0 at the top, so the filled run is the bottom `fill`
	// fraction of the quad. Health and stamina therefore fill upward.
	float edge = 1.0 - fill;
	// One pixel of antialiasing, derived rather than fixed so it holds at any
	// distance. Same intent as stylized.gdshader's band_softness: reads as a
	// hard step, does not shimmer as the camera moves. Without it a 45px-tall
	// gauge visibly stair-steps as the value changes.
	float aa = max(fwidth(UV.y) * 0.5, 0.0001);
	float on = smoothstep(edge - aa, edge + aa, UV.y);

	ALBEDO = fill_color.rgb * mix(track_level, 1.0, on);
}
