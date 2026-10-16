extends "res://tests/test_case.gd"

# EXIA's sprint. See docs/specs/exia-sprint.md.
#
# The clip half calls MechSprint.build() on the real imported skeleton and samples the result with
# the same tree-free sampler the build uses. The movement half drives mech.gd the way test_mech.gd
# does. How the run LOOKS is a probe (tests/_probe_mech_sprint.gd) and a play session.

const MechScene := preload("res://scenes/mech.tscn")
const Mech := preload("res://scripts/mech.gd")
const MechSprint := preload("res://scripts/mech_sprint.gd")

var _mech: Node3D = null
var _skeleton: Skeleton3D = null
var _clip: Animation = null
var _standing: Animation = null

func _rig() -> void:
	if _clip != null:
		return
	_mech = MechScene.instantiate()
	_skeleton = _mech.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = _mech.find_child("AnimationPlayer", true, false)
	_standing = ap.get_animation("MECH_standing")
	_clip = MechSprint.build(_skeleton, _standing)

func _bone(name: String) -> int:
	return _skeleton.find_bone(name)

func _pose(t: float) -> Array[Transform3D]:
	_rig()
	return MechSprint.pose_at(_skeleton, _clip, t)

func _origin(name: String, t: float) -> Vector3:
	return _pose(t)[_bone(name)].origin

# --- the clip -----------------------------------------------------------------------

func _ctx():
	_rig()
	return MechSprint._context(_skeleton, MechSprint.locals_at(_skeleton, _standing, 0.0))

func _floor_y() -> float:
	return _ctx().floor_y

# The sole plate's tip at `t`: the plate bone's head plus its axis at the plate's standing length.
func _plate_tip(side: String, t: float) -> Vector3:
	var ball: Transform3D = _pose(t)[_bone("toe" + side + ".001")]
	return ball.origin + ball.basis.y.normalized() * MechSprint.plate_vector(_ctx(), side).length()

# The lower of the ball and the plate tip, above the floor.
func _sole_height(side: String, t: float) -> float:
	return minf(_origin("toe" + side + ".001", t).y, _plate_tip(side, t).y) - _floor_y()

func test_the_clip_loops_and_is_one_second_of_31_keys() -> void:
	_rig()
	eq(_clip.loop_mode, Animation.LOOP_LINEAR, "MECH_sprint loops")
	approx(_clip.length, 1.0, 0.0001, "one cycle is 1.0 s: two steps, 2 a second")
	approx(MechSprint.SPRINT_SPEED, 14.0, 0.0001, "authored for 14 m/s: a 7 m step")
	for track in _clip.get_track_count():
		eq(_clip.track_get_key_count(track), 31, "31 keys on %s" % _clip.track_get_path(track))

func test_the_last_key_is_the_first() -> void:
	_rig()
	for track in _clip.get_track_count():
		var last := _clip.track_get_key_count(track) - 1
		var a: Variant = _clip.track_get_key_value(track, 0)
		var z: Variant = _clip.track_get_key_value(track, last)
		match _clip.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				check(absf((a as Quaternion).dot(z as Quaternion)) > 0.99999,
					"seamless loop on %s" % _clip.track_get_path(track))
			_:
				check((a as Vector3).is_equal_approx(z as Vector3),
					"seamless loop on %s" % _clip.track_get_path(track))

