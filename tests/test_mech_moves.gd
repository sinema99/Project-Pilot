extends "res://tests/test_case.gd"

# EXIA's non-cycle clips and the locomotion state machine. See docs/specs/exia-movement.md.
#
# The clips are built on the real imported skeleton and sampled with the tree-free sampler. The state
# machine is next_loco(), a pure function, driven row by row through the spec's table. A whole drive
# through real physics is tests/_probe_mech_drive.gd.

const MechScene := preload("res://scenes/mech.tscn")
const Mech := preload("res://scripts/mech.gd")
const MechGait := preload("res://scripts/mech_gait.gd")
const MechMoves := preload("res://scripts/mech_moves.gd")

var _skeleton: Skeleton3D = null
var _standing: Animation = null
var _clips: Dictionary = {}
var _ctx = null

func _rig() -> void:
	if _ctx != null:
		return
	var mech: Node3D = MechScene.instantiate()
	_skeleton = mech.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = mech.find_child("AnimationPlayer", true, false)
	_standing = ap.get_animation("MECH_standing")
	_ctx = MechGait.context(_skeleton, _standing)
	_clips = MechMoves.build_all(_skeleton, _standing)

func _pose(clip: String, t: float) -> Array[Transform3D]:
	_rig()
	return MechGait.pose_at(_skeleton, _clips[clip], t)

func _origin(clip: String, bone: String, t: float) -> Vector3:
	return _pose(clip, t)[_skeleton.find_bone(bone)].origin

func _hip_height(clip: String, t: float) -> float:
	return (_origin(clip, "thigh.L", t).y + _origin(clip, "thigh.R", t).y) * 0.5 - _ctx.floor_y

# The worst distance of any bone at `t` of `clip` from MECH_standing.
func _off_standing(clip: String, t: float) -> float:
	var stand := MechGait.pose_at(_skeleton, _standing, 0.0)
	var pose := _pose(clip, t)
	var worst := 0.0
	for b in _skeleton.get_bone_count():
		worst = maxf(worst, pose[b].origin.distance_to(stand[b].origin))
	return worst

# --- the clips -----------------------------------------------------------------------

func test_every_clip_is_built_with_its_length_and_loop() -> void:
	_rig()
	var expect := {
		"MECH_run": [1.2, true], "MECH_sprint": [1.0, true], "MECH_stand_idle": [4.0, true],
		"MECH_turn_step": [1.0, true], "MECH_stop_L": [1.0, false], "MECH_stop_R": [1.0, false],
		"MECH_jump_crouch": [0.25, false], "MECH_jump_air": [1.2, true], "MECH_land": [0.6, false],
	}
	eq(_clips.size(), expect.size(), "nine built clips")
	for name in expect:
		check(_clips.has(name), "%s is built" % name)
		if not _clips.has(name):
			continue
		var clip: Animation = _clips[name]
		approx(clip.length, expect[name][0], 0.0001, "%s length" % name)
		eq(clip.loop_mode, Animation.LOOP_LINEAR if expect[name][1] else Animation.LOOP_NONE,
			"%s loop mode" % name)

func test_the_joins_land_on_the_standing_pose() -> void:
	_rig()
	check(_off_standing("MECH_stand_idle", 0.0) < 0.005, "the idle starts on standing")
	check(_off_standing("MECH_stop_L", 1.0) < 0.005, "the left-lead stop ends on standing")
	check(_off_standing("MECH_stop_R", 1.0) < 0.005, "the right-lead stop ends on standing")
	check(_off_standing("MECH_land", 0.6) < 0.005, "the landing ends on standing")

func test_the_idle_breathes_a_little() -> void:
	_rig()
	var stand_h: float = _ctx.stand_hip_h
	approx(_hip_height("MECH_stand_idle", 2.0), stand_h - MechMoves.IDLE_BOB, 0.005,
		"the hips are 4 cm down at the bottom of the breath")
	check(_off_standing("MECH_stand_idle", 1.0) > 0.01, "it is not a frozen frame")
	for side in [".L", ".R"]:
		for t in [0.5, 1.5, 2.5, 3.5]:
			var ball := _origin("MECH_stand_idle", "toe" + side + ".001", t)
			var stand: Vector3 = _ctx.g0[_skeleton.find_bone("toe" + side + ".001")].origin
			check(ball.distance_to(stand) < 0.01, "%s stays planted through the breath" % side)

