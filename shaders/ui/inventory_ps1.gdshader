// The inventory screen's composite: the low-res canvas, scaled up nearest, made PS1.
// See docs/specs/inventory.md, decision 9, and docs/specs/ps1-ui.md.
//
// - alpha: no blending and NO dither. A texel is drawn or it is not (cut at 0.5), so plates are
//   solid. The old 4x4 Bayer screen-door read as a checkerboard and was removed on request.
// - 15-bit colour: every channel rounded to 32 levels, plain rounding, so gradients band in hard
//   steps like the real thing instead of dithering.
shader_type canvas_item;

uniform vec2 canvas_texels = vec2(640.0, 360.0);
uniform bool colour_15bit = true;

void fragment() {
	ivec2 texel = ivec2(floor(UV * canvas_texels));
	vec4 c = texture(TEXTURE, (vec2(texel) + 0.5) / canvas_texels);
	if (c.a < 0.5) {
		discard;
	}
	vec3 col = c.rgb;
	if (colour_15bit) {
		col = floor(col * 31.0 + 0.5) / 31.0;
	}
	COLOR = vec4(col, 1.0);
}
