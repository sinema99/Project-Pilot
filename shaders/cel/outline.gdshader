shader_type spatial;

render_mode cull_front, unshaded, depth_draw_never;

global uniform vec4 outline_color;
global uniform float outline_width;
// Window pixels per rendered pixel; above 1 while PixelWorld renders the world low-res. The
// outline is then exactly one block: width 2.0 pushes the hull out 1 texel, since NDC spans 2
// units per VIEWPORT_SIZE. See docs/specs/pixel-world.md.
global uniform float pixel_block;

// The Ichi storm fogs the hull itself: drawn over sky pixels, the fog quad never reaches it.
#include "res://shaders/storm/storm_fog.gdshaderinc"
// RETRO colours the hull from the fill under it - see docs/specs/retro-look.md.
#include "res://shaders/cel/includes/ink_fill.gdshaderinc"

// This material's own VISIBLE line width in pixels at 1080p, scaled with the viewport height so the
// line is the same share of the frame at any resolution; below 0 = the global outline_width. Note
// the units differ: outline_width is the hull push, and the visible line is half of it (CEL's 4
// draws 2 px). RETRO's line without touching the global the cutscenes share.
uniform float ink_width = -1.0;

void vertex() {
	float width = pixel_block > 1.0 ? 2.0 : (ink_width >= 0.0 ? ink_width * 2.0 * VIEWPORT_SIZE.y / 1080.0 : outline_width);
	vec4 clip_position = 
			PROJECTION_MATRIX *
			(MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 clip_normal =
			mat3(PROJECTION_MATRIX) *
			(mat3(MODELVIEW_MATRIX) * NORMAL);
	clip_position.xy +=
			normalize(clip_normal.xy) /
			VIEWPORT_SIZE *
			clip_position.w *
			width;
	POSITION = clip_position;
}

void fragment() {
	vec3 ink = ink_from_fill ? ink_from(ink_fill_at(UV)) : outline_color.rgb;
	ALBEDO = storm_fog_ink(ink, length(VERTEX), TIME);
}
