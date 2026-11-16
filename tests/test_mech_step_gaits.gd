extends "res://tests/test_case.gd"

# EXIA's strafe, back walk and diagonal clips. See docs/specs/exia-aim-control.md, "The new clips".
#
# Built on the real imported skeleton with MechMoves.build_all and sampled with the tree-free sampler,
# like test_mech_gait.gd. How they LOOK is tests/_probe_mech_moves.gd and a play session.

const MechScene := preload("res://scenes/mech.tscn")
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

func _steps() -> Array:
	return [MechGait.strafe(true), MechGait.strafe(false), MechGait.back(),
		MechGait.back(-MechMoves.DIAGONAL_DEG), MechGait.back(MechMoves.DIAGONAL_DEG)]

func _origin(clip: String, bone: String, t: float) -> Vector3:
	_rig()
	return MechGait.pose_at(_skeleton, _clips[clip], t)[_skeleton.find_bone(bone)].origin

func _ball(clip: String, side: String, t: float) -> Vector3:
	return _origin(clip, "toe" + side + ".001", t)

func _plate_tip(clip: String, side: String, t: float) -> Vector3:
	_rig()
	var ball: Transform3D = MechGait.pose_at(_skeleton, _clips[clip], t)[_skeleton.find_bone("toe" + side + ".001")]
	return ball.origin + ball.basis.y.normalized() * MechGait.plate_vector(_ctx, side).length()

# The travel direction of a step gait in mech space (x, z), with its diagonal's yaw applied.
func _travel(g) -> Vector2:
	var v := Vector3(g.dir.x, 0.0, g.dir.y).rotated(Vector3.UP, deg_to_rad(g.leg_yaw))
	return Vector2(v.x, v.z)

func test_every_new_clip_is_built_and_loops_at_its_length() -> void:
	_rig()
	for g in _steps():
		check(_clips.has(g.clip), "%s built" % g.clip)
		eq(_clips[g.clip].loop_mode, Animation.LOOP_LINEAR, "%s loops" % g.clip)
		approx(_clips[g.clip].length, g.length, 0.0001, "%s one cycle long" % g.clip)
	for name in ["MECH_run_diag_L", "MECH_run_diag_R", "MECH_sprint_diag_L", "MECH_sprint_diag_R"]:
		check(_clips.has(name), "%s built" % name)
		eq(_clips[name].loop_mode, Animation.LOOP_LINEAR, "%s loops" % name)

func test_the_speeds_are_the_grilled_numbers() -> void:
	approx(MechGait.strafe(true).speed, 6.0, 0.0001, "strafe 6 m/s")
	approx(MechGait.back().speed, 5.0, 0.0001, "back 5 m/s")
	approx(MechGait.back(45.0).speed, 5.5, 0.0001, "back diagonal 5.5 m/s")

func test_a_planted_ball_slides_against_the_travel_at_the_gait_speed() -> void:
	_rig()
	for g in _steps():
		var travel := _travel(g)
		for side in [".L", ".R"]:
			var start: float = 0.0 if side == ".L" else g.length * 0.5
			# Mid-stance, where the plate is flat: the ball is the contact.
			for w in [0.3, 0.45, 0.6]:
				var t: float = start + w * g.contact
				var dt := 1.0 / 240.0
				var a := _ball(g.clip, side, t)
				var b := _ball(g.clip, side, t + dt)
				var v := Vector2(b.x - a.x, b.z - a.z) / dt
				approx(v.dot(travel), -g.speed, g.speed * 0.05,
					"%s %s planted: slides back along the travel at %s (%s)" % [g.clip, side, g.speed, w])
				approx(v.dot(Vector2(-travel.y, travel.x)), 0.0, g.speed * 0.05,
					"%s %s planted: no sideways slip (%s)" % [g.clip, side, w])
				check(a.y < _ctx.floor_y + 0.05, "%s %s on the floor mid-stance" % [g.clip, side])

func test_no_foot_goes_through_the_floor() -> void:
	_rig()
	for g in _steps():
		for i in int(round(g.length * 30.0)):
			for side in [".L", ".R"]:
				var low := minf(_ball(g.clip, side, i / 30.0).y, _plate_tip(g.clip, side, i / 30.0).y)
				check(low - _ctx.floor_y > -0.02, "%s %s above the floor at key %d" % [g.clip, side, i])

func test_the_swing_foot_lifts() -> void:
	_rig()
	for g in _steps():
		# Half way through the left's swing.
		var cf: float = g.contact / g.length
		var t: float = (cf + (1.0 - cf) * 0.5) * g.length
		check(_ball(g.clip, ".L", t).y - _ctx.floor_y > g.lift * 0.6, "%s: L up mid-swing" % g.clip)

