extends "res://tests/test_case.gd"

# EXIA's two gaits, the run and the sprint. See docs/specs/exia-movement.md.
#
# The clip half builds both cycles on the real imported skeleton with MechGait and samples them with
# the same tree-free sampler the build uses. The movement half pins mech.gd's speed, rate, turn and
# bank functions and drives a live mech for the toggle, the camera and the dust. How the runs LOOK
# is tests/_probe_mech_moves.gd and a play session.

const MechScene := preload("res://scenes/mech.tscn")
const Mech := preload("res://scripts/mech.gd")
const MechGait := preload("res://scripts/mech_gait.gd")

var _mech: Node3D = null
var _skeleton: Skeleton3D = null
var _standing: Animation = null
var _ctx = null
var _clips: Dictionary = {}

func _rig() -> void:
	if _ctx != null:
		return
	_mech = MechScene.instantiate()
	_skeleton = _mech.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = _mech.find_child("AnimationPlayer", true, false)
	_standing = ap.get_animation("MECH_standing")
	_ctx = MechGait.context(_skeleton, _standing)
	for g in _gaits():
		_clips[g.clip] = MechGait.build(_ctx, _standing, g)

func _gaits() -> Array:
	return [MechGait.run(), MechGait.sprint()]

func _bone(name: String) -> int:
	return _skeleton.find_bone(name)

func _pose(g, t: float) -> Array[Transform3D]:
	_rig()
	return MechGait.pose_at(_skeleton, _clips[g.clip], t)

func _origin(g, name: String, t: float) -> Vector3:
	return _pose(g, t)[_bone(name)].origin

# The sole plate's tip at `t`: the plate bone's head plus its axis at the plate's standing length.
func _plate_tip(g, side: String, t: float) -> Vector3:
	var ball: Transform3D = _pose(g, t)[_bone("toe" + side + ".001")]
	return ball.origin + ball.basis.y.normalized() * MechGait.plate_vector(_ctx, side).length()

# The lower of the ball and the plate tip, above the floor.
func _sole_height(g, side: String, t: float) -> float:
	return minf(_origin(g, "toe" + side + ".001", t).y, _plate_tip(g, side, t).y) - _ctx.floor_y

func _hip_height(g, t: float) -> float:
	return (_origin(g, "thigh.L", t).y + _origin(g, "thigh.R", t).y) * 0.5 - _ctx.floor_y

# --- the numbers ---------------------------------------------------------------------

func test_the_run_and_the_sprint_are_the_grilled_numbers() -> void:
	var run = MechGait.run()
	var sprint = MechGait.sprint()
	eq(run.clip, "MECH_run", "the run's clip")
	eq(sprint.clip, "MECH_sprint", "the sprint's clip")
	approx(run.speed, 9.0, 0.0001, "the run is 9 m/s")
	approx(sprint.speed, 14.0, 0.0001, "the sprint is 14 m/s")
	approx(run.length, 1.2, 0.0001, "the run's cycle is 1.2 s")
	approx(sprint.length, 1.0, 0.0001, "the sprint's is 1.0 s")
	approx(run.lean, 4.0, 0.0001, "the run is upright")
	approx(sprint.lean, 8.0, 0.0001, "the sprint leans 8 degrees")
	check(sprint.hip_high < run.hip_high and sprint.hip_low < run.hip_low,
		"the sprint's hips are lower than the run's")
	check(run.arm_fwd < sprint.arm_fwd and run.arm_back > sprint.arm_back,
		"the sprint swings its arms further")
	check(run.stride_front < sprint.stride_front, "and reaches further")
	approx(Mech.SPEED, run.speed, 0.0001, "the body and the run clip agree on the speed")
	approx(Mech.SPRINT_SPEED, sprint.speed, 0.0001, "and on the sprint's")

# --- the clips -----------------------------------------------------------------------

func test_both_clips_loop_at_their_length_on_30_fps_keys() -> void:
	_rig()
	for g in _gaits():
		var clip: Animation = _clips[g.clip]
		eq(clip.loop_mode, Animation.LOOP_LINEAR, "%s loops" % g.clip)
		approx(clip.length, g.length, 0.0001, "%s is one cycle long" % g.clip)
		for track in clip.get_track_count():
			eq(clip.track_get_key_count(track), int(round(g.length * 30.0)) + 1,
				"%s: 30 fps keys on %s" % [g.clip, clip.track_get_path(track)])

