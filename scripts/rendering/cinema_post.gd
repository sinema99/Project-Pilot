@tool
class_name CinemaPost
extends CompositorEffect

# The cinema look (docs/specs/cinema-post.md): an anamorphic lens streak on the brightest pixels,
# a colour grade, chromatic aberration at the edges, a soft vignette and moving film grain. Runs
# after the transparent pass on the HDR colour, before the tonemap, so the environment's glow
# also blooms the streak. Built on the intro space shot; any shot takes it by putting one in its
# WorldEnvironment's Compositor.
#
# Passes (compute): copy the colour, pull the bright pixels into a small buffer (quarter width,
# half height, so the streak stays thin), blur that buffer sideways a few times with a growing
# stride (one long streak), then composite everything back onto the colour.

@export_group("Streak")
## HDR brightness a pixel needs before it streaks. Above the trail cores (1.5), below the glints.
@export var streak_threshold := 1.6
## Soft knee below the threshold, as a fraction of it.
@export_range(0.0, 1.0) var streak_knee := 0.3
## Caps one pixel's contribution, so a single hot texel cannot paint the whole line.
@export var streak_clamp := 12.0
@export var streak_tint := Color(0.35, 0.6, 1.0)
## 0 = off (2026-10-16, user: "get rid of the weird horizontal streaks"; was 1.2).
@export var streak_intensity := 0.0
## How much the streak takes the tint instead of the source colour, 0-1.
@export_range(0.0, 1.0) var streak_tint_mix := 0.8
## Per-tap falloff of the sideways blur; higher = longer tails.
@export_range(0.3, 0.98) var streak_decay := 0.82
## Blur passes; each one stretches the streak four times further.
@export_range(1, 5) var streak_passes := 4

@export_group("Ghosts")
@export var ghost_tint := Color(0.45, 0.4, 1.0)
## 0 = off with the streak (the ghosts are copies of it; was 0.25).
@export var ghost_intensity := 0.0
## Where the ghosts sit on the line through the screen centre (negative = mirrored).
@export var ghost_scales := Vector3(-0.6, -1.25, 0.45)

@export_group("Grade")
## Contrast around mid grey (1 = untouched).
@export var contrast := 1.08
@export var saturation := 1.15
## Multipliers for the darks and the lights: teal shadows, warm highlights.
@export var shadow_tint := Color(0.88, 1.0, 1.08)
@export var highlight_tint := Color(1.06, 1.0, 0.93)
@export_range(0.0, 1.0) var split_strength := 1.0

@export_group("Lens")
## Red / blue spread at the very corner, fraction of the screen.
@export var aberration := 0.0012
## Distance from the centre (0 centre, 1 corner) where the fringes start.
@export_range(0.0, 1.0) var aberration_start := 0.6
@export_range(0.0, 1.0) var vignette_strength := 0.35
@export_range(0.0, 1.0) var vignette_start := 0.45
@export_range(0.0, 2.0) var vignette_end := 1.1

@export_group("Grain")
## Multiplicative grain on everything.
@export var grain := 0.07
## Extra grain in the darks, added on top (linear HDR units).
@export var grain_floor := 0.004
## Grain frames per second. Film runs at 24.
@export var grain_fps := 24.0

const _COPY := """
#version 450
layout(local_size_x = 8, local_size_y = 8) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict readonly image2D color;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D dst;
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(p, imageSize(dst)))) return;
	imageStore(dst, p, imageLoad(color, p));
}
"""

const _BRIGHT := """
#version 450
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0) uniform sampler2D src;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D dst;
layout(push_constant, std430) uniform P { vec4 a; } pc; // threshold, knee, clamp, -
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(dst);
	if (any(greaterThanEqual(p, size))) return;
	vec2 uv = (vec2(p) + 0.5) / vec2(size);
	vec2 h = 0.25 / vec2(size);
	// Four bilinear taps: the average of the source block under this texel.
	vec3 c = texture(src, uv + vec2(-h.x, -h.y)).rgb + texture(src, uv + vec2(h.x, -h.y)).rgb
			+ texture(src, uv + vec2(-h.x, h.y)).rgb + texture(src, uv + vec2(h.x, h.y)).rgb;
	c *= 0.25;
	float b = max(c.r, max(c.g, c.b));
	float t = pc.a.x;
	float k = max(t * pc.a.y, 1e-4);
	float soft = clamp(b - t + k, 0.0, 2.0 * k);
	soft = soft * soft / (4.0 * k);
	float w = max(soft, b - t) / max(b, 1e-4);
	c = min(c * w, vec3(pc.a.z));
	imageStore(dst, p, vec4(c, 1.0));
}
"""

