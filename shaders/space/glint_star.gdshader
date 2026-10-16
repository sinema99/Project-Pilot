// The hull glint's star flare (docs/specs/cutscene-intro-space.md, "Effects pass"): a hard
// four-point star on a camera-facing quad. intro_space.gd moves it and sets `glint`.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform float glint = 0.0;
uniform vec3 star_color : source_color = vec3(1.0, 0.98, 0.92);
uniform float energy = 4.0;
// Ray thickness at the centre (fraction of the quad half-size) and the centre disc radius.
uniform float ray_width : hint_range(0.0, 0.5) = 0.06;
uniform float core_radius : hint_range(0.0, 0.5) = 0.1;

void vertex() {
	// Billboard: keep the quad facing the camera, its size in the model's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	// Rays get longer with the glint; each ray tapers to a point.
	float len = glint;
	float h = ray_width * max(0.0, 1.0 - abs(p.x) / max(len, 1e-3));
	float v = ray_width * max(0.0, 1.0 - abs(p.y) / max(len, 1e-3));
	float star = max(step(abs(p.y), h), step(abs(p.x), v));
	star = max(star, step(length(p), core_radius * glint));
	if (star <= 0.0 || glint <= 0.0) {
		discard;
	}
	ALBEDO = star_color * energy * glint;
}
