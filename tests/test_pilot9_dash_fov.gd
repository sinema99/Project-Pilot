extends "res://tests/test_case.gd"

# Covers the dash FOV kick: fast in, slow out, on top of the sprint FOV.
# See docs/specs/pilot9-dash-fov.md.
#
# Most of this is the pure envelope, because that is where the feel lives and where a wrong
# curve looks fine in a convergence test: a lerp at a rate arrives at the same places a
# smoothstep does, and is exactly the jarring close the ask ruled out. The rig tests fence the
# seam this feature cut into the sprint FOV - the camera is written now, never read back.
#
# is_dashing is set by hand rather than through _start_dash(), which would hide him, start the
# streak and the lag, and none of which this reads. The rig is off the floor, so every rig dash
# here is an air dash; is_on_floor() cannot be made true headlessly, so the ground case is
# fenced by the source check at the bottom instead.

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

func _sprint(root: Node) -> void:
	root.set("sprint_toggled", true)
	root.set("input_dir", Vector2(0.0, -1.0))

func _settle(root: Node, count: int) -> float:
	for i in count:
		root.call("_handle_camera_fov", STEP)
	return _camera(root).fov

# --- the envelope ----------------------------------------------------------

func test_the_rise_goes_from_nothing_to_full_in_rise_time() -> void:
	approx(PILOT._dash_fov_kick_at(true, 0.0, 0.0, 0.12, 0.6), 0.0, 1e-6,
		"the kick is already open on the launch frame - that is a snap")
	approx(PILOT._dash_fov_kick_at(true, 0.06, 0.0, 0.12, 0.6), 0.5, 1e-6,
		"halfway through the rise is not halfway open")
	approx(PILOT._dash_fov_kick_at(true, 0.12, 0.0, 0.12, 0.6), 1.0, 1e-6,
		"the kick is not full at rise_time")
	approx(PILOT._dash_fov_kick_at(true, 0.25, 0.0, 0.12, 0.6), 1.0, 1e-6,
		"the kick does not hold at full for the rest of the dash")

func test_the_release_reaches_nothing_at_release_time() -> void:
	approx(PILOT._dash_fov_kick_at(false, 0.0, 1.0, 0.12, 0.6), 1.0, 1e-6,
		"the release dropped the kick on its first frame")
	approx(PILOT._dash_fov_kick_at(false, 0.6, 1.0, 0.12, 0.6), 0.0, 1e-6,
		"the kick is not gone at release_time")
	approx(PILOT._dash_fov_kick_at(false, 5.0, 1.0, 0.12, 0.6), 0.0, 1e-6,
		"the kick came back long after the release")

# The whole point of smoothstep over a lerp at a rate: gentle at BOTH ends of the close, the
# first of which is the frame he reappears. A rate-lerp loses ~13% on its first 60 Hz frame at
# a 0.6 s time constant; smoothstep loses a fraction of a percent.
func test_the_release_is_eased_at_both_ends() -> void:
	var first := 1.0 - PILOT._dash_fov_kick_at(false, STEP, 1.0, 0.12, 0.6)
	var middle := PILOT._dash_fov_kick_at(false, 0.3 - STEP * 0.5, 1.0, 0.12, 0.6) \
		- PILOT._dash_fov_kick_at(false, 0.3 + STEP * 0.5, 1.0, 0.12, 0.6)
	var last := PILOT._dash_fov_kick_at(false, 0.6 - STEP, 1.0, 0.12, 0.6)
	check(first < 0.01, "the release's first frame drops %.3f of the kick - the close is " % first +
		"steepest the frame he reappears, which is the jarring version")
	check(last < 0.01, "the release's last frame drops %.3f - it lands with a bump" % last)
	check(middle > first * 5.0, "the release is not faster in the middle than at its ends")

# A wall stops the dash before the rise finishes. The close has to start from where the rise
# got to - not from full, which would pop the lens open on the way down.
func test_a_blocked_dash_releases_from_where_it_got_to() -> void:
	var partial := PILOT._dash_fov_kick_at(true, 0.04, 0.0, 0.12, 0.6)
	check(partial > 0.0 and partial < 1.0, "0.04 s into the rise should be partly open")
	approx(PILOT._dash_fov_kick_at(false, 0.0, partial, 0.12, 0.6), partial, 1e-6,
		"the release did not start from the blocked dash's partial kick")
	for i in 40:
		var k := PILOT._dash_fov_kick_at(false, i * STEP, partial, 0.12, 0.6)
		check(k <= partial + 1e-6, "the release rose above where the dash left it (%.3f > %.3f)" %
			[k, partial])

func test_a_redash_mid_release_rises_from_the_current_kick() -> void:
	var mid := PILOT._dash_fov_kick_at(false, 0.3, 1.0, 0.12, 0.6)
	approx(PILOT._dash_fov_kick_at(true, 0.0, mid, 0.12, 0.6), mid, 1e-6,
		"a re-dash dropped the lens back to base before opening it again")
	approx(PILOT._dash_fov_kick_at(true, 0.12, mid, 0.12, 0.6), 1.0, 1e-6,
		"a re-dash does not reach full kick")

