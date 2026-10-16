// Cel scatter: smudged band edges. Noise is added to the value that feeds diffuse_curve, so each
// cel edge wanders and smears like a dry brush dragged across it: stretched, softly bending
// strokes lying along the surface. Dark strokes push into the lit side of an edge, lighter ones
// into the dark side. With five bands there is an edge everywhere, so the smear shows everywhere.
// See docs/specs/cel-scatter.md.
//
// Needs painted.gdshaderinc (paint_value_noise) included first. Not part of the upstream shader.

global uniform float scatter_strength;
global uniform float scatter_dark;
global uniform float scatter_light;
global uniform float scatter_reach;
global uniform float scatter_world_size;
global uniform float scatter_uv_size;

// How much longer a stroke is than it is wide, and how far the strokes bow sideways.
const float SCATTER_STRETCH = 8.0;
const float SCATTER_BEND = 1.6;

// One stroke field: first coordinate is the stroke direction. A slow warp bends the strokes, then
// two octaves of value noise stretched along that direction give broad strokes plus fine bristle.
// Returns 0..1 around 0.5.
float scatter_stroke(vec2 p) {
	p += vec2(91.7, 13.3);
	p.y += SCATTER_BEND * (paint_value_noise(p * vec2(0.12, 0.25)) - 0.5) * 4.0;
	vec2 q = vec2(p.x / SCATTER_STRETCH, p.y);
	float broad = paint_value_noise(q);
	float bristle = paint_value_noise(vec2(q.x * 0.5, q.y * 3.1) + vec2(7.9, 23.1));
	return 0.7 * broad + 0.3 * bristle;
}

// World anchor: the dominant axis only, strokes running horizontally on walls and along x on
// floors. On axis-aligned level geometry this is one plane anyway.
float scatter_stroke_world(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.x >= a.y && a.x >= a.z) {
		return scatter_stroke(p.zy);
	}
	if (a.y >= a.z) {
		return scatter_stroke(p.xz + vec2(31.7, 11.9));
	}
	return scatter_stroke(p.xy + vec2(63.1, 47.3));
}

// The signed shift added to the diffuse curve input at this pixel. Negative = darker, positive =
// lighter. Value noise bunches around 0.5, so it is stretched before use.
float scatter_shift_at(float stroke) {
	float s = clamp((stroke - 0.5) * 3.0, -1.0, 1.0);
	float weight = s < 0.0 ? scatter_dark : scatter_light;
	return s * weight * scatter_reach * scatter_strength;
}
