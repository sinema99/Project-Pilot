shader_type spatial;
// cull_disabled preserves the double-sided blockout behaviour that
// scripts/hub_import.gd bakes into the hub's StandardMaterial3D, which this
// material_override replaces.
// ambient_light_disabled: this shader supplies its own two-colour hemisphere
// ambient (see fragment()), which Godot's Environment cannot express. Leaving
// engine ambient on as well would double up and wash the cel bands out.
render_mode blend_mix, depth_draw_opaque, cull_disabled, ambient_light_disabled;

// Stylized cel material (Moebius / Sable art direction).
//
// Flat albedo + hard-stepped light bands. No PBR, no tiling textures, no normal
// maps: detail is meant to read through silhouette and the compositor's outline,
// not through surface texture. Everything is fully rough and non-metal.

group_uniforms albedo;
uniform vec4 albedo_color : source_color = vec4(0.807, 0.552, 0.275, 1.0); // #E8C48F sand, lit
// Optional world-space vertical gradient, so large flat surfaces do not read
// dead. Opt-in per material: strength ships at 0.
uniform vec4 gradient_color : source_color = vec4(0.807, 0.552, 0.275, 1.0);
uniform float gradient_strength : hint_range(0.0, 1.0) = 0.0;
uniform float gradient_low = 0.0;
uniform float gradient_high = 10.0;

group_uniforms cel;
// 3 bands, not 2: the middle band is what describes a slope's pitch, which is
// what makes terrain legible to read while piloting the mech.
uniform int band_count : hint_range(2, 6) = 3;
// Razor-thin terminator: reads as a hard step, but antialiased so the edge does
// not shimmer when the camera moves.
uniform float band_softness : hint_range(0.0, 0.25) = 0.02;
// Floor the darkest band at this fraction of the key light instead of letting
// it fall to zero. At 0 a surface the sun never reaches -- every interior wall
// of the hub, every exterior face turned away from it -- is lit by the
// hemisphere ambient alone, which crushes it to near-black. Raising the floor
// keeps the band edges hard, it just compresses the whole ramp upward.
// Applied per light, so keep it at 0 on anything lit by more than the key sun.
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.0;

group_uniforms dotting;
// Comic halftone in the shadow band instead of a smooth gradient. The matrix is
// locked to the screen (ink on a page) and the surface slides underneath, so it
// needs no UVs and works on the greybox hub as-is. Accepted tradeoff: the dots
// appear to crawl across surfaces as the camera moves -- this is what Sable does.
uniform bool dot_enabled = true;
uniform float dot_density : hint_range(0.0, 1.0) = 0.55;
uniform float dot_scale_px : hint_range(2.0, 32.0) = 6.0;

group_uniforms ambient;
// Sky tint onto upward faces, warm ground bounce onto downward ones. This is
// what fills the shadow band -- without it the darkest band crushes to black.
uniform vec3 ambient_sky_color : source_color = vec3(0.521, 0.745, 0.823);    // #BFE0EA
uniform vec3 ambient_ground_color : source_color = vec3(0.584, 0.275, 0.102); // #C98F5A
uniform float ambient_energy : hint_range(0.0, 4.0) = 0.35;

group_uniforms rim;
// Silhouette separation for the night pass: against a dark wall a dark character
// dissolves, and the compositor cannot help -- it draws a line where depth or
// normals break, and a body in front of a wall two metres behind it breaks
// neither by enough. Stepped with `band_softness` like everything else here, so
// it reads as one more flat shape rather than a soft glow, and added through
// EMISSION so it survives on faces no light reaches. Off by default: the day
// scene does not need it and would only get haloed edges.
uniform bool rim_enabled = false;
uniform vec3 rim_color : source_color = vec3(0.521, 0.658, 1.0); // #BFD4FF moonlight
// Fresnel value at which the rim starts. Higher = a thinner band clinging closer
// to the silhouette edge.
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.62;
uniform float rim_strength : hint_range(0.0, 4.0) = 0.5;

group_uniforms specular;
// Hard white blob, stepped like the bands so the outline pass draws around it.
// Off by default; this is here for Exia's metal, not for terrain.
uniform bool specular_enabled = false;
uniform float specular_threshold : hint_range(0.0, 1.0) = 0.85;
uniform float specular_sharpness : hint_range(1.0, 256.0) = 32.0;
uniform vec3 specular_color : source_color = vec3(1.0, 1.0, 1.0);

varying vec3 world_position;

