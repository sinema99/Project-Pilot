// Re-entry bow shock around the intro cutscene ship (docs/specs/cutscene-intro-space.md,
// "Effects pass"): a shell over the ship's nose, only its rim drawn, in hard orange steps.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// 0..1, set by intro_space.gd from the shot time.
uniform float heat = 0.0;
uniform vec3 rim_hot_color : source_color = vec3(1.0, 0.8, 0.45);
uniform vec3 rim_color : source_color = vec3(1.0, 0.38, 0.08);
// Rim thickness: how far toward face-on the outer and the hot band reach.
uniform float rim_outer : hint_range(0.0, 1.0) = 0.5;
uniform float rim_hot : hint_range(0.0, 1.0) = 0.78;
uniform float energy = 1.8;

void fragment() {
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	// The shell grows in as the heat builds.
	float outer = step(1.0 - rim_outer * heat, rim);
	if (outer <= 0.0 || heat <= 0.0) {
		discard;
	}
	float hot = step(1.0 - (1.0 - rim_hot) * heat, rim);
	ALBEDO = mix(rim_color, rim_hot_color * 1.6, hot) * energy * heat;
}
