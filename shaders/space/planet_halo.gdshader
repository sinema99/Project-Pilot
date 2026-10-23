// Atmosphere halo for the intro cutscene planet (docs/specs/cutscene-intro-space.md, "Planet
// upgrade"): a shell a little bigger than the planet, drawn from the inside (back faces) so only
// the ring outside the planet's silhouette survives the depth test. A soft glow by how close the
// line of sight passes to the surface (no hard bands since 2026-10-19: the user wanted it to glow);
// it thins into a crescent toward the night side.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_add, shadows_disabled;

uniform vec3 halo_color : source_color = vec3(0.45, 0.85, 1.0);
// Surface and shell radii, metres (the planet and this mesh).
uniform float planet_radius = 4000.0;
uniform float halo_radius = 4200.0;
// Brightness where the sight line skims the surface. Over 1 is HDR, so the glow pass blooms it.
uniform float core_strength = 1.3;
// Falloff length as a fraction of the shell height: the glow drops to 1/e this far out.
uniform float falloff = 0.14;
// Where the glow has faded fully to nothing, a fraction of the shell height.
uniform float outer_edge : hint_range(0.1, 1.0) = 0.75;
// Fade-in at the surface (fraction of the shell height), so the ring has no hard inner line.
uniform float inner_soft = 0.025;
// Toward the sun, world space. intro_space.gd copies it from the Sun node.
uniform vec3 sun_dir = vec3(-0.7, 0.3, 0.65);
// Night side: the halo thins to this fraction of its height, a crescent rather than a hard cut.
uniform float night_thickness : hint_range(0.0, 1.0) = 0.3;
// Day measure (sun dot limb normal, plus day_reach) over which the halo thins.
uniform float thin_width : hint_range(0.05, 1.0) = 0.35;
// The air stays sunlit past the ground's terminator (twilight). The camera only sees the limb on
// the night side of the planet, so without this the halo would be thin throughout.
uniform float day_reach : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 dir = normalize(wp - cam);
	vec3 c = NODE_POSITION_WORLD;
	vec3 closest = cam + dir * dot(c - cam, dir);
	float h = (length(closest - c) - planet_radius) / (halo_radius - planet_radius);
	float day = dot(normalize(closest - c), normalize(sun_dir)) + day_reach;
	h /= mix(night_thickness, 1.0, smoothstep(-thin_width, thin_width, day));
	if (h < 0.0 || h > outer_edge) {
		discard;
	}
	float strength = core_strength * exp(-h / falloff)
			* smoothstep(0.0, inner_soft, h)
			* (1.0 - smoothstep(outer_edge * 0.4, outer_edge, h));
	ALBEDO = halo_color * strength;
}
