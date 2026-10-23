global uniform sampler2D diffuse_curve: repeat_disable;
global uniform float specular_smoothness;
global uniform float fresnel_smoothness;

// Per-pixel shift for the chipped band edges, written by fragment() - see scatter.gdshaderinc.
// 0 when the scatter is off.
varying float scatter_shift;

// How hard the shift pushes shadow attenuation. Only the penumbra moves (see is_lit), so this is
// large: the penumbra is thin and a chip has to flip it to fully lit or fully shadowed.
const float SCATTER_SHADOW_GAIN = 4.0;

// RETRO pass 2 (docs/specs/retro-look-pass-2.md). The defaults are today's look; only RetroLook's
// twins set them.
// Added to the wrapped light term before the cel step: negative puts more of the form in shadow.
uniform float shade_bias = 0.0;
// 0 = the hard cel step. Above 0 the step is averaged across this width of the wrapped term, a
// soft painted gradient (RETRO's background), and cast-shadow edges soften to match.
uniform float paint_soft = 0.0;

float diffuse_curve_at(float x) {
	return texture(diffuse_curve, vec2(clamp(x, 0.0, 1.0), 0)).r;
}

 float diffuse_sample(vec3 light, vec3 normal) {
	// Half-Lambert (Valve): wrap the light term so simple/flat geometry still
	// gets tonal range across faces instead of collapsing to lit-or-black.
	float wrapped = dot(light, normal) * 0.5 + 0.5;
	wrapped *= wrapped;
	float x = wrapped + scatter_shift + shade_bias;
	if (paint_soft <= 0.0) {
		return diffuse_curve_at(x);
	}
	float sum = 0.0;
	for (int i = -3; i <= 3; i++) {
		sum += diffuse_curve_at(x + paint_soft * float(i) / 3.0);
	}
	return sum / 7.0;
 }

// Two cels: light is the full albedo, dark is albedo * shadow_tone. Form shadow and cast shadow
// share the dark tone, so there are exactly two tones on a surface. RETRO's background lifts it.
uniform float shadow_tone = 0.45;

// RETRO's shadow paint (docs/specs/retro-look.md): the dark tone leans toward this colour by its
// alpha, at the same brightness. Alpha 0 (the default) is the plain darkened fill, so CEL and the
// cutscenes are unchanged; only RetroLook's twins set it.
uniform vec4 shadow_tint: source_color = vec4(0.55, 0.5, 0.7, 0.0);

vec3 shadow_paint() {
	float l = dot(shadow_tint.rgb, vec3(0.2126, 0.7152, 0.0722));
	return mix(vec3(1.0), shadow_tint.rgb / max(l, 1e-4), shadow_tint.a);
}

// Hard 0/1 cast-shadow mask: the shadow-map penumbra snapped to a crisp edge.
float shadow_mask(float attenuation) {
	// 4a(1-a) is 0 in full light and full shadow and 1 mid-penumbra, so cast-shadow edges get
	// chipped without fleck-ing the lit or shadowed interiors.
	float edge = 4.0 * attenuation * (1.0 - attenuation);
	float a = clamp(attenuation + scatter_shift * SCATTER_SHADOW_GAIN * edge, 0.0, 1.0);
	float soft = 0.02 + paint_soft;
	return smoothstep(0.5 - soft, 0.5 + soft, a);
}

// 1 where a highlight may show (facing the light and out of cast shadow), 0 elsewhere.
float is_lit(vec3 light, vec3 normal, float attenuation) {
	return shadow_mask(attenuation) * diffuse_sample(light, normal);
}

vec3 diffuse_light(
		vec3 albedo,
		vec3 light_color,
		vec3 light,
		vec3 normal,
		float attenuation
) {
	vec3 tone = mix(shadow_tone * shadow_paint(), vec3(1.0), is_lit(light, normal, attenuation));
	return albedo * light_color * tone;
}

vec3 specular_light(
		vec3 light_color,
		vec3 specular_color,
		float specular_strength,
		vec3 normal,
		vec3 view,
		vec3 light,
		float attenuation
) {
	vec3 half = normalize(view + light);
	float gloss = pow(2.0, 8.0 * (1.0 - specular_strength));
	float intensity = pow(dot(normal, half), gloss * gloss);
	return light_color
			* specular_color
			* is_lit(light, normal, attenuation)
			* smoothstep(
					0.05,
					0.05 + specular_smoothness,
					intensity
			);
}

vec3 fresnel_light(
		vec3 light_color,
		vec3 fresnel_color,
		float fresnel_strength,
		vec3 normal,
		vec3 view,
		vec3 light,
		float attenuation
) {
	float fresnel_dot = 1.0 - dot(normal, view);
	float fresnel_threshold = pow((1.0 - fresnel_strength), dot(light, normal));
	return light_color
			* fresnel_color
			* is_lit(light, normal, attenuation)
			* smoothstep(
					fresnel_threshold - fresnel_smoothness / 2.0,
					fresnel_threshold + fresnel_smoothness / 2.0,
					fresnel_dot
			);
}
