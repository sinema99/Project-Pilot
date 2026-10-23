@tool
class_name DepthComposite
extends CompositorEffect

# The composite look (docs/specs/descent-composite.md): a depth-driven pass that does what a
# compositor does to a flat cel render. Near goes dark and tinted, far hazes up toward the light,
# the light itself glows in the distance, and the bright background wraps over the dark edges in
# front of it. Runs after the transparent pass on the HDR colour (so the storm fog and the snow are
# in it), before CinemaPost and the tonemap, so the environment's glow blooms the light.
#
# Passes (compute): pull the far pixels (with the haze and light already on them) into a quarter
# size buffer, blur it a few times, then composite in place on the colour.
#
# Distances are metres from the camera, read from the depth buffer through the inverse projection.
# Everything works on log distance, since a shot spans a metre to tens of kilometres.

@export_group("Light")
## Where the light sits on screen, 0..1 from the top left.
@export var light_uv := Vector2(0.65, 0.4)
## The light's colour. Also the colour the haze lifts toward near it.
@export var light_color := Color(1.0, 0.957, 0.902)
## HDR brightness added to far pixels at the light's centre (glow threshold is 1).
@export var light_energy := 0.55
## The light's core size, as a fraction of the screen height.
@export var light_radius := 0.16
## Vertical squash of the light: above 1 it spreads wider than tall, along the horizon.
@export var light_stretch := 1.6

@export_group("Haze")
@export var haze_color := Color(0.8, 0.77, 0.86)
## Where the haze starts and where it is full (m).
@export var haze_start := 1500.0
@export var haze_end := 14000.0
## How much the haze replaces the far colour at full distance, inside the light's wide lobe.
@export_range(0.0, 1.0) var haze_amount := 0.5
## The wide lobe's size (fraction of screen height), and how much haze is left outside it.
@export var haze_radius := 0.7
@export_range(0.0, 1.0) var haze_floor := 0.25
## How far the haze colour shifts toward the light colour in the light's core.
@export_range(0.0, 1.0) var haze_light_mix := 0.7

@export_group("Dark band")
## Where the near band ends (m): full dark up to near_end, full light from lit_start.
@export var near_end := 15.0
@export var lit_start := 400.0
## Perceived brightness the near band drops to (0..1, applied in gamma 2.2).
@export_range(0.0, 1.0) var near_value := 0.28
## The near band's tint (normalised to unit brightness, so it only shifts the hue).
@export var dark_tint := Color(0.72, 0.75, 0.92)
## Added to the near band so pure blacks lift to slate (linear).
@export var dark_lift := Color(0.011, 0.014, 0.03)
## Pixels this bright (luminance, HDR) escape the near band, so glows on a dark hull stay lit; they
## start escaping at 60% of it. 0 = off.
@export var dark_keep := 0.0

@export_group("Flash")
## 0..1, pushed every frame by the shot: lifts the near band toward the flash look.
@export_range(0.0, 1.0) var flash := 0.0
@export_range(0.0, 1.0) var flash_near_value := 0.6
@export var flash_tint := Color(0.8, 0.9, 1.0)
## Nearer than this (m) the flash does not lift: the ruin around the camera stays dark.
@export var flash_start := 12.0

@export_group("Sky")
## Distance (m) the sky pixels are taken to be, for a shot whose ground is painted in the sky (the
## flyover's streets). 0 = infinitely far.
@export var sky_distance := 0.0

@export_group("Light wrap")
## The background, for the wrap: from wrap_near (m) it starts to count, from wrap_far it is full.
@export var wrap_near := 1500.0
@export var wrap_far := 4000.0
## How much of the blurred background is added over the near pixels.
@export var wrap_strength := 0.55
## Blur passes; each one doubles the reach.
@export_range(1, 5) var wrap_passes := 3

@export_group("Debug")
## 0 = off, 1 = distance bands, 2 = dark band mask, 3 = wrap buffer.
@export_range(0, 3) var debug_view := 0

