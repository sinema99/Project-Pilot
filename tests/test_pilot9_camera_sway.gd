extends "res://tests/test_case.gd"

# Covers pilot9's camera sway and landing dip - the curves, the spring, and the switches that
# fail silently. See docs/specs/pilot9-camera-sway.md.
#
# None of this can judge the feel; the player does that. What it fences is the stuff that looks
# fine and is wrong: a spring that rebounds, a dip that grows at a step-off, a sway that does
# not shrink with the zoom, a bounce pad that dips, an OFF switch that leaves the camera parked
# a centimetre off. is_on_floor() cannot be made true without a physics world, so the touchdown
# itself is exercised through the pure functions and the one-frame hand-off either side of it.

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
	Settings.set_value(&"camera_motion", "on")
	super()

func _camera(root: Node) -> Camera3D:
	return root.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D

# --- the sway's weight -----------------------------------------------------

func test_sway_weight_hits_its_three_anchors() -> void:
	approx(PILOT._camera_sway_weight(2.5, 2.5, 5.0, 7.5, 0.4), 0.0, 1e-6,
		"walking pace should get no sway at all")
	approx(PILOT._camera_sway_weight(5.0, 2.5, 5.0, 7.5, 0.4), 0.4, 1e-6,
		"a run should get the run fraction of the sprint's sway")
	approx(PILOT._camera_sway_weight(7.5, 2.5, 5.0, 7.5, 0.4), 1.0, 1e-6,
		"a sprint should get the full sway")
	approx(PILOT._camera_sway_weight(20.0, 2.5, 5.0, 7.5, 0.4), 1.0, 1e-6,
		"faster than a sprint should clamp at full, not grow")
	approx(PILOT._camera_sway_weight(0.0, 2.5, 5.0, 7.5, 0.4), 0.0, 1e-6,
		"standing still should get no sway")

func test_sway_weight_never_steps() -> void:
	var prev := 0.0
	var v := 0.0
	while v <= 9.0:
		var w: float = PILOT._camera_sway_weight(v, 2.5, 5.0, 7.5, 0.4)
		check(w >= prev - 1e-6, "the weight fell from %.3f to %.3f at %.2f m/s" % [prev, w, v])
		check(w - prev < 0.05, "the weight jumped %.3f at %.2f m/s - a switch, not a ramp" %
			[w - prev, v])
		prev = w
		v += 0.1

func test_stride_eases_from_run_clip_to_sprint_clip() -> void:
	approx(PILOT._sway_stride(5.0, 5.0, 7.5), PILOT.SWAY_RUN_STRIDE, 1e-6,
		"a run should keep the run clip's stride")
	approx(PILOT._sway_stride(7.5, 5.0, 7.5), PILOT.SWAY_SPRINT_STRIDE, 1e-6,
		"a sprint should keep the sprint clip's stride")
	approx(PILOT._sway_stride(1.0, 5.0, 7.5), PILOT.SWAY_RUN_STRIDE, 1e-6,
		"below a run the stride should hold at the run clip's, not stretch")

# --- zoom --------------------------------------------------------------------

func test_motion_scales_with_the_arm() -> void:
	approx(PILOT._camera_motion_scale(3.5, 3.5), 1.0, 1e-6, "the authored arm is the reference")
	approx(PILOT._camera_motion_scale(7.0, 3.5), 2.0, 1e-6,
		"twice the arm should be twice the metres, so the same size on screen")
	approx(PILOT._camera_motion_scale(0.0, 3.5), 0.0, 1e-6, "first person should get none")
	approx(PILOT._camera_motion_scale(-1.0, 3.5), 0.0, 1e-6, "a negative length is not a scale")

# --- the dip's size ------------------------------------------------------------

func _depth(v: float) -> float:
	return PILOT._landing_dip_depth(v, 5.0, 10.0, 0.04, 28.0, 0.08)

