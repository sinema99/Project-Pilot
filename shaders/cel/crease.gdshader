shader_type spatial;

// unshaded: this is ink, not a surface. It must read the same black in the sun and in a
//   room's interior shadow, so it deliberately skips the cel bands the base shader applies.
// blend_mix: the line is antialiased by coverage (see `half_w` below), so it needs to blend
//   rather than discard.
// cull_back: this pass draws on the map's own front faces. Unlike outline.gdshader it is
//   NOT a hull - nothing is extruded, the geometry is redrawn exactly where it already is.
// depth_draw_never: coplanar with depth that the base pass already wrote. If the build ever
//   shows z-fighting or whole faces of ink dropping out, do NOT nudge a bias - swap to
//   `depth_test_disabled` and test by hand:
//       if (texture(depth_tex, SCREEN_UV).x > FRAGCOORD.z) discard;  // reverse-Z: greater == nearer
//   which is exact and costs a tap that is already being fetched.
render_mode unshaded, blend_mix, cull_back, depth_draw_never;

// Map crease ink. See docs/specs/map-crease-ink.md.
//
// Third pass on the map material, after cel-shader-base (the flat colour) and before
// outline.gdshader (the inverted-hull silhouette). It inks the interior corners a hull
// cannot reach - where a wall meets a floor, or a wall meets another wall - so that a room
// painted one flat swatch per Blender slot still reads as geometry.
//
// It is scoped to the map by *material assignment*, not by any screen-space test: it lives
// on cel_ground.tres and nothing else, so pilot9, EXIA and the sky are never candidates.
//
// == The shape of the pass: WHERE the crease is, not HOW SHARP it is ==
//
// The first build thresholded a sharpness measure directly - it inked wherever a depth tap
// sat far enough off this fragment's tangent plane. That draws a line, but it draws one of
// *variable width*, and it is worth being precise about why, because the fix is the whole
// rewrite:
//
//   Take a fragment k pixels from a crease and tap r pixels towards it. The tap lands on the
//   far face, (r - k) pixels past the corner, so its elevation off this plane grows as the
//   fragment approaches the corner. Thresholding that elevation therefore inks a band - but
//   the band's edge falls wherever "sharpness * (r - k)" happens to cross the threshold, so a
//   90-degree corner inks wider than a 30-degree one, and a corner between a face-on wall and
//   a grazing floor inks wider on one side of itself than on the other. That is exactly the
//   uneven weight this pass shipped with.
//
// So sharpness now decides only *whether* an edge is a crease, and the width comes from an
// independently measured screen-space distance to it. Two taps per direction, at r and 2r
// pixels, give both:
//
//   * `k`, the distance to the crease IN PIXELS, from the ratio of the two elevations. The
//     sharpness cancels out of that ratio (see probe_axis), which is the whole trick.
//   * `bend`, the dihedral angle, from the segment BETWEEN the two taps - that segment lies
//     wholly on the far face, so its tilt is the corner's own angle and does not depend on
//     where between the taps the corner actually falls.
//
// The line is then "1 - smoothstep" over k against a fixed pixel half-width, which is a
// constant weight by construction: at 5 m and at 60 m, on a 90-degree corner and on a
// 30-degree one, at any viewing angle. It matches outline.gdshader, which offsets its hull by
// outline_width / 2 pixels in clip space and is likewise constant in pixels, not in metres.
//
// Both measures are ratios of two 3D lengths, so neither needs the projection matrix and
// neither has a grazing-angle blow-up. An earlier version gated taps against a world-space
// pixel footprint derived from PROJECTION_MATRIX; that footprint came out orders of magnitude
// wrong in this pass and silently rejected every tap in the scene. Nothing here is measured in
// metres, and the only pixel quantities are k and the line width itself.
//
// Reading the depth buffer also means this needs no welded normals, unlike the hull.

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

