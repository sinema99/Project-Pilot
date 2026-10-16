// Material overlay on the intro cutscene ship (docs/specs/cutscene-intro-space.md, "Effects pass"):
// re-entry heat on the leading faces and the hull glint, added on top of its cel material.
// intro_space.gd drives every uniform from the shot time.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

group_uniforms Heat;
// 0..1, how far into the re-entry the ship is.
uniform float heat = 0.0;
// World direction the ship is flying (the leading faces point along it).
uniform vec3 lead_dir = vec3(0.0, 0.0, -1.0);
uniform vec3 heat_hot_color : source_color = vec3(1.0, 0.92, 0.7);
uniform vec3 heat_warm_color : source_color = vec3(1.0, 0.45, 0.1);
uniform vec3 heat_dull_color : source_color = vec3(0.45, 0.08, 0.02);
// HDR multiplier on the hottest tone, so the glow catches it.
uniform float heat_energy = 2.5;
group_uniforms;

group_uniforms Glint;
// 0..1 brightness of the glint right now (0 = none).
uniform float glint = 0.0;
// The glint band: a world-space plane (point + normal) sweeping along the hull.
uniform vec3 glint_point = vec3(0.0);
uniform vec3 glint_axis = vec3(0.0, 0.0, 1.0);
// Band half-width in metres.
uniform float glint_width = 1.2;
// World direction toward the sun: faces whose mirror of the sun points at the camera light up.
uniform vec3 sun_toward = vec3(0.0, 0.0, 1.0);
uniform float glint_facing : hint_range(0.0, 1.0) = 0.55;
uniform float glint_energy = 4.0;
group_uniforms;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 col = vec3(0.0);

	// Heat: hard bands on the faces that lead, the bands spread back as the heat builds.
	if (heat > 0.0) {
		float f = dot(n, normalize(lead_dir));
		float hot = step(1.0 - heat * 0.35, f);
		float warm = step(1.0 - heat * 0.9, f);
		float dull = step(0.9 - heat * 1.4, f);
		col += mix(mix(heat_dull_color * dull, heat_warm_color, warm), heat_hot_color * heat_energy, hot)
				* heat;
	}

	// Glint: one hard white band across the faces that mirror the sun into the camera.
	if (glint > 0.0) {
		vec3 view = normalize(CAMERA_POSITION_WORLD - world_pos);
		vec3 h = normalize(normalize(sun_toward) + view);
		float facing = step(glint_facing, dot(n, h));
		float band = step(abs(dot(world_pos - glint_point, normalize(glint_axis))), glint_width);
		col += vec3(1.0) * glint_energy * glint * facing * band;
	}
	ALBEDO = col;
}