const _STREAK := """
#version 450
layout(local_size_x = 8, local_size_y = 8) in;
layout(set = 0, binding = 0) uniform sampler2D src;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D dst;
layout(push_constant, std430) uniform P { vec4 a; } pc; // stride (texels), decay, -, -
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(dst);
	if (any(greaterThanEqual(p, size))) return;
	vec2 uv = (vec2(p) + 0.5) / vec2(size);
	float step_uv = pc.a.x / float(size.x);
	vec3 sum = vec3(0.0);
	float wsum = 0.0;
	for (int i = -3; i <= 3; i++) {
		float w = pow(pc.a.y, abs(float(i)));
		sum += texture(src, uv + vec2(float(i) * step_uv, 0.0)).rgb * w;
		wsum += w;
	}
	imageStore(dst, p, vec4(sum / wsum, 1.0));
}
"""

const _COMPOSITE := """
#version 450
layout(local_size_x = 8, local_size_y = 8) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict writeonly image2D color;
layout(set = 0, binding = 1) uniform sampler2D src;
layout(set = 0, binding = 2) uniform sampler2D streak;
layout(push_constant, std430) uniform P {
	vec4 streak_tint;   // rgb, intensity
	vec4 ghost_tint;    // rgb, intensity
	vec4 ghost_scales;  // xyz, tint mix
	vec4 shadow_tint;   // rgb, split strength
	vec4 high_tint;     // rgb, contrast
	vec4 lens;          // saturation, vignette strength, vignette start, vignette end
	vec4 fx;            // aberration, aberration start, grain, grain floor
	vec4 frame;         // grain seed, -, -, -
} pc;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(color);
	if (any(greaterThanEqual(p, size))) return;
	vec2 uv = (vec2(p) + 0.5) / vec2(size);
	float aspect = float(size.x) / float(size.y);
	vec2 off = uv - 0.5;
	// 0 at the centre, 1 at the corners.
	float r = length(off * vec2(aspect, 1.0)) / length(vec2(aspect, 1.0) * 0.5);

	// Chromatic aberration: red out, blue in, only toward the edges.
	float ca = pc.fx.x * smoothstep(pc.fx.y, 1.0, r);
	vec3 c;
	c.r = texture(src, uv + off * ca * 2.0).r;
	c.g = texture(src, uv).g;
	c.b = texture(src, uv - off * ca * 2.0).b;

	// Anamorphic streak: mostly the lens tint, a little of the source colour.
	vec3 s = texture(streak, uv).rgb;
	vec3 lens_tint = pc.streak_tint.rgb / max(luma(pc.streak_tint.rgb), 1e-3);
	c += mix(s, luma(s) * lens_tint, pc.ghost_scales.w) * pc.streak_tint.w;
	// Ghosts: the streak buffer again, along the line through the centre, fading at the edges.
	vec3 g = vec3(0.0);
	for (int i = 0; i < 3; i++) {
		vec2 guv = 0.5 + off * pc.ghost_scales[i];
		float edge = 1.0 - smoothstep(0.25, 0.5, length(guv - 0.5));
		g += texture(streak, guv).rgb * edge;
	}
	c += luma(g) * pc.ghost_tint.rgb * pc.ghost_tint.w;

	// Grade: contrast around mid grey, saturation, then split toning by brightness.
	c = max(c, vec3(0.0));
	c = 0.18 * pow(c / 0.18 + 1e-6, vec3(pc.high_tint.w));
	float l = luma(c);
	c = max(mix(vec3(l), c, pc.lens.x), vec3(0.0));
	float tl = l / (1.0 + l);
	vec3 tint = mix(pc.shadow_tint.rgb, pc.high_tint.rgb, smoothstep(0.08, 0.45, tl));
	c *= mix(vec3(1.0), tint, pc.shadow_tint.w);

	// Vignette.
	c *= 1.0 - pc.lens.y * smoothstep(pc.lens.z, pc.lens.w, r);

	// Grain: two hashes summed (roughly bell shaped), new pattern every grain frame.
	vec2 q = vec2(p) + pc.frame.x * vec2(37.0, 17.0);
	float n = hash(q) + hash(q + 71.3) - 1.0;
	float dark = 1.0 - smoothstep(0.0, 0.25, tl);
	c = max(c * (1.0 + n * pc.fx.z) + n * pc.fx.w * dark, vec3(0.0));

	imageStore(color, p, vec4(c, 1.0));
}
"""