// Shared with outline.gdshader rather than redeclared, so the crease and the silhouette
// can never drift to two different blacks. Defined in project.godot [shader_globals].
global uniform vec4 outline_color;
// Window pixels per rendered pixel - see docs/specs/pixel-world.md.
global uniform float pixel_block;
// The Ichi storm fogs the ink itself: this pass draws after the fog quad.
#include "res://shaders/storm/storm_fog.gdshaderinc"
// RETRO colours the ink from the fill under it - see docs/specs/retro-look.md.
#include "res://shaders/cel/includes/ink_fill.gdshaderinc"

/// Minimum dihedral angle that earns a line. Below ~20 the blockout's own tessellation
/// starts showing through.
uniform float crease_angle_deg : hint_range(1.0, 89.0) = 28.0;
/// How far a tap's depth may differ from this fragment's, as a fraction of that depth, before
/// it is treated as a separate object rather than a corner of this one. Scale-free on purpose:
/// a fraction works at 2 m and at 200 m, where anything measured in metres or in pixel
/// footprints does not. This is what stops the wall behind pilot9 from tracing a second line
/// around him, and what keeps the sky and the far field out of the test.
uniform float max_depth_jump : hint_range(0.02, 2.0) = 0.25;
/// Convex creases must clear `crease_angle_deg * this`. A tightly curved mesh reads as a
/// shallow convex corner; raise it if a rounded mesh smudges.
uniform float convex_scale : hint_range(1.0, 4.0) = 1.5;
/// Total drawn width of the line, in pixels, at any resolution and any distance. Both faces
/// of a corner ink their own side of it, so each paints half of this. The default matches the
/// hull: outline.gdshader offsets by outline_width / 2, which is 2 px at the project's
/// outline_width of 4.
uniform float line_width_px : hint_range(0.5, 6.0) = 2.0;
/// Full strength up to here...
uniform float fade_start_m = 45.0;
/// ...and gone by here, so a distant room does not become a wire mesh of its own corners.
uniform float fade_end_m = 120.0;
/// Master alpha, for backing the whole effect off without retuning the angles.
uniform float ink_opacity : hint_range(0.0, 1.0) = 1.0;

/// The reciprocal distance a probe reports when it finds nothing: infinitely far away.
const float NO_CREASE = 0.0;

// One depth tap, reconstructed into view space.
//
// Returns w = 1.0 when the tap is usable and w = 0.0 when it must be ignored: the sky (whose
// roofline is the hull's line, and inking it here would double it), or a surface far enough
// off in depth to be a different object rather than a corner of this one. That second test is
// what keeps pilot9 standing against a wall to a single outline instead of two.
//
// `inv_proj` is passed in rather than read from INV_PROJECTION_MATRIX directly: Godot's
// built-ins exist only in the fragment/vertex entry points, and naming one in a helper is a
// compile error ("Unknown identifier in expression"). The headless suite parses shaders even
// though it never draws, so that mistake fails the suite rather than reaching a play session.
vec4 tap_view(vec2 uv, mat4 inv_proj, float centre_depth, float max_jump) {
	float d = texture(depth_tex, uv).x;
	// Reverse-Z: the far plane is 0.0, so this is the sky.
	if (d <= 0.0) {
		return vec4(0.0);
	}
	// Godot 4's own view-space reconstruction. Only xy are remapped to NDC; z is used raw
	// because the depth buffer is already in the projection's own (reversed) range.
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	vec3 p = view.xyz / view.w;
	if (abs(-p.z - centre_depth) > centre_depth * max_jump) {
		return vec4(0.0);
	}
	return vec4(p, 1.0);
}

