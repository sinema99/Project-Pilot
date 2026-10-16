shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix, shadows_disabled, fog_disabled;

// Distance fog with a two-tone gradient: near colour close to the camera, blending to the far
// colour at the visibility wall. A full-screen quad that reads the depth buffer (Godot's own fog
// has one colour). Sky pixels are left alone, so the sky material shows through and its horizon
// colour is what the far fog fades into. The wall closes in on each gust, on the snow's own gust
// curve. Every value is a storm_* global (storm_fog.gdshaderinc), shared with the ink passes.
// See docs/specs/ichi-snowstorm.md.

#include "res://shaders/storm/storm_fog.gdshaderinc"
#include "res://shaders/storm/storm_torch.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

void vertex() {
	// Reversed-Z: z = 1 is the near plane, so the quad covers everything and is never clipped.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).x;
	bool sky = depth < 0.0000001;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, sky ? 0.0000001 : depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float dist = length(view.xyz);
	// Sky pixels take no fog (the sky material shows through), only the staff light's haze.
	vec4 fog = sky ? vec4(0.0) : storm_fog_at(dist, TIME);
	vec3 light = (VIEW_MATRIX * vec4(storm_torch_pos, 1.0)).xyz;
	float haze = storm_torch_haze(view.xyz / max(dist, 0.0001), sky ? 1e6 : dist, light);
	if (fog.a <= 0.0 && haze <= 0.0) {
		discard;
	}
	// The haze over the fog, both over the scene.
	float a = 1.0 - (1.0 - fog.a) * (1.0 - haze);
	ALBEDO = (fog.rgb * fog.a * (1.0 - haze) + storm_torch_color.rgb * haze) / max(a, 0.00001);
	ALPHA = a;
}
