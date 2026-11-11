extends "res://tests/test_case.gd"

# Covers the GTA-style camera pass: the framing numbers, the asymmetric pitch limits, the look
# stick's curve and ramp, and the sprint pull-back / crouch drop. See docs/specs/pilot9-gta-camera.md.
# None of this can judge the feel; the player does that.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const PILOT := preload("res://scripts/pilot9.gd")
const STEP := 1.0 / 60.0

var _instances: Array[Node] = []

func _scene() -> Node:
	var ps := load(PILOT_TSCN) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		n.free()
		return null
	tree.root.add_child(n)
	_instances.append(n)
	return n

func end() -> void:
	for n in _instances:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_instances.clear()
	super()

# The framing numbers moved to the DayZ camera (test_pilot9_camera_dayz.gd); the limits stay.
func test_pitch_limit_defaults() -> void:
	var p := _scene()
	if p == null:
		fail("could not instance pilot9")
		return
	approx(p.tilt_up_limit, deg_to_rad(45), 0.0001, "look-up limit is 45 from the horizon")
	approx(p.tilt_down_limit, deg_to_rad(60), 0.0001, "look-down limit is 60 from the horizon")

func test_pitch_limits_are_asymmetric() -> void:
	approx(PILOT._clamp_pitch(2.0, deg_to_rad(45), deg_to_rad(60)), deg_to_rad(45), 0.0001, "look-up caps at 45")
	approx(PILOT._clamp_pitch(-2.0, deg_to_rad(45), deg_to_rad(60)), -deg_to_rad(60), 0.0001, "look-down caps at 60")
	approx(PILOT._clamp_pitch(0.2, deg_to_rad(45), deg_to_rad(60)), 0.2, 0.0001, "inside the limits is untouched")

func test_stick_curve_keeps_direction_and_ends() -> void:
	var half := PILOT._look_stick_shape(Vector2(0.5, 0.0), 1.6)
	check(half.x > 0.0 and half.x < 0.5, "a half push is slower than linear")
	approx(half.y, 0.0, 0.0001, "direction is kept")
	approx(PILOT._look_stick_shape(Vector2(1.0, 0.0), 1.6).x, 1.0, 0.0001, "a full push stays full")
	eq(PILOT._look_stick_shape(Vector2.ZERO, 1.6), Vector2.ZERO, "zero stays zero")
	approx(PILOT._look_stick_shape(Vector2(0.5, 0.0), 1.0).x, 0.5, 0.0001, "exponent 1 is linear")

func test_ramp_builds_only_at_full_deflection() -> void:
	approx(PILOT._look_ramp_step(0.5, 0.5, STEP, 0.3), 0.0, 0.0001, "a gentle push drops the ramp")
	var t := 0.0
	for i in 18:
		t = PILOT._look_ramp_step(t, 1.0, STEP, 0.3)
	approx(t, 1.0, 0.0001, "0.3 s of full push is a full ramp")
	approx(PILOT._look_ramp_step(0.0, 1.0, STEP, 0.0), 1.0, 0.0001, "ramp time 0 turns it off")

func test_ramp_factor_starts_slow_ends_full_and_spares_gentle_pushes() -> void:
	approx(PILOT._look_ramp_factor(0.0, 1.0, 0.5), 0.5, 0.0001, "a fresh full push starts at the start fraction")
	approx(PILOT._look_ramp_factor(1.0, 1.0, 0.5), 1.0, 0.0001, "a ramped full push is full speed")
	approx(PILOT._look_ramp_factor(0.0, 0.3, 0.5), 1.0, 0.0001, "a gentle push is never slowed by the ramp")

func test_sprint_pulls_the_camera_back_and_releases() -> void:
	var p := _scene()
	if p == null:
		fail("could not instance pilot9")
		return
	# Zeroed by the DayZ camera; the code is kept, so drive it with the old GTA number.
	p.camera_sprint_pullback = 0.3
	p.is_sprinting = true
	for i in 60:
		p._handle_camera_state(STEP)
	approx(p._camera_state_back, p.camera_sprint_pullback, 0.01, "sprint settles at the pull-back")
	p.is_sprinting = false
	p.is_dashing = true
	for i in 60:
		p._handle_camera_state(STEP)
	approx(p._camera_state_back, p.camera_sprint_pullback, 0.01, "a dash holds it too")
	p.is_dashing = false
	for i in 60:
		p._handle_camera_state(STEP)
	approx(p._camera_state_back, 0.0, 0.01, "it eases back out")

func test_state_shift_starts_from_rest_and_never_overshoots() -> void:
	# The slide-exit snap: the old exponential ease covered 22% of the way on its first frame.
	var s := PILOT._camera_state_spring(0.0, 0.0, 0.4, STEP, 0.3)
	check(s.x < 0.4 * 0.06, "the first frame barely moves")
	var peak := 0.0
	for i in 60:
		s = PILOT._camera_state_spring(s.x, s.y, 0.4, STEP, 0.3)
		peak = maxf(peak, s.x)
	approx(s.x, 0.4, 0.001, "it settles on the target")
	check(peak <= 0.4 + 0.0001, "no overshoot")

func test_crouch_and_slide_drop_the_pivot_and_first_person_is_untouched() -> void:
	var p := _scene()
	if p == null:
		fail("could not instance pilot9")
		return
	p.camera_crouch_drop = 0.4 # zeroed by the DayZ camera; the code is kept
	p._camera_mode_length = p.camera_distance
	var standing: float = p._camera_zoom_lift()
	p.is_crouching = true
	for i in 60:
		p._handle_camera_state(STEP)
	approx(standing - p._camera_zoom_lift(), p.camera_crouch_drop, 0.01, "crouch lowers the pivot")
	p.is_crouching = false
	p.is_sliding = true
	for i in 60:
		p._handle_camera_state(STEP)
	approx(standing - p._camera_zoom_lift(), p.camera_crouch_drop, 0.01, "slide lowers it too")
	p._camera_mode_length = 0.0
	approx(p._camera_zoom_lift(), 0.0, 0.0001, "first person gets no raise and no drop")
