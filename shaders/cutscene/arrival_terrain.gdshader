// The arrival shot's land (scripts/cutscene/arrival_land.gd). The project's cel lighting
// (base-cel-shader: half-Lambert through the diffuse curve, two tones) on a fill picked per pixel:
// snow on the flats, rock on the steeps, dark forest floor where the terrain lets a forest grow
// (spec R2-2: below the treeline, off the steeps, the flats and the ridgelines, out of the
// clearings), broken up at tree scale. Per pixel rather than per triangle, so the edges are crisp
// curves and not a staircase of cells. ArrivalLand.forest_score is the same rule on the CPU, so
// ArrivalForest stands its spruce where this paints the floor.
shader_type spatial;

#include "res://shaders/cel/includes/base-cel-shader.gdshaderinc"

uniform vec3 snow_color : source_color = vec3(0.86, 0.88, 0.92);
uniform vec3 rock_color : source_color = vec3(0.36, 0.39, 0.46);
uniform vec3 forest_color : source_color = vec3(0.122, 0.18, 0.165);
uniform float snow_threshold = 0.72;
// Cleared ground holds snow down to this normal y.
uniform float clear_snow = 0.55;
uniform float forest_min_slope = 0.58;
uniform float forest_max_slope = 0.998;
uniform float treeline = 60.0;
uniform float tree_band = 220.0;
// Convexity (vertex colour r) over which a ridgeline goes bare.
uniform vec2 ridge_clear = vec2(0.05, 0.14);
// The break-up noise (0..1), tiled every `mask_size` metres of world xz.
uniform sampler2D mask_tex : repeat_enable, filter_linear;
uniform float mask_size = 600.0;
// The clear map over the base's surroundings: r cleared (aprons, road, power-line cut, chutes),
// g the walls' shade. Its world rect: x, z, width, depth.
uniform sampler2D clear_tex : filter_linear;
uniform vec4 clear_rect = vec4(-3000.0, -4300.0, 6000.0, 4000.0);
// How dark the walls' shade gets at their foot.
uniform float shade_strength = 0.55;
// Past the trees (m from the camera) the bare forest floor fades toward rock, so far forest reads as
// texture, not as ink blots: starts, full.
uniform vec2 forest_fade = vec2(3200.0, 9600.0);
// How far the noise wobbles the snow line (normal y), near; it fades out by `jitter_fade` (m) so the
// far layers draw as clean two-tone shapes. The terrain does most of it: snow holds in the gullies
// (concave) down to `gully_snow` lower, and wind scours the ridges.
uniform float snow_jitter = 0.03;
uniform float gully_snow = 0.14;
uniform vec2 jitter_fade = vec2(1500.0, 2400.0);
// Spec R6-5: past the near slopes the snow line and the forest read the broad normal
// (ArrivalLand.broad_reach out) instead of the vertex's own, so the far bowls draw as a few big
// shapes, not flecks: blended over `broad_fade` (m). ArrivalForest reads the same (ArrivalLand.far_ny).
uniform vec2 broad_fade = vec2(1800.0, 2400.0);
// Out to this band (m) the far flats keep their forest (ArrivalLand.flat_k).
uniform vec2 flat_forest_fade = vec2(3500.0, 5000.0);
// Spec R4-4: the forest floor a step lighter on faces toward the sun, so the landform reads through
// the trees: where normal . sun_dir crosses `forest_light_step`.
uniform vec3 forest_lit_color : source_color = vec3(0.17, 0.27, 0.29);
uniform float forest_light_step = 0.5;
uniform vec3 sun_dir = vec3(-0.38, 0.74, -0.55);
// Where the viewer stands (world xz): every distance above is measured from here. The shot's
// camera is at the origin; the boss arena puts it on the arena (ArrivalLand.view_centre).
uniform vec2 view_centre = vec2(0.0);

varying vec3 world_pos;
varying vec3 world_normal;
varying float ridge;
varying vec3 broad_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	ridge = COLOR.r * 2.0 - 1.0;
	vec2 bxz = COLOR.gb * 2.0 - 1.0;
	broad_normal = normalize(mat3(MODEL_MATRIX) * vec3(bxz.x, sqrt(max(1.0 - dot(bxz, bxz), 0.0)), bxz.y));
}

vec3 clear_at(vec2 xz) {
	vec2 uv = (xz - clear_rect.xy) / clear_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return vec3(0.0);
	}
	return texture(clear_tex, uv).rgb;
}

// ArrivalLand.forest_score.
float forest_score(float y, float ny, float r, float cleared, float flat_k) {
	float alt = 1.0 - smoothstep(treeline - tree_band, treeline, y);
	float flat_ny = mix(forest_max_slope, 1.02, flat_k);
	float slope = smoothstep(forest_min_slope, forest_min_slope + 0.08, ny)
			* (1.0 - smoothstep(flat_ny - 0.012, flat_ny, ny));
	float open = 1.0 - smoothstep(ridge_clear.x, ridge_clear.y, r);
	return alt * slope * open * (1.0 - cleared);
}

void fragment() {
	scatter_shift = 0.0;
	float dist = length(world_pos.xz - view_centre);
	float far_k = smoothstep(broad_fade.x, broad_fade.y, dist);
	float m = texture(mask_tex, world_pos.xz / mask_size).r;
	vec3 c = clear_at(world_pos.xz);
	float ny = normalize(world_normal).y;
	float snow_ny = mix(ny, normalize(broad_normal).y, far_k);
	float jitter = (m - 0.5) * snow_jitter * (1.0 - smoothstep(jitter_fade.x, jitter_fade.y, dist));
	// Wind scours the ridgelines: a little more rock there.
	// The gully / ridge terms read the vertex's own convexity, fine detail: gone with the broad normal.
	float line = mix(snow_threshold, clear_snow, c.r) + (0.06 * smoothstep(ridge_clear.x, ridge_clear.y, ridge)
			- gully_snow * smoothstep(0.0, 0.12, -ridge)) * (1.0 - far_k);
	vec3 fill = snow_ny > line + jitter ? snow_color : rock_color;
	if (forest_score(world_pos.y, snow_ny, ridge, c.r,
			far_k * (1.0 - smoothstep(flat_forest_fade.x, flat_forest_fade.y, dist))) > mix(0.15, 0.85, m)) {
		float lit = dot(normalize(world_normal), normalize(sun_dir));
		vec3 floor_color = lit > forest_light_step ? forest_lit_color : forest_color;
		fill = mix(floor_color, rock_color, 0.7 * smoothstep(forest_fade.x, forest_fade.y, dist));
	}
	ALBEDO = fill * (1.0 - shade_strength * c.g);
}

void light() {
	DIFFUSE_LIGHT += diffuse_light(ALBEDO, LIGHT_COLOR, LIGHT, NORMAL, ATTENUATION);
}
