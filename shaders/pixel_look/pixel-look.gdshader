shader_type spatial;

// The PIXEL look's surface shader: wrapped light cut into a few soft steps, coloured shadows from
// the ambient, and three-tone surface clumps. Swapped in for the cel base shader by scripts/rendering/pixel_look.gd; it never
// carries the outline or crease next_pass. See docs/specs/pixel-look.md.
//
// Uniform names match cel-shader-base where they mean the same thing (`color`, `base_texture`,
// `uv_scale`, `uv_offset`, `paint_seed`), so a swapped material keeps its slot colour and the
// per-mesh seed apply_stylized stamps.

// Open shells (the map blockouts) need their back faces, same as the cel base.
render_mode cull_disabled, specular_disabled;

#include "clumps.gdshaderinc"

// How far light wraps past the terminator. 0 is plain Lambert; higher softens the falloff.
global uniform float look_wrap;
// The light is cut into this many levels, dark and full lit included (4: dark, two mids, lit).
global uniform float look_light_steps;
// Width of the soft edge between two light steps, in steps. 0 is a hard cut, 0.5 is smooth.
global uniform float look_light_softness;

uniform vec4 color: source_color = vec4(0.7, 0.7, 0.7, 1.0);
uniform sampler2D base_texture: source_color, hint_default_white;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
// UV for skinned characters (clumps ride the limbs), World for level geometry.
uniform int clump_anchor: hint_enum("UV", "World") = 0;

instance uniform float paint_seed = 0.0;

varying vec2 clump_uv_coord;
varying vec3 clump_world_pos;
varying vec3 clump_world_normal;

void vertex() {
	clump_uv_coord = UV;
	clump_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	clump_world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	UV = UV * uv_scale + uv_offset;
}

void fragment() {
	vec3 albedo = color.rgb * texture(base_texture, UV).rgb;
	float tone = clump_anchor == 1
			? clump_world(clump_world_pos, normalize(clump_world_normal))
			: clump_uv(clump_uv_coord, paint_seed);
	ALBEDO = clump_apply(albedo, tone);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float w = max(look_wrap, 0.0);
	float wrapped = clamp((dot(NORMAL, LIGHT) + w) / (1.0 + w), 0.0, 1.0);
	// Cut after the shadow, so a cast shadow's soft edge bands the same way the form does.
	// A point light's attenuation is its distance falloff, not a shadow: banding it drew a hard
	// disc on the floor under the spark lights. It stays a smooth glow; only the sun's shadow bands.
	float lit = wrapped * (LIGHT_IS_DIRECTIONAL ? ATTENUATION : 1.0);
	vec3 light_tint = LIGHT_IS_DIRECTIONAL ? LIGHT_COLOR : LIGHT_COLOR * ATTENUATION;
	float steps = max(look_light_steps - 1.0, 1.0);
	float q = lit * steps;
	float s = clamp(look_light_softness, 0.0, 0.5);
	float edge = s > 0.0 ? smoothstep(0.5 - s, 0.5 + s, fract(q)) : step(0.5, fract(q));
	lit = (floor(q) + edge) / steps;
	DIFFUSE_LIGHT += ALBEDO * light_tint * lit;
}