func test_the_last_key_is_the_first() -> void:
	_rig()
	for g in _gaits():
		var clip: Animation = _clips[g.clip]
		for track in clip.get_track_count():
			var last := clip.track_get_key_count(track) - 1
			var a: Variant = clip.track_get_key_value(track, 0)
			var z: Variant = clip.track_get_key_value(track, last)
			match clip.track_get_type(track):
				Animation.TYPE_ROTATION_3D:
					check(absf((a as Quaternion).dot(z as Quaternion)) > 0.99999,
						"%s seamless on %s" % [g.clip, clip.track_get_path(track)])
				_:
					check((a as Vector3).is_equal_approx(z as Vector3),
						"%s seamless on %s" % [g.clip, clip.track_get_path(track)])

func test_the_planted_foot_moves_back_at_the_gait_speed() -> void:
	_rig()
	for g in _gaits():
		for side in [".L", ".R"]:
			var start: float = 0.0 if side == ".L" else g.length * 0.5
			# Landing, the plate rocks on its back edge (the ball); once flat, its tip holds the floor
			# through the push-off. Whichever is down moves back at exactly the body's speed.
			for w in [0.03, 0.1, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9]:
				var t: float = start + w * g.contact
				var dt := 1.0 / 240.0
				var on_ball: bool = w < g.plate_flat_by
				var a: Vector3 = _origin(g, "toe" + side + ".001", t) if on_ball else _plate_tip(g, side, t)
				var b: Vector3 = _origin(g, "toe" + side + ".001", t + dt) if on_ball \
					else _plate_tip(g, side, t + dt)
				approx((b.z - a.z) / dt, -g.speed, g.speed * 0.05,
					"%s %s planted: moves back at %s m/s (%s of the stance)" % [g.clip, side, g.speed, w])
				check(a.y < _ctx.floor_y + 0.05,
					"%s %s stays on the floor through contact (%s)" % [g.clip, side, w])

func test_no_foot_goes_through_the_floor() -> void:
	_rig()
	for g in _gaits():
		for i in int(round(g.length * 30.0)):
			for side in [".L", ".R"]:
				check(_sole_height(g, side, i / 30.0) > -0.02,
					"%s %s above the floor at key %d" % [g.clip, side, i])

func test_the_planted_foot_is_down_and_the_other_up_at_mid_stance() -> void:
	_rig()
	for g in _gaits():
		var mid: float = g.contact * 0.5
		check(_sole_height(g, ".L", mid) < 0.05, "%s: L down at its mid-stance" % g.clip)
		check(_sole_height(g, ".R", mid) > 0.25, "%s: R up while L is planted" % g.clip)
		# The flight half way between the plants: both clear.
		var flight: float = (g.contact + g.length * 0.5) * 0.5
		for side in [".L", ".R"]:
			check(_sole_height(g, side, flight) > 0.05, "%s: %s off the floor in the flight" % [g.clip, side])

func test_the_hips_bob_between_their_low_and_high() -> void:
	_rig()
	for g in _gaits():
		approx(_hip_height(g, g.hip_low_at), g.hip_low, 0.03, "%s: low point after the plant" % g.clip)
		var lo := INF
		var hi := -INF
		for i in int(round(g.length * 30.0)):
			var h := _hip_height(g, i / 30.0)
			lo = minf(lo, h)
			hi = maxf(hi, h)
		approx(hi - lo, g.hip_high - g.hip_low, 0.03, "%s: nothing bobs past it" % g.clip)
		# The spine never moves forward or back - zero root travel.
		var stand: Vector3 = MechGait.pose_at(_skeleton, _standing, 0.0)[_bone("spine")].origin
		for i in 10:
			approx(_origin(g, "spine", g.length * i / 10.0).z, stand.z, 0.001,
				"%s: the spine holds its standing z" % g.clip)