func test_dip_depth_hits_its_three_anchors() -> void:
	approx(_depth(3.0), 0.0, 1e-6, "a step-off should not dip")
	approx(_depth(5.0), 0.0, 1e-6, "the floor speed itself should not dip")
	approx(_depth(10.0), 0.04, 1e-6, "a full jump should dip the full-jump depth")
	approx(_depth(28.0), 0.08, 1e-6, "terminal speed should dip the cap")
	approx(_depth(60.0), 0.08, 1e-6, "past terminal should clamp at the cap")

func test_dip_depth_grows_with_the_fall() -> void:
	var prev := 0.0
	var v := 0.0
	while v <= 30.0:
		var d := _depth(v)
		check(d >= prev - 1e-9, "the dip shrank from %.4f to %.4f at %.1f m/s" % [prev, d, v])
		prev = d
		v += 0.25

func test_a_full_jump_lands_at_jump_velocity() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	# The anchor the middle of the curve is pinned to. With no fall multiplier the fall mirrors
	# the rise, so this is jump_velocity - 10 m/s today.
	var jv := float(root.get("jump_velocity"))
	var mult := float(root.get("jump_fall_multiplier"))
	approx(jv * sqrt(mult), 10.0, 0.01,
		"a full jump no longer lands at 10 m/s - check landing_dip_full_jump still means what " +
		"the spec says it does")

# --- the spring ------------------------------------------------------------------

# Counted in whole steps, not accumulated time - a float `t < seconds` loop takes one step more
# or fewer depending on rounding, and two rates would stop comparing the same instant.
func _run_spring(kick_depth: float, omega: float, seconds: float, dt: float) -> Dictionary:
	var x := 0.0
	var v := -float(PILOT._dip_kick(kick_depth, omega))
	var lowest := 0.0
	var lowest_at := 0.0
	var highest := 0.0
	for i in roundi(seconds / dt):
		var t := (i + 1) * dt
		var s: Vector2 = PILOT._dip_spring_step(x, v, omega, dt)
		x = s.x
		v = s.y
		if x < lowest:
			lowest = x
			lowest_at = t
		highest = maxf(highest, x)
	return {"lowest": lowest, "lowest_at": lowest_at, "highest": highest, "end": x}

func test_the_dip_bottoms_at_its_depth_and_time() -> void:
	var omega: float = PILOT._dip_omega(0.08)
	var r := _run_spring(0.04, omega, 1.0, 0.001)
	approx(r["lowest"], -0.04, 0.0005, "the dip should bottom at exactly its depth")
	approx(r["lowest_at"], 0.08, 0.002, "the dip should bottom at landing_dip_time")

func test_the_dip_never_rebounds_above_rest() -> void:
	var omega: float = PILOT._dip_omega(0.08)
	var r := _run_spring(0.08, omega, 2.0, STEP)
	check(float(r["highest"]) <= 1e-9,
		"the spring overshot above rest by %.5f m - it is underdamped" % r["highest"])
	approx(r["end"], 0.0, 1e-5, "the dip should be gone within two seconds")

func test_the_spring_is_frame_rate_independent() -> void:
	var omega: float = PILOT._dip_omega(0.08)
	var a := _run_spring(0.04, omega, 0.2, 1.0 / 30.0)
	var b := _run_spring(0.04, omega, 0.2, 1.0 / 240.0)
	approx(a["end"], b["end"], 1e-6, "30 Hz and 240 Hz should agree on where the dip is at 0.2 s")

func test_a_second_landing_stacks_rather_than_restarts() -> void:
	var omega: float = PILOT._dip_omega(0.08)
	var x := 0.0
	var v := -float(PILOT._dip_kick(0.04, omega))
	for i in 6:
		var s: Vector2 = PILOT._dip_spring_step(x, v, omega, STEP)
		x = s.x
		v = s.y
	var before := x
	v -= PILOT._dip_kick(0.04, omega)
	var s2: Vector2 = PILOT._dip_spring_step(x, v, omega, 0.0)
	approx(s2.x, before, 1e-9, "a kick must not jump the offset - it adds velocity, not position")

