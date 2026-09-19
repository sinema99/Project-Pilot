shader_type spatial;

// The dash's ink streak. Unlit and pure black - outline_color is the same pigment every
// outline in the game is inked in, so a speed line drawn in it reads as part of the same
// frame rather than a borrowed effect. See docs/specs/pilot9-dash.md, "The ink streak".
//
// cull_disabled: the ribbon is a flat quad strip and camera-facing, so the camera can end up
// looking at either side of it as it turns past. No depth write: it is a few centimetres from
// the geometry he just ran through and a z-fight there would flicker.
render_mode cull_disabled, unshaded, blend_mix, depth_draw_never, shadows_disabled;

global uniform vec4 outline_color;

// Per-vertex alpha carries both tapers pilot9.gd builds into the mesh: the geometric one
// (width narrowing toward the tail, baked into vertex position and therefore free here) and
// the temporal one (the ~0.15 s fade after he reappears, written as a flat per-vertex alpha
// by _rebuild_dash_streak_mesh()).
void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a * COLOR.a;
}