const _COMMON := """
#version 450
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0, std140) uniform Params {
	vec4 proj_z;    // inverse projection, z row
	vec4 proj_w;    // inverse projection, w row
	vec4 light;     // uv, radius, stretch
	vec4 light_col; // rgb, energy
	vec4 haze;      // rgb, amount
	vec4 haze2;     // radius, floor, light mix, aspect
	vec4 dark;      // tint rgb, near value (linear)
	vec4 lift;      // rgb, wrap strength
	vec4 dists;     // log near_end, log lit_start, log haze_start, log haze_end
	vec4 wrap;      // log wrap_near, log wrap_far, debug, -
	vec4 flash;     // near multiplier with the flash in rgb, log flash_start
	vec4 extra;     // log sky distance (0 = infinite), dark keep, -, -
} pm;

float log_dist(float depth, vec2 uv) {
	if (depth <= 1e-7) return pm.extra.x != 0.0 ? pm.extra.x : 30.0;
	vec4 ndc = vec4(uv * 2.0 - 1.0, depth, 1.0);
	float z = dot(pm.proj_z, ndc) / dot(pm.proj_w, ndc);
	return log(max(-z, 1e-3));
}

// 1 at the light's centre, falling off; `radius` is a fraction of the screen height.
float lobe(vec2 uv, float radius) {
	vec2 d = (uv - pm.light.xy) * vec2(pm.haze2.w, pm.light.w);
	float r = length(d) / max(radius, 1e-4);
	return exp(-r * r);
}

// The distance: haze toward the light colour near the light, and the light itself.
vec3 far_treatment(vec3 c, float L, vec2 uv) {
	float core = lobe(uv, pm.light.z);
	float wide = lobe(uv, pm.haze2.x);
	float h = smoothstep(pm.dists.z, pm.dists.w, L) * pm.haze.w * mix(pm.haze2.y, 1.0, wide);
	vec3 hc = mix(pm.haze.rgb, pm.light_col.rgb, pm.haze2.z * core);
	c = mix(c, hc, h);
	float far = smoothstep(pm.wrap.x, pm.wrap.y, L);
	return c + pm.light_col.rgb * pm.light_col.w * core * far;
}
"""

const _DOWN := """
layout(rgba16f, set = 0, binding = 1) uniform restrict readonly image2D color;
layout(set = 0, binding = 2) uniform sampler2D depth_tex;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D dst;
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(dst);
	if (any(greaterThanEqual(p, size))) return;
	ivec2 full = imageSize(color);
	vec4 sum = vec4(0.0);
	// Four taps spread over the 4x4 block under this texel.
	for (int i = 0; i < 4; i++) {
		ivec2 q = min(p * 4 + ivec2(1 + 2 * (i & 1), 1 + 2 * (i >> 1)), full - 1);
		vec2 uv = (vec2(q) + 0.5) / vec2(full);
		float L = log_dist(texelFetch(depth_tex, q, 0).r, uv);
		float far = smoothstep(pm.wrap.x, pm.wrap.y, L);
		vec3 c = far_treatment(imageLoad(color, q).rgb, L, uv);
		sum += vec4(min(c, vec3(8.0)) * far, far);
	}
	imageStore(dst, p, sum * 0.25);
}
"""

const _BLUR := """
layout(set = 0, binding = 1) uniform sampler2D src;
layout(rgba16f, set = 0, binding = 2) uniform restrict writeonly image2D dst;
layout(push_constant, std430) uniform P { vec4 a; } pc; // direction (texels), -, -
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(dst);
	if (any(greaterThanEqual(p, size))) return;
	vec2 uv = (vec2(p) + 0.5) / vec2(size);
	vec2 step_uv = pc.a.xy / vec2(size);
	const float w[5] = float[](0.227, 0.194, 0.121, 0.054, 0.016);
	vec4 sum = texture(src, uv) * w[0];
	for (int i = 1; i < 5; i++) {
		sum += texture(src, uv + step_uv * float(i)) * w[i];
		sum += texture(src, uv - step_uv * float(i)) * w[i];
	}
	imageStore(dst, p, sum);
}
"""