// Quantise 0..1 into `count` discrete levels with an antialiased seam.
float cel_bands(float x, int count, float softness) {
	float n = float(count);
	float level = 0.0;
	for (int i = 1; i < count; i++) {
		float edge = float(i) / n;
		level += smoothstep(edge - softness, edge + softness, x);
	}
	return level / max(n - 1.0, 1.0);
}

// Ordered dot matrix in screen space. `coverage` 0..1 drives dot radius, so
// density ramps naturally: thin toward the lit edge, filling toward full dark.
float halftone(vec2 frag_px, float scale_px, float coverage) {
	// 45-degree grid: the classic print screen angle, and it keeps the dot rows
	// off the horizontal/vertical edges the outline pass is already drawing.
	const vec2 rot_x = vec2(0.7071068, -0.7071068);
	const vec2 rot_y = vec2(0.7071068, 0.7071068);
	vec2 cell = vec2(dot(frag_px, rot_x), dot(frag_px, rot_y)) / max(scale_px, 1.0);

	vec2 offset = fract(cell) - 0.5;
	float dist = length(offset);
	// sqrt so coverage reads as area, not radius.
	float radius = sqrt(clamp(coverage, 0.0, 1.0)) * 0.5;
	return smoothstep(radius + 0.03, radius - 0.03, dist);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float span = max(gradient_high - gradient_low, 0.0001);
	float height = clamp((world_position.y - gradient_low) / span, 0.0, 1.0);

	ALBEDO = mix(albedo_color.rgb, gradient_color.rgb, height * gradient_strength);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	// Two-colour hemisphere, keyed off the world-space up component of the
	// normal: 1.0 straight up (sky), 0.0 straight down (bounce).
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up = world_normal.y * 0.5 + 0.5;
	vec3 ambient = mix(ambient_ground_color, ambient_sky_color, up) * ambient_energy;
	// Delivered through EMISSION: Godot 4 spatial shaders have no writable
	// AMBIENT_LIGHT, and emission is added unlit before fog, which is exactly
	// how an ambient fill should behave here.
	EMISSION = ambient * ALBEDO;

	if (rim_enabled) {
		// NORMAL and VIEW are both view-space here, so this is a plain fresnel:
		// 0 facing the camera, 1 at the grazing edge of the silhouette.
		float fresnel = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		float rim = smoothstep(rim_threshold - band_softness, rim_threshold + band_softness, fresnel);
		// Not multiplied by ALBEDO: the rim is the moon catching an edge, not the
		// surface's own colour, and a dark material needs the rim most.
		EMISSION += rim * rim_strength * rim_color;
	}
}

void light() {
	// Fold shadow attenuation in *before* quantising so a shadowed surface snaps
	// to the darkest band instead of smoothly dimming through it. That is what
	// keeps shadow edges as crisp as the band terminators.
	float ndotl = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0);
	float lit = ndotl * ATTENUATION;
	float banded = cel_bands(lit, band_count, band_softness);

	if (dot_enabled) {
		float n = float(band_count);
		float band_width = 1.0 / n;
		if (lit < band_width) {
			// Inside the darkest band: stipple between "full shadow" and the
			// next band up, so the terminator breaks into dots rather than a
			// smooth ramp. `local` is how far through the shadow band we are.
			float local = clamp(lit * n, 0.0, 1.0);
			float coverage = clamp((1.0 - local) * dot_density, 0.0, 1.0);
			float mask = halftone(FRAGCOORD.xy, dot_scale_px, coverage);
			float next_level = 1.0 / max(n - 1.0, 1.0);
			banded = mix(next_level, 0.0, mask);
		}
	}

	// Lift into [shadow_floor, 1] *after* the dotting branch, so the halftone
	// still stipples between the shadow level and the band above it -- it just
	// does so at a readable tone rather than against black.
	banded = shadow_floor + (1.0 - shadow_floor) * banded;

	DIFFUSE_LIGHT += banded * LIGHT_COLOR * ALBEDO / PI;

	if (specular_enabled) {
		vec3 half_vec = normalize(normalize(LIGHT) + normalize(VIEW));
		float spec = pow(clamp(dot(normalize(NORMAL), half_vec), 0.0, 1.0), specular_sharpness);
		// Threshold to a flat blob rather than a falloff -- one hard edge the
		// compositor can find and outline.
		float blob = smoothstep(specular_threshold - band_softness, specular_threshold + band_softness, spec);
		SPECULAR_LIGHT += blob * ATTENUATION * specular_color * LIGHT_COLOR;
	}
}
