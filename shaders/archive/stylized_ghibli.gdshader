shader_type spatial;
// cull_disabled keeps the double-sided blockout behaviour the hub relies on.
// Engine ambient is left ON: test2 uses an HDR panorama sky, and its sky-source
// ambient is what fills the shadow side now (the earlier hemisphere-in-shader
// ambient was stripped when the HDR sky went in).
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// Ghibli / BOTW material — scenes/test2.tscn only. See docs/specs/ghibli-pass.md.
//
// A fork of stylized.gdshader that trades the hard 3-band cel step for a soft
// painterly ramp with ONE readable plateau at the terminator, adds a warm-lit /
// cool-shadow colour shift, and breaks the flat albedo up with world-space
// noise. The daytime desert pipeline (stylized.gdshader, test.tscn, main.tscn)
// is untouched — this shader exists so test2 can chase a different look without
// disturbing it.

group_uniforms albedo;
uniform vec4 albedo_color : source_color = vec4(0.254, 0.292, 0.262, 1.0); // weathered stone, lit
uniform vec4 gradient_color : source_color = vec4(0.254, 0.292, 0.262, 1.0);
uniform float gradient_strength : hint_range(0.0, 1.0) = 0.0;
uniform float gradient_low = 0.0;
uniform float gradient_high = 10.0;

group_uniforms ramp;
// The Sable <-> Ghibli hardness dial. 0.0 collapses the terminator knee to a
// hard cel step (back to stylized.gdshader's look); 0.5-0.6 is a broad
// painterly wrap. This is the single knob to nudge once palette and fog are in.
uniform float soft_terminator : hint_range(0.0, 0.6) = 0.38;
// Warm on the lit side, cool in shadow — the reference's shadows are bluer, not
// just darker. Cast shadows drive the ramp to zero, so they land on shadow_tint
// for free.
uniform vec3 lit_tint : source_color = vec3(1.0, 0.896, 0.745);
uniform vec3 shadow_tint : source_color = vec3(0.347, 0.485, 0.584);
uniform float warm_cool_strength : hint_range(0.0, 1.0) = 0.6;
// Floor under the darkest part of the ramp, as a fraction of the key light.
// Applied per light — keep it at 0 on anything lit by more than the key sun.
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.0;
// Antialiasing width on the one soft step the ramp keeps at the terminator, and
// on the rim. Reads as a step, does not shimmer in motion.
uniform float band_softness : hint_range(0.0, 0.25) = 0.02;

group_uniforms breakup;
// Low-frequency triplanar value noise on the albedo, so a flat fill reads as
// painted rather than plastic. World-space, needs no UVs. 0.0 = dead flat.
uniform float breakup_strength : hint_range(0.0, 1.0) = 0.18;
// World units per noise cell. Larger = broader, slower mottling.
uniform float breakup_scale : hint_range(0.1, 20.0) = 3.2;

group_uniforms rim;
// Silhouette separation for the busy background. On for Setsuna's body in test2,
// off on the hub (a rim on every wall edge is line noise the compositor already
// draws) and off on the black screen bezels.
uniform bool rim_enabled = false;
uniform vec3 rim_color : source_color = vec3(0.62, 0.72, 0.85);
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.6;
uniform float rim_strength : hint_range(0.0, 4.0) = 0.4;

varying vec3 world_position;

// --- value noise, for the albedo breakup -------------------------------------

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

// Quantise 0..1 into `count` levels with an antialiased seam.
float cel_bands(float x, int count, float softness) {
	float n = float(count);
	float level = 0.0;
	for (int i = 1; i < count; i++) {
		float edge = float(i) / n;
		level += smoothstep(edge - softness, edge + softness, x);
	}
	return level / max(n - 1.0, 1.0);
}

// Smooth half-Lambert base, with one soft 3-level plateau blended in around the
// terminator so a mech-scale slope still snaps to a readable value once. `lit`
// is ndotl * attenuation.
float hybrid_ramp(float lit) {
	float l = clamp(lit, 0.0, 1.0);
	float hl = clamp(lit * 0.5 + 0.5, 0.0, 1.0);
	float base = hl * hl;
	float w = max(soft_terminator * 0.5, band_softness);
	float knee = smoothstep(0.5 - w, 0.5 + w, l);
	float stepped = cel_bands(l, 3, w);
	return mix(base, mix(base, stepped, 0.6), knee);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float span = max(gradient_high - gradient_low, 0.0001);
	float height = clamp((world_position.y - gradient_low) / span, 0.0, 1.0);

	vec3 base_albedo = mix(albedo_color.rgb, gradient_color.rgb, height * gradient_strength);

	// Triplanar-ish breakup: three axis-aligned noise samples averaged, so it
	// works on any face orientation without UVs. Centred on zero — it darkens
	// some patches and lifts others, and pulls the darkened ones toward the cool
	// shadow tint so it reads as paint pooling rather than grime.
	if (breakup_strength > 0.0) {
		vec3 wp = world_position / max(breakup_scale, 0.001);
		float nz = (value_noise(wp) + value_noise(wp.yzx + 11.3) + value_noise(wp.zxy + 27.7)) / 3.0;
		float d = (nz - 0.5) * 2.0;
		base_albedo *= 1.0 + d * breakup_strength * 0.5;
		base_albedo = mix(base_albedo, base_albedo * shadow_tint, max(-d, 0.0) * breakup_strength * 0.5);
	}

	ALBEDO = base_albedo;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	// Ambient fill is the engine's now (sky-source, driven by the HDR panorama).
	// EMISSION carries only the rim.
	EMISSION = vec3(0.0);

	if (rim_enabled) {
		// NORMAL and VIEW are view-space here, so this is a plain fresnel: 0
		// facing the camera, 1 at the grazing silhouette edge.
		float fresnel = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		float rim = smoothstep(rim_threshold - band_softness, rim_threshold + band_softness, fresnel);
		EMISSION += rim * rim_strength * rim_color;
	}
}

void light() {
	float ndotl = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float lit = ndotl * ATTENUATION;
	float ramp = hybrid_ramp(lit);

	// Lift into [shadow_floor, 1].
	ramp = shadow_floor + (1.0 - shadow_floor) * ramp;

	// Warm lit / cool shadow. mix toward white by (1 - strength) so the shift
	// can be dialled out entirely.
	vec3 tint = mix(shadow_tint, lit_tint, ramp);
	tint = mix(vec3(1.0), tint, warm_cool_strength);

	DIFFUSE_LIGHT += ramp * LIGHT_COLOR * ALBEDO * tint / PI;
}