const _COMPOSITE := """
layout(rgba16f, set = 0, binding = 1) uniform restrict image2D color;
layout(set = 0, binding = 2) uniform sampler2D depth_tex;
layout(set = 0, binding = 3) uniform sampler2D wrap_tex;
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(color);
	if (any(greaterThanEqual(p, size))) return;
	vec2 uv = (vec2(p) + 0.5) / vec2(size);
	float L = log_dist(texelFetch(depth_tex, p, 0).r, uv);
	vec3 c = imageLoad(color, p).rgb;

	// Near: down and tinted, blacks lifted to slate.
	float dark = 1.0 - smoothstep(pm.dists.x, pm.dists.y, L);
	if (pm.extra.y > 0.0) {
		float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
		dark *= 1.0 - smoothstep(pm.extra.y * 0.6, pm.extra.y, lum);
	}
	vec3 mult = mix(pm.dark.rgb, pm.flash.rgb, smoothstep(pm.flash.w - 0.4, pm.flash.w, L));
	c = mix(c, c * mult + pm.lift.rgb, dark);
	// Far: haze and the light.
	c = far_treatment(c, L, uv);
	// Light wrap: the blurred background over everything nearer than it.
	vec4 w = texture(wrap_tex, uv);
	float far = smoothstep(pm.wrap.x, pm.wrap.y, L);
	c += w.rgb * pm.lift.w * (1.0 - far);

	int dbg = int(pm.wrap.z + 0.5);
	if (dbg == 1) {
		// Bands every e-fold of distance; red = dark band, blue = background.
		float band = fract(L);
		c = vec3(dark, band * 0.6, far);
	} else if (dbg == 2) {
		c = vec3(dark);
	} else if (dbg == 3) {
		c = w.rgb;
	}
	imageStore(color, p, vec4(c, 1.0));
}
"""

const _PARAMS_SIZE := 192

var _rd: RenderingDevice
var _linear: RID
var _nearest: RID
var _params: RID
var _shaders := {}
var _pipelines := {}
var _size := Vector2i.ZERO
var _small_a: RID
var _small_b: RID


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	RenderingServer.call_on_render_thread(_setup)


func _notification(what: int) -> void:
	# No method calls here: the script is already being torn down. Freeing a shader also frees its
	# pipeline and the cached uniform sets built on it.
	if what == NOTIFICATION_PREDELETE and _rd:
		for t: RID in [_small_a, _small_b, _params, _linear, _nearest]:
			if t.is_valid():
				_rd.free_rid(t)
		for sh: RID in _shaders.values():
			if sh.is_valid():
				_rd.free_rid(sh)


func _setup() -> void:
	_rd = RenderingServer.get_rendering_device()
	if not _rd:
		return
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_linear = _rd.sampler_create(ss)
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_nearest = _rd.sampler_create(ss)
	_params = _rd.uniform_buffer_create(_PARAMS_SIZE)
	for key: String in ["down", "blur", "composite"]:
		var code: String = {"down": _DOWN, "blur": _BLUR, "composite": _COMPOSITE}[key]
		var src := RDShaderSource.new()
		src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
		src.source_compute = _COMMON + code
		var spirv := _rd.shader_compile_spirv_from_source(src)
		if spirv.compile_error_compute != "":
			push_error("DepthComposite %s: %s" % [key, spirv.compile_error_compute])
			return
		var shader := _rd.shader_create_from_spirv(spirv)
		_shaders[key] = shader
		_pipelines[key] = _rd.compute_pipeline_create(shader)


## The wrap buffer: quarter size each way.
static func wrap_size(size: Vector2i) -> Vector2i:
	return Vector2i(maxi(size.x / 4, 1), maxi(size.y / 4, 1))


func _ensure_textures(size: Vector2i) -> void:
	if size == _size and _small_a.is_valid():
		return
	for t: RID in [_small_a, _small_b]:
		if t.is_valid():
			_rd.free_rid(t)
	_size = size
	var f := RDTextureFormat.new()
	f.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	var small := wrap_size(size)
	f.width = small.x
	f.height = small.y
	f.usage_bits = (RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT)
	_small_a = _rd.texture_create(f, RDTextureView.new())
	_small_b = _rd.texture_create(f, RDTextureView.new())


