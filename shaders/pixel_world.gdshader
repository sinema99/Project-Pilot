shader_type canvas_item;

#include "res://shaders/pixel_quantize.gdshaderinc"

// Draws PixelWorld's low-res WorldView (or its full-res SharpView) over the whole screen. See
// docs/specs/pixel-world.md.
//
// The texel is picked from the *physical* pixel this fragment lands on, not from UV: the canvas
// is stretched (canvas_items, 1920x1080 base), so a texture laid on a rect would map a block to
// 3.999 or 4.001 window pixels and some columns would come out a pixel wider. texelFetch at
// floor(pixel / block) makes every block exactly `block` x `block` window pixels.

uniform sampler2D view_tex : filter_nearest, repeat_disable;
// Window pixels per texel: the block size for WorldView, 1 for SharpView.
uniform int block = 3;
// Levels per channel; 0 leaves colour untouched. WorldView only.
uniform int color_steps = 0;
// WorldView covers the screen; SharpView is mostly transparent and blends.
uniform bool opaque = true;
// Rendered texels per block side. Above 1 the block is the box average of supersample x
// supersample texels, so an edge or a grain speck that covers part of a block shades it part-way
// instead of snapping the whole block on or off as the camera moves. The PIXEL look uses 2.
uniform int supersample = 1;

void fragment() {
	vec2 pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	ivec2 size = textureSize(view_tex, 0);
	int ss = max(supersample, 1);
	// The block this fragment is in.
	ivec2 texel = clamp(ivec2(floor(pixel / float(max(block, 1)))), ivec2(0), size / ss - 1);
	vec4 col = vec4(0.0);
	for (int y = 0; y < ss; y++) {
		for (int x = 0; x < ss; x++) {
			col += texelFetch(view_tex, clamp(texel * ss + ivec2(x, y), ivec2(0), size - 1), 0);
		}
	}
	col /= float(ss * ss);

	col.rgb = pixel_quantize(col.rgb, color_steps);

	COLOR = opaque ? vec4(col.rgb, 1.0) : col;
}
