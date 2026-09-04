shader_type canvas_item;

// Full-screen retro downsample. Lives on a ColorRect inside a CanvasLayer so it
// runs after the 3D viewport (and the cel outline pass) have already drawn - it
// crunches the finished frame, it is not a material.
//
// Two knobs, both driven from scripts/rendering/pixelate.gd:
//   pixel_grid  - the effective resolution the frame is resampled to. The screen
//                 UV is snapped to this grid and sampled at the cell centre, so
//                 geometry edges and outlines go blocky together.
//   color_steps - levels per channel. 0 disables the quantise; low values give
//                 the PS1-era banded look, high values leave colour untouched.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 pixel_grid = vec2(320.0, 180.0);
uniform int color_steps = 0;

void fragment() {
	vec2 uv = (floor(SCREEN_UV * pixel_grid) + 0.5) / pixel_grid;
	vec3 col = texture(screen_tex, uv).rgb;

	if (color_steps > 1) {
		float steps = float(color_steps);
		col = floor(col * steps + 0.5) / steps;
	}

	COLOR = vec4(col, 1.0);
}