func test_the_planted_foot_moves_back_at_the_body_speed() -> void:
	var floor_y := _floor_y()
	var stance := MechSprint.CONTACT_TIME
	for side in [".L", ".R"]:
		var start := 0.0 if side == ".L" else MechSprint.LENGTH * 0.5
		# Landing, the plate rocks on its back edge (the ball); once flat, its tip holds the floor
		# through the push-off. Whichever is down moves back at exactly the body's speed.
		for w in [0.03, 0.1, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9]:
			var t: float = start + w * stance
			var dt := 1.0 / 240.0
			var on_ball: bool = w < MechSprint.PLATE_FLAT_BY
			var a: Vector3 = _origin("toe" + side + ".001", t) if on_ball else _plate_tip(side, t)
			var b: Vector3 = _origin("toe" + side + ".001", t + dt) if on_ball else _plate_tip(side, t + dt)
			approx((b.z - a.z) / dt, -MechSprint.SPRINT_SPEED, MechSprint.SPRINT_SPEED * 0.05,
				"%s planted: moves back at 14 m/s (%s of the stance)" % [side, w])
			check(a.y < floor_y + 0.05,
				"%s stays on the floor through contact (%s: %f)" % [side, w, a.y - floor_y])

func test_each_foot_is_down_035_s_and_both_are_up_only_between_steps() -> void:
	approx(MechSprint.CONTACT_TIME, 0.35, 0.0001, "each foot is down for 0.35 s")
	# Mid-stance the planted foot is down and the other is in the air.
	check(_sole_height(".L", 0.175) < 0.05, "L down at its mid-stance")
	check(_sole_height(".R", 0.175) > 0.3, "R up while L is planted")
	# The short flight half way between the plants: both clear.
	for t in [0.425, 0.925]:
		for side in [".L", ".R"]:
			check(_sole_height(side, t) > 0.1, "%s is off the floor at t=%s" % [side, t])

func test_the_right_leg_is_the_left_leg_half_a_cycle_later() -> void:
	_rig()
	var half := MechSprint.LENGTH * 0.5
	var hip_z: float = (_origin("thigh.L", 0.0).z + _origin("thigh.R", 0.0).z) * 0.5
	var cx: float = (_origin("thigh.L", 0.0).x + _origin("thigh.R", 0.0).x) * 0.5
	for t in [0.0, 0.1, 0.2, 0.3, 0.4, 0.6, 0.8]:
		var l := _origin("toe.L.001", t)
		var r := _origin("toe.R.001", fposmod(t + half, MechSprint.LENGTH))
		approx(r.y, l.y, 0.08, "R ball height half a cycle later matches L at t=%s" % t)
		approx(r.z - hip_z, l.z - hip_z, 0.2, "R ball reach half a cycle later matches L at t=%s" % t)
		approx(r.x - cx, -(l.x - cx), 0.15,
			"R ball mirrors L in x at t=%s (the standing rig is 0.09 m asymmetric)" % t)

func _hip_height(t: float) -> float:
	return (_origin("thigh.L", t).y + _origin("thigh.R", t).y) * 0.5 - _floor_y()

func test_the_hips_bob_a_fifth_of_a_metre_and_sway_over_the_planted_foot() -> void:
	# Lowest a beat after the plant, highest in the flight between steps.
	approx(_hip_height(MechSprint.HIP_LOW_AT), MechSprint.HIP_LOW, 0.03, "low point 0.07 s after the plant")
	approx(_hip_height(0.425), MechSprint.HIP_HIGH, 0.03, "high point in the flight")
	approx(MechSprint.HIP_HIGH - MechSprint.HIP_LOW, 0.2, 0.0001, "a fifth of a metre of bob")
	var lo := INF
	var hi := -INF
	for i in 30:
		var h := _hip_height(i / 30.0)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	approx(hi - lo, 0.2, 0.03, "nothing bobs past it")
	# The spine (the root of the hips) never moves forward or back - zero root travel - and slides
	# sideways over whichever foot is planted (+X is the mech's left).
	var stand: Vector3 = MechSprint.pose_at(_skeleton, _standing, 0.0)[_bone("spine")].origin
	for i in 30:
		approx(_origin("spine", i / 30.0).z, stand.z, 0.001, "the spine holds its standing z (key %d)" % i)
	check(_origin("spine", 0.2).x - stand.x > 0.12, "over the left foot in its stance")
	check(_origin("spine", 0.7).x - stand.x < -0.12, "over the right foot in its stance")

