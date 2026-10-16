shader_type spatial;

// The fill's depth pass: writes depth, draws nothing. Render priority -1, so every ghost's depth
// is down before any ghost's colour - see afterimage.gdshader.
render_mode unshaded, cull_back, shadows_disabled, depth_draw_always;

instance uniform float ghost_fade : instance_index(2) = 1.0;

#include "res://shaders/cel/vfx/afterimage_dissolve.gdshaderinc"

void fragment() {
	if (ghost_dissolved(FRAGCOORD.xy, ghost_fade)) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
