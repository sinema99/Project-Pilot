extends "res://tests/test_case.gd"

# EXIA's aim-forward control: the body chases the camera at a tank-heavy cap, W goes along the nose,
# A / D strafe, S backs up, Alt free-looks. See docs/specs/exia-aim-control.md.
#
# The pure half pins the rate, chase, key and clip tables and the aim-mode state rows. The live half
# drives an in-tree mech through drive_aim_step() with the inputs and floor passed in. How it FEELS
# is a play session.

const MechScene := preload("res://scenes/mech.tscn")
const Mech := preload("res://scripts/mech.gd")

const DT := 1.0 / 60.0

# --- the numbers ------------------------------------------------------------------------

func test_the_chase_caps_are_the_grilled_numbers() -> void:
	var stand := rad_to_deg(Mech.aim_turn_rate(0.0, 120.0, 100.0, 60.0))
	var run := rad_to_deg(Mech.aim_turn_rate(9.0, 120.0, 100.0, 60.0))
	var sprint := rad_to_deg(Mech.aim_turn_rate(14.0, 120.0, 100.0, 60.0))
	approx(stand, 120.0, 0.001, "120 deg/s standing")
	approx(run, 100.0, 0.001, "100 deg/s at the run")
	approx(sprint, 60.0, 0.001, "60 deg/s at a sprint")
	approx(rad_to_deg(Mech.aim_turn_rate(4.5, 120.0, 100.0, 60.0)), 110.0, 0.001, "blended below the run")
	approx(rad_to_deg(Mech.aim_turn_rate(11.5, 120.0, 100.0, 60.0)), 80.0, 0.001, "blended into the sprint")
	approx(rad_to_deg(Mech.aim_turn_rate(30.0, 120.0, 100.0, 60.0)), 60.0, 0.001, "no faster than the sprint's")
	var exia: Node3D = Mech.new()
	approx(exia.turn_rate_stand_deg, 120.0, 0.0, "export default: standing")
	approx(exia.turn_rate_run_deg, 100.0, 0.0, "export default: run")
	approx(exia.turn_rate_sprint_deg, 60.0, 0.0, "export default: sprint")
	check(exia.aim_lock, "aim lock is the default control")
	exia.free()

func test_the_chase_is_capped_and_wraps() -> void:
	approx(Mech.chase_yaw(0.0, 1.0, 0.1), 0.1, 0.0001, "a big gap: one capped step")
	approx(Mech.chase_yaw(0.0, 0.05, 0.1), 0.05, 0.0001, "a small gap: closed outright")
	approx(Mech.chase_yaw(0.0, -1.0, 0.1), -0.1, 0.0001, "the other way")
	approx(Mech.chase_yaw(3.1, -3.1, 0.05), wrapf(3.1 + 0.05, -PI, PI), 0.0001,
		"across the seam it goes the short way round")

func test_the_keys_map_to_a_gait_a_clip_and_a_speed() -> void:
	var rows := [
		[Vector2(0, -1), Mech.MoveGait.FORWARD, "MECH_run", 9.0],
		[Vector2(-1, -1), Mech.MoveGait.FORWARD_L, "MECH_run_diag_L", 9.0],
		[Vector2(1, -1), Mech.MoveGait.FORWARD_R, "MECH_run_diag_R", 9.0],
		[Vector2(-1, 0), Mech.MoveGait.LEFT, "MECH_strafe_L", 6.0],
		[Vector2(1, 0), Mech.MoveGait.RIGHT, "MECH_strafe_R", 6.0],
		[Vector2(0, 1), Mech.MoveGait.BACK, "MECH_back", 5.0],
		[Vector2(-1, 1), Mech.MoveGait.BACK_L, "MECH_back_diag_L", 5.5],
		[Vector2(1, 1), Mech.MoveGait.BACK_R, "MECH_back_diag_R", 5.5],
	]
	for row in rows:
		var g: int = Mech.move_gait_for(row[0])
		eq(g, row[1], "keys %s -> gait" % row[0])
		eq(Mech.gait_clip(g, 5.0), row[2], "keys %s -> clip" % row[0])
		approx(Mech.gait_speed(g), row[3], 0.0001, "keys %s -> speed" % row[0])
	eq(Mech.gait_clip(Mech.MoveGait.FORWARD, 13.0), "MECH_sprint", "W at a sprint")
	eq(Mech.gait_clip(Mech.MoveGait.FORWARD_L, 13.0), "MECH_sprint_diag_L", "W+A at a sprint")
	eq(Mech.gait_clip(Mech.MoveGait.LEFT, 13.0), "MECH_strafe_L", "a strafe never sprints")

