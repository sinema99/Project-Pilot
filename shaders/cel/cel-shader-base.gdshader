shader_type spatial;

#define USE_ALPHA 0
#define USE_ALPHA_CUTOFF 0
#define USE_EMISSION 0
#define USE_REFLECTIONS 0
#define USE_NORMAL_MAP 0
#define USE_OCCLUSION 0
#define USE_HEIGHT_MAP 0
#define USE_ANISOTROPY 0
#define USE_BACKLIGHT 0
#define USE_REFRACTION 0

// cull_disabled: the map blockouts are open shells, not closed solids. mission1
// lost its outer box on 2026-09-09, so the terrain is now seen from outside and
// its back faces have to draw or the map reads as holes from some angles.
// scripts/map_import.gd already forces the imported materials double-sided, but
// apply_stylized.gd replaces those with this shader, so the setting has to live
// here too. Godot takes render_mode per shader rather than per material, so this
// covers cel_character.tres as well; closed character meshes never show a back
// face, so it costs them nothing but fill rate.
#if USE_ALPHA
render_mode cull_disabled, depth_draw_always;
#else
render_mode cull_disabled;
#endif

#include "includes/base-cel-shader.gdshaderinc"
#include "includes/painted.gdshaderinc"
#include "includes/scatter.gdshaderinc"

#if USE_EMISSION
#include "includes/emission.gdshaderinc"
#endif

#if USE_REFLECTIONS
#include "includes/reflections.gdshaderinc"
#endif

#if USE_NORMAL_MAP
#include "includes/normal-map.gdshaderinc"
#endif

#if USE_OCCLUSION
#include "includes/occlusion.gdshaderinc"
#endif

#if USE_HEIGHT_MAP
#include "includes/height-map.gdshaderinc"
#endif

#if USE_ANISOTROPY
#include "includes/anisotropy.gdshaderinc"
#endif

#if USE_BACKLIGHT
#include "includes/backlight.gdshaderinc"
#endif

#if USE_REFRACTION
#include "includes/refraction.gdshaderinc"
#elif !USE_REFRACTION && USE_ALPHA
#include "includes/transparency.gdshaderinc"
#endif

group_uniforms BaseProperties;
#if USE_ALPHA_CUTOFF
uniform float alpha_cutoff: hint_range(0.0, 1.0) = 0.5;
#endif
uniform vec4 color: source_color = vec4(0.7, 0.12, 0.86, 1.0);
uniform sampler2D base_texture: source_color;
uniform vec4 specular: source_color = vec4(0.3, 0.3, 0.3, 0.5);
uniform sampler2D specular_texture: hint_default_white;
uniform vec4 fresnel: source_color = vec4(0.2, 0.2, 0.2, 0.3);
uniform sampler2D fresnel_texture: hint_default_white;
// Opt-in repeating tile multiplied over the albedo on the raw UV (base_texture clamps). White
// by default, so nothing changes unless a material sets it (the flyover city's window grid).
uniform sampler2D tile_texture: source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
group_uniforms;

varying vec3 SPECULAR_COLOR;
varying float SPECULAR_STRENGTH;
varying vec3 FRESNEL_COLOR;
varying float FRESNEL_STRENGTH;

varying vec2 base_uv;

// Painted shading - see includes/painted.gdshaderinc and docs/specs/painted-shading.md.
// UV for skinned characters (the pattern rides the limbs), World for level geometry (no UVs
// needed, same patch size everywhere).
group_uniforms PaintedShading;
uniform int paint_anchor: hint_enum("UV", "World") = 0;
// RETRO's flat fills (docs/specs/retro-look.md): no painted patches and no scatter chips on this
// material, whatever the PAINTED SHADING / CEL SCATTER globals say. Only RetroLook's twins set it.
uniform bool flat_fill = false;
group_uniforms;

