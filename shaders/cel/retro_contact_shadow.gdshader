shader_type spatial;

// RETRO's contact shadow (docs/specs/retro-look-pass-2.md): a soft flat ellipse painted on the
// ground under a cel, the anime staple. Multiplied over what is already there, so it darkens the
// floor toward `tint` without hiding its panel lines. The quad's UV spans the ellipse.
render_mode unshaded, blend_mul, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint: source_color = vec3(0.55, 0.55, 0.72);
// 0..1, set per frame by RetroContactShadow (fades with height).
uniform float strength = 0.6;
// How much of the radius the soft edge takes.
uniform float softness = 0.35;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float a = (1.0 - smoothstep(1.0 - softness, 1.0, r)) * strength;
	ALBEDO = mix(vec3(1.0), tint, a);
}
