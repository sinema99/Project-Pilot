extends "res://tests/test_case.gd"

# Covers the DayZ camera: the framing defaults, the neutral pitch, the world-referenced pitch
# clamp, free-look (heading freeze + eased return), the horizontal trail, the zeroed effects and
# the Alt / Caps Lock / R3 bindings. See docs/specs/pilot9-dayz-camera.md. How it frames and
# feels is the player's call.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const PILOT := preload("res://scripts/pilot9.gd")
const STEP := 1.0 / 60.0
const KEY_ALT_PHYS := 4194328
const KEY_CAPS_PHYS := 4194329

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

func test_framing_defaults_match_the_screenshot() -> void:
	var p := _scene()
	if p == null:
		fail("could not instance pilot9")
		return
	approx(p.camera_distance, 1.7, 0.0001, "arm is 1.7 m")
	approx(p.camera_shoulder_offset, 0.25, 0.0001, "shoulder is 0.25 m")
	approx(p.camera_neutral_pitch, -15.0, 0.0001, "neutral pitch is -15 deg")
	check(p.face_travel_direction, "the control model is unchanged: he still turns to face travel")
	check(p.camera_zoom_min > 0.3 * p.camera_distance,
		"the zoom floor must stay clear of the body-hide line at the 1.7 m reference")
	# Eye at about his head height (capsule top ~1.96 m): pivot plus the neutral orbit's rise.
	# Was ~0.3 m over his head until 2026-11-11 (pivot_raise 0.6 -> 0.3, user: "a little high").
	p._camera_mode_length = p.camera_distance
	var pivot_y: float = PILOT.CAMERA_PIVOT_OFFSET.y + p._camera_zoom_lift()
	var eye_y: float = pivot_y + sin(deg_to_rad(-p.camera_neutral_pitch)) * p.camera_distance
	check(eye_y > 1.8 and eye_y < 2.1, "the eye sits at about his head height (%.2f m)" % eye_y)
	var eye_back: float = cos(deg_to_rad(p.camera_neutral_pitch)) * p.camera_distance
	approx(eye_back, 1.64, 0.05, "and ~1.6 m behind him")

func test_the_view_starts_at_the_neutral_pitch() -> void:
	var p := _scene()
	if p == null:
		fail("could not instance pilot9")
		return
	approx(p.camera_pivot.rotation.x, deg_to_rad(-15.0), 0.0001,
		"with the mouse untouched the orbit rests at the neutral pitch")

func test_pitch_limits_are_world_referenced_both_ways() -> void:
	var up := deg_to_rad(45.0)
	var down := deg_to_rad(60.0)
	var lens := deg_to_rad(5.0)
	approx(PILOT._clamp_world_pitch(2.0, lens, up, down) + lens, up, 0.0001,
		"the WORLD look-up caps at 45 whatever the lens tilt")
	approx(PILOT._clamp_world_pitch(-2.0, lens, up, down) + lens, -down, 0.0001,
		"the WORLD look-down caps at 60")
	approx(PILOT._clamp_world_pitch(-2.0, 0.0, up, down), -down, 0.0001, "no lens: plain limits")
	# From the -15 neutral that is 60 up and 45 down.
	var neutral := deg_to_rad(-15.0)
	approx(PILOT._clamp_world_pitch(2.0, 0.0, up, down) - neutral, deg_to_rad(60.0), 0.0001,
		"60 deg of look-up from neutral")
	approx(neutral - PILOT._clamp_world_pitch(-2.0, 0.0, up, down), deg_to_rad(45.0), 0.0001,
		"45 deg of look-down from neutral")

func test_free_look_freezes_the_move_basis() -> void:
	var p := _scene()
	if p == null:
		fail("could not instance pilot9")
		return
	p.camera_pivot.rotation.y = 0.0
	var before: Vector3 = p._travel_direction(Vector2(0, -1))
	p._step_free_look(true, STEP)
	p.camera_pivot.rotation.y = PI * 0.75
	var held: Vector3 = p._travel_direction(Vector2(0, -1))
	check(held.distance_to(before) < 0.0001, "orbiting during free-look does not steer the run")
	approx(p._move_yaw(), 0.0, 0.0001, "the move yaw is the frozen one")