func test_each_arm_peaks_forward_at_the_opposite_plant() -> void:
	_rig()
	for g in _gaits():
		approx(MechGait.arm_swing(g, 0.0), 1.0, 0.0001, "%s: R arm fully forward at the L plant" % g.clip)
		approx(MechGait.arm_swing(g, 0.5), -1.0, 0.0001, "%s: fully back at the R plant" % g.clip)
		check(_origin(g, "hand.R", 0.0).z > _origin(g, "hand.L", 0.0).z + 0.8,
			"%s: R fist ahead of the L at the L plant" % g.clip)
		check(_origin(g, "hand.L", g.length * 0.5).z > _origin(g, "hand.R", g.length * 0.5).z + 0.8,
			"%s: L fist ahead of the R at the R plant" % g.clip)

func test_the_sprint_swings_further_than_the_run() -> void:
	_rig()
	var run = MechGait.run()
	var sprint = MechGait.sprint()
	var run_gap := _origin(run, "hand.R", 0.0).z - _origin(run, "hand.L", 0.0).z
	var sprint_gap := _origin(sprint, "hand.R", 0.0).z - _origin(sprint, "hand.L", 0.0).z
	check(sprint_gap > run_gap, "the sprint's fists are further apart (%f vs %f)" % [sprint_gap, run_gap])

func test_the_ik_leftovers_hold_their_standing_values() -> void:
	_rig()
	var base := MechGait.pose_at(_skeleton, _standing, 0.0)
	for g in _gaits():
		for name in ["hand.L.001", "hand.R.001", "spine.002", "toe.L.002", "toe.R.002"]:
			var i := _bone(name)
			for t in [0.0, 0.3, 0.7]:
				var p := _pose(g, t)[i]
				check(p.origin.is_equal_approx(base[i].origin), "%s %s holds position" % [g.clip, name])
				check(p.basis.is_equal_approx(base[i].basis), "%s %s holds rotation" % [g.clip, name])

func test_the_legs_never_go_out_of_reach() -> void:
	# A leg clamped to its reach comes up short; every key hits its target to the centimetre.
	_rig()
	for g in _gaits():
		var keys := int(round(g.length * 30.0))
		for i in keys:
			var u := float(i) / keys
			var solved: Dictionary = MechGait.pose_from(_ctx, MechGait.gait_spec(_ctx, g, u))
			for thigh in ["thigh.L", "thigh.R"]:
				var ball := _origin(g, thigh.replace("thigh", "toe") + ".001", u * g.length)
				var off := ball.distance_to(solved.balls[thigh])
				check(off < 0.02, "%s %s reaches its ball target at key %d (off %f)" % [g.clip, thigh, i, off])

# The solve bends each knee in the plane the standing knee sits in, so the standing targets give the
# standing pose back - which is what lets the idle, the stop and the landing join it with no pop.
func test_the_standing_spec_is_the_standing_pose() -> void:
	_rig()
	var stand := MechGait.pose_at(_skeleton, _standing, 0.0)
	var solved: Dictionary = MechGait.pose_from(_ctx, MechGait.standing_spec(_ctx))
	var locals: Array[Transform3D] = []
	for b in _skeleton.get_bone_count():
		var base: Transform3D = _ctx.base_locals[b]
		locals.append(Transform3D(Basis(solved.rot[b]),
			solved.spine_pos if b == _ctx.spine else base.origin))
	var pose := MechGait.mech_pose(_skeleton, locals)
	for b in _skeleton.get_bone_count():
		check(pose[b].origin.distance_to(stand[b].origin) < 0.02,
			"%s within 2 cm of standing" % _skeleton.get_bone_name(b))

# --- rate, speed, turn, bank -----------------------------------------------------------

func test_each_clip_plays_at_the_bodys_speed() -> void:
	approx(Mech.gait_rate("MECH_sprint", 14.0), 1.0, 0.0001, "sprint: full rate at 14")
	approx(Mech.gait_rate("MECH_sprint", 10.5), 0.75, 0.0001, "sprint: three quarters at 10.5")
	approx(Mech.gait_rate("MECH_sprint", 0.0), 9.0 / 14.0, 0.0001, "sprint: never below the run's share")
	approx(Mech.gait_rate("MECH_run", 9.0), 1.0, 0.0001, "run: full rate at 9")
	approx(Mech.gait_rate("MECH_run", 4.5), 0.5, 0.0001, "run: half at 4.5")
	approx(Mech.gait_rate("MECH_run", 0.0), 0.4, 0.0001, "run: floored for the first step")
	approx(Mech.gait_rate("MECH_run", 30.0), 1.0, 0.0001, "never faster than authored")
	for v in [9.0, 12.0, 14.0]:
		approx(14.0 * Mech.gait_rate("MECH_sprint", v), v, 0.0001, "no sprint skate at %s m/s" % v)
	for v in [3.6, 6.0, 9.0]:
		approx(9.0 * Mech.gait_rate("MECH_run", v), v, 0.0001, "no run skate at %s m/s" % v)

