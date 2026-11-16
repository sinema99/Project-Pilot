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

// Characters in a coarser grid (docs/specs/airframe-character-pixels.md). CharView draws only the
// characters, `char_block` window pixels per texel, hard-edged, on a transparent background. The
// 2X world pass paints each close character a flat marker colour (ps1_surface), so the marker says
// "a character is visible here, not behind the level". A char block shows CharView's colour where
// CharView covers it AND the world pass has marker inside it; the world's own depth decides the
// occlusion, at the world's block size. 0 = off (WorldView only).
uniform sampler2D char_tex : filter_nearest, repeat_disable;
uniform int char_block = 0;

bool is_marker(vec3 c) {
	// Fuzzy on purpose: a transparent effect (revolver materialize, afterimage, speed trail) drawn
	// over a character blends with the magenta marker, and a strict test lets that pink through.
	float lo = min(c.r, c.b);
	return lo > 0.5 && c.g < lo * 0.75;
}

// The box average of one world block's texels, markers left out. `all_marker` when nothing is left.
vec3 world_block(ivec2 texel, ivec2 size, int ss, out bool all_marker) {
	vec3 sum = vec3(0.0);
	float n = 0.0;
	for (int y = 0; y < ss; y++) {
		for (int x = 0; x < ss; x++) {
			vec3 t = texelFetch(view_tex, clamp(texel * ss + ivec2(x, y), ivec2(0), size - 1), 0).rgb;
			if (char_block == 0 || !is_marker(t)) {
				sum += t;
				n += 1.0;
			}
		}
	}
	all_marker = n < 0.5;
	return all_marker ? vec3(0.0) : sum / n;
}

void fragment() {
	vec2 pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	ivec2 size = textureSize(view_tex, 0);
	int ss = max(supersample, 1);
	float bf = float(max(block, 1));
	ivec2 blocks = size / ss;
	// The block this fragment is in.
	ivec2 texel = clamp(ivec2(floor(pixel / bf)), ivec2(0), blocks - 1);
	if (!opaque) {
		// SharpView: a plain transparent copy, no characters.
		vec4 sharp = vec4(0.0);
		for (int y = 0; y < ss; y++) {
			for (int x = 0; x < ss; x++) {
				sharp += texelFetch(view_tex, clamp(texel * ss + ivec2(x, y), ivec2(0), size - 1), 0);
			}
		}
		sharp /= float(ss * ss);
		sharp.rgb = pixel_quantize(sharp.rgb, color_steps);
		COLOR = sharp;
	} else {
	bool all_marker;
	vec4 col = vec4(world_block(texel, size, ss, all_marker), 1.0);

	if (char_block > 0) {
		if (all_marker) {
			// A character's 2X silhouette edge the 4X grid does not cover: borrow the nearest
			// block that is level, not marker.
			ivec2 offs[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
			for (int i = 0; i < 4; i++) {
				bool am;
				vec3 c = world_block(clamp(texel + offs[i], ivec2(0), blocks - 1), size, ss, am);
				if (!am) {
					col.rgb = c;
					break;
				}
			}
		}
		float cf = float(char_block);
		ivec2 csize = textureSize(char_tex, 0);
		ivec2 cb = clamp(ivec2(floor(pixel / cf)), ivec2(0), csize - 1);
		vec4 ch = texelFetch(char_tex, cb, 0);
		if (ch.a > 0.5) {
			bool visible = false;
			for (int i = 0; i < 4; i++) {
				vec2 p = (vec2(cb) + vec2((i & 1) == 1 ? 0.75 : 0.25, (i >> 1) == 1 ? 0.75 : 0.25)) * cf;
				ivec2 wt = clamp(ivec2(floor(p / bf)), ivec2(0), blocks - 1);
				if (is_marker(texelFetch(view_tex, wt * ss + ivec2(ss / 2), 0).rgb)) {
					visible = true;
				}
			}
			if (visible) {
				col.rgb = ch.rgb;
			}
		}
	}

	col.rgb = pixel_quantize(col.rgb, color_steps);

	COLOR = vec4(col.rgb, 1.0);
	}
}
