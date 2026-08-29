@tool
extends CompositorEffect

# Moebius outline + grain compositor effect.
#
# One effect, one pass chain: edge detection over depth + normals, with the
# stepped film grain composited in the same pass (they are not two effects).

@export_group("Line")
## Screen-space line weight in pixels, sitting at Sable's own weight; 1.5 gives
## a slightly heavier pen. Resolution-scaled so it holds at 4K. This is the
## radius of the Sobel taps rather than a stroke width, so raising it thickens
## the line and coarsens fine creases in the same move.
@export var line_thickness_px: float = 1.0
## Warm near-black by default; set to pure black for a harder look.
@export var line_color: Color = Color("#1A1410")
@export var depth_edge_threshold: float = 0.05
@export var normal_edge_threshold: float = 0.6

@export_group("Distance fade")
## Lines are full strength up to here...
@export var fade_start_m: float = 60.0
## ...and gone by here, so nothing pops in across the far field. Keep roughly
## aligned with the fog by eye; this is deliberately not linked to the fog node.
@export var fade_end_m: float = 150.0

@export_group("Wobble")
## Hand-inked quiver, measured as a fraction of two pixels of sideways drift --
## so 0.5 is a line that wanders about a pixel off true, which on a 1px pen is
## a waver you can actually see. The lines are still meant to read as straight,
## just not machine-straight: a steady hand failing to be a ruler. Past ~1.0 it
## stops looking drawn and starts looking like heat haze.
@export var wobble_strength: float = 0.5
## Wavelength of the quiver. Low numbers give long lazy waves down the length
## of a line; high numbers give jitter, which reads as noise, not as a hand.
@export var wobble_scale: float = 24.0
## How fast the quiver drifts. The noise field slides continuously instead of
## being re-drawn in steps the way the grain is, so this stays slow - fast
## drift on a subtle wobble reads as shimmer rather than as ink.
@export var wobble_speed: float = 0.35

@export_group("Grain")
@export var grain_strength: float = 0.035
## Re-seed interval, in rendered frames. The grain is meant to read as paper
## tooth, so the noise field is held for a stretch of frames rather than
## resampled every frame (which reads as crawling TV static).
@export var grain_step_frames: int = 10

const SHADER_PATH := "res://shaders/moebius_outline.glsl"

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID

var _frame := 0
var _grain_step := -1
var _grain_seed := 0.0

# Advances the grain clock by one rendered frame and returns the seed to use.
# The seed holds steady for `grain_step_frames` frames, then jumps.
func tick_grain() -> float:
	var step := _frame / maxi(grain_step_frames, 1)
	if step != _grain_step:
		_grain_step = step
		# Golden-ratio stride: deterministic, and successive steps land far
		# apart so consecutive grain fields do not look related.
		_grain_seed = fmod(float(step) * 0.6180339887498949, 1.0)
	_frame += 1
	return _grain_seed


# --- push constant --------------------------------------------------------

## Number of floats in the push_constant block declared by moebius_outline.glsl.
## 20 floats = 80 bytes, a multiple of the required 16.
const PUSH_CONSTANT_FLOATS := 20
## Viewport height the line thickness is authored against.
const REFERENCE_HEIGHT := 1080.0

# Packs the push constant exactly as moebius_outline.glsl declares it. Kept pure
# and free of any RenderingDevice access so it can be checked against the GLSL
# struct directly.
func build_push_constant(size: Vector2i, grain_seed: float, time: float,
		z_near: float = 0.05, z_far: float = 1000.0) -> PackedByteArray:
	# Scale the pen by viewport height so a weight authored at 1080 keeps its
	# apparent thickness at 4K instead of thinning to a hairline.
	var resolution_scale := float(size.y) / REFERENCE_HEIGHT
	var scaled_thickness := line_thickness_px * resolution_scale

	var values := PackedFloat32Array([
		float(size.x),
		float(size.y),
		scaled_thickness,
		depth_edge_threshold,
		normal_edge_threshold,
		fade_start_m,
		fade_end_m,
		wobble_strength,
		wobble_scale,
		wobble_speed,
		grain_strength,
		grain_seed,
		line_color.r,
		line_color.g,
		line_color.b,
		time,
		z_near,
		z_far,
		0.0,
		0.0,
	])
	return values.to_byte_array()


# --- render plumbing ------------------------------------------------------
# Everything below needs a live RenderingDevice, so it does not run (and is not
# covered) under --headless. The pure parts it depends on -- push-constant
# packing and the grain clock -- are tested directly.

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	# Lines are drawn over the resolved colour buffer, and MSAA 4x is on, so the
	# resolved (single-sample) colour and depth are what this pass needs.
	access_resolved_color = true
	access_resolved_depth = true
	needs_normal_roughness = true
	RenderingServer.call_on_render_thread(_initialize_compute)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Inlined rather than delegated: during PREDELETE the script instance is
		# already tearing down, so calling a method on self fails. Freed through
		# RenderingServer so it lands on the render thread.
		if _sampler.is_valid():
			RenderingServer.free_rid(_sampler)
		if _pipeline.is_valid():
			RenderingServer.free_rid(_pipeline)
		if _shader.is_valid():
			RenderingServer.free_rid(_shader)

func _initialize_compute() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return

	var shader_file: RDShaderFile = load(SHADER_PATH)
	if shader_file == null:
		push_error("moebius_compositor: could not load %s" % SHADER_PATH)
		return

	var spirv := shader_file.get_spirv()
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		push_error("moebius_compositor: %s failed to compile" % SHADER_PATH)
		return
	_pipeline = _rd.compute_pipeline_create(_shader)

	# Nearest + clamp: point-sampling depth and normals keeps the edge test
	# reading true texel values rather than a blurred average of them.
	var state := RDSamplerState.new()
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(state)

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if _rd == null or not _pipeline.is_valid():
		return
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return

	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	var scene_data := render_data.get_render_scene_data() as RenderSceneDataRD

	# One grain tick per rendered frame, not per view.
	var seed := tick_grain()
	var time := float(Time.get_ticks_msec()) / 1000.0

	@warning_ignore("integer_division")
	var groups_x := (size.x - 1) / 8 + 1
	@warning_ignore("integer_division")
	var groups_y := (size.y - 1) / 8 + 1

	for view in buffers.get_view_count():
		var color := buffers.get_color_layer(view)
		var depth := buffers.get_depth_layer(view)
		var normal_roughness := buffers.get_texture_slice("forward_clustered", "normal_roughness", view, 0, 1, 1)
		if not color.is_valid() or not depth.is_valid() or not normal_roughness.is_valid():
			continue

		var z_near := 0.05
		var z_far := 1000.0
		if scene_data != null:
			var projection := scene_data.get_view_projection(view)
			z_near = projection.get_z_near()
			z_far = projection.get_z_far()

		var color_uniform := RDUniform.new()
		color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		color_uniform.binding = 0
		color_uniform.add_id(color)

		var depth_uniform := RDUniform.new()
		depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		depth_uniform.binding = 1
		depth_uniform.add_id(_sampler)
		depth_uniform.add_id(depth)

		var normal_uniform := RDUniform.new()
		normal_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		normal_uniform.binding = 2
		normal_uniform.add_id(_sampler)
		normal_uniform.add_id(normal_roughness)

		var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, [color_uniform, depth_uniform, normal_uniform])
		var push_constant := build_push_constant(size, seed, time, z_near, z_far)

		var compute_list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
		_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		_rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
		_rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
		_rd.compute_list_end()