func test_the_lean_is_eight_degrees() -> void:
	approx(MechSprint.LEAN_DEG, 8.0, 0.0001, "mostly upright: the weight over the hips")
	approx(MechSprint.LEAN_BOB_DEG, 1.0, 0.0001, "a degree deeper at the low point")
	# The spine really is turned by about that much against standing, give or take the bob, yaw and roll.
	var stand: Basis = MechSprint.pose_at(_skeleton, _standing, 0.0)[_bone("spine")].basis
	for t in [0.0, 0.25, 0.5, 0.75]:
		var b: Basis = _pose(t)[_bone("spine")].basis
		var deg := rad_to_deg((b * stand.inverse()).get_rotation_quaternion().get_angle())
		check(deg > 6.0 and deg < 12.0, "spine about 8 degrees off standing at t=%s (%f)" % [t, deg])

func test_each_arm_peaks_forward_at_the_opposite_plant() -> void:
	_rig()
	approx(MechSprint.arm_swing(0.0), 1.0, 0.0001, "R arm fully forward at the L plant")
	approx(MechSprint.arm_swing(0.5), -1.0, 0.0001, "and fully back at the R plant")
	# Held through the low contact pose: still most of the way forward a beat after the plant.
	check(MechSprint.arm_swing(MechSprint.HIP_LOW_AT / MechSprint.LENGTH) > 0.9, "held through the low point")
	check(_origin("hand.R", 0.0).z > _origin("hand.L", 0.0).z + 1.5, "R fist ahead of the L at the L plant")
	check(_origin("hand.L", 0.5).z > _origin("hand.R", 0.5).z + 1.5, "L fist ahead of the R at the R plant")
	# The fist's own forward peak lands inside that hold, not drifting a step late.
	var best_t := 0.0
	var best_z := -INF
	for i in 30:
		var z: float = _origin("hand.R", i / 30.0).z
		if z > best_z:
			best_z = z
			best_t = i / 30.0
	var off := wrapf(best_t, -0.5, 0.5)
	check(absf(off) <= 0.1, "R fist's forward peak is within 0.1 s of the L plant (%f)" % off)

func test_the_ik_leftovers_hold_their_standing_values() -> void:
	_rig()
	var base := MechSprint.pose_at(_skeleton, _standing, 0.0)
	for name in ["hand.L.001", "hand.R.001", "spine.002", "toe.L.002", "toe.R.002"]:
		var i := _bone(name)
		for t in [0.0, 0.3, 0.7]:
			var p := _pose(t)[i]
			check(p.origin.is_equal_approx(base[i].origin), "%s holds position at t=%s" % [name, t])
			check(p.basis.is_equal_approx(base[i].basis), "%s holds rotation at t=%s" % [name, t])

func test_the_legs_never_go_out_of_reach() -> void:
	# A leg clamped to its reach comes up short; every key hits its target to the centimetre.
	var ctx = _ctx()
	for i in 30:
		var u := float(i) / 30.0
		var solved: Dictionary = MechSprint.solve_pose(ctx, u)
		for thigh in ["thigh.L", "thigh.R"]:
			var ball := _origin(thigh.replace("thigh", "toe") + ".001", u * MechSprint.LENGTH)
			var off := ball.distance_to(solved.balls[thigh])
			check(off < 0.02, "%s reaches its ball target at key %d (off %f)" % [thigh, i, off])

