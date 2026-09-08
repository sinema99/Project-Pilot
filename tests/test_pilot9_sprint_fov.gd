extends "res://tests/test_case.gd"

# Covers the sprint FOV: the camera opens 10 degrees at a sprint and eases shut for
# everything else.
#
# Two of these are the whole feature and the rest are guards. The first is that the base FOV
# is read off the camera rather than declared, because the failure there is silent - a
# constant in pilot9.gd would overwrite the Camera3D's own value on the first frame and give
# no sign it had. The second is the airborne case: `is_sprinting` needs is_on_floor(), so a
# gate written the obvious way dips the view on every sprint jump and reads as a camera bug
# rather than a wrong condition.
#
# See docs/specs/pilot9-sprint-fov.md.

const PILOT_TSCN := "res://scenes/pilot9.tscn"

# Physics steps, at the project's 60 Hz.
const STEP := 1.0 / 60.0

var _instances: Array[Node] = []

# Unlike the slide tests, these need _ready() to have run: base_fov is captured there and
# camera_3d is an @onready. So the rig goes into the real tree and comes back out in end().
# Nothing steps physics here - every test drives _handle_camera_fov() by hand.
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

func _camera(root: Node) -> Camera3D:
	return root.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D

# The sprint gait, minus the floor: sprint toggled on and the stick pushed. This is exactly
# what _handle_camera_fov() reads. The `walk` term is unreachable headlessly - Input cannot
# be driven from a test - so it is the one term in the gate nothing here covers.
func _sprint(root: Node) -> void:
	root.set("sprint_toggled", true)
	root.set("input_dir", Vector2(0.0, -1.0))

# Steps the FOV loop `count` times and returns where it ended up.
func _settle(root: Node, count: int) -> float:
	for i in count:
		root.call("_handle_camera_fov", STEP)
	return _camera(root).fov

# One second of frames - about twice what an 8.0 lerp needs to be indistinguishable from
# arrived, and short enough that a loop which is not converging is still obviously wrong.
func _settled(root: Node) -> float:
	return _settle(root, 60)

# --- the base FOV ----------------------------------------------------------

# The base is a measurement of the rig, not a number in pilot9.gd. A constant here would be
# invisible until someone tuned the camera in the editor and found the tuning gone.
func test_the_base_fov_is_read_off_the_camera() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var cam := _camera(root)
	if cam == null:
		fail("no Camera3D at CameraPivot/SpringArm3D/Camera3D")
		return
	approx(float(root.get("base_fov")), cam.fov, 0.001,
		"base_fov is not the camera's own fov - it was declared rather than captured, and " +
		"tuning the Camera3D in the editor will be silently overwritten on the first frame")

# Standing still, nothing happens: no boost, and no drift away from the base either.
func test_standing_still_holds_the_base_fov() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var base := float(root.get("base_fov"))
	approx(_settled(root), base, 0.01,
		"the FOV moved off %.1f with no input at all" % base)

# --- the sprint ------------------------------------------------------------

func test_sprinting_opens_the_view_by_the_boost() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var base := float(root.get("base_fov"))
	var boost := float(root.get("sprint_fov_boost"))
	check(boost > 0.0, "sprint_fov_boost ships at %.1f - the feature is off by default" % boost)
	_sprint(root)
	approx(_settled(root), base + boost, 0.01,
		"a sprint did not reach %.1f + %.1f" % [base, boost])

# The ask was +10, so the shipping value is asserted rather than left to whatever the
# inspector last held.
func test_the_shipping_boost_is_ten_degrees() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	approx(float(root.get("sprint_fov_boost")), 10.0, 0.001,
		"sprint_fov_boost is not the +10 the mechanic asks for")

func test_letting_go_of_the_sprint_returns_to_the_base() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var base := float(root.get("base_fov"))
	_sprint(root)
	_settled(root)
	root.set("sprint_toggled", false)
	approx(_settled(root), base, 0.01,
		"the view stayed open after the sprint ended - it is meant to come back to %.1f" % base)

# The dial reaches the target rather than a constant somewhere behind it.
func test_the_boost_is_whatever_the_export_says() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var base := float(root.get("base_fov"))
	root.set("sprint_fov_boost", 25.0)
	_sprint(root)
	approx(_settled(root), base + 25.0, 0.01,
		"sprint_fov_boost does not reach the camera - the boost is hard-coded somewhere")

# The off switch. Zero degrees has to be the camera the project had before this existed,
# because it is the fallback if the effect turns out to be unwanted.
func test_a_zero_boost_is_the_feature_switched_off() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var base := float(root.get("base_fov"))
	root.set("sprint_fov_boost", 0.0)
	_sprint(root)
	approx(_settled(root), base, 0.001,
		"a zero boost still moved the FOV")

