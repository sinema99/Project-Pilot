shader_type spatial;

// The ink's depth pass: the same hull, depth only, render priority -1. See afterimage.gdshader.
render_mode cull_front, unshaded, depth_draw_always, shadows_disabled;

instance uniform float ghost_fade = 1.0;

#include "res://shaders/cel/vfx/afterimage_dissolve.gdshaderinc"
#include "res://shaders/cel/vfx/afterimage_hull.gdshaderinc"

void fragment() {
	if (ghost_dissolved(FRAGCOORD.xy, ghost_fade)) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
