shader_type canvas_item;

// COLOUR DEPTH with the pixel filter OFF: bands the normal full-res 3D render. Sits on
// PixelWorld's layer -100, under every UI layer, so only the world is banded. With the filter on,
// pixel_world.gdshader bands in its own pass instead. See docs/specs/pixel-world.md.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int color_steps = 0;

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	if (color_steps > 1) {
		// color_steps levels, black and white included.
		float steps = float(color_steps - 1);
		col = floor(col * steps + 0.5) / steps;
	}
	COLOR = vec4(col, 1.0);
}
