extends "res://tests/test_case.gd"

# Covers the camera framing curves (and, since 2026-11-12, that the wheel no longer zooms).
# See docs/specs/pilot9-camera-zoom.md and docs/specs/mech-stash.md.
#
# The feature is the clamp and the direction; the guard is that the wheel never touches
# camera_distance, because that is what the body-hide check divides by.

const PILOT_TSCN := "res://scenes/pilot9.tscn"

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

func _wheel(root: Node, button: MouseButton) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.factor = 1.0
	root.call("_unhandled_input", e)

# The wheel zoom was removed 2026-11-12 (docs/specs/mech-stash.md, decision 9): the camera is
# locked at camera_distance and the wheel belongs to the interaction panel's option list.
func test_wheel_no_longer_zooms() -> void:
	var root := _scene()
	check(root != null, "pilot9.tscn did not instantiate")
	if root == null:
		return
	var start := float(root.get("target_camera_distance"))
	approx(start, float(root.get("camera_distance")), 0.0001, "the arm does not start at camera_distance")
	approx(float(root.get("camera_distance")), 2.0, 0.0001, "the locked arm is 2 m")
	for i in 5:
		_wheel(root, MOUSE_BUTTON_WHEEL_UP)
	approx(float(root.get("target_camera_distance")), start, 0.0001, "wheel up still zooms")
	for i in 5:
		_wheel(root, MOUSE_BUTTON_WHEEL_DOWN)
	approx(float(root.get("target_camera_distance")), start, 0.0001, "wheel down still zooms")
	check(not root.has_method("_zoom_camera"), "the zoom function is still there")

# --- framing ----------------------------------------------------------------

const PILOT := preload("res://scripts/pilot9.gd")
const FOV := deg_to_rad(75.0)

# Where a point `drop` under the pivot lands, as a fraction of the screen from the top.
func _screen_height(length: float, tilt: float, drop: float) -> float:
	return 0.5 + 0.5 * tan(atan(drop / length) + tilt) / tan(FOV * 0.5)

func test_full_zoom_in_is_left_as_it_was() -> void:
	approx(PILOT._camera_zoom_tilt(1.5, 1.5, 8.0, 0.68, 0.5, FOV), 0.0, 0.0001,
		"full zoom-in was tilted - that is the framing the player liked")

func test_full_zoom_out_holds_him_at_the_target_height() -> void:
	var tilt: float = PILOT._camera_zoom_tilt(8.0, 1.5, 8.0, 0.68, 0.5, FOV)
	approx(_screen_height(8.0, tilt, 0.5), 0.68, 0.001,
		"full zoom-out does not put him at camera_zoom_out_screen_height")

# He must never bob up toward centre partway through the zoom.
func test_he_stays_in_the_lower_part_of_the_screen_all_the_way_out() -> void:
	var length := 1.5
	while length <= 8.0:
		var tilt: float = PILOT._camera_zoom_tilt(length, 1.5, 8.0, 0.68, 0.5, FOV)
		check(_screen_height(length, tilt, 0.5) >= 0.679,
			"at %.1f m he rose above the zoom-out framing" % length)
		length += 0.25

func test_no_tilt_in_first_person_or_squeezed_by_a_wall() -> void:
	approx(PILOT._camera_zoom_tilt(0.0, 1.5, 8.0, 0.68, 0.5, FOV), 0.0, 0.0001,
		"first person got a tilt")
	approx(PILOT._camera_zoom_tilt(0.6, 1.5, 8.0, 0.68, 0.5, FOV), 0.0, 0.0001,
		"a wall squeezing the arm in tilted the camera")

# Full zoom-in gets the in-lift (a drop), full zoom-out the out-lift, first person neither.
func test_the_lift_is_the_in_lift_zoomed_in_and_full_zoomed_out() -> void:
	var root := _scene()
	check(root != null, "pilot9.tscn did not instantiate")
	if root == null:
		return
	root.set("_camera_mode_length", 0.0)
	approx(float(root.call("_camera_zoom_lift")), 0.0, 0.0001, "first person was lifted")
	root.set("_camera_mode_length", float(root.get("camera_zoom_min")))
	approx(float(root.call("_camera_zoom_lift")), float(root.get("camera_zoom_in_lift")) + float(root.get("camera_pivot_raise")), 0.0001,
		"full zoom-in did not get the in-lift plus the raise")
	root.set("_camera_mode_length", float(root.get("camera_zoom_max")))
	approx(float(root.call("_camera_zoom_lift")), float(root.get("camera_zoom_out_lift")) + float(root.get("camera_pivot_raise")), 0.0001,
		"full zoom-out did not get the whole lift plus the raise")
