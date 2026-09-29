shader_type spatial;

// The dash's afterimages - the fill. See docs/specs/pilot9-dash.md, "The afterimages".
//
// One flat colour, unlit: no bands, no rim, no shadow. Drawn at ghost_opacity, but only its
// frontmost surface: afterimage_depth.gdshader lays every ghost's depth down first (render
// priority -1), and this pass only lands where it matches, so a ghost never shows its own limbs
// or the ghost behind it through itself. The ink is afterimage_outline.gdshader, chained on as
// next_pass.
//
// Both colours, the opacity and the fade are instance uniforms, so every ghost shares one
// material and Pilot9Afterimage sets them per ghost with set_instance_shader_parameter().
render_mode unshaded, cull_back, shadows_disabled, depth_draw_never;

instance uniform vec4 ghost_color : source_color = vec4(0.30, 0.90, 1.00, 1.00);
instance uniform float ghost_opacity = 0.5;
// 1.0 solid, 0.0 gone. A dissolve, not alpha - see ghost_dissolved().
instance uniform float ghost_fade = 1.0;

#include "res://shaders/cel/vfx/afterimage_dissolve.gdshaderinc"

void fragment() {
	if (ghost_dissolved(FRAGCOORD.xy, ghost_fade)) {
		discard;
	}
	ALBEDO = ghost_color.rgb;
	ALPHA = ghost_opacity;
}
