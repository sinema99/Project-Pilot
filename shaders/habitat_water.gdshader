shader_type spatial;
render_mode unshaded, cull_disabled;

// The habitat lake: flat dark water with a pale sky sheen at grazing angles and a few cel-hard
// glare streaks near `glare_centre`, like the painting's bright patch under the tower. Unshaded and
// opaque: the lakebed below is solid, and letting it show through is not worth a depth read.

uniform vec4 deep_color : source_color = vec4(0.055, 0.095, 0.17, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.12, 0.22, 0.34, 1.0);
uniform vec4 sky_color : source_color = vec4(0.72, 0.82, 0.93, 1.0);
uniform vec2 glare_centre = vec2(60.0, -10.0);
uniform float glare_radius = 70.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 v = normalize(VIEW);
	float fres = pow(1.0 - clamp(abs(dot(v, vec3(0.0, 1.0, 0.0))), 0.0, 1.0), 3.0);

	// Slow ripple bands, hard-edged so they read as paint strokes rather than smooth noise.
	float w = sin(world_pos.x * 0.35 + sin(world_pos.z * 0.21) * 2.0 + TIME * 0.25)
		+ sin(world_pos.z * 0.9 + sin(world_pos.x * 0.17) * 1.5 - TIME * 0.35) * 0.6;
	float band = step(0.55, w);

	vec3 col = mix(deep_color.rgb, shallow_color.rgb, band * 0.6 + 0.2);
	col = mix(col, sky_color.rgb, fres * 0.75);

	float d = length(world_pos.xz - glare_centre) / glare_radius;
	float glare = (1.0 - smoothstep(0.35, 1.0, d)) * step(0.85, w + fres * 0.6);
	col = mix(col, vec3(0.95, 0.97, 1.0), glare * 0.8);

	ALBEDO = col;
}