func test_the_stop_locks_the_lead_foot_to_the_floor() -> void:
	_rig()
	for lead in [".L", ".R"]:
		var clip: String = "MECH_stop" + lead.replace(".", "_")
		for t in [0.05, 0.15, 0.25, 0.35]:
			var dt := 1.0 / 240.0
			var a := _origin(clip, "toe" + lead + ".001", t)
			var b := _origin(clip, "toe" + lead + ".001", t + dt)
			approx((b.z - a.z) / dt, -MechMoves.stop_speed(t + dt * 0.5), 0.3,
				"%s: the lead ball moves back at the brake's speed at %s s" % [clip, t])
			check(a.y - _ctx.floor_y < 0.03, "%s: and stays on the floor" % clip)
		# The trail foot is up before it plants, and down after.
		var trail := ".R" if lead == ".L" else ".L"
		check(_origin(clip, "toe" + trail + ".001", 0.15).y - _ctx.floor_y > 0.2,
			"%s: the trail foot swings through" % clip)
		check(_origin(clip, "toe" + trail + ".001", 0.5).y - _ctx.floor_y < 0.03,
			"%s: and is planted after %s s" % [clip, MechMoves.STOP_TRAIL_PLANT])

func test_the_stop_settles_below_standing() -> void:
	_rig()
	check(_hip_height("MECH_stop_L", MechMoves.STOP_SETTLE_AT) < _ctx.stand_hip_h - 0.3,
		"the hips dip 0.35 m in the settle")

func test_the_stop_distance_is_a_linear_brake() -> void:
	approx(MechMoves.stop_distance(MechMoves.STOP_TIME), 1.8, 0.0001, "9 m/s over 0.4 s is 1.8 m")
	approx(MechMoves.stop_speed(0.0), 9.0, 0.0001, "starts at the run speed")
	approx(MechMoves.stop_speed(0.2), 4.5, 0.0001, "half way at half the time")
	approx(MechMoves.stop_speed(0.5), 0.0, 0.0001, "stopped by 0.4 s")

func test_the_stop_lead_is_the_foot_that_planted_last() -> void:
	eq(MechMoves.stop_lead(0.0), ".L", "at the left plant")
	eq(MechMoves.stop_lead(0.1), ".L", "just after it")
	eq(MechMoves.stop_lead(0.9), ".L", "the left about to plant")
	eq(MechMoves.stop_lead(0.5), ".R", "at the right plant")
	eq(MechMoves.stop_lead(0.6), ".R", "just after it")

func test_the_turn_step_lifts_one_foot_at_a_time_and_puts_it_back() -> void:
	_rig()
	check(_origin("MECH_turn_step", "toe.R.001", 0.25).y - _ctx.floor_y > 0.4, "R up in the first half")
	check(_origin("MECH_turn_step", "toe.L.001", 0.25).y - _ctx.floor_y < 0.01, "L planted under it")
	check(_origin("MECH_turn_step", "toe.L.001", 0.75).y - _ctx.floor_y > 0.4, "L up in the second half")
	check(_origin("MECH_turn_step", "toe.R.001", 0.75).y - _ctx.floor_y < 0.01, "R planted under it")
	eq(MechMoves.turn_pivot(0.25), ".L", "the pivot is the planted left")
	eq(MechMoves.turn_pivot(0.75), ".R", "then the planted right")
	for side in [".L", ".R"]:
		var stand: Vector3 = _ctx.g0[_skeleton.find_bone("toe" + side + ".001")].origin
		check(_origin("MECH_turn_step", "toe" + side + ".001", 0.0).distance_to(stand) < 0.01,
			"%s comes back down where it stands" % side)

func test_the_crouch_loads_and_the_landing_goes_deeper() -> void:
	_rig()
	var stand_h: float = _ctx.stand_hip_h
	approx(_hip_height("MECH_jump_crouch", MechMoves.CROUCH_TIME), stand_h - 1.0, 0.01, "crouch: 1 m down")
	approx(_hip_height("MECH_land", MechMoves.LAND_HOLD_TO - 0.02), stand_h - 1.1, 0.01, "landing: 1.1 m down")
	check(_hip_height("MECH_land", 0.4) > _hip_height("MECH_land", 0.15), "and coming back up")
	for side in [".L", ".R"]:
		var stand: Vector3 = _ctx.g0[_skeleton.find_bone("toe" + side + ".001")].origin
		for clip in ["MECH_jump_crouch", "MECH_land"]:
			check(_origin(clip, "toe" + side + ".001", 0.12).distance_to(stand) < 0.01,
				"%s: %s stays planted" % [clip, side])

func test_the_air_pose_tucks_both_feet() -> void:
	_rig()
	for t in [0.0, 0.3, 0.9]:
		for side in [".L", ".R"]:
			check(_origin("MECH_jump_air", "toe" + side + ".001", t).y - _ctx.floor_y > 0.5,
				"%s tucked up at %s" % [side, t])
	check(_origin("MECH_jump_air", "toe.L.001", 0.0).z > _origin("MECH_jump_air", "toe.R.001", 0.0).z + 1.0,
		"left forward, right back")

