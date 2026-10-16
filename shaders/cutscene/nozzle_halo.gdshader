// Bloom halo on the main engine (docs/specs/cutscene-flyover.md, "Nozzle propulsion"): a soft
// camera-facing ball of light around the nozzle, white-hot in the middle and pale cyan out to its
// rim, behind the hard glow disc. Its size and brightness flicker on the shot clock (a sum of
// sines, so seeking shows the same frame). Additive, and drawn without a depth test: it is light
// spilling over the hull, the way the reference's bloom spills over the rocket.
//
// The quad is a unit QuadMesh on a node scaled to the halo's diameter.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 rim_color : source_color = vec3(0.7, 0.93, 1.0);
// Brightness at the centre (HDR, so the environment glow catches it) and how soon it turns cyan.
uniform float energy = 1.2;
uniform float core_radius : hint_range(0.0, 1.0) = 0.5;
// Falloff power: higher pulls the light in toward the centre.
uniform float falloff = 3.0;
// Flicker: fraction of size and brightness it swings by, and its rough rate (Hz).
uniform float flicker = 0.08;
uniform float flicker_rate = 9.0;
uniform float shot_time = 0.0;

varying float v_flick;

void vertex() {
	float w = TAU * flicker_rate * shot_time;
	v_flick = 0.55 * sin(w + 0.3) + 0.3 * sin(w * 1.73 + 2.1) + 0.15 * sin(w * 2.91 + 4.0);
	float size = length(MODEL_MATRIX[0].xyz) * (1.0 + flicker * v_flick);
	// Billboard: the quad's corners laid out along the camera's right and up.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size,
			INV_VIEW_MATRIX[2] * size, MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	if (r >= 1.0) {
		discard;
	}
	float a = pow(1.0 - r, falloff);
	vec3 col = mix(core_color, rim_color, smoothstep(0.0, core_radius, r));
	ALBEDO = col * energy * (1.0 + flicker * v_flick);
	ALPHA = clamp(a, 0.0, 1.0);
}
