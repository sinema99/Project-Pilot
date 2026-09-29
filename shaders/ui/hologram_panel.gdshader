shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix;
// Pilot's meshes write stencil 1 while the menu is up: the glass is skipped over him, so he
// stands in front of the hologram.
stencil_mode read, compare_not_equal, 1;

// The pause menu's glass. The menu window is drawn into a SubViewport with its own dark fill, teal
// rim and cut corners; this shows those pixels through a light teal cast and puts a little glass on
// the frame only - glyphs, the selected row's bar and the red-orange destructive tint are the
// bright pixels of the viewport and stay solid, so the row hierarchy survives. Pixels outside the
// frame (the cut corners) stay clear. See docs/specs/menu-refresh.md, "The hologram, toned down".

uniform sampler2D ui_tex : source_color, filter_linear;
uniform vec3 tint : source_color = vec3(0.25, 0.95, 0.9);
// How far the viewport's colours lean toward the tint. 0 = untouched, 1 = the old full mono-tint.
uniform float tint_amount : hint_range(0.0, 1.0) = 0.25;
// 0..1 scanline wipe from the edge nearest his head (the panel's left).
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float glass_alpha = 0.55;
uniform float scan_density = 420.0;
uniform float scan_strength = 0.035;
// Strength of the thin bright rim at the very edge of the quad.
uniform float rim_strength = 0.3;

void fragment() {
	vec2 uv = UV;
	vec4 ui = texture(ui_tex, uv);
	// The viewport is transparent behind the frame and its texture is premultiplied.
	vec3 base = ui.a > 0.001 ? ui.rgb / ui.a : vec3(0.0);
	float lum = dot(base, vec3(0.299, 0.587, 0.114));

	// Glyphs, bars and the destructive tint: near-solid, no scanlines.
	float text = smoothstep(0.22, 0.5, lum) * step(0.001, ui.a);
	// How much of this pixel is the window at all (its fill is ~0.88 alpha).
	float inside = clamp(ui.a / 0.88, 0.0, 1.0);

	float scan = 0.5 + 0.5 * sin(uv.y * scan_density - TIME * 1.5);
	vec2 e = min(uv, 1.0 - uv);
	float edge = 1.0 - smoothstep(0.0, 0.008, min(e.x, e.y));

	vec3 cast = tint / max(max(tint.r, tint.g), tint.b);
	vec3 shown = mix(base, base * cast, tint_amount);
	vec3 glass = shown + tint * (scan * scan_strength * 0.5 + edge * rim_strength);

	vec3 col = mix(glass, shown, text);
	float a = mix(glass_alpha * inside + edge * rim_strength * 0.3 * inside, 1.0, text);

	// Wipe: a bright leading line, then solid behind it.
	float front = reveal * 1.08;
	float visible = 1.0 - smoothstep(front - 0.02, front, uv.x);
	float line = smoothstep(front - 0.06, front - 0.01, uv.x) * visible;
	col += tint * line * 1.5;
	a = max(a * visible, line * 0.9 * step(0.001, inside));

	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