func test_no_built_clip_puts_a_foot_through_the_floor() -> void:
	_rig()
	for name in _clips:
		var clip: Animation = _clips[name]
		for i in int(clip.length * 30.0) + 1:
			for side in [".L", ".R"]:
				var y: float = _origin(name, "toe" + side + ".001", minf(i / 30.0, clip.length)).y - _ctx.floor_y
				check(y > -0.02, "%s %s above the floor at key %d" % [name, side, i])

# --- the jump numbers ----------------------------------------------------------------

func test_the_jump_reaches_three_metres_under_the_heavy_gravity() -> void:
	var g := 9.8
	var v := Mech.jump_velocity(g)
	var apex := v * v / (2.0 * g * Mech.MECH_GRAVITY_SCALE)
	approx(apex, 3.0, 0.001, "a 3 m apex")
	var air := 2.0 * v / (g * Mech.MECH_GRAVITY_SCALE)
	check(air > 1.1 and air < 1.4, "about 1.25 s in the air (%f)" % air)

func test_the_landing_rate() -> void:
	approx(Mech.land_rate(0.5, false), 1.8, 0.0001, "a short drop is a light landing")
	approx(Mech.land_rate(3.0, false), 1.0, 0.0001, "a full jump plays it out")
	approx(Mech.land_rate(3.0, true), 1.5, 0.0001, "quicker with a key held")

# --- next_loco ------------------------------------------------------------------------

func _r(over: Dictionary = {}) -> Dictionary:
	var r := {on_floor = true, air_time = 0.0, rising = false, wants_move = false, heading_off = 0.0,
		h_speed = 0.0, jump = false, time = 1.0, clip_done = false}
	for k in over:
		r[k] = over[k]
	return r

const S := Mech.Loco.STAND
const T := Mech.Loco.TURN
const R := Mech.Loco.RUN
const P := Mech.Loco.STOP
const C := Mech.Loco.CROUCH
const A := Mech.Loco.AIR
const L := Mech.Loco.LAND

func test_standing() -> void:
	eq(Mech.next_loco(S, _r()), S, "nothing held: stand")
	eq(Mech.next_loco(S, _r({wants_move = true, heading_off = deg_to_rad(10.0)})), R,
		"a key ahead: run")
	eq(Mech.next_loco(S, _r({wants_move = true, heading_off = deg_to_rad(90.0)})), T,
		"a key well off the nose: step round first")
	eq(Mech.next_loco(S, _r({jump = true})), C, "Space: crouch")

func test_turning() -> void:
	eq(Mech.next_loco(T, _r({wants_move = true, heading_off = deg_to_rad(40.0)})), T, "still turning")
	eq(Mech.next_loco(T, _r({wants_move = true, heading_off = deg_to_rad(5.0)})), R, "lined up: run")
	eq(Mech.next_loco(T, _r()), S, "let go: stand")

func test_running_and_letting_go() -> void:
	eq(Mech.next_loco(R, _r({wants_move = true, h_speed = 9.0})), R, "held: run")
	eq(Mech.next_loco(R, _r({h_speed = 12.0})), R, "let go at a sprint: brake to the run first")
	eq(Mech.next_loco(R, _r({h_speed = 9.0})), P, "let go at the run: stop")
	eq(Mech.next_loco(R, _r({h_speed = 3.0})), S, "let go crawling: just stand")
	eq(Mech.next_loco(R, _r({jump = true, h_speed = 9.0, wants_move = true})), C, "jump from a run")

func test_stopping() -> void:
	eq(Mech.next_loco(P, _r()), P, "the stop plays out")
	eq(Mech.next_loco(P, _r({clip_done = true})), S, "then stands")
	eq(Mech.next_loco(P, _r({wants_move = true})), R, "a key mid-stop runs again")

func test_the_jump() -> void:
	eq(Mech.next_loco(C, _r({time = 0.1})), C, "the crouch loads")
	eq(Mech.next_loco(C, _r({time = 0.25})), A, "and launches at 0.25 s")
	eq(Mech.next_loco(C, _r({time = 0.1, jump = true})), C, "no double press mid-crouch")
	eq(Mech.next_loco(A, _r({on_floor = false, time = 0.5})), A, "in the air")
	eq(Mech.next_loco(A, _r({on_floor = true, rising = true, time = 0.5})), A, "not while still rising")
	eq(Mech.next_loco(A, _r({on_floor = true, time = 0.5})), L, "down: land")
	eq(Mech.next_loco(A, _r({jump = true, on_floor = false, time = 0.5})), A, "no jump in the air")