// Walk one screen direction looking for a crease, and report how far away it is.
//
// `step_uv` is one probe radius in UV; the taps are taken at that radius and at twice it.
//
// Returns (1 / distance-to-the-crease-in-pixels, confidence), and (0.0, 0.0) when this
// direction sees no crease worth inking. The reciprocal rather than the distance itself is
// what the caller wants: taking the nearer of two probes and composing the two axes are both
// operations on reciprocals (see fragment()).
vec2 probe_axis(
		vec2 uv, vec2 step_uv, mat4 inv_proj,
		vec3 centre_view, vec3 n, float centre_depth,
		float max_jump, float probe_px,
		float concave_sin, float convex_sin, float soft) {
	vec4 near_tap = tap_view(uv + step_uv, inv_proj, centre_depth, max_jump);
	vec4 far_tap = tap_view(uv + step_uv * 2.0, inv_proj, centre_depth, max_jump);
	if (near_tap.w * far_tap.w < 1.0) {
		return vec2(NO_CREASE, 0.0);
	}

	// Elevation of each tap above this fragment's tangent plane, in metres. Only their RATIO
	// is ever used, so the unit never has to be reconciled with pixels.
	float h_near = dot(near_tap.xyz - centre_view, n);
	float h_far = dot(far_tap.xyz - centre_view, n);
	// Both taps still on this face (a flat surface), or the crease sits beyond the near tap -
	// in which case it is beyond the line's half-width too, and there is nothing to draw here.
	// The floor is relative to depth so it means the same thing at 2 m and at 200 m.
	if (abs(h_near) < centre_depth * 1e-4) {
		return vec2(NO_CREASE, 0.0);
	}
	// The two taps disagree about which way the surface leaves this plane, so they are not two
	// samples of one far face and the linear model below does not hold.
	if (h_near * h_far <= 0.0) {
		return vec2(NO_CREASE, 0.0);
	}

	// The dihedral angle. The segment between the two taps lies wholly on the far face, so its
	// elevation off this plane - divided by its own 3D length, which makes it a pure sine - is
	// the corner's angle, whatever the viewing angle and wherever between the taps the corner
	// actually falls. Positive is concave (a floor meeting a wall: the far face rises above
	// this plane), negative is convex (the outside corner of a pillar).
	vec3 seg = far_tap.xyz - near_tap.xyz;
	float seg_len = length(seg);
	if (seg_len <= 0.0) {
		return vec2(NO_CREASE, 0.0);
	}
	float bend = dot(seg, n) / seg_len;
	if (bend * h_near <= 0.0) {
		return vec2(NO_CREASE, 0.0);
	}
	// Convex corners are held to the stricter bar; see convex_scale.
	float threshold = bend > 0.0 ? concave_sin : convex_sin;
	// One shoulder of feathering on the ANGLE, so a corner near the cut-off fades in over a
	// few degrees instead of popping. This is confidence, not coverage - it never changes how
	// wide the line is drawn, only how dark.
	float confidence = smoothstep(threshold - soft, threshold + soft, abs(bend));
	if (confidence <= 0.0) {
		return vec2(NO_CREASE, 0.0);
	}

	// Where the crease is, in pixels. Past the corner the far face's elevation grows linearly
	// with screen distance, so with the crease k pixels away and taps at r and 2r:
	//
	//     h_near = c * (r - k)      h_far = c * (2r - k)      q = h_far / h_near
	//     =>  k = r * (q - 2) / (q - 1)
	//
	// The growth rate c - the sharpness of the corner, and the foreshortening of both faces -
	// divides out. That is the entire reason for taking two taps instead of one: k comes back
	// in pixels and in nothing else, so the line drawn from it is a constant pixel weight.
	// q is >= 2 for any real corner (2 when the crease is underfoot, rising as it recedes).
	float q = h_far / h_near;
	float k = probe_px * (q - 2.0) / max(q - 1.0, 1e-4);
	// Guard the reciprocal rather than the distance: a crease underfoot is k = 0.
	return vec2(1.0 / clamp(k, 0.05, probe_px), confidence);
}