func test_the_move_is_off_the_nose() -> void:
	var a := Mech.move_local(Vector2(-1, 0))
	check(a.is_equal_approx(Vector3(1, 0, 0)), "A is the mech's left (+X)")
	check(Mech.move_local(Vector2(0, -1)).is_equal_approx(Vector3(0, 0, 1)), "W is the nose (+Z)")
	check(Mech.move_local(Vector2(0, 1)).is_equal_approx(Vector3(0, 0, -1)), "S is backward")
	approx(Mech.move_local(Vector2(-1, -1)).length(), 1.0, 0.0001, "a diagonal is unit length")

func test_the_side_and_back_clips_play_at_the_bodys_speed() -> void:
	approx(6.0 * Mech.gait_rate("MECH_strafe_L", 6.0), 6.0, 0.0001, "strafe at full rate at 6")
	approx(Mech.gait_rate("MECH_strafe_R", 3.0), 0.5, 0.0001, "half at 3")
	approx(Mech.gait_rate("MECH_back", 5.0), 1.0, 0.0001, "back at full rate at 5")
	approx(Mech.gait_rate("MECH_back_diag_L", 5.5), 1.0, 0.0001, "back diagonal at full rate at 5.5")
	approx(Mech.gait_rate("MECH_sprint_diag_R", 14.0), 1.0, 0.0001, "the sprint diagonal is a sprint")
	check(Mech.is_gait("MECH_strafe_L") and Mech.is_gait("MECH_back_diag_R") and Mech.is_gait("MECH_run_diag_L"),
		"the new clips are gaits (phase carried, footfalls tracked)")
	check(not Mech.is_forward_gait("MECH_strafe_L") and not Mech.is_forward_gait("MECH_back"),
		"side and back are not forward gaits")
	check(Mech.is_forward_gait("MECH_run_diag_L") and Mech.is_forward_gait("MECH_sprint"),
		"the runs are, diagonals included")

# --- the aim-mode state rows -------------------------------------------------------------

func _r(over: Dictionary = {}) -> Dictionary:
	var r := {on_floor = true, air_time = 0.0, rising = false, wants_move = false, heading_off = 0.0,
		h_speed = 0.0, jump = false, time = 1.0, clip_done = false, aim_lock = true, forward_gait = true}
	for k in over:
		r[k] = over[k]
	return r

const S := Mech.Loco.STAND
const T := Mech.Loco.TURN
const R := Mech.Loco.RUN
const P := Mech.Loco.STOP

func test_standing_has_a_30_degree_dead_cone() -> void:
	eq(Mech.next_loco(S, _r({heading_off = deg_to_rad(25.0)})), S, "inside the cone: stands")
	eq(Mech.next_loco(S, _r({heading_off = deg_to_rad(35.0)})), T, "past it: steps round")
	eq(Mech.next_loco(T, _r({heading_off = deg_to_rad(20.0)})), T, "keeps turning past 8 deg")
	eq(Mech.next_loco(T, _r({heading_off = deg_to_rad(5.0)})), S, "within 8: stands")

func test_a_key_moves_off_the_nose_whatever_the_camera() -> void:
	eq(Mech.next_loco(S, _r({wants_move = true, heading_off = deg_to_rad(170.0)})), R,
		"camera behind it: W still walks the nose, no step-turn first")
	eq(Mech.next_loco(T, _r({wants_move = true, heading_off = deg_to_rad(90.0)})), R,
		"a key mid-turn: it moves and keeps turning")