func test_landing() -> void:
	eq(Mech.next_loco(L, _r({time = 0.1})), L, "the landing plays")
	eq(Mech.next_loco(L, _r({time = 0.1, jump = true})), L, "no jump in the first 0.2 s")
	eq(Mech.next_loco(L, _r({time = 0.3, jump = true})), C, "after that, a jump")
	eq(Mech.next_loco(L, _r({clip_done = true})), S, "done, nothing held: stand")
	eq(Mech.next_loco(L, _r({clip_done = true, wants_move = true})), R, "done, a key held: run")

func test_walking_off_a_ledge() -> void:
	eq(Mech.next_loco(R, _r({on_floor = false, air_time = 0.05, wants_move = true})), R,
		"the coyote time: still running")
	eq(Mech.next_loco(R, _r({on_floor = false, air_time = 0.05, jump = true})), C,
		"and still able to jump")
	eq(Mech.next_loco(R, _r({on_floor = false, air_time = 0.2, wants_move = true})), A, "then falling")
	eq(Mech.next_loco(S, _r({on_floor = false, air_time = 0.2})), A, "from a stand too")

func test_each_state_plays_its_clip() -> void:
	eq(Mech.loco_clip(S, 0.0, "MECH_stop_L"), "MECH_stand_idle", "stand")
	eq(Mech.loco_clip(T, 0.0, "MECH_stop_L"), "MECH_turn_step", "turn")
	eq(Mech.loco_clip(R, 9.0, "MECH_stop_L"), "MECH_run", "run")
	eq(Mech.loco_clip(R, 12.0, "MECH_stop_L"), "MECH_sprint", "sprint above 9.1")
	eq(Mech.loco_clip(P, 0.0, "MECH_stop_R"), "MECH_stop_R", "the stop with its lead")
	eq(Mech.loco_clip(C, 0.0, ""), "MECH_jump_crouch", "crouch")
	eq(Mech.loco_clip(A, 0.0, ""), "MECH_jump_air", "air")
	eq(Mech.loco_clip(L, 0.0, ""), "MECH_land", "land")

# --- getting out ----------------------------------------------------------------------

func test_the_exit_waits_for_the_floor_and_the_run_speed() -> void:
	check(Mech.can_exit_now(true, 0.0, S), "standing: out")
	check(Mech.can_exit_now(true, 9.0, R), "at the run: out")
	check(not Mech.can_exit_now(true, 14.0, R), "at a sprint: wait")
	check(not Mech.can_exit_now(false, 0.0, A), "in the air: wait")
	check(not Mech.can_exit_now(true, 0.0, C), "mid-crouch: wait")

var _live: Array[Node] = []

func end() -> void:
	for n in _live:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_live.clear()
	super()

class _StubPilot extends Node3D:
	var exited_at := Vector3.INF
	func exit_vehicle(pos: Vector3, _yaw: float) -> void:
		exited_at = pos

func _in_tree(n: Node) -> Node:
	(Engine.get_main_loop() as SceneTree).root.add_child(n)
	_live.append(n)
	return n

func test_f_at_a_sprint_queues_the_exit() -> void:
	var exia: Node3D = _in_tree(MechScene.instantiate())
	var pilot: _StubPilot = _in_tree(_StubPilot.new())
	exia.pilot = pilot
	exia.sprint_toggled = true
	exia.velocity = Vector3(0.0, 0.0, 14.0)
	exia._request_exit()
	check(exia.exit_pending, "too fast: the exit waits")
	check(not exia.sprint_toggled, "and the sprint is dropped so it brakes")
	eq(exia.pilot, pilot, "the pilot is still aboard")
	eq(exia.prompt_label.text, "EXIT...", "the prompt says it is waiting")
	exia._request_exit()
	check(not exia.exit_pending, "F again calls it off")

# The blocked-spot fallback needs physics steps to see a blocker, so it is checked by
# tests/_probe_mech_drive.gd. Synchronously the space is empty and the answer is ExitPoint.
func test_the_exit_spot_is_behind_the_mech_facing_it() -> void:
	var exia: Node3D = _in_tree(MechScene.instantiate())
	exia.global_position = Vector3.ZERO
	exia.rotation.y = 0.7
	var spot: Dictionary = exia.exit_spot()
	var behind: Vector3 = exia.exit_point.global_position
	approx(spot.position.x, behind.x, 0.01, "behind the mech (x)")
	approx(spot.position.z, behind.z, 0.01, "behind the mech (z)")
	approx(wrapf(spot.yaw - exia.rotation.y, -PI, PI), 0.0, 0.01, "facing the mech")