func test_the_clip_plays_at_the_bodys_speed() -> void:
	approx(Mech.SPRINT_SPEED, MechSprint.SPRINT_SPEED, 0.0001, "the body and the clip agree on the speed")
	approx(Mech.sprint_rate(14.0), 1.0, 0.0001, "full rate at the sprint speed")
	approx(Mech.sprint_rate(10.5), 0.75, 0.0001, "three quarter rate at three quarters the speed")
	approx(Mech.sprint_rate(7.0), 0.5, 0.0001, "the walk speed's share at the walk")
	approx(Mech.sprint_rate(0.0), 0.5, 0.0001, "never slower than that")
	approx(Mech.sprint_rate(30.0), 1.0, 0.0001, "never faster than authored")
	# A planted foot then moves back through the mech at exactly the body's speed.
	for v in [7.0, 9.0, 12.0, 14.0]:
		approx(MechSprint.SPRINT_SPEED * Mech.sprint_rate(v), v, 0.0001, "no skate at %s m/s" % v)

# --- movement and the rest ----------------------------------------------------------

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

# An in-tree mech, so _ready has run: the sprint clip is built, MechVfx is added.
func _live() -> Node3D:
	var exia: Node3D = MechScene.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(exia)
	_live_mechs.append(exia)
	return exia

func test_the_mech_gets_the_sprint_clip() -> void:
	var exia := _live()
	var ap: AnimationPlayer = exia.anim_player
	check(ap.has_animation("MECH_sprint"), "_ready adds MECH_sprint to the player")
	eq(ap.get_animation("MECH_sprint").loop_mode, Animation.LOOP_LINEAR, "it loops")
	check(not exia.travel_curves.has("MECH_sprint"),
		"the sprint is not split for root motion - the body supplies the 14 m/s")

func test_the_toggle_flips_on_sprint_and_clears_on_walk() -> void:
	var exia := _live()
	exia._update_sprint_toggle(true, true, 7.0, true, false)
	check(exia.sprint_toggled, "sprint turns it on")
	exia._update_sprint_toggle(true, true, 7.0, true, false)
	check(not exia.sprint_toggled, "sprint again turns it off")
	exia._update_sprint_toggle(true, true, 7.0, true, false)
	exia._update_sprint_toggle(true, true, 7.0, false, true)
	check(not exia.sprint_toggled, "walk clears it")

func test_a_complete_stop_clears_the_toggle_but_a_press_while_standing_survives() -> void:
	var exia := _live()
	exia._update_sprint_toggle(true, true, 7.0, true, false)
	check(exia.sprint_toggled, "sprinting")
	exia._update_sprint_toggle(true, false, 0.0, false, false)
	check(not exia.sprint_toggled, "on the floor, at rest, no key held: the toggle clears")
	# A press made while standing still is the commonest way to start a run: the stop edge is
	# spent, so it must not eat the press.
	exia._update_sprint_toggle(true, false, 0.0, true, false)
	check(exia.sprint_toggled, "a press at a standstill is kept")
	exia._update_sprint_toggle(true, false, 0.0, false, false)
	check(exia.sprint_toggled, "and holding still after it does not clear it again")
	exia._update_sprint_toggle(true, true, 7.0, false, false)
	exia._update_sprint_toggle(true, false, 0.0, false, false)
	check(not exia.sprint_toggled, "a fresh stop clears it again")

func test_the_toggle_survives_the_air_and_a_held_key() -> void:
	var exia := _live()
	exia._update_sprint_toggle(true, true, 7.0, true, false)
	exia._update_sprint_toggle(false, false, 0.0, false, false)
	check(exia.sprint_toggled, "in the air it has not stopped")
	exia._update_sprint_toggle(true, true, 0.0, false, false)
	check(exia.sprint_toggled, "against a wall with a key held it is still being asked for")

func test_getting_out_clears_the_toggle() -> void:
	var exia := _live()
	exia.sprint_toggled = true
	var pilot := _StubPilot.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(pilot)
	_live_mechs.append(pilot)
	exia.pilot = pilot
	exia._exit_mech()
	check(not exia.sprint_toggled, "exiting clears the sprint")

func _simulate(sprinting: bool, speed: float, seconds: float) -> float:
	var steps := int(round(seconds * 60.0))
	for i in steps:
		var step: Vector2 = Mech.speed_target(sprinting, speed, 7.0)
		speed = move_toward(speed, step.x, step.y / 60.0)
	return speed

