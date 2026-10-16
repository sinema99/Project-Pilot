shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

// Roof-map bake: drawn on every static level mesh by Storm's top-down orthographic camera, once
// at load. Writes the surface's world height so the snow shader can tell "under a roof" from
// "open sky". See docs/specs/ichi-snowstorm.md, "Snow shelter".
//
// Output contract (read back by scripts/rendering/storm.gd and storm_snow.gdshader): h is the
// height normalised over [y_min, y_min + y_span]; R = floor(h * 255) / 255, G = fract(h * 255),
// A = 1 where there is geometry (the clear colour is A = 0). Split so it survives any precision.

uniform float y_min = 0.0;
uniform float y_span = 1.0;

varying float v_height;

void vertex() {
	v_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float h = clamp((v_height - y_min) / y_span, 0.0, 1.0) * 255.0;
	ALBEDO = vec3(floor(h) / 255.0, fract(h), 0.0);
}