// RETRO's painted background (docs/specs/retro-look-pass-2.md). Neutral by default; only
// RetroLook's background twins set them.
group_uniforms RetroBackground;
// rgb multiplies the fill (darker, cooler); alpha is the strength of the world-space brush texture.
uniform vec4 bg_paint: source_color = vec4(1.0, 1.0, 1.0, 0.0);
// On up-facing fragments: the fill moves toward floor_color by its alpha, and panel lines of
// floor_panel's colour (strength = alpha) are painted on a floor_panel_size world grid.
uniform vec4 floor_color: source_color = vec4(0.55, 0.62, 0.66, 0.0);
uniform vec4 floor_panel: source_color = vec4(0.2, 0.24, 0.3, 0.0);
uniform float floor_panel_size = 4.0;
// Visible panel line width in metres.
uniform float floor_panel_width = 0.035;
group_uniforms;
// Set per mesh by apply_stylized.gd, so two meshes with the same unwrap do not wear the same
// patches. World-anchored materials ignore it.
instance uniform float paint_seed = 0.0;
varying vec2 paint_uv;
varying vec3 paint_world_pos;
varying vec3 paint_world_normal;

group_uniforms Tiling;
uniform vec2 uv_scale = vec2(1,1);
uniform vec2 uv_offset = vec2(0,0);
group_uniforms;

void vertex() {
	// Raw UV, before the tiling below: patch size is set by paint_uv_size, not per material.
	paint_uv = UV;
	paint_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	paint_world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	UV = UV * uv_scale.xy + uv_offset.xy;
	#if !USE_HEIGHT_MAP
		base_uv = UV;
	#endif
}

void fragment() {
#if USE_HEIGHT_MAP
	base_uv = height_map_fragment(UV, VERTEX, TANGENT, BINORMAL, NORMAL);
#endif

#if USE_ALPHA
	float alpha = color.a * texture(base_texture, base_uv).a;
	ALBEDO *= alpha;
#elif USE_ALPHA_CUTOFF
	ALPHA = color.a * texture(base_texture, base_uv).a;
	ALPHA_SCISSOR_THRESHOLD = color.a * texture(base_texture, base_uv).a;
#endif

#if USE_REFRACTION && USE_ALPHA
	EMISSION += refraction_fragment(alpha, NORMAL, SCREEN_UV, FRAGCOORD.z);
#elif !USE_REFRACTION && USE_ALPHA
	EMISSION += transparency_fragment(alpha, SCREEN_UV);
#endif

	SPECULAR_COLOR = specular.rgb * texture(specular_texture, base_uv).rgb;
	SPECULAR_STRENGTH = specular.a * texture(specular_texture, base_uv).a;
	FRESNEL_COLOR = fresnel.rgb * texture(fresnel_texture, base_uv).rgb;
	FRESNEL_STRENGTH = fresnel.a * texture(fresnel_texture, base_uv).a;

#if USE_EMISSION
	EMISSION += emission_fragment(base_uv);
#endif

#if USE_REFLECTIONS
	Surface surf = reflections_fragment(UV);
	METALLIC = surf.metallic;
	ROUGHNESS = surf.roughness;
#endif

#if USE_NORMAL_MAP
	NormalData normal = normal_map_fragment(base_uv, NORMAL, TANGENT, BINORMAL);
	NORMAL = normal.vector;
	NORMAL_MAP = normal.map;
	NORMAL_MAP_DEPTH = normal.depth;
#endif

#if USE_OCCLUSION
	OcclusionData occlusion = occlusion_fragment(base_uv);
	AO = occlusion.ao;
	AO_LIGHT_AFFECT = occlusion.ao_light_affect;
#endif

#if USE_ANISOTROPY
	AnisotropyData aniso = anisotropy_fragment(UV);
	ANISOTROPY_DIR = aniso.direction;
	ANISOTROPY_RATIO = aniso.ratio;
#endif

#if USE_BACKLIGHT
	BACKLIGHT = backlight_fragment(base_uv);
#endif

ALBEDO = color.rgb * texture(base_texture, base_uv).rgb * texture(tile_texture, paint_uv).rgb;

	float paint_n = 0.5;
	if (flat_fill) {
	} else if (paint_anchor == 1) {
		paint_n = paint_noise_world(paint_world_pos, paint_world_normal);
	} else {
		vec2 seed_offset = vec2(paint_seed * 7.13, paint_seed * 3.71);
		paint_n = paint_noise(paint_uv / max(paint_uv_size, 1e-4) + seed_offset);
	}
	if (!flat_fill) {
		ALBEDO = paint_apply(ALBEDO, paint_level(paint_n));
	}

	// Chipped band edges - see includes/scatter.gdshaderinc. Same UV / World split as the paint.
	scatter_shift = 0.0;
	if (scatter_strength > 0.0 && !flat_fill) {
		float scatter_c;
		if (paint_anchor == 1) {
			scatter_c = scatter_stroke_world(paint_world_pos / max(scatter_world_size, 1e-3),
					paint_world_normal);
		} else {
			vec2 scatter_seed = vec2(paint_seed * 5.31, paint_seed * 2.17);
			scatter_c = scatter_stroke(paint_uv / max(scatter_uv_size, 1e-4) + scatter_seed);
		}
		scatter_shift = scatter_shift_at(scatter_c);
	}

	// RETRO background: floor slate + panel lines, then the cooler darker fill and brush grain.
	// Derivatives outside the branches, so they stay defined.
	vec2 panel_g = paint_world_pos.xz / max(floor_panel_size, 1e-3);
	vec2 panel_fw = fwidth(panel_g) * floor_panel_size;
	if (floor_color.a > 0.0 || floor_panel.a > 0.0) {
		float up = smoothstep(0.85, 0.95, paint_world_normal.y);
		ALBEDO = mix(ALBEDO, floor_color.rgb, floor_color.a * up);
		// Distance to the nearest grid line in metres, per axis, anti-aliased on the pixel's
		// footprint. The line fades out once a pixel covers more than ~3 line widths: past that it
		// would shimmer into moire.
		vec2 d = abs(fract(panel_g + 0.5) - 0.5) * floor_panel_size;
		vec2 fw = max(panel_fw, vec2(1e-5));
		vec2 on = 1.0 - smoothstep(vec2(floor_panel_width * 0.5), vec2(floor_panel_width * 0.5) + fw, d);
		vec2 fade = 1.0 - smoothstep(vec2(floor_panel_width), vec2(floor_panel_width * 3.0), fw);
		float line = max(on.x * fade.x, on.y * fade.y);
		ALBEDO = mix(ALBEDO, floor_panel.rgb, line * floor_panel.a * up);
	}
	ALBEDO *= bg_paint.rgb;
	if (bg_paint.a > 0.0) {
		// Brush texture: value noise stretched along one axis of the dominant world plane, so it
		// reads as strokes rather than mottling.
		vec3 an = abs(paint_world_normal);
		vec2 plane = an.y > max(an.x, an.z) ? paint_world_pos.xz
				: (an.x > an.z ? paint_world_pos.zy : paint_world_pos.xy);
		float stroke = paint_cloud(vec2(plane.x * 0.35, plane.y * 2.2));
		float fine = paint_value_noise(vec2(plane.x * 3.1, plane.y * 9.0) + vec2(41.7, 13.3));
		float grain = 0.75 * stroke + 0.25 * fine - 0.5;
		ALBEDO *= 1.0 + grain * 2.0 * bg_paint.a;
	}
}

