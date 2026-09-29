// Shared by afterimage.gdshader and afterimage_outline.gdshader, so a ghost's fill and its ink
// throw away the same pixels as it fades and the line never outlives the body it outlines.
//
// A screen-space hash on 3 px cells rather than fading alpha, so the depth passes throw away the
// same pixels as the colour passes and the ghost never needs sorting. Cells rather than single
// pixels so the dissolve reads as breaking up, not as static.
bool ghost_dissolved(vec2 frag_coord, float fade) {
	vec2 cell = floor(frag_coord / 3.0);
	float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	return h >= fade;
}
