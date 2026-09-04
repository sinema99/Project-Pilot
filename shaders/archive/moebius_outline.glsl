#[compute]
#version 450

// Moebius outline + grain. Post-transparent compute pass.
//
// Edges come from depth and normals only -- no object/ID buffer in this phase.
// Depth discontinuity gives silhouettes; normal discontinuity gives creases and
// corners. Grain is composited in the same pass; this is one effect, not two.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_sampler;
layout(set = 0, binding = 2) uniform sampler2D normal_roughness_sampler;

// Declared as flat floats on purpose: std430 offsets are then a plain 4-byte
// sequence, with no vec3 alignment traps between here and the GDScript packer.
layout(push_constant, std430) uniform Params {
	float raster_width;
	float raster_height;
	float line_thickness_px;
	float depth_edge_threshold;
	float normal_edge_angle_deg;
	float fade_start_m;
	float fade_end_m;
	float wobble_strength;
	float wobble_scale;
	float wobble_speed;
	float grain_strength;
	float grain_seed;
	float line_color_r;
	float line_color_g;
	float line_color_b;
	float time;
	float z_near;
	float z_far;
	float grain_luma_falloff;
	float ink_sky_silhouette;
} params;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i + vec2(0.0, 0.0)), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

// Godot's Forward+ depth buffer is reverse-Z: 1.0 at the near plane, 0.0 at the
// far plane (and exactly 0.0 for sky, which is how sky rejection works).
float linear_depth(float d) {
	return (params.z_near * params.z_far) / (params.z_near + d * (params.z_far - params.z_near));
}

bool is_sky(float raw_depth) {
	return raw_depth <= 0.0;
}