void light() {
	// A point light's ATTENUATION is its distance falloff, not a shadow: through the 0.5 shadow
	// threshold it drew a hard disc on the floor under the spark lights. Fold it into the colour.
	vec3 light_color = LIGHT_IS_DIRECTIONAL ? LIGHT_COLOR : LIGHT_COLOR * ATTENUATION;
	float attenuation = LIGHT_IS_DIRECTIONAL ? ATTENUATION : 1.0;
#if USE_BACKLIGHT
	DIFFUSE_LIGHT += backlight_diffuse(
			ALBEDO,
			light_color,
			LIGHT,
			NORMAL,
			attenuation,
			BACKLIGHT
	);
#else
	DIFFUSE_LIGHT += diffuse_light(
			ALBEDO,
			light_color,
			LIGHT,
			NORMAL,
			attenuation
	);
#endif

#if USE_ANISOTROPY
	SPECULAR_LIGHT += anisotropy_specular(
			light_color,
			SPECULAR_COLOR,
			SPECULAR_STRENGTH,
			NORMAL,
			VIEW,
			LIGHT,
			attenuation,
			UV,
			ANISOTROPY_DIR,
			ANISOTROPY_RATIO
	);
#else
	SPECULAR_LIGHT += specular_light(
			light_color,
			SPECULAR_COLOR,
			SPECULAR_STRENGTH,
			NORMAL,
			VIEW,
			LIGHT,
			attenuation
	);
#endif

	SPECULAR_LIGHT += fresnel_light(
			light_color,
			FRESNEL_COLOR,
			FRESNEL_STRENGTH,
			NORMAL,
			VIEW,
			LIGHT,
			attenuation
	);
}