func _simulate(sprinting: bool, speed: float, seconds: float) -> float:
	var steps := int(round(seconds * 60.0))
	for i in steps:
		var step: Vector2 = Mech.speed_target(sprinting, speed, Mech.SPEED / Mech.RUN_RAMP_TIME)
		speed = move_toward(speed, step.x, step.y / 60.0)
	return speed

func test_the_run_ramps_from_a_standstill_in_0_6_s() -> void:
	approx(_simulate(false, 0.0, 0.6), 9.0, 0.01, "0 to 9 m/s in 0.6 s")
	check(_simulate(false, 0.0, 0.5) < 8.5, "and not before")

func test_the_sprint_ramps_from_the_run_in_half_a_second() -> void:
	approx(_simulate(true, 9.0, 0.5), 14.0, 0.01, "9 to 14 m/s in 0.5 s")
	check(_simulate(true, 9.0, 0.45) < 13.5, "and not before")
	var step: Vector2 = Mech.speed_target(true, 3.0, 15.0)
	approx(step.x, 9.0, 0.0001, "below the run speed a sprint heads for the run speed first")

func test_dropping_the_sprint_eases_back_to_the_run_in_a_quarter_second() -> void:
	approx(_simulate(false, 14.0, 0.25), 9.0, 0.01, "14 to 9 m/s in 0.25 s")

func test_letting_go_of_a_sprint_brakes_to_the_run_in_0_2_s() -> void:
	var speed := 14.0
	for i in 12:
		speed = move_toward(speed, 9.0, Mech.release_rate() / 60.0)
	approx(speed, 9.0, 0.01, "down to the run speed in 0.2 s, then the stop")

func test_the_turn_rate_is_4_at_a_sprint_and_10_at_the_run() -> void:
	approx(Mech.turn_rate(14.0), 4.0, 0.0001, "sprint turn rate")
	approx(Mech.turn_rate(9.0), 10.0, 0.0001, "run turn rate")
	approx(Mech.turn_rate(0.0), 10.0, 0.0001, "standing turn rate")
	var mid := Mech.turn_rate(11.5)
	check(mid > 4.0 and mid < 10.0, "blended by speed in between")

func test_the_bank_leans_into_a_left_turn_and_caps_at_12_degrees() -> void:
	# A left turn is a positive yaw rate (+Y takes the nose +Z towards +X, the mech's left), and a
	# left lean is a negative roll about the nose.
	check(Mech.bank_target(14.0, 1.0) < 0.0, "a left turn rolls negative")
	check(Mech.bank_target(14.0, -1.0) > 0.0, "a right turn rolls positive")
	approx(rad_to_deg(Mech.bank_target(14.0, 10.0)), -12.0, 0.0001, "capped at 12 degrees")
	approx(Mech.bank_target(0.0, 5.0), 0.0, 0.0001, "no bank standing still")
	approx(rad_to_deg(Mech.bank_target(14.0, 14.0 / 12.0)), -12.0, 0.01,
		"full lean at 14 m/s on a 12 m circle")

func test_the_fov_widens_by_ten_while_sprinting() -> void:
	approx(Mech.fov_boost_target(14.0), 10.0, 0.0001, "sprinting")
	approx(Mech.fov_boost_target(9.0), 0.0, 0.0001, "running")
	approx(Mech.fov_boost_target(0.0), 0.0, 0.0001, "standing")

# --- a live mech -------------------------------------------------------------------------

var _live_mechs: Array[Node] = []

# The two methods of the pilot contract the cut-out exit calls.
class _StubPilot extends Node3D:
	func exit_vehicle(_pos: Vector3, _yaw: float) -> void:
		pass

