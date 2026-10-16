// Colour quantize shared by PixelWorld's world pass and ScreenPixel's whole-screen pass, so the two
// land on exactly the same colours and the screen pass leaves the already-pixelated world alone.
// See docs/specs/pixel-look.md and docs/specs/pixel-world.md.

// color_steps levels per channel, black and white included; 0 or 1 is full colour. Plain
// rounding, no dither: the PIXEL look's banding should read as a few wide, soft steps, not a
// pattern (the Bayer dither was removed in the 2026-10-06 reference pass).
vec3 pixel_quantize(vec3 col, int color_steps) {
	if (color_steps > 1) {
		float steps = float(color_steps - 1);
		return floor(col * steps + 0.5) / steps;
	}
	return col;
}