// Fractional sky coverage at a UV, via a manual 2x2 bilinear tap of the sky
// mask. The depth sampler is NEAREST (the crease path needs true texel values),
// so a plain sky test flips hard 0<->1 between texels and the silhouette line
// inherits that stepping. Filtering the mask here gives sub-texel coverage,
// which is what lets the line blend instead of staircase.
float sky_coverage(vec2 uv_s, vec2 size) {
	vec2 p = uv_s * size - 0.5;
	vec2 base = floor(p) + 0.5;
	vec2 f = fract(uv_s * size - 0.5);
	float s00 = is_sky(texture(depth_sampler, (base + vec2(0.0, 0.0)) / size).r) ? 1.0 : 0.0;
	float s10 = is_sky(texture(depth_sampler, (base + vec2(1.0, 0.0)) / size).r) ? 1.0 : 0.0;
	float s01 = is_sky(texture(depth_sampler, (base + vec2(0.0, 1.0)) / size).r) ? 1.0 : 0.0;
	float s11 = is_sky(texture(depth_sampler, (base + vec2(1.0, 1.0)) / size).r) ? 1.0 : 0.0;
	return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

void main() {
	ivec2 size = ivec2(int(params.raster_width), int(params.raster_height));
	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
	if (coord.x >= size.x || coord.y >= size.y) {
		return;
	}

	vec2 texel = 1.0 / vec2(size);
	vec2 uv = (vec2(coord) + 0.5) * texel;

	// Hand-inked quiver. Nudges the whole 3x3 tap window at once, so a line
	// drifts sideways as a unit rather than thickening or breaking up - the
	// difference between a hand that isn't a ruler and a shaky one.
	if (params.wobble_strength > 0.0) {
		vec2 w = vec2(
			value_noise(uv * params.wobble_scale + params.time * params.wobble_speed),
			value_noise(uv * params.wobble_scale + 31.7 - params.time * params.wobble_speed));
		uv += (w - 0.5) * params.wobble_strength * texel * 4.0;
	}

	// Sample offset carries the line weight: already resolution-scaled by the
	// GDScript side, so it holds at 4K.
	vec2 offset = texel * max(params.line_thickness_px, 0.0);

	float raw_depth[9];
	vec3 normals[9];
	bool any_sky = false;

	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			int i = (y + 1) * 3 + (x + 1);
			vec2 s = uv + vec2(float(x), float(y)) * offset;
			raw_depth[i] = texture(depth_sampler, s).r;
			normals[i] = texture(normal_roughness_sampler, s).xyz * 2.0 - 1.0;
			if (is_sky(raw_depth[i])) {
				any_sky = true;
			}
		}
	}

	float edge = 0.0;
	float center_distance = linear_depth(raw_depth[4]);
	bool center_sky = is_sky(raw_depth[4]);

	// Silhouette where geometry meets the sky. Off by default -- the base look
	// keeps the horizon and the sky's own silhouette clean -- but scenes where
	// the terrain itself is the skyline (open desert, mountains) want that ridge
	// inked. Inking every pixel whose 3x3 touches sky gives a fat, binary,
	// stair-stepped band (a dune ridge is bumpy at grazing angle and the resolved
	// depth has no MSAA). Instead: average a *filtered* sky-coverage field over a
	// small disc and lay a soft line along its 50% isocontour. sky_coverage()
	// bilinear-filters the mask so the field is continuous, not 17 hard steps;
	// two rings plus centre keep it even; the wide feather blends the line into
	// the sand rather than ending on a hard edge. Gated on the 3x3 any_sky so
	// the disc is only walked on pixels actually near the horizon.
	if (params.ink_sky_silhouette > 0.5 && !center_sky && any_sky) {
		vec2 fsize = vec2(size);
		float pen = max(params.line_thickness_px, 0.5);
		float sky_cov = sky_coverage(uv, fsize);
		float wsum = 1.0;
		const int RING_TAPS = 8;
		for (int i = 0; i < RING_TAPS; i++) {
			float a = 6.2831853 * (float(i) + 0.5) / float(RING_TAPS);
			vec2 dir = vec2(cos(a), sin(a));
			sky_cov += sky_coverage(uv + dir * texel * pen * 1.1, fsize);
			sky_cov += sky_coverage(uv + dir * texel * pen * 2.2, fsize);
			wsum += 2.0;
		}
		sky_cov /= wsum;
		// Soft line centred on the 50% isocontour: 1 on the contour, feathering
		// smoothly to 0 by +/- `band` of coverage either side. Spike tips
		// (mostly sky) fall back off, so they do not blob. A wide band here is
		// deliberate -- the ask is a line that blends, not a crisp one.
		const float band = 0.44;
		edge = 1.0 - smoothstep(0.0, band, abs(sky_cov - 0.5));
		edge *= edge; // ease-in, so the blend tails off gently into the sand
	// Otherwise: no line on the sky, and none where any neighbour is sky.
	} else if (!any_sky) {
		float d[9];
		for (int i = 0; i < 9; i++) {
			d[i] = linear_depth(raw_depth[i]);
		}

		// Sobel 3x3 on depth.
		float gx = (d[0] + 2.0 * d[3] + d[6]) - (d[2] + 2.0 * d[5] + d[8]);
		float gy = (d[0] + 2.0 * d[1] + d[2]) - (d[6] + 2.0 * d[7] + d[8]);
		// Relative to distance, so a threshold tuned up close still behaves far away.
		float depth_edge = length(vec2(gx, gy)) / max(center_distance, 0.001);

		// Crease test by dihedral angle, not gradient magnitude: measure the
		// angle between the centre pixel's normal and each of its 8 neighbours,
		// take the widest bend, and ink only once that clears the configured
		// angle. This makes the threshold read as "fold the faces past N
		// degrees before drawing a line" -- a shallow bevel stays clean, a hard
		// corner inks -- and keeps gentle surface curvature from being hatched.
		vec3 n_center = normalize(normals[4]);
		float min_dot = 1.0;
		for (int i = 0; i < 9; i++) {
			if (i == 4) continue;
			min_dot = min(min_dot, dot(n_center, normalize(normals[i])));
		}
		float crease_angle = acos(clamp(min_dot, -1.0, 1.0));
		float crease_threshold = radians(params.normal_edge_angle_deg);
		// +/- 4 degrees of softness on the seam so it antialiases rather than
		// popping, matching the feathering on the depth edge.
		float crease_soft = radians(4.0);

		float de = smoothstep(params.depth_edge_threshold, params.depth_edge_threshold * 2.0, depth_edge);
		float ne = smoothstep(crease_threshold - crease_soft, crease_threshold + crease_soft, crease_angle);

		// Open-vista mode pushes fade_end far out so distant silhouettes survive,
		// but low-poly terrain seen near edge-on turns every facet seam into a
		// crease line, and those pile up under the horizon as chatter. Retire the
		// crease term on the original near curve so only the silhouette and true
		// depth steps carry into the far field. Base scenes (flag off) keep the
		// old single fade untouched.
		if (params.ink_sky_silhouette > 0.5) {
			ne *= 1.0 - smoothstep(60.0, 150.0, center_distance);
		}

		edge = max(de, ne);
	}

	// Fade with distance so lines do not pop in across the far field -- applied
	// to the crease/depth edges and the sky silhouette alike.
	float fade = 1.0 - smoothstep(params.fade_start_m, params.fade_end_m, center_distance);
	edge *= fade;

	vec4 color = imageLoad(color_image, coord);
	vec3 line_color = vec3(params.line_color_r, params.line_color_g, params.line_color_b);
	color.rgb = mix(color.rgb, line_color, clamp(edge, 0.0, 1.0));

	// Paper tooth. The seed is held for a stretch of frames by the GDScript side,
	// so the field steps rather than crawling like TV static.
	if (params.grain_strength > 0.0) {
		float g = hash12(vec2(coord) + params.grain_seed * 1024.0) - 0.5;
		float amount = params.grain_strength;
		// Ink absorbs tooth: grain that is additive all the way down lifts pure
		// black off zero, and flat black is the one place the speckle has nothing
		// to hide behind. Ramp the grain out below this luminance so black stays
		// black. At 0.0 the ramp is off and the grain is uniform, as before.
		if (params.grain_luma_falloff > 0.0) {
			float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
			amount *= clamp(luma / params.grain_luma_falloff, 0.0, 1.0);
		}
		color.rgb += g * amount;
	}

	imageStore(color_image, coord, color);
}