var _rd: RenderingDevice
var _sampler: RID
var _shaders := {}
var _pipelines := {}
var _size := Vector2i.ZERO
var _src: RID
var _bright: RID
var _ping: RID


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	RenderingServer.call_on_render_thread(_setup)


func _notification(what: int) -> void:
	# No method calls here: the script is already being torn down. Freeing a shader also frees its
	# pipeline and the cached uniform sets built on it.
	if what == NOTIFICATION_PREDELETE and _rd:
		for t: RID in [_src, _bright, _ping, _sampler]:
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
	_sampler = _rd.sampler_create(ss)
	for key: String in ["copy", "bright", "streak", "composite"]:
		var code: String = {"copy": _COPY, "bright": _BRIGHT, "streak": _STREAK, "composite": _COMPOSITE}[key]
		var src := RDShaderSource.new()
		src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
		src.source_compute = code
		var spirv := _rd.shader_compile_spirv_from_source(src)
		if spirv.compile_error_compute != "":
			push_error("CinemaPost %s: %s" % [key, spirv.compile_error_compute])
			return
		var shader := _rd.shader_create_from_spirv(spirv)
		_shaders[key] = shader
		_pipelines[key] = _rd.compute_pipeline_create(shader)


func _free_textures() -> void:
	for t: RID in [_src, _bright, _ping]:
		if t.is_valid():
			_rd.free_rid(t)
	_src = RID()
	_bright = RID()
	_ping = RID()


func _texture(size: Vector2i) -> RID:
	var f := RDTextureFormat.new()
	f.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	f.width = size.x
	f.height = size.y
	f.usage_bits = (RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT)
	return _rd.texture_create(f, RDTextureView.new())


## The small buffer the streak lives in: quarter width, half height.
static func streak_size(size: Vector2i) -> Vector2i:
	return Vector2i(maxi(size.x / 4, 1), maxi(size.y / 2, 1))


func _ensure_textures(size: Vector2i) -> void:
	if size == _size and _src.is_valid():
		return
	_free_textures()
	_size = size
	_src = _texture(size)
	var small := streak_size(size)
	_bright = _texture(small)
	_ping = _texture(small)


func _image(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u


func _sampled(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(_sampler)
	u.add_id(rid)
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


static func _vec4(c: Color, w: float) -> PackedFloat32Array:
	return PackedFloat32Array([c.r, c.g, c.b, w])


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or not _rd or _pipelines.size() < 4:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if not buffers:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	_ensure_textures(size)
	var small := streak_size(size)
	var seed := floorf(Time.get_ticks_msec() / 1000.0 * grain_fps)
	for view in buffers.get_view_count():
		var color := buffers.get_color_layer(view)
		_dispatch("copy", [_image(0, color), _image(1, _src)], PackedFloat32Array(), size)
		_dispatch("bright", [_sampled(0, _src), _image(1, _bright)],
				PackedFloat32Array([streak_threshold, streak_knee, streak_clamp, 0.0]), small)
		# Ping-pong the sideways blur; the stride grows four times per pass.
		var a := _bright
		var b := _ping
		var stride := 1.0
		for i in streak_passes:
			_dispatch("streak", [_sampled(0, a), _image(1, b)],
					PackedFloat32Array([stride, streak_decay, 0.0, 0.0]), small)
			var t := a
			a = b
			b = t
			stride *= 4.0
		var push := PackedFloat32Array()
		push.append_array(_vec4(streak_tint, streak_intensity))
		push.append_array(_vec4(ghost_tint, ghost_intensity))
		push.append_array(PackedFloat32Array([ghost_scales.x, ghost_scales.y, ghost_scales.z, streak_tint_mix]))
		push.append_array(_vec4(shadow_tint, split_strength))
		push.append_array(_vec4(highlight_tint, contrast))
		push.append_array(PackedFloat32Array([saturation, vignette_strength, vignette_start, vignette_end]))
		push.append_array(PackedFloat32Array([aberration, aberration_start, grain, grain_floor]))
		push.append_array(PackedFloat32Array([fmod(seed, 1000.0), 0.0, 0.0, 0.0]))
		_dispatch("composite", [_image(0, color), _sampled(1, _src), _sampled(2, a)], push, size)
