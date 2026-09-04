extends "res://tests/test_case.gd"

const COMPOSITOR_PATH := "res://scripts/archive/moebius_compositor.gd"

func _effect() -> Object:
	var script := load(COMPOSITOR_PATH) as GDScript
	return script.new() if script != null else null

# Spec: the grain is paper tooth, not crawling TV static -- the noise field is
# re-seeded every ~N rendered frames rather than every frame. The seed must hold
# steady inside a step and change on the boundary.
func test_grain_seed_holds_for_grain_step_frames_then_changes() -> void:
	var fx := _effect()
	if fx == null:
		fail("%s does not exist" % COMPOSITOR_PATH)
		return

	fx.grain_step_frames = 10

	var seeds: Array[float] = []
	for i in 25:
		seeds.append(fx.tick_grain())

	# Frames 0-9 share one seed, 10-19 the next, 20-24 the third.
	for i in range(1, 10):
		eq(seeds[i], seeds[0], "seed must hold steady within a step (frame %d)" % i)
	for i in range(11, 20):
		eq(seeds[i], seeds[10], "seed must hold steady within the second step (frame %d)" % i)

	check(seeds[10] != seeds[0], "seed must change at the step boundary (frame 10)")
	check(seeds[20] != seeds[10], "seed must change at the next step boundary (frame 20)")

func test_grain_step_frames_defaults_to_ten() -> void:
	var fx := _effect()
	if fx == null:
		fail("%s does not exist" % COMPOSITOR_PATH)
		return
	eq(fx.grain_step_frames, 10, "spec default: re-seed every ~10 rendered frames")

const GLSL_PATH := "res://shaders/archive/moebius_outline.glsl"

# Reads the push_constant block out of the compute shader and returns its field
# names in declaration order. The struct is declared as flat floats precisely so
# std430 offsets are a plain 4-byte sequence with no alignment traps.
func _glsl_push_constant_fields() -> PackedStringArray:
	var f := FileAccess.open(GLSL_PATH, FileAccess.READ)
	if f == null:
		return []
	var src := f.get_as_text()
	var block := RegEx.new()
	block.compile(r"layout\s*\(\s*push_constant[^)]*\)\s*uniform\s+\w+\s*\{([^}]*)\}")
	var m := block.search(src)
	if m == null:
		return []
	var field := RegEx.new()
	field.compile(r"float\s+(\w+)\s*;")
	var names: PackedStringArray = []
	for hit in field.search_all(m.get_string(1)):
		names.append(hit.get_string(1))
	return names

# The GDScript packs the buffer and the GLSL reads it. If either side reorders a
# field without the other, every tunable silently drives the wrong thing. This
# checks the two artifacts against each other rather than against themselves.
func test_push_constant_matches_the_glsl_struct_field_for_field() -> void:
	var fx := _effect()
	if fx == null:
		fail("%s does not exist" % COMPOSITOR_PATH)
		return

	var fields := _glsl_push_constant_fields()
	check(fields.size() > 0, "could not read a push_constant block from %s" % GLSL_PATH)
	if fields.is_empty():
		return

	fx.line_thickness_px = 2.5
	fx.line_color = Color(0.125, 0.25, 0.375)
	fx.depth_edge_threshold = 0.11
	fx.normal_edge_angle_deg = 22.0
	fx.fade_start_m = 33.0
	fx.fade_end_m = 44.0
	fx.wobble_strength = 0.55
	fx.wobble_scale = 6.0
	fx.wobble_speed = 7.0
	fx.grain_strength = 0.08
	fx.grain_luma_falloff = 0.07
	fx.ink_sky_silhouette = true

	# Reference height, so no resolution scaling is in play here.
	var buffer: PackedByteArray = fx.build_push_constant(Vector2i(1920, 1080), 0.625, 9.5)

	var expected := {
		"raster_width": 1920.0,
		"raster_height": 1080.0,
		"line_thickness_px": 2.5,
		"depth_edge_threshold": 0.11,
		"normal_edge_angle_deg": 22.0,
		"fade_start_m": 33.0,
		"fade_end_m": 44.0,
		"wobble_strength": 0.55,
		"wobble_scale": 6.0,
		"wobble_speed": 7.0,
		"grain_strength": 0.08,
		"grain_seed": 0.625,
		"line_color_r": 0.125,
		"line_color_g": 0.25,
		"line_color_b": 0.375,
		"time": 9.5,
		# Supplied by the render callback from the view projection; the packer
		# falls back to these when called without them.
		"z_near": 0.05,
		"z_far": 1000.0,
		"grain_luma_falloff": 0.07,
		"ink_sky_silhouette": 1.0,
	}

	eq(buffer.size(), fields.size() * 4, "buffer size must cover exactly the declared fields")
	check(buffer.size() % 16 == 0, "push constants must be a multiple of 16 bytes (got %d)" % buffer.size())

	for i in fields.size():
		var name := fields[i]
		if name.begins_with("pad"):
			continue  # explicit 16-byte alignment padding, carries no value
		if not expected.has(name):
			fail("GLSL declares push-constant field '%s' that the test does not know about" % name)
			continue
		approx(buffer.decode_float(i * 4), expected[name], 0.0001,
			"field '%s' (float slot %d) does not match what the GLSL expects there" % [name, i])

func _float_field(fx: Object, size: Vector2i, field: String) -> float:
	var fields := _glsl_push_constant_fields()
	var index := Array(fields).find(field)
	if index < 0:
		return NAN
	var buffer: PackedByteArray = fx.build_push_constant(size, 0.0, 0.0)
	return buffer.decode_float(index * 4)

# Spec: line weight is fixed in screen space but resolution-scaled, so a 1.5 px
# pen authored at 1080 still reads as the same pen at 4K rather than shrinking
# to a hairline.
func test_line_thickness_scales_with_viewport_height() -> void:
	var fx := _effect()
	if fx == null:
		fail("%s does not exist" % COMPOSITOR_PATH)
		return

	fx.line_thickness_px = 1.5

	approx(_float_field(fx, Vector2i(1920, 1080), "line_thickness_px"), 1.5, 0.0001,
		"at the authoring height the pen is exactly as configured")
	approx(_float_field(fx, Vector2i(3840, 2160), "line_thickness_px"), 3.0, 0.0001,
		"at 4K (double the height) the pen must double to hold its apparent weight")
	approx(_float_field(fx, Vector2i(1280, 720), "line_thickness_px"), 1.0, 0.0001,
		"at 720p it scales down by the same ratio")
