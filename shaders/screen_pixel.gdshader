shader_type canvas_item;

// ScreenPixel: the PIXEL look laid over the finished frame - HUD, menus, prompts and the hologram
// included. See docs/specs/pixel-look.md, "Whole screen".
//
// Same block grid as pixel_world.gdshader (floor(physical pixel / block) from the top-left), and
// the same quantize, so the world under it - already one solid, already-quantized colour per
// block - comes through unchanged. Only things drawn at full resolution (the UI) change.
//
// Each block is the box average of its window pixels rather than one picked pixel: thin text
// strokes then shade a block part-way and stay readable, where a nearest pick would make them
// flicker in and out of existence.

#include "res://shaders/pixel_quantize.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
// Window pixels per block.
uniform int block = 3;
uniform int color_steps = 0;

void fragment() {
	vec2 pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	ivec2 size = textureSize(screen_tex, 0);
	int b = max(block, 1);
	ivec2 texel = ivec2(floor(pixel / float(b)));
	vec3 col = vec3(0.0);
	for (int y = 0; y < b; y++) {
		for (int x = 0; x < b; x++) {
			col += texelFetch(screen_tex, clamp(texel * b + ivec2(x, y), ivec2(0), size - 1), 0).rgb;
		}
	}
	col /= float(b * b);
	COLOR = vec4(pixel_quantize(col, color_steps), 1.0);
}
