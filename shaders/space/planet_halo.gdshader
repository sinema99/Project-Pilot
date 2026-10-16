// Atmosphere halo for the intro cutscene planet (docs/specs/cutscene-intro-space.md, "Planet
// upgrade"): a shell a little bigger than the planet, drawn from the inside (back faces) so only
// the ring outside the planet's silhouette survives the depth test. Hard cel bands by how close
// the line of sight passes to the surface; the bands thin into a crescent toward the night side.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_add, shadows_disabled;

uniform vec3 halo_color : source_color = vec3(0.45, 0.85, 1.0);
// Surface and shell radii, metres (the planet and this mesh).
uniform float planet_radius = 4000.0;
uniform float halo_radius = 4200.0;
// Band outer edges as a fraction of the shell height, and their strengths (inner -> outer).
uniform vec3 band_edges = vec3(0.13, 0.32, 0.62);
uniform vec3 band_strengths = vec3(0.7, 0.34, 0.13);
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
	if (h < 0.0 || h > band_edges.z) {
		discard;
	}
	float strength = h < band_edges.x ? band_strengths.x
			: (h < band_edges.y ? band_strengths.y : band_strengths.z);
	ALBEDO = halo_color * strength;
}
