shader_type spatial;

// The dash's afterimages - the ink. outline.gdshader's inverted hull, same global outline_width
// so a ghost's line is the same pen as his, but inked in a darker shade of the ghost's own
// colour instead of black, at the fill's ghost_opacity. Chained as next_pass on
// afterimage.gdshader; afterimage_outline_depth.gdshader is its depth pass, so the hull's
// overlapping back faces blend once, not twice.
render_mode cull_front, unshaded, depth_draw_never, shadows_disabled;

instance uniform vec4 ghost_line_color : source_color, instance_index(3) = vec4(0.12, 0.40, 0.45, 1.00);
instance uniform float ghost_opacity : instance_index(1) = 0.5;
instance uniform float ghost_fade : instance_index(2) = 1.0;

#include "res://shaders/cel/vfx/afterimage_dissolve.gdshaderinc"
#include "res://shaders/cel/vfx/afterimage_hull.gdshaderinc"

void fragment() {
	if (ghost_dissolved(FRAGCOORD.xy, ghost_fade)) {
		discard;
	}
	ALBEDO = ghost_line_color.rgb;
	ALPHA = ghost_opacity;
}
