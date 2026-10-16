shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// The soft glow round the tredge's staff light: a camera-facing quad, brightest at the centre and
// gone at the rim. Ichi has no bloom, so this is the ball's glow. See docs/specs/pilot9-tredge.md,
// "Staff light".

uniform vec3 color : source_color = vec3(1.0, 0.824, 0.627);
// 0..1: the light's fade times its flicker.
uniform float strength = 1.0;
uniform float intensity = 0.8;

void vertex() {
	// Billboard: keep the node's position and scale, face the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1],
			INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float glow = 1.0 - smoothstep(0.0, 1.0, r);
	glow *= glow;
	ALBEDO = color * glow * intensity * strength;
	ALPHA = 1.0;
}