func end() -> void:
	for n in _live_mechs:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_live_mechs.clear()
	Settings.set_value(&"camera_motion", "on")
	Settings.set_value(&"movement_effects", "on")
	super()

# An in-tree mech, so _ready has run: the clips are built, MechVfx is added.
func _live() -> Node3D:
	var exia: Node3D = MechScene.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(exia)
	_live_mechs.append(exia)
	return exia

func test_the_mech_gets_both_gait_clips() -> void:
	var exia := _live()
	var ap: AnimationPlayer = exia.anim_player
	for clip_name in ["MECH_run", "MECH_sprint"]:
		check(ap.has_animation(clip_name), "_ready adds %s to the player" % clip_name)
		eq(ap.get_animation(clip_name).loop_mode, Animation.LOOP_LINEAR, "%s loops" % clip_name)
		check(not exia.travel_curves.has(clip_name), "%s is not split for root motion" % clip_name)

func test_the_toggle_flips_on_sprint_and_clears_on_walk() -> void:
	var exia := _live()
	exia._update_sprint_toggle(true, true, 9.0, true, false)
	check(exia.sprint_toggled, "sprint turns it on")
	exia._update_sprint_toggle(true, true, 9.0, true, false)
	check(not exia.sprint_toggled, "sprint again turns it off")
	exia._update_sprint_toggle(true, true, 9.0, true, false)
	exia._update_sprint_toggle(true, true, 9.0, false, true)
	check(not exia.sprint_toggled, "walk clears it")

func test_a_complete_stop_clears_the_toggle_but_a_press_while_standing_survives() -> void:
	var exia := _live()
	exia._update_sprint_toggle(true, true, 9.0, true, false)
	exia._update_sprint_toggle(true, false, 0.0, false, false)
	check(not exia.sprint_toggled, "on the floor, at rest, no key held: the toggle clears")
	exia._update_sprint_toggle(true, false, 0.0, true, false)
	check(exia.sprint_toggled, "a press at a standstill is kept")
	exia._update_sprint_toggle(true, false, 0.0, false, false)
	check(exia.sprint_toggled, "and holding still after it does not clear it again")

func test_the_toggle_survives_the_air() -> void:
	var exia := _live()
	exia._update_sprint_toggle(true, true, 9.0, true, false)
	exia._update_sprint_toggle(false, false, 0.0, false, false)
	check(exia.sprint_toggled, "in the air it has not stopped")

func test_getting_out_clears_the_toggle() -> void:
	var exia := _live()
	exia.sprint_toggled = true
	var pilot := _StubPilot.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(pilot)
	_live_mechs.append(pilot)
	exia.pilot = pilot
	exia._exit_mech()
	check(not exia.sprint_toggled, "exiting clears the sprint")

func test_the_bank_composes_with_the_models_yaw() -> void:
	var exia := _live()
	var rest: Transform3D = exia._model_rest
	exia.bank = 0.2
	exia._update_bank(0.0001, false, 0.0)
	var banked: Transform3D = exia.model.transform
	var roll := Basis(Vector3(0.0, 0.0, 1.0), exia.bank)
	check((roll.inverse() * banked.basis).is_equal_approx(rest.basis),
		"the bank rides on top of the authored transform, it does not replace it")
	exia.bank = 0.0
	exia._update_bank(0.016, false, 0.0)
	check(exia.model.transform.is_equal_approx(rest), "with no bank the model is exactly as authored")

func test_the_crossfades() -> void:
	approx(Mech.blend_for("MECH_run", "MECH_sprint"), 0.15, 0.0001, "run to sprint")
	approx(Mech.blend_for("MECH_sprint", "MECH_run"), 0.15, 0.0001, "sprint to run")
	approx(Mech.blend_for("MECH_stand_idle", "MECH_run"), 0.2, 0.0001, "setting off")
	approx(Mech.blend_for("MECH_run", "MECH_stop_L"), 0.15, 0.0001, "into the stop")
	approx(Mech.blend_for("MECH_stop_R", "MECH_stand_idle"), 0.1, 0.0001, "the stop ends on standing")
	approx(Mech.blend_for("MECH_standing", "MECH_stand_idle"), 0.3, 0.0001, "the boot-up into the idle")
	approx(Mech.blend_for("MECH_jump_crouch", "MECH_jump_air"), 0.08, 0.0001, "the push-off")
	approx(Mech.blend_for("MECH_run", "MECH_jump_air"), 0.25, 0.0001, "off a ledge")
	approx(Mech.blend_for("MECH_jump_air", "MECH_land"), 0.05, 0.0001, "the impact")

