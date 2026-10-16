shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix, shadows_disabled, fog_disabled;

// The flyover's ground mist (docs/specs/cutscene-flyover.md, "Ground mist"): a low layer lying on
// the snow, so the ruins' feet and the rubble sink into it and the ground/building seams never
// show. A full-screen pass that reads depth: every pixel's world point gets mist by how high it is
// over `ground_y` (full `density` at the snow, gone by `height`, the top edge broken up by noise),
// in patches drifting with the wind on the shot clock. Sky pixels are the painted ground plane
// (flyover_sky.gdshader), so they are run down to it. The storm's distance fog is applied over
// the mist's colour, so far mist sinks into the storm like everything else. FlyoverShot sorts it
// after the crease ink, so it covers the ink too.

#include "res://shaders/storm/storm_fog.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

uniform float ground_y = 0.0;
uniform float height = 45.0;
uniform float density = 0.8;
uniform vec3 color : source_color = vec3(0.42, 0.46, 0.52);
// Patch size (m), how much the patches thin it (0 = an even sheet), and how far (m) the noise
// lifts or sinks the layer's top.
uniform float patch_size = 180.0;
uniform float breakup = 0.5;
uniform float top_wobble = 15.0;
// World xz drift (m/s) and the shot time it is drifted to.
uniform vec2 drift = vec2(0.0, -6.0);
uniform float shot_time = 0.0;
// Lightning, 0..1 (FlyoverShot.flash_at): lifts the mist toward `flash_color`.
uniform float flash = 0.0;
uniform vec3 flash_color : source_color = vec3(0.55, 0.9, 1.0);
uniform float flash_lift = 0.5;

float mist_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float mist_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mist_hash(i), mist_hash(i + vec2(1.0, 0.0)), f.x),
			mix(mist_hash(i + vec2(0.0, 1.0)), mist_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// Reversed-Z: z = 1 is the near plane, so the quad covers everything and is never clipped.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).x;
	bool sky = depth < 0.0000001;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, sky ? 0.0000001 : depth, 1.0);
	view.xyz /= view.w;
	vec3 eye = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 p = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	if (sky) {
		// The painted ground: where this ray meets the plane.
		vec3 dir = normalize(p - eye);
		if (dir.y >= 0.0) {
			discard;
		}
		p = eye + dir * (ground_y - eye.y) / dir.y;
	}
	vec2 q = (p.xz - drift * shot_time) / patch_size;
	float n = 0.65 * mist_noise(q) + 0.35 * mist_noise(q * 2.7 + 9.2);
	float top = height + top_wobble * (n - 0.5) * 2.0;
	float h = max(p.y - ground_y, 0.0);
	float layer = 1.0 - smoothstep(0.0, max(top, 1.0), h);
	float amount = density * layer * layer * mix(1.0, smoothstep(0.15, 0.75, n), breakup);
	if (amount <= 0.002) {
		discard;
	}
	vec3 c = mix(color, flash_color, flash * flash_lift);
	vec4 fog = storm_fog_at(length(p - eye), TIME);
	ALBEDO = mix(c, fog.rgb, fog.a);
	ALPHA = amount;
}