func test_the_walk_ramps_to_14_in_half_a_second() -> void:
	approx(_simulate(true, 7.0, 0.5), 14.0, 0.01, "7 to 14 m/s in 0.5 s")
	check(_simulate(true, 7.0, 0.45) < 13.5, "and not before")

func test_a_standing_sprint_is_the_walk_start_and_then_the_ramp() -> void:
	var step: Vector2 = Mech.speed_target(true, 3.0, 7.0)
	approx(step.x, 7.0, 0.0001, "below the walk speed a sprint still heads for the walk speed first")
	approx(step.y, 7.0, 0.0001, "at the walk start's own rate")

func test_dropping_the_sprint_eases_back_to_7_in_a_quarter_second() -> void:
	approx(_simulate(false, 14.0, 0.25), 7.0, 0.01, "14 to 7 m/s in 0.25 s")

func test_letting_go_of_a_sprint_brakes_to_zero_in_a_quarter_second() -> void:
	var speed := 14.0
	for i in 15:
		speed = move_toward(speed, 0.0, Mech.brake_rate() / 60.0)
	approx(speed, 0.0, 0.01, "a sprint is stopped in 0.25 s")
	approx(Mech.brake_rate(), 56.0, 0.0001, "14 m/s over 0.25 s")

func test_below_the_walk_speed_the_stop_is_still_instant() -> void:
	# The no-input branch only brakes above SPEED or while already braking, so a walk's stop is the
	# old instant one. A walk keeps its own start rate.
	eq(Mech.speed_target(false, 5.0, 7.0), Vector2(7.0, 7.0), "a walk keeps the walk's own rate")
	check(5.0 <= Mech.SPEED, "5 m/s is below the braking threshold")

func test_the_turn_rate_is_4_at_a_sprint_and_10_at_a_walk() -> void:
	approx(Mech.turn_rate(14.0), 4.0, 0.0001, "sprint turn rate")
	approx(Mech.turn_rate(7.0), 10.0, 0.0001, "walk turn rate")
	approx(Mech.turn_rate(0.0), 10.0, 0.0001, "standing turn rate")
	var mid := Mech.turn_rate(10.5)
	check(mid > 4.0 and mid < 10.0, "blended by speed in between")

func test_the_bank_leans_into_a_left_turn_and_caps_at_12_degrees() -> void:
	# A left turn is a positive yaw rate (+Y takes the nose +Z towards +X, the mech's left), and a
	# left lean is a negative roll about the nose.
	check(Mech.bank_target(14.0, 1.0) < 0.0, "a left turn rolls negative")
	check(Mech.bank_target(14.0, -1.0) > 0.0, "a right turn rolls positive")
	approx(rad_to_deg(Mech.bank_target(14.0, 10.0)), -12.0, 0.0001, "capped at 12 degrees")
	approx(Mech.bank_target(0.0, 5.0), 0.0, 0.0001, "no bank standing still")
	# 14 m/s on a 12 m circle is a yaw rate of 14 / 12.
	approx(rad_to_deg(Mech.bank_target(14.0, 14.0 / 12.0)), -12.0, 0.01,
		"full lean at 14 m/s on a 12 m circle")

func test_the_bank_composes_with_the_models_yaw() -> void:
	var exia := _live()
	var rest: Transform3D = exia._model_rest
	exia.bank = 0.2
	exia._update_bank(0.0001, false, 0.0)
	var banked: Transform3D = exia.model.transform
	var roll := Basis(Vector3(0.0, 0.0, 1.0), exia.bank)
	check((roll.inverse() * banked.basis).is_equal_approx(rest.basis),
		"the bank rides on top of the authored transform, it does not replace it")
	check((roll * Vector3(0.0, 0.0, 1.0)).is_equal_approx(Vector3(0.0, 0.0, 1.0)),
		"the roll axis is the mech's nose")
	exia.bank = 0.0
	exia._update_bank(0.016, false, 0.0)
	check(exia.model.transform.is_equal_approx(rest), "with no bank the model is exactly as authored")

