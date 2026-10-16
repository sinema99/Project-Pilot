shader_type spatial;

// pilot9's one-sided white rim light, after the Marvel Rivals character renders.
// Drawn as a material_overlay over pilot9's cel pass - see docs/specs/pilot9-rim-light.md.
// Unshaded on purpose: it is painted on, so it holds up in shadow the same as in sun.
//
// Where it goes, settled over three looks on 2026-09-25:
//   - Silhouette only, never interior. Fresnel lit every surface turning from the camera (an arm
//     across the chest got a white edge), so this is a screen-space depth test instead: step
//     `rim_width` pixels toward the light and read the depth there. Far behind pilot means
//     background, so this pixel is on the lit edge of his outline.
//   - INSIDE the black ink line, on his body. An inverted hull pushed past the ink put the white
//     outside his edge; that was wrong.
//   - Under the ink wherever the two meet. The ink's inverted hull lays some of its black over
//     his own edge pixels, and this pass draws after it, so it would paint white over that ink.
//     Every pixel already ink-coloured in the screen texture is left alone.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

// The ink's colour, from project.godot [shader_globals].
global uniform vec4 outline_color;
// Window pixels per rendered pixel. rim_width is in window pixels, so it is divided by this to
// keep the rim its screen size when PixelWorld renders low-res - see docs/specs/pixel-world.md.
global uniform float pixel_block;

uniform sampler2D depth_texture: hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_texture: hint_screen_texture, filter_nearest, repeat_disable;

// Alpha is overall strength.
uniform vec4 rim_color: source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Screen-space side the light comes from: x right, y up. Fixed to the screen, not the sun,
// so it stays on the same side however the camera orbits.
uniform vec2 rim_direction = vec2(-1.0, 0.35);
// Thickness of the rim in pixels, measured in from the silhouette, where the edge faces the
// light head-on. It thins from there as the edge turns away - see `rim_taper`.
uniform float rim_width: hint_range(0.0, 20.0, 0.5) = 5.0;
// Thickness where the edge is side-on to the light. 0 lets the rim run out to nothing.
uniform float rim_width_min: hint_range(0.0, 20.0, 0.5) = 0.0;
// How the thickness falls off as the edge turns from the light. 1 is an even fade; higher keeps
// it thin for longer and swells only where the edge faces the light, for a sharper crescent.
uniform float rim_taper: hint_range(0.25, 6.0, 0.05) = 1.5;
// Metres behind pilot a pixel must be to count as background. Must exceed how far one part of
// him sits in front of another (arm over chest), or those overlaps light up again. The cost:
// a wall closer behind him than this hides the rim along it.
uniform float depth_threshold: hint_range(0.05, 5.0, 0.05) = 0.6;
// How close to the ink colour a pixel must be to count as ink and stay black. Too high and
// pilot's own darkest paint in shadow is spared too.
uniform float ink_tolerance: hint_range(0.0, 0.5, 0.01) = 0.04;

float linear_depth(vec2 uv, mat4 inv_projection) {
	float raw = texture(depth_texture, uv).r;
	// Forward+ is reverse-Z with a 0..1 NDC depth, so the raw value goes in as-is.
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return -view.z / view.w;
}

void fragment() {
	vec2 dir = normalize(rim_direction);
	// Thickness from the mesh's own shape: NORMAL.xy is the way the surface faces across the
	// screen (view space, y up, same frame as rim_direction). Near the silhouette that is the
	// edge's outward direction, so the rim swells where the edge faces the light and runs out as
	// it curves away - crescents rather than an even stroke.
	vec2 n = NORMAL.xy;
	float facing = clamp(dot(n / max(length(n), 1e-4), dir), 0.0, 1.0);
	float width = mix(rim_width_min, rim_width, pow(facing, rim_taper)) / max(pixel_block, 1.0);
	// UV y runs down the screen, rim_direction's y runs up.
	vec2 step_uv = vec2(dir.x, -dir.y) * width / VIEWPORT_SIZE;
	float here = -VERTEX.z;
	float there = linear_depth(SCREEN_UV + step_uv, INV_PROJECTION_MATRIX);
	float edge = step(depth_threshold, there - here);

	vec3 under = texture(screen_texture, SCREEN_UV).rgb;
	float is_ink = step(distance(under, outline_color.rgb), ink_tolerance);

	// Under half a pixel the step never leaves pilot, but say so rather than rely on it.
	float some = step(0.5, width);

	ALBEDO = rim_color.rgb;
	ALPHA = edge * some * (1.0 - is_ink) * rim_color.a;
}