void fragment() {
	float view_depth = -VERTEX.z;

	// Half-width because a corner is inked from both sides: this fragment's face paints its
	// own half and the far face paints the other, and they meet at the crease.
	// One block while PixelWorld renders low-res, like the hull outline.
	float half_w = (pixel_block > 1.0 ? 1.0 : max(line_width_px, 0.0)) * 0.5;
	// Probe just past the line's own edge, rounded to whole pixels so the taps land on texel
	// centres - filter_nearest would otherwise snap them, skewing the ratio k is read from.
	float probe_px = max(floor(half_w + 1.5), 1.0);
	vec2 step_x = vec2(probe_px, 0.0) / VIEWPORT_SIZE;
	vec2 step_y = vec2(0.0, probe_px) / VIEWPORT_SIZE;
	float max_jump = max(max_depth_jump, 0.001);

	// sin(), not tan(): `bend` and both thresholds are sines, because every measure here
	// divides by a real 3D length rather than by a screen footprint.
	float concave_sin = sin(radians(clamp(crease_angle_deg, 1.0, 89.0)));
	float convex_sin = min(concave_sin * convex_scale, 1.0);
	float soft = concave_sin * 0.35;

	// A cross, not a ring of eight. The map is axis-aligned boxes, so its creases are
	// horizontal and vertical in screen space far more often than not - the case a cross is
	// best at. Revisit if a curved or rotated map ever ships.
	mat4 inv_proj = INV_PROJECTION_MATRIX;
	vec2 right = probe_axis(SCREEN_UV, step_x, inv_proj, VERTEX, NORMAL, view_depth, max_jump, probe_px, concave_sin, convex_sin, soft);
	vec2 left = probe_axis(SCREEN_UV, -step_x, inv_proj, VERTEX, NORMAL, view_depth, max_jump, probe_px, concave_sin, convex_sin, soft);
	vec2 up = probe_axis(SCREEN_UV, step_y, inv_proj, VERTEX, NORMAL, view_depth, max_jump, probe_px, concave_sin, convex_sin, soft);
	vec2 down = probe_axis(SCREEN_UV, -step_y, inv_proj, VERTEX, NORMAL, view_depth, max_jump, probe_px, concave_sin, convex_sin, soft);

	// Nearer crease wins per axis; these are reciprocals, so nearer is larger.
	float inv_x = max(right.x, left.x);
	float inv_y = max(up.x, down.x);

	// Perpendicular distance to the crease, from its two axis intercepts. A straight line at
	// perpendicular distance p with intercepts a and b satisfies 1/p^2 = 1/a^2 + 1/b^2, so
	// this is exact for a straight crease at any screen orientation. It is the second half of
	// "constant thickness": a cross only ever measures along x and y, and a 45-degree crease
	// is sqrt(2) further away along both of them than it really is, so reading the axis
	// distances raw would draw every diagonal corner thinner than every axis-aligned one. An
	// axis that found nothing contributes 0 and drops out, which is the right answer for a
	// crease running parallel to it.
	float inv_sq = inv_x * inv_x + inv_y * inv_y;

	vec3 ink = ink_from_fill ? ink_from(ink_fill_at(UV)) : outline_color.rgb;
	ALBEDO = storm_fog_ink(ink, length(VERTEX), TIME);
	if (inv_sq <= 0.0) {
		ALPHA = 0.0;
	} else {
		float dist_px = inversesqrt(inv_sq);
		// The line itself: a fixed pixel half-width with one pixel of coverage feathering. A
		// hard step here would alias and crawl as the camera moves, which was logged the last
		// time round and is not being relearned.
		float coverage = 1.0 - smoothstep(half_w - 0.5, half_w + 0.5, dist_px);
		// Darkness comes from the most confident probe that fired.
		float confidence = max(max(right.y, left.y), max(up.y, down.y));
		float fade = 1.0 - smoothstep(fade_start_m, max(fade_end_m, fade_start_m + 0.001), view_depth);
		ALPHA = coverage * confidence * fade * ink_opacity * outline_color.a;
	}
}
