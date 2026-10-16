extends "res://tests/test_case.gd"

# docs/specs/pilot9-camera-shoulder.md. The binding, the swap, the wall-run's override, the ease
# and the arm's local x. How the framing feels is judged in play.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const PILOT := preload("res://scripts/pilot9.gd")

var _pilot: Node = null

func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	_pilot._shoulder_side = 1.0
	_pilot._shoulder_pos = 0.0
	_pilot.is_wall_running = false
	return _pilot

func near(actual: float, expected: float, tol: float, msg: String) -> void:
	check(absf(actual - expected) <= tol, "%s (got %f, want %f)" % [msg, actual, expected])

func _has_event(action: StringName, pred: Callable) -> bool:
	for ev in InputMap.action_get_events(action):
		if pred.call(ev):
			return true
	return false

func test_swap_is_on_x_and_joypad_x() -> void:
	check(InputMap.has_action(&"shoulder_swap"), "project.godot has no `shoulder_swap` action")
	if not InputMap.has_action(&"shoulder_swap"):
		return
	check(_has_event(&"shoulder_swap", func(ev): return ev is InputEventKey and ev.physical_keycode == KEY_X),
		"`shoulder_swap` should be on X")
	check(_has_event(&"shoulder_swap", func(ev): return ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_X),
		"`shoulder_swap` should be on joypad X")

func test_defaults() -> void:
	var p := _scene()
	if p == null:
		fail("could not instance pilot9")
		return
	near(p.camera_shoulder_offset, 0.8, 0.0001, "offset is 0.8 m")
	near(p.camera_shoulder_swap_time, 0.25, 0.0001, "swap takes 0.25 s")
	eq(p._shoulder_target_side(), 1.0, "starts on the right shoulder")

func test_swap_flips_and_persists_across_a_wall_run() -> void:
	var p := _scene()
	if p == null:
		fail("could not instance pilot9")
		return
	p.swap_shoulder()
	eq(p._shoulder_target_side(), -1.0, "one swap: left")
	p.is_wall_running = true
	p._wall_run_right = false
	eq(p._shoulder_target_side(), 1.0, "wall on the left: camera to the right, whatever was chosen")
	p._wall_run_right = true
	eq(p._shoulder_target_side(), -1.0, "wall on the right: camera to the left")
	p.is_wall_running = false
	eq(p._shoulder_target_side(), -1.0, "after the run the chosen side is back")

func test_ease_reaches_the_target_in_the_swap_time() -> void:
	var pos := 0.6
	var t := 0.0
	while t < 0.25 - 0.0001:
		pos = PILOT._shoulder_ease(pos, -0.6, 1.0 / 60.0, 0.25)
		t += 1.0 / 60.0
	check(absf(pos - -0.6) < 0.6 * 2.0 * 0.05, "near the far side after 0.25 s, got %f" % pos)
	check(pos < 0.0, "and across the middle")
	eq(PILOT._shoulder_ease(0.6, -0.6, 1.0, 0.25), -0.6, "a huge step lands exactly, never past")

func test_arm_sits_at_the_offset_after_settling() -> void:
	var p := _scene()
	if p == null:
		fail("could not instance pilot9")
		return
	p._camera_mode_length = p.camera_distance
	for i in 60:
		p._handle_camera_shoulder(1.0 / 60.0)
	near(p.spring_arm.position.x, 0.8, 0.02, "right shoulder: arm 0.8 m to the camera's right")
	p.swap_shoulder()
	for i in 60:
		p._handle_camera_shoulder(1.0 / 60.0)
	near(p.spring_arm.position.x, -0.8, 0.02, "left shoulder: arm 0.8 m to the left")

func test_first_person_has_no_offset() -> void:
	var p := _scene()
	if p == null:
		fail("could not instance pilot9")
		return
	p._camera_mode_length = 0.0
	for i in 60:
		p._handle_camera_shoulder(1.0 / 60.0)
	near(p.spring_arm.position.x, 0.0, 0.0001, "a zero-length arm gets no offset")
