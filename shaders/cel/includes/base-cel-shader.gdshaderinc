global uniform sampler2D diffuse_curve: repeat_disable;
global uniform float specular_smoothness;
global uniform float fresnel_smoothness;

// Per-pixel shift for the chipped band edges, written by fragment() - see scatter.gdshaderinc.
// 0 when the scatter is off.
varying float scatter_shift;

// How hard the shift pushes shadow attenuation. Only the penumbra moves (see is_lit), so this is
// large: the penumbra is thin and a chip has to flip it to fully lit or fully shadowed.
const float SCATTER_SHADOW_GAIN = 4.0;

 float diffuse_sample(vec3 light, vec3 normal) {
	// Half-Lambert (Valve): wrap the light term so simple/flat geometry still
	// gets tonal range across faces instead of collapsing to lit-or-black.
	float wrapped = dot(light, normal) * 0.5 + 0.5;
	wrapped *= wrapped;
	return texture(diffuse_curve, vec2(clamp(wrapped + scatter_shift, 0.0, 1.0), 0)
	).r;
 }

// Two cels: light is the full albedo, dark is albedo * SHADOW_TONE. Form shadow and cast shadow
// share the dark tone, so there are exactly two tones on a surface.
const float SHADOW_TONE = 0.45;

// Hard 0/1 cast-shadow mask: the shadow-map penumbra snapped to a crisp edge.
float shadow_mask(float attenuation) {
	// 4a(1-a) is 0 in full light and full shadow and 1 mid-penumbra, so cast-shadow edges get
	// chipped without fleck-ing the lit or shadowed interiors.
	float edge = 4.0 * attenuation * (1.0 - attenuation);
	float a = clamp(attenuation + scatter_shift * SCATTER_SHADOW_GAIN * edge, 0.0, 1.0);
	return smoothstep(0.48, 0.52, a);
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
	float tone = mix(SHADOW_TONE, 1.0, is_lit(light, normal, attenuation));
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
