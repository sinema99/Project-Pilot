// Coloured ink for the RETRO look - see docs/specs/retro-look.md.
//
// Shared by outline.gdshader (the hull) and crease.gdshader. Off by default: both passes draw the
// global outline_color unless a material sets ink_from_fill, which only RetroLook's twins do, so
// CEL and every cutscene keep their black ink.
//
// The twin copies its fill's colour, texture and tiling here, so the line is the surface's own
// colour under it, darkened and pushed toward red-brown: brown on ochre, slate on blue-grey, warm
// grey on white - the 90s cel line.

group_uniforms InkFromFill;
uniform bool ink_from_fill = false;
uniform vec4 ink_fill_color: source_color = vec4(1.0);
uniform sampler2D ink_fill_texture: source_color, hint_default_white;
uniform vec2 ink_uv_scale = vec2(1.0);
uniform vec2 ink_uv_offset = vec2(0.0);
// How bright the line is next to its fill, in sRGB terms (0.4 = 40% of the fill's brightness).
uniform float ink_value: hint_range(0.0, 1.0) = 0.4;
// How far the line moves toward red-brown of the same brightness.
uniform float ink_warmth: hint_range(0.0, 1.0) = 0.35;
// Red-brown, as a hue: scaled to the darkened fill's brightness before mixing.
uniform vec3 ink_warm_hue: source_color = vec3(0.42, 0.16, 0.10);
group_uniforms;

float ink_luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// `fill` is linear. Darkening is done in (approximate) sRGB so ink_value reads as "this much of
// the fill's brightness" the way a painter would mix it.
vec3 ink_from(vec3 fill) {
	vec3 dark = pow(pow(max(fill, vec3(0.0)), vec3(1.0 / 2.2)) * ink_value, vec3(2.2));
	vec3 warm = ink_warm_hue / max(ink_luma(ink_warm_hue), 1e-4) * ink_luma(dark);
	return mix(dark, warm, ink_warmth);
}

// The fill under this fragment, from the raw mesh UV.
vec3 ink_fill_at(vec2 uv) {
	return ink_fill_color.rgb * texture(ink_fill_texture, uv * ink_uv_scale + ink_uv_offset).rgb;
}
