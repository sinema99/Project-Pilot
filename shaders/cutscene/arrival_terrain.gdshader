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
uniform vec2 jitter_fade = vec2(2000.0, 6000.0);

varying vec3 world_pos;
varying vec3 world_normal;
varying float ridge;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	ridge = COLOR.r * 2.0 - 1.0;
}

vec2 clear_at(vec2 xz) {
	vec2 uv = (xz - clear_rect.xy) / clear_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return vec2(0.0);
	}
	return texture(clear_tex, uv).rg;
}

// ArrivalLand.forest_score.
float forest_score(float y, float ny, float r, float cleared) {
	float alt = 1.0 - smoothstep(treeline - tree_band, treeline, y);
	float slope = smoothstep(forest_min_slope, forest_min_slope + 0.08, ny)
			* (1.0 - smoothstep(forest_max_slope - 0.012, forest_max_slope, ny));
	float open = 1.0 - smoothstep(ridge_clear.x, ridge_clear.y, r);
	return alt * slope * open * (1.0 - cleared);
}

void fragment() {
	scatter_shift = 0.0;
	float dist = length(world_pos.xz);
	float m = texture(mask_tex, world_pos.xz / mask_size).r;
	vec2 c = clear_at(world_pos.xz);
	float ny = normalize(world_normal).y;
	float jitter = (m - 0.5) * snow_jitter * (1.0 - smoothstep(jitter_fade.x, jitter_fade.y, dist));
	// Wind scours the ridgelines: a little more rock there.
	float line = mix(snow_threshold, clear_snow, c.r) + 0.06 * smoothstep(ridge_clear.x, ridge_clear.y, ridge)
			- gully_snow * smoothstep(0.0, 0.12, -ridge);
	vec3 fill = ny > line + jitter ? snow_color : rock_color;
	if (forest_score(world_pos.y, ny, ridge, c.r) > mix(0.15, 0.85, m)) {
		fill = mix(forest_color, rock_color, 0.7 * smoothstep(forest_fade.x, forest_fade.y, dist));
	}
	ALBEDO = fill * (1.0 - shade_strength * c.g);
}

void light() {
	DIFFUSE_LIGHT += diffuse_light(ALBEDO, LIGHT_COLOR, LIGHT, NORMAL, ATTENUATION);
}