func test_the_strafe_legs_never_cross() -> void:
	_rig()
	for left in [true, false]:
		var g = MechGait.strafe(left)
		var closest := INF
		for i in int(round(g.length * 30.0)) * 2:
			var t := i / 60.0
			closest = minf(closest, _ball(g.clip, ".L", t).x - _ball(g.clip, ".R", t).x)
		check(closest > 1.4, "%s: the balls stay %.2f m apart at the closest" % [g.clip, closest])

func test_the_legs_never_go_out_of_reach() -> void:
	_rig()
	for g in _steps():
		var keys := int(round(g.length * 30.0))
		for i in keys:
			var u := float(i) / keys
			var solved: Dictionary = MechGait.pose_from(_ctx, MechGait.step_gait_spec(_ctx, g, u))
			for thigh in ["thigh.L", "thigh.R"]:
				var ball := _ball(g.clip, thigh.right(2), u * g.length)
				var off := ball.distance_to(solved.balls[thigh])
				check(off < 0.02, "%s %s reaches its ball at key %d (off %f)" % [g.clip, thigh, i, off])
	for g in [MechGait.run(), MechGait.sprint()]:
		for deg in [45.0, -45.0]:
			var keys := int(round(g.length * 30.0))
			for i in keys:
				var u := float(i) / keys
				var spec := MechGait.diagonal(MechGait.gait_spec(_ctx, g, u), deg)
				var solved: Dictionary = MechGait.pose_from(_ctx, spec)
				var clip := MechGait.diagonal_clip(g, ".L" if deg > 0.0 else ".R")
				for thigh in ["thigh.L", "thigh.R"]:
					var off := _ball(clip, thigh.right(2), u * g.length).distance_to(solved.balls[thigh])
					check(off < 0.02, "%s %s reaches its ball at key %d (off %f)" % [clip, thigh, i, off])

# The point of the diagonal: the legs run along the 45 deg line while the chest stays on the nose.
func test_a_diagonal_runs_its_legs_at_45_and_keeps_the_chest_on_the_nose() -> void:
	_rig()
	var stand: Array[Transform3D] = MechGait.pose_at(_skeleton, _standing, 0.0)
	var chest := _skeleton.find_bone("spine.001")
	for g in [MechGait.run(), MechGait.sprint()]:
		for side in [".L", ".R"]:
			var clip := MechGait.diagonal_clip(g, side)
			var deg := 45.0 if side == ".L" else -45.0
			var travel := Vector2(sin(deg_to_rad(deg)), cos(deg_to_rad(deg)))
			# The left ball mid-stance: it slides back along the travel line.
			var t: float = 0.3 * g.contact
			var dt := 1.0 / 240.0
			var a := _ball(clip, ".L", t)
			var b := _ball(clip, ".L", t + dt)
			var v := Vector2(b.x - a.x, b.z - a.z) / dt
			approx(v.dot(travel), -g.speed, g.speed * 0.05, "%s: the planted ball slides along the 45" % clip)
			approx(v.dot(Vector2(-travel.y, travel.x)), 0.0, g.speed * 0.05, "%s: and not across it" % clip)
			# The chest's forward axis, flattened, against the straight clip's at the same time.
			var straight: Transform3D = MechGait.pose_at(_skeleton, _clips[g.clip], t)[chest]
			var diag: Transform3D = MechGait.pose_at(_skeleton, _clips[clip], t)[chest]
			var f0 := Vector2(straight.basis.z.x, straight.basis.z.z).normalized()
			var f1 := Vector2(diag.basis.z.x, diag.basis.z.z).normalized()
			check(rad_to_deg(absf(f0.angle_to(f1))) < 1.0,
				"%s: the chest faces where the straight clip's does (%.2f deg off)"
				% [clip, rad_to_deg(absf(f0.angle_to(f1)))])
	# And the back diagonals' chests face the nose too.
	for clip in ["MECH_back_diag_L", "MECH_back_diag_R"]:
		var straight: Transform3D = MechGait.pose_at(_skeleton, _clips["MECH_back"], 0.2)[chest]
		var diag: Transform3D = MechGait.pose_at(_skeleton, _clips[clip], 0.2)[chest]
		var f0 := Vector2(straight.basis.z.x, straight.basis.z.z).normalized()
		var f1 := Vector2(diag.basis.z.x, diag.basis.z.z).normalized()
		check(rad_to_deg(absf(f0.angle_to(f1))) < 1.0, "%s: the chest stays on the nose" % clip)
	check(stand.size() > 0, "rig sampled")

func test_the_standing_spec_still_gives_the_standing_pose() -> void:
	# The new foot x and leg yaw fields default to the standing pose.
	_rig()
	var spec := MechGait.standing_spec(_ctx)
	approx(spec.leg_yaw, 0.0, 0.0, "no leg yaw standing")
	for side in [".L", ".R"]:
		approx(spec.feet[side].x, _ctx.g0[_skeleton.find_bone("toe" + side + ".001")].origin.x, 0.0001,
			"%s ball x is the rig's" % side)