func test_free_look_eases_back_then_hands_back() -> void:
	var p := _scene()
	if p == null:
		fail("could not instance pilot9")
		return
	p.camera_pivot.rotation.y = 0.3
	p.camera_pivot.rotation.x = -0.2
	p._step_free_look(true, STEP)
	p.camera_pivot.rotation.y = 2.5
	p.camera_pivot.rotation.x = 0.4
	p._step_free_look(false, STEP)
	check(p._free_look_returning(), "release starts the return")
	check(absf(angle_difference(p.camera_pivot.rotation.y, 0.3)) > 0.5, "the return is eased, not a snap")
	var t := STEP
	while t < p.free_look_return_time - 0.001:
		p._step_free_look(false, STEP)
		t += STEP
	p._step_free_look(false, STEP)
	check(not p._free_look_active(), "after the return time free-look is over")
	approx(angle_difference(p.camera_pivot.rotation.y, 0.3), 0.0, 0.0001, "back behind the frozen heading")
	approx(p.camera_pivot.rotation.x, -0.2, 0.0001, "and at the pitch it left")
	p.camera_pivot.rotation.y = 1.0
	approx(p._move_yaw(), 1.0, 0.0001, "movement is camera-relative again")

func test_free_look_return_weight_ends() -> void:
	approx(PILOT._free_look_return_weight(0.0, 0.25), 0.0, 0.0001, "starts at 0")
	approx(PILOT._free_look_return_weight(0.25, 0.25), 1.0, 0.0001, "lands at the return time")
	approx(PILOT._free_look_return_weight(1.0, 0.25), 1.0, 0.0001, "holds after")
	approx(PILOT._free_look_return_weight(0.1, 0.0), 1.0, 0.0001, "0 s return is a snap")

func test_the_trail_settles_in_its_time_with_y_welded() -> void:
	var p := _scene()
	if p == null:
		fail("could not instance pilot9")
		return
	p._trail_pivot(Vector3(0, 1.5, 0), STEP)
	var target := Vector3(1.0, 2.5, 0.0)
	var pos: Vector3 = p._trail_pivot(target, STEP)
	approx(pos.y, 2.5, 0.0001, "Y is welded on the first frame")
	check(pos.x > 0.0 and pos.x < 0.5, "X trails behind (%.3f on frame 1)" % pos.x)
	var peak := 0.0
	var t := STEP
	while t < p.camera_trail_time + 0.5 * STEP:
		pos = p._trail_pivot(target, STEP)
		peak = maxf(peak, pos.x)
		t += STEP
	check(pos.x > 0.95, "settled within ~%.2f s (x = %.3f)" % [p.camera_trail_time, pos.x])
	for i in 30:
		pos = p._trail_pivot(target, STEP)
		peak = maxf(peak, pos.x)
	check(peak <= 1.0001, "no overshoot")
	pos = p._trail_pivot(Vector3(50, 0, 0), STEP)
	approx(pos.x, 50.0, 0.0001, "a teleport snaps")

func test_the_camera_effects_ship_zeroed() -> void:
	var p := _scene()
	if p == null:
		fail("could not instance pilot9")
		return
	for prop in [&"sprint_fov_boost", &"dash_fov_boost", &"camera_sway_vertical",
			&"camera_sway_lateral", &"camera_sway_roll", &"landing_dip_full_jump",
			&"landing_dip_max", &"camera_sprint_pullback", &"camera_crouch_drop",
			&"wall_run_camera_roll", &"reflect_fov_scale"]:
		approx(float(p.get(prop)), 0.0, 0.0, "%s ships at 0" % prop)
	check(not p.camera_dash_lag, "the dash camera lag ships off")
	check(p.rail_camera_swing_rate > 0.0, "the rail swing is kept")

func test_bindings() -> void:
	check(InputMap.has_action(&"free_look"), "free_look exists")
	var alt := false
	var r3 := false
	for e in InputMap.action_get_events(&"free_look"):
		if e is InputEventKey and e.physical_keycode == KEY_ALT_PHYS:
			alt = true
		if e is InputEventJoypadButton and e.button_index == 8:
			r3 = true
	check(alt, "Alt is free-look")
	check(r3, "R3 is free-look")
	var caps := false
	for e in InputMap.action_get_events(&"walk"):
		if e is InputEventKey:
			check(e.physical_keycode != KEY_ALT_PHYS, "walk is off Alt")
			caps = caps or e.physical_keycode == KEY_CAPS_PHYS
	check(caps, "walk is on Caps Lock")