func test_only_a_forward_gait_stops_with_the_settle() -> void:
	eq(Mech.next_loco(R, _r({h_speed = 9.0})), P, "let go of a run: the stop")
	eq(Mech.next_loco(R, _r({h_speed = 6.0, forward_gait = false})), S, "let go of a strafe: brake to stand")
	eq(Mech.next_loco(R, _r({h_speed = 12.0, forward_gait = false})), R,
		"still above the run speed: brakes in RUN first")

# --- a live mech on a floor ---------------------------------------------------------------

var _nodes: Array[Node] = []

class _StubPilot extends Node3D:
	func exit_vehicle(_pos: Vector3, _yaw: float) -> void:
		pass

func end() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_nodes.clear()
	super()

func _add(n: Node) -> Node:
	(Engine.get_main_loop() as SceneTree).root.add_child(n)
	_nodes.append(n)
	return n

# A piloted, standing mech. No physics step runs in the suite, so the floor is passed in as a reading
# (drive_aim_step's on_floor) and the body moves through empty space; real physics is
# tests/_probe_mech_drive.gd.
func _driven() -> Node3D:
	var exia: Node3D = _add(MechScene.instantiate())
	exia.global_position = Vector3(5000.0, 0.0, 5000.0)
	exia.pilot = _add(_StubPilot.new())
	exia.rotation.y = 0.0
	exia.camera_yaw = Mech.yaw_behind(0.0)
	exia.loco = Mech.Loco.STAND
	exia.velocity = Vector3.ZERO
	return exia

func _drive(exia: Node3D, seconds: float, keys := Vector2.ZERO, free_look := false) -> void:
	for i in int(round(seconds / DT)):
		exia.velocity.y = 0.0
		exia.drive_aim_step(keys, free_look, false, false, false, DT, true)

func test_a_180_swings_the_camera_and_the_mech_grinds_round_after_it() -> void:
	var exia := _driven()
	exia.camera_yaw = Mech.yaw_behind(PI)   # the mouse flicked half a turn
	_drive(exia, 0.5)
	eq(exia.loco, Mech.Loco.TURN, "standing, way out of the cone: a step-turn")
	var turned := absf(wrapf(exia.rotation.y, -PI, PI))
	check(turned > deg_to_rad(50.0) and turned <= deg_to_rad(61.0),
		"half a second in it has turned about 60 deg, no more (%.1f)" % rad_to_deg(turned))
	_drive(exia, 1.4)
	var off := absf(wrapf(exia.rotation.y - PI, -PI, PI))
	check(off < deg_to_rad(8.5), "about 1.5 s for the half turn, then it stands (%.1f off)" % rad_to_deg(off))
	eq(exia.loco, Mech.Loco.STAND, "lined up: standing")

func test_a_small_look_standing_does_not_turn_the_mech() -> void:
	var exia := _driven()
	exia.camera_yaw = Mech.yaw_behind(deg_to_rad(20.0))
	_drive(exia, 0.5)
	approx(exia.rotation.y, 0.0, 0.0001, "20 deg is inside the cone")

func test_a_strafes_sideways_off_the_nose_and_keeps_facing() -> void:
	var exia := _driven()
	_drive(exia, 1.0, Vector2(-1, 0))
	var v := Vector2(exia.velocity.x, exia.velocity.z)
	approx(v.length(), 6.0, 0.05, "strafes at 6 m/s")
	# Nose +Z at yaw 0, so the mech's left is world +X.
	check(v.normalized().dot(Vector2(1, 0)) > 0.999, "along the mech's left (%s)" % v)
	approx(exia.rotation.y, 0.0, 0.0001, "the nose never turned")
	eq(exia.anim_player.current_animation, "MECH_strafe_L", "the side-step plays")

func test_s_backs_up_and_a_back_diagonal_is_5_5() -> void:
	var exia := _driven()
	_drive(exia, 1.0, Vector2(0, 1))
	var v := Vector2(exia.velocity.x, exia.velocity.z)
	approx(v.length(), 5.0, 0.05, "backs up at 5")
	check(v.normalized().dot(Vector2(0, -1)) > 0.999, "straight back")
	eq(exia.anim_player.current_animation, "MECH_back", "the back walk plays")
	_drive(exia, 1.0, Vector2(-1, 1))
	approx(Vector2(exia.velocity.x, exia.velocity.z).length(), 5.5, 0.05, "S+A at 5.5")
	eq(exia.anim_player.current_animation, "MECH_back_diag_L", "the back diagonal plays")