func test_clip_for_picks_the_sprint_only_above_the_walk() -> void:
	eq(Mech.clip_for(true, true, true, "MECH_walk", true), "MECH_sprint", "fast: the run")
	eq(Mech.clip_for(true, true, true, "MECH_sprint", true), "", "already running: leave it")
	eq(Mech.clip_for(true, true, true, "MECH_sprint", false), "MECH_walk",
		"slowed back to the walk: the walk loop")
	eq(Mech.clip_for(true, false, true, "MECH_sprint", false), "MECH_standing",
		"let go: stand")
	eq(Mech.clip_for(true, true, false, "MECH_standing", false), "MECH_walk_start",
		"the existing chains are unchanged below the walk speed")
	eq(Mech.clip_for(true, true, true, "MECH_walk", false), "", "walk holds")

func test_the_crossfades() -> void:
	# Short: two clips blending is where the feet slide.
	approx(Mech.blend_for("MECH_walk", "MECH_sprint"), 0.15, 0.0001, "walk to sprint")
	approx(Mech.blend_for("MECH_walk_start", "MECH_sprint"), 0.15, 0.0001, "walk start to sprint")
	approx(Mech.blend_for("MECH_sprint", "MECH_walk"), 0.15, 0.0001, "sprint to walk")
	approx(Mech.blend_for("MECH_sprint", "MECH_standing"), 0.15, 0.0001, "sprint to a stop")
	approx(Mech.blend_for("MECH_standing", "MECH_walk_start"), 0.0, 0.0001,
		"every existing transition still cuts")

func test_the_fov_widens_by_ten_while_sprinting() -> void:
	approx(Mech.fov_boost_target(14.0), 10.0, 0.0001, "sprinting")
	approx(Mech.fov_boost_target(7.0), 0.0, 0.0001, "walking")
	approx(Mech.fov_boost_target(0.0), 0.0, 0.0001, "standing")

func test_the_camera_offsets_are_zero_with_camera_motion_off() -> void:
	Settings.set_value(&"camera_motion", "off")
	var exia := _live()
	exia._on_footfall(0)
	approx(exia._dip, 0.0, 0.0, "no dip")
	check(exia._shake_age == INF, "no shake")
	exia._step_bound_camera(0.016)
	approx(exia._bounce, 0.0, 0.0, "no bounce")
	Settings.set_value(&"camera_motion", "on")
	exia._on_footfall(0)
	approx(exia._dip, -Mech.FOOTFALL_DIP, 0.0001, "the footfall dips the camera 0.25 m")
	check(exia._shake_age == 0.0, "and starts the shake")
	for i in 30:
		exia._step_bound_camera(1.0 / 60.0)
	approx(exia._dip, 0.0, 0.01, "the dip settles in about half a second")
	check(Mech.shake_offset(Mech.FOOTFALL_SHAKE_TIME) == Vector2.ZERO, "the shake decays to zero")
	check(Mech.shake_offset(0.0).length() <= deg_to_rad(Mech.FOOTFALL_SHAKE_DEG) * 1.5,
		"and starts within 0.6 degrees")

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
func test_every_clip_keys_every_bone_the_run_moves() -> void:
	var exia := _live()
	var ap: AnimationPlayer = exia.anim_player
	var sprint := ap.get_animation("MECH_sprint")
	for clip_name in ap.get_animation_list():
		if clip_name == "MECH_sprint":
			continue
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
	ap.play("MECH_walk")
	ap.seek(0.5, true)
	check(absf(sk.get_bone_pose_rotation(plate).dot(stand_q)) > 0.99999,
		"and the walk holds it at standing too")
