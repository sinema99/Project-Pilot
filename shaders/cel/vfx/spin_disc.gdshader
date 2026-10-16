shader_type spatial;

// The reflect spin's disc - see docs/specs/pilot9-reflect.md, "The spin disc".
//
// A quad on the staff's spin plane, turned with the staff every frame, so the staff always lies
// along the quad's local Y and its tips sit at the top and bottom edge centres. Inside the circle:
// a faint fill, a brighter rim where the tips run, and a smear wedge trailing each tip. Because
// the quad turns with the staff, the wedges are fixed in UV space and still sweep with it.
//
// The staff turns from local +Y toward local -X (Basis(facing, a), a growing), so "behind" a tip
// is clockwise of it as seen down local +Z.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// 0..1: the staff's angular speed as a fraction of its peak. Set by reflect_spin.gd every frame.
uniform float fade = 0.0;
uniform float disc_alpha = 0.35;
uniform float fill = 0.06;
uniform float rim = 0.6;
// Width of the rim band, as a fraction of the radius.
uniform float rim_width = 0.08;
// How far behind each tip its smear reaches, radians.
uniform float smear_length = 2.1;

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float r = length(p);
	if (r > 1.0 || fade <= 0.0) {
		discard;
	}
	// Angle from +Y in the direction of travel. Both tips share one wedge shape: mod by PI.
	float phi = atan(-p.x, p.y);
	float behind = mod(-phi, PI);
	float smear = 1.0 - clamp(behind / max(smear_length, 0.001), 0.0, 1.0);
	smear = sqrt(smear) * smear;
	// The tips move fastest, so the smear is strongest toward the rim.
	smear *= smoothstep(0.1, 1.0, r);
	float edge = smoothstep(1.0 - rim_width, 1.0 - rim_width * 0.35, r)
		* (1.0 - smoothstep(1.0 - rim_width * 0.35, 1.0, r));
	float a = clamp(fill + rim * edge + smear * (1.0 - fill), 0.0, 1.0);
	ALBEDO = vec3(1.0);
	ALPHA = a * disc_alpha * fade;
}
