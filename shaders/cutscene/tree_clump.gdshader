shader_type spatial;
// The descent shot's far spruce clumps, 1.5-5 km out (docs/specs/descent-trees.md row 6): a forced
// 2-tone cel, a lit green and a shadow green split hard by the sun's direction. No snow, paint,
// scatter or ink. Opaque, so the storm's depth fog pales it like the city.
render_mode unshaded, cull_back, shadows_disabled;

uniform vec3 lit_color : source_color = vec3(0.1, 0.155, 0.14);
uniform vec3 shadow_color : source_color = vec3(0.045, 0.07, 0.065);
// World direction toward the sun (DescentTrees sets it from the Sun node).
uniform vec3 to_light = vec3(-1.0, 0.0, 0.0);
// How far a face may turn from the sun and still count as lit (cosine).
uniform float split = 0.05;

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ALBEDO = dot(n, normalize(to_light)) > split ? lit_color : shadow_color;
}
