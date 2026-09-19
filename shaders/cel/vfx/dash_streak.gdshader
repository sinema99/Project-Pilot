shader_type spatial;

// The dash's manga speed lines. Unlit and pure black - outline_color is the same pigment every
// outline in the game is inked in, so a speed line drawn in it reads as part of the same frame
// rather than a borrowed effect. See docs/specs/pilot9-dash.md, "The ink streak".
//
// The bundle is 5-7 separate strokes, one surface each, splayed open behind him and pinched to
// a short segment where they meet his chest. All of the shape - the spindle taper along each
// line, the pen weight in pixels, the converging offsets - is built in pilot9.gd's
// _streak_bundle(), because it is geometry rather than shading and because a static function
// can be asserted headlessly where a shader cannot.
//
// cull_disabled: the strokes are flat quad strips and camera-facing, so the camera can end up
// looking at either side of one as it turns past. No depth write: they are a few centimetres
// from the geometry he just ran through and a z-fight there would flicker. Lines within the
// bundle also overlap each other constantly, and with depth write on the nearer stroke would
// punch a hole in the one behind it instead of inking over it.
render_mode cull_disabled, unshaded, blend_mix, depth_draw_never, shadows_disabled;

global uniform vec4 outline_color;

// Per-vertex alpha is the staggered fade: pilot9.gd writes one flat alpha per stroke via
// surface_set_color(), and the strokes carry different ones on the same frame - the thinnest
// lines reach zero first so the bundle thins out as it dies rather than dimming as a slab.
// The geometric tapers (the spindle along the line, the pen weight) are baked into vertex
// position and are therefore free here.
void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a * COLOR.a;
}
