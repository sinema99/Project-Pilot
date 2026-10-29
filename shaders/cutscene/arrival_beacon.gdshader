// A blinking beacon on the arrival shot's towers (scripts/cutscene/arrival.gd): a camera-facing
// HDR dot, bright enough to bloom. `energy` is pushed per beacon every frame (0 = off).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.1, 0.06);
instance uniform float energy = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float glow = exp(-r * r * 7.0) * (1.0 - smoothstep(0.85, 1.0, r));
	ALBEDO = color * energy * glow;
}