func test_the_camera_offsets_are_zero_with_camera_motion_off() -> void:
	Settings.set_value(&"camera_motion", "off")
	var exia := _live()
	exia._on_footfall(0, "MECH_sprint")
	approx(exia._dip, 0.0, 0.0, "no dip")
	check(exia._shake_age == INF, "no shake")
	exia._step_bound_camera(0.016)
	approx(exia._bounce, 0.0, 0.0, "no bounce")
	Settings.set_value(&"camera_motion", "on")
	exia._on_footfall(0, "MECH_sprint")
	approx(exia._dip, -Mech.FOOTFALL_DIP, 0.0001, "the sprint's footfall dips the camera 0.25 m")
	check(exia._shake_age == 0.0, "and starts the shake")
	for i in 30:
		exia._step_bound_camera(1.0 / 60.0)
	approx(exia._dip, 0.0, 0.01, "the dip settles in about half a second")
	check(Mech.shake_offset(Mech.FOOTFALL_SHAKE_TIME) == Vector2.ZERO, "the shake decays to zero")
	check(Mech.shake_offset(0.0).length() <= deg_to_rad(Mech.FOOTFALL_SHAKE_DEG) * 1.5,
		"and starts within 0.6 degrees")

func test_the_runs_footfall_is_forty_percent_and_does_not_shake() -> void:
	var exia := _live()
	exia._on_footfall(1, "MECH_run")
	approx(exia._dip, -Mech.FOOTFALL_DIP * 0.4, 0.0001, "0.1 m dip")
	check(exia._shake_age == INF, "no shake on the run")

func test_the_footfall_dust_is_off_with_movement_effects_off() -> void:
	var exia := _live()
	Settings.set_value(&"movement_effects", "off")
	exia._on_footfall(1)
	eq(exia._vfx.get_child_count(), 0, "no dust with MOVEMENT EFFECTS off")
	Settings.set_value(&"movement_effects", "on")
	exia._on_footfall(1)
	eq(exia._vfx.get_child_count(), 1, "a dust ring on each footfall with it on")

# --- the feet come back after a run ---------------------------------------------------

# The exported clips never key `toe.L.001` (the left sole plate), so before the fix it kept the
# run's last angle under every clip that followed. Every clip must now key every bone the run does.
func test_every_clip_keys_every_bone_the_gaits_move() -> void:
	var exia := _live()
	var ap: AnimationPlayer = exia.anim_player
	var sprint := ap.get_animation("MECH_sprint")
	for clip_name in ap.get_animation_list():
		var clip := ap.get_animation(clip_name)
		for track in sprint.get_track_count():
			check(clip.find_track(sprint.track_get_path(track), sprint.track_get_type(track)) >= 0,
				"%s keys %s" % [clip_name, sprint.track_get_path(track)])

func test_the_left_sole_plate_is_back_to_standing_after_a_run() -> void:
	var exia := _live()
	var ap: AnimationPlayer = exia.anim_player
	var sk: Skeleton3D = exia._skeleton
	var plate := sk.find_bone("toe.L.001")
	ap.play("MECH_standing")
	ap.advance(0.0)
	var stand_q := sk.get_bone_pose_rotation(plate)
	ap.play("MECH_sprint")
	ap.seek(0.3, true)     # the push-off: the plate's heel well up
	check(absf(sk.get_bone_pose_rotation(plate).dot(stand_q)) < 0.999, "the run moves the left plate")
	ap.play("MECH_standing")
	ap.advance(0.0)
	check(absf(sk.get_bone_pose_rotation(plate).dot(stand_q)) > 0.99999,
		"standing puts the left plate back")
	ap.play("MECH_launch")
	ap.seek(0.5, true)
	ap.play("MECH_walk")
	ap.seek(0.5, true)
	check(absf(sk.get_bone_pose_rotation(plate).dot(stand_q)) > 0.99999,
		"and the old walk holds it at standing too")
