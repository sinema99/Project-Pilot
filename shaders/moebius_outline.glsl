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
	float normal_edge_threshold;
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
	float pad0;
	float pad1;
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

	// No line on the sky, and none where any neighbour is sky -- that keeps the
	// horizon and the sky's own silhouette clean.
	if (!any_sky) {
		float d[9];
		for (int i = 0; i < 9; i++) {
			d[i] = linear_depth(raw_depth[i]);
		}

		// Sobel 3x3 on depth.
		float gx = (d[0] + 2.0 * d[3] + d[6]) - (d[2] + 2.0 * d[5] + d[8]);
		float gy = (d[0] + 2.0 * d[1] + d[2]) - (d[6] + 2.0 * d[7] + d[8]);
		// Relative to distance, so a threshold tuned up close still behaves far away.
		float depth_edge = length(vec2(gx, gy)) / max(center_distance, 0.001);

		// Sobel 3x3 on normals.
		vec3 ngx = (normals[0] + 2.0 * normals[3] + normals[6]) - (normals[2] + 2.0 * normals[5] + normals[8]);
		vec3 ngy = (normals[0] + 2.0 * normals[1] + normals[2]) - (normals[6] + 2.0 * normals[7] + normals[8]);
		float normal_edge = sqrt(dot(ngx, ngx) + dot(ngy, ngy));

		float de = smoothstep(params.depth_edge_threshold, params.depth_edge_threshold * 2.0, depth_edge);
		float ne = smoothstep(params.normal_edge_threshold, params.normal_edge_threshold * 2.0, normal_edge);
		edge = max(de, ne);

		// Fade with distance so lines do not pop in across the far field.
		float fade = 1.0 - smoothstep(params.fade_start_m, params.fade_end_m, center_distance);
		edge *= fade;
	}

	vec4 color = imageLoad(color_image, coord);
	vec3 line_color = vec3(params.line_color_r, params.line_color_g, params.line_color_b);
	color.rgb = mix(color.rgb, line_color, clamp(edge, 0.0, 1.0));

	// Paper tooth. The seed is held for a stretch of frames by the GDScript side,
	// so the field steps rather than crawling like TV static.
	if (params.grain_strength > 0.0) {
		float g = hash12(vec2(coord) + params.grain_seed * 1024.0) - 0.5;
		color.rgb += g * params.grain_strength;
	}

	imageStore(color_image, coord, color);
}