func test_zero_times_are_snaps_not_divisions_by_zero() -> void:
	approx(PILOT._dash_fov_kick_at(true, 0.0, 0.0, 0.0, 0.6), 1.0, 1e-6, "zero rise")
	approx(PILOT._dash_fov_kick_at(false, 0.0, 1.0, 0.12, 0.0), 0.0, 1e-6, "zero release")

# --- the ceiling -----------------------------------------------------------

func test_the_ceiling_limits_the_kick_only() -> void:
	approx(PILOT._dash_fov_lens(85.0, 10.0, 115.0), 95.0, 1e-6,
		"the ceiling engaged at the default FOV")
	approx(PILOT._dash_fov_lens(110.0, 10.0, 115.0), 115.0, 1e-6,
		"the kick pushed past the ceiling")
	approx(PILOT._dash_fov_lens(120.0, 10.0, 115.0), 120.0, 1e-6,
		"the ceiling pulled a sprint FOV already above it down - it must only limit the kick")

# --- on the rig ------------------------------------------------------------

func test_the_shipping_numbers() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	approx(float(root.get("dash_fov_boost")), 10.0, 1e-6, "dash_fov_boost")
	approx(float(root.get("dash_fov_rise_time")), 0.12, 1e-6, "dash_fov_rise_time")
	approx(float(root.get("dash_fov_release_time")), 0.6, 1e-6, "dash_fov_release_time")
	approx(float(root.get("dash_fov_ceiling")), 115.0, 1e-6, "dash_fov_ceiling")

# The seam: the kick stacks on the sprint and the close lands back on the sprint, not on the
# base. With the sprint lerp still reading camera_3d.fov back, the dash would never reach
# base + sprint + dash - the lerp would be dragging it down every frame.
func test_a_dash_from_a_sprint_stacks_and_returns_to_the_sprint() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var base := float(root.get("base_fov"))
	var sprint := float(root.get("sprint_fov_boost"))
	var dash := float(root.get("dash_fov_boost"))
	_sprint(root)
	approx(_settle(root, 90), base + sprint, 0.01, "the sprint did not settle before the dash")
	root.set("is_dashing", true)
	approx(_settle(root, 12), base + sprint + dash, 0.01,
		"a dash from a sprint did not reach base + sprint + dash - the sprint lerp is fighting " +
		"the kick")
	root.set("is_dashing", false)
	var one := _settle(root, 1)
	check(one > base + sprint + dash - 0.2,
		"the lens dropped %.2f degrees the frame he reappeared" % (base + sprint + dash - one))
	approx(_settle(root, 60), base + sprint, 0.01,
		"the close did not land back on the sprint FOV")

func test_the_kick_opens_quickly_but_not_instantly() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var base := float(root.get("base_fov"))
	var dash := float(root.get("dash_fov_boost"))
	_settle(root, 60)
	root.set("is_dashing", true)
	var one := _settle(root, 1)
	check(one > base and one < base + dash * 0.5,
		"one frame of dash put the lens at %.2f - not an ease" % one)
	# 0.25 s is the whole dash; the kick must be open well inside it.
	approx(_settle(root, 8), base + dash, 0.01, "the kick is not full within the dash")

func test_a_zero_boost_is_the_kick_switched_off() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var base := float(root.get("base_fov"))
	root.set("dash_fov_boost", 0.0)
	root.set("is_dashing", true)
	approx(_settle(root, 30), base, 0.001, "a zero dash_fov_boost still moved the lens")

func test_camera_motion_off_holds_the_kick_at_zero() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var base := float(root.get("base_fov"))
	Settings.set_value(&"camera_motion", "off")
	root.set("is_dashing", true)
	approx(_settle(root, 30), base, 0.001, "CAMERA MOTION off still kicked the lens on a dash")
	# Back on mid-dash: rises from nothing, never pops.
	Settings.set_value(&"camera_motion", "on")
	var one := _settle(root, 1)
	check(one < base + 1.0, "switching CAMERA MOTION on mid-dash popped the lens to %.2f" % one)

# Ground and air are the same kick because nothing in it asks where he is. The rig can only be
# airborne headlessly, so the ground half is this: the kick's step must not read the floor.
func test_the_kick_does_not_read_the_floor() -> void:
	var src := FileAccess.open("res://scripts/pilot9.gd", FileAccess.READ)
	if src == null:
		fail("could not read scripts/pilot9.gd")
		return
	var text := src.get_as_text()
	var at := text.find("func _step_dash_fov_kick")
	check(at != -1, "pilot9.gd has no _step_dash_fov_kick")
	if at == -1:
		return
	var end_at := text.find("\nfunc ", at + 1)
	var end2 := text.find("\nstatic func ", at + 1)
	if end2 != -1 and (end_at == -1 or end2 < end_at):
		end_at = end2
	var body := text.substr(at, end_at - at)
	check(body.find("is_on_floor") == -1,
		"the dash kick reads is_on_floor() - ground and air dashes are meant to kick alike")