func test_a_strafe_let_go_brakes_in_about_0_3_s() -> void:
	var exia := _driven()
	_drive(exia, 1.0, Vector2(1, 0))
	_drive(exia, 0.35)
	approx(Vector2(exia.velocity.x, exia.velocity.z).length(), 0.0, 0.01, "stopped")
	eq(exia.loco, Mech.Loco.STAND, "no stop settle after a strafe")

func test_sprint_only_with_w() -> void:
	var exia := _driven()
	exia.sprint_toggled = true
	_drive(exia, 1.0, Vector2(-1, 0))
	approx(Vector2(exia.velocity.x, exia.velocity.z).length(), 6.0, 0.05, "a strafe with the toggle on: 6")
	check(exia.sprint_toggled, "the toggle stays on")
	_drive(exia, 2.0, Vector2(-1, -1))
	approx(Vector2(exia.velocity.x, exia.velocity.z).length(), 14.0, 0.1, "W+A sprints")

func test_w_runs_along_the_nose_while_the_body_chases() -> void:
	var exia := _driven()
	_drive(exia, 1.0, Vector2(0, -1))
	exia.camera_yaw = Mech.yaw_behind(PI * 0.5)   # a quarter turn left
	_drive(exia, 0.2, Vector2(0, -1))
	var turned := exia.rotation.y
	check(turned > deg_to_rad(15.0) and turned <= deg_to_rad(20.5),
		"0.2 s at the run cap: ~20 deg (%.1f)" % rad_to_deg(turned))
	var v := Vector2(exia.velocity.x, exia.velocity.z).normalized()
	var nose := Mech.facing_for(exia.rotation.y)
	check(v.dot(Vector2(nose.x, nose.z)) > 0.999, "the velocity is along the nose, not the camera")

func test_the_jump_is_committed() -> void:
	var exia := _driven()
	exia.loco = Mech.Loco.AIR
	exia.velocity = Vector3(3.0, 0.0, 4.0)
	exia.camera_yaw = Mech.yaw_behind(PI * 0.5)
	exia.drive_aim_step(Vector2(-1, 0), false, false, false, false, 0.5, false)
	approx(exia.velocity.x, 3.0, 0.0001, "no air steer or strafe (x)")
	approx(exia.velocity.z, 4.0, 0.0001, "no air steer or strafe (z)")
	var cap := Mech.aim_turn_rate(5.0, 120.0, 100.0, 60.0) * Mech.AIR_TURN_SHARE * 0.5
	approx(exia.rotation.y, cap, 0.0001, "the nose tracks at 20% of the cap")

func test_alt_freezes_the_body_and_release_eases_the_view_back_to_the_nose() -> void:
	var exia := _driven()
	exia.camera_pitch = -0.2
	_drive(exia, 0.1, Vector2.ZERO, true)
	exia.camera_yaw = Mech.yaw_behind(PI * 0.8)
	exia.camera_pitch = 0.4
	_drive(exia, 1.0, Vector2.ZERO, true)
	approx(exia.rotation.y, 0.0, 0.0001, "held: the body never turns")
	_drive(exia, 1.0, Vector2(0, -1), true)
	approx(exia.rotation.y, 0.0, 0.0001, "held and driving: still on its own nose")
	check(Vector2(exia.velocity.x, exia.velocity.z).normalized().dot(Vector2(0, 1)) > 0.999,
		"W drives the nose, not the camera")
	_drive(exia, DT)
	check(exia.free_look_returning(), "let go: the return runs")
	_drive(exia, 0.25)
	check(not exia.free_look_returning(), "and lands in 0.25 s")
	approx(wrapf(exia.camera_yaw - Mech.yaw_behind(exia.rotation.y), -PI, PI), 0.0, 0.0001,
		"the camera is back behind the nose")
	approx(exia.camera_pitch, -0.2, 0.0001, "at the pitch it had at the press")
	approx(exia.rotation.y, 0.0, 0.1, "the mech never turned for it")