# --- the airborne seam -----------------------------------------------------

# The reason _handle_camera_fov() does not read is_sprinting. That flag needs is_on_floor(),
# and the rig instantiated here is not standing on anything - so if the gate were written
# off it, this test would find the view shut during exactly the state it is meant to be open
# in. A sprint jump is the commonest way into this state and the one where a dip shows most.
func test_a_sprinting_jump_keeps_the_view_open() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var base := float(root.get("base_fov"))
	var boost := float(root.get("sprint_fov_boost"))
	_sprint(root)
	root.set("is_jumping", true)
	check(not bool(root.get("is_sprinting")),
		"is_sprinting is already true off the floor - this test is no longer testing the seam")
	approx(_settled(root), base + boost, 0.01,
		"the view shut mid-jump. The gate is reading is_sprinting, which needs is_on_floor(), " +
		"so every sprint jump dips the FOV and pops it back on landing")

# --- the states that drop it -----------------------------------------------

# Each of these owns the body in a way a sprint does not, and each has to bring the view
# back on its own. Run as a table because the failure is always the same shape: one term
# missing from the gate, which nothing else notices.
func test_every_other_state_brings_the_view_back() -> void:
	var cases := {
		"is_crouching": "a crouch",
		"is_sliding": "a slide",
		"is_climbing": "a mantle",
		"frozen": "a freeze",
	}
	for flag in cases:
		var root := _scene()
		if root == null:
			fail("scenes/pilot9.tscn did not load")
			return
		var base := float(root.get("base_fov"))
		_sprint(root)
		_settled(root)
		root.set(flag, true)
		approx(_settled(root), base, 0.01,
			"%s left the sprint FOV open - `not %s` is missing from the gate" %
				[cases[flag], flag])

# Sprint toggled on with the stick centred is not a sprint - _apply_movement() says so, and
# so does this. Standing still with the toggle latched from the last run is a common state.
func test_a_centred_stick_is_not_a_sprint() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var base := float(root.get("base_fov"))
	_sprint(root)
	_settled(root)
	root.set("input_dir", Vector2.ZERO)
	approx(_settled(root), base, 0.01,
		"the view stayed open with the stick centred and only the sprint toggle latched")

# --- the ease --------------------------------------------------------------

# A snap would pass every convergence test above. This is the one that says it travels.
func test_the_view_eases_open_rather_than_snapping() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var base := float(root.get("base_fov"))
	var boost := float(root.get("sprint_fov_boost"))
	_sprint(root)
	var after_one := _settle(root, 1)
	check(after_one > base + 0.01,
		"one frame of sprint moved the FOV by %.4f degrees - the ease is not running" %
			(after_one - base))
	check(after_one < base + boost - 1.0,
		"one frame of sprint arrived at %.2f of %.2f - that is a snap, not an ease" %
			[after_one, base + boost])

# The weight is a rate times a frame, so a hitch hands lerpf a number above 1 and the FOV
# shoots past the target. Clamped, a long frame simply arrives.
func test_a_long_frame_arrives_instead_of_overshooting() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var base := float(root.get("base_fov"))
	var boost := float(root.get("sprint_fov_boost"))
	_sprint(root)
	# A full second in one step: eight times the weight lerpf is allowed to take.
	root.call("_handle_camera_fov", 1.0)
	approx(_camera(root).fov, base + boost, 0.001,
		"a 1 s frame overshot to %.2f instead of landing on %.2f - the lerp weight is unclamped" %
			[_camera(root).fov, base + boost])

# --- where it runs ---------------------------------------------------------

# The placement is load-bearing, not incidental. A mantle and a freeze both return early
# from _physics_process(), and those are the frames on which the view most needs to be
# closing - so the call has to sit above both of them. Moved down, the tests above all stay
# green and the FOV sticks open for the length of every mantle.
func test_the_fov_runs_above_every_early_return() -> void:
	var src := FileAccess.open("res://scripts/pilot9.gd", FileAccess.READ)
	if src == null:
		fail("could not read scripts/pilot9.gd")
		return
	var text := src.get_as_text()
	var at := text.find("func _physics_process")
	check(at != -1, "pilot9.gd has no _physics_process")
	if at == -1:
		return
	var body := text.substr(at)
	var call_at := body.find("_handle_camera_fov(")
	check(call_at != -1, "_physics_process does not call _handle_camera_fov at all")
	if call_at == -1:
		return
	for guard in ["if is_climbing:", "if frozen:"]:
		var guard_at := body.find(guard)
		check(guard_at != -1, "_physics_process no longer has a `%s` early return" % guard)
		check(guard_at == -1 or call_at < guard_at,
			"_handle_camera_fov is called below `%s`, so the FOV freezes wherever the " % guard +
			"sprint left it for the whole of that state instead of easing back")