func _image(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u


func _sampled(binding: int, rid: RID, sampler: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(sampler)
	u.add_id(rid)
	return u


func _params_uniform() -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u.binding = 0
	u.add_id(_params)
	return u


func _dispatch(key: String, uniforms: Array[RDUniform], push: PackedFloat32Array, size: Vector2i) -> void:
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipelines[key])
	var set_rid := UniformSetCacheRD.get_cache(_shaders[key], 0, uniforms)
	_rd.compute_list_bind_uniform_set(cl, set_rid, 0)
	if not push.is_empty():
		var bytes := push.to_byte_array()
		_rd.compute_list_set_push_constant(cl, bytes, bytes.size())
	_rd.compute_list_dispatch(cl, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	_rd.compute_list_end()


## The DepthComposite on `env`'s compositor, or null.
static func find_in(env: WorldEnvironment) -> DepthComposite:
	if env == null or env.compositor == null:
		return null
	for e in env.compositor.compositor_effects:
		if e is DepthComposite:
			return e
	return null


## A world point as a screen UV (0..1 from the top left) through `camera`, for `light_uv`: the shots
## that move their camera place the light from a world point every frame (docs/specs/shots-composite.md).
## Pinhole through the camera's vertical fov (keep-height) rather than unproject_position, which gave
## distance-dependent nonsense for far points here. Points behind the camera mirror.
static func screen_uv(camera: Camera3D, point: Vector3) -> Vector2:
	var size := camera.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var local := camera.global_transform.affine_inverse() * point
	var depth := maxf(absf(local.z), 1e-4)
	var tan_v := tan(deg_to_rad(camera.fov) * 0.5)
	return Vector2(0.5 + 0.5 * local.x / depth / (tan_v * aspect), 0.5 - 0.5 * local.y / depth / tan_v)


## The near band's colour multiplier: the tint at unit brightness times the linear value, with the
## flash lerped in. Static so the tests can check it without a GPU.
static func near_multiplier(tint: Color, value: float, f_tint: Color, f_value: float, f: float) -> Color:
	var t := tint.lerp(f_tint, f)
	var lum := maxf(0.2126 * t.r + 0.7152 * t.g + 0.0722 * t.b, 1e-4)
	var v := pow(lerpf(value, f_value, f), 2.2)
	return Color(t.r / lum * v, t.g / lum * v, t.b / lum * v, 1.0)


func _params_bytes(inv: Projection, size: Vector2i) -> PackedByteArray:
	var m := near_multiplier(dark_tint, near_value, flash_tint, flash_near_value, 0.0)
	var mf := near_multiplier(dark_tint, near_value, flash_tint, flash_near_value, flash)
	var a := PackedFloat32Array([
		inv.x.z, inv.y.z, inv.z.z, inv.w.z,
		inv.x.w, inv.y.w, inv.z.w, inv.w.w,
		light_uv.x, light_uv.y, light_radius, light_stretch,
		light_color.r, light_color.g, light_color.b, light_energy,
		haze_color.r, haze_color.g, haze_color.b, haze_amount,
		haze_radius, haze_floor, haze_light_mix, float(size.x) / float(size.y),
		m.r, m.g, m.b, 1.0,
		dark_lift.r, dark_lift.g, dark_lift.b, wrap_strength,
		log(near_end), log(lit_start), log(haze_start), log(haze_end),
		log(wrap_near), log(wrap_far), float(debug_view), 0.0,
		mf.r, mf.g, mf.b, log(flash_start),
		log(sky_distance) if sky_distance > 0.0 else 0.0, dark_keep, 0.0, 0.0,
	])
	return a.to_byte_array()


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or not _rd or _pipelines.size() < 3:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene_data := render_data.get_render_scene_data()
	if not buffers or not scene_data:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	_ensure_textures(size)
	var small := wrap_size(size)
	for view in buffers.get_view_count():
		var inv := scene_data.get_view_projection(view).inverse()
		var bytes := _params_bytes(inv, size)
		_rd.buffer_update(_params, 0, bytes.size(), bytes)
		var color := buffers.get_color_layer(view)
		var depth := buffers.get_depth_layer(view)
		_dispatch("down", [_params_uniform(), _image(1, color), _sampled(2, depth, _nearest),
				_image(3, _small_a)], PackedFloat32Array(), small)
		var a := _small_a
		var b := _small_b
		var stride := 1.0
		for i in wrap_passes:
			for dir: Vector2 in [Vector2(stride, 0.0), Vector2(0.0, stride)]:
				_dispatch("blur", [_params_uniform(), _sampled(1, a, _linear), _image(2, b)],
						PackedFloat32Array([dir.x, dir.y, 0.0, 0.0]), small)
				var t := a
				a = b
				b = t
			stride *= 2.0
		_dispatch("composite", [_params_uniform(), _image(1, color), _sampled(2, depth, _nearest),
				_sampled(3, a, _linear)], PackedFloat32Array(), size)