# --- the hand-off either side of touchdown --------------------------------------

func test_a_bounce_pad_cancels_the_dip() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("_dip_pending_speed", 20.0)
	root.set("is_jumping", true)   # what BouncePad.bounce() sets after the touchdown frame
	root.call("_resolve_landing_dip")
	approx(float(root.get("_dip_velocity")), 0.0, 1e-9, "a bounce pad launch should not dip")
	approx(float(root.get("_dip_pending_speed")), 0.0, 1e-9, "the pending touchdown should be spent")

func test_a_plain_landing_kicks_the_spring_down() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("_dip_pending_speed", 20.0)
	root.set("is_jumping", false)
	root.call("_resolve_landing_dip")
	check(float(root.get("_dip_velocity")) < 0.0, "a hard landing should kick the camera down")

func test_a_mantle_is_never_a_touchdown() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("_dip_was_on_floor", false)
	root.set("_landing_speed_in", 15.0)
	root.set("is_climbing", true)
	root.call("_track_landing")
	approx(float(root.get("_dip_pending_speed")), 0.0, 1e-9,
		"finishing a mantle recorded a landing")
	root.set("is_climbing", false)

func test_airborne_the_sway_fades_and_is_gone() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	# Headless, is_on_floor() is false - he is in the air as far as the gate knows.
	root.set("_sway_weight", 1.0)
	root.set("velocity", Vector3(0.0, 0.0, -7.5))
	root.call("_handle_camera_motion", STEP)
	var w1 := float(root.get("_sway_weight"))
	check(w1 > 0.0 and w1 < 1.0, "the sway should fade out in the air, not cut (weight %.3f)" % w1)
	for i in 30:
		root.call("_handle_camera_motion", STEP)
	approx(float(root.get("_sway_weight")), 0.0, 1e-6, "0.5 s airborne should leave no sway")

# --- the switches -----------------------------------------------------------------

func test_camera_motion_off_is_completely_still() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var cam := _camera(root)
	root.set("_sway_weight", 1.0)
	root.set("_dip_offset", -0.05)
	root.set("_dip_velocity", -1.0)
	root.call("_handle_camera_motion", STEP)
	check(absf(cam.v_offset) > 0.0, "with motion on, a live dip should move the camera")
	Settings.set_value(&"camera_motion", "off")
	var roll := float(root.call("_handle_camera_motion", STEP))
	eq(cam.h_offset, 0.0, "CAMERA MOTION off left h_offset off centre")
	eq(cam.v_offset, 0.0, "CAMERA MOTION off left v_offset off centre")
	eq(roll, 0.0, "CAMERA MOTION off still returned a sway roll")
	root.set("_dip_pending_speed", 20.0)
	root.set("is_jumping", false)
	root.call("_resolve_landing_dip")
	eq(float(root.get("_dip_velocity")), 0.0, "CAMERA MOTION off still dipped on a landing")

func test_camera_motion_defaults_on() -> void:
	eq(Settings.defaults()[&"camera_motion"], "on", "CAMERA MOTION should ship on")

func test_leaving_exia_resets_the_motion() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("_sway_weight", 1.0)
	root.set("_dip_offset", -0.05)
	root.set("_dip_velocity", -1.0)
	root.set("_dip_pending_speed", 20.0)
	root.call("exit_vehicle", Vector3.ZERO, 0.0)
	eq(float(root.get("_sway_weight")), 0.0, "the sway survived leaving EXIA")
	eq(float(root.get("_dip_offset")), 0.0, "the dip survived leaving EXIA")
	eq(float(root.get("_dip_pending_speed")), 0.0, "a stale touchdown survived leaving EXIA")
	eq(_camera(root).v_offset, 0.0, "the camera was left off centre after leaving EXIA")
