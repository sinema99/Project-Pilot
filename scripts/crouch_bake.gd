extends RefCounted

## pilot9's crouch, generated in code (2026-11-15): the right-knee-down rifle kneel he holds when
## crouched and still, and the four Arma-style crouch-jog cycles he strafes on when crouched and
## moving. See docs/specs/pilot9-crouch-kneel.md.
##
## Hips and legs only. Every clip keys the Hips position, a Hips rotation held at the idle's own
## first key, and UpperLeg / LowerLeg / Foot on both sides - nothing above the hips, so the crouch
## state plays them through a filter over the standing idle and the spine, head, arms and the gun
## stay exactly the idle's.
##
## Skeleton space throughout: +Y up, +Z his forward, +X his LEFT (pilot9's mesh faces its own +Z).
## Rotations are written the way RC's clips write them - absolute local rotations, not deltas
## from rest - and solved against the rest pose of the skeleton they are baked for.

## The kneel's rear (down) knee joint above the ground, metres. The shin's own thickness keeps
## the box off the floor; much lower and the knee sinks in.
const KNEEL_KNEE_HEIGHT := 0.085
## The rear thigh's lean back from vertical, degrees - how far he sits back toward the heel. This
## is what sets the kneel's depth. 2026-11-15 rev 2 (user's Arma reference): 10 deg, the knee almost
## straight under the hip and the kneel tall - was 42 (hips ~0.44 m under the idle's, legs splayed).
const KNEEL_THIGH_BACK := 10.0
## The rear knee pulled in toward his centreline from under its hip, metres. Rev 2: the legs stay
## close together like the reference instead of splaying (was 0.04 OUT).
const KNEEL_KNEE_IN := 0.05
## The rear foot pitched toes-down (toes curled under, heel up), degrees.
const KNEEL_REAR_FOOT_PITCH := 60.0
## The front (left) foot ahead of its hip, metres, pulled in toward his centreline, metres, and
## turned out, degrees. Rev 2: about a thigh's length ahead so the front shin stands vertical, foot
## straight ahead, in toward the middle (was 0.03 out, 10 deg turned out).
const KNEEL_FRONT_REACH := 0.46
const KNEEL_FRONT_IN := 0.03
const KNEEL_FRONT_TOE_OUT := 3.0
## Hips forward of the idle's, metres: centres him over the knee-to-foot base.
const KNEEL_HIPS_FORWARD := 0.0

## Ground speed the cycles are authored at, m/s (pilot9's crouch_speed when they were made). The
## state's TimeScale is ground speed / this, so the planted foot never skates.
const DESIGN_SPEED := 2.5
## One cycle, two steps, seconds. 0.6 s is RC's own run cycle: ~3.3 steps a second.
const CYCLE := 0.58
## Fraction of the cycle each foot is planted. Under 0.5: a jog with a float between steps. Short
## on purpose - see JOG_FOOT_AHEAD.
const STANCE := 0.55
## The jog's Hips below the idle's, metres. The grill asked for 0.40; on this rig that is the
## floor: with the planted foot behind him the thigh hangs straight down, the knee sits at hip
## height minus the thigh (0.51 m), and at 0.40 it scrapes the ground. 0.36 with the stride
## shifted ahead (below) keeps the knee joint ~0.1 m clear at its lowest - measured, 2026-11-15.
const JOG_HIPS_DROP := 0.22
## Where the planted foot's travel is centred, ahead of the hip joint, metres. Rev 2 (2026-11-15):
## 0.25 -> 0.18, the hips sat back over his heels so the knees stop jutting out ahead like he is
## sat on a stool; the runtime lean (scripts/crouch_lean.gd) puts his chest over his feet. The grill
## asked for 0.1 m back (0.15); that put the back jog's trailing knee 0.08 m off the floor, under the
## test's 0.1 m - 0.18 is the most it takes and keeps clear.
const JOG_FOOT_AHEAD := 0.2
## Hips forward of the idle's in the jog, metres - the weight over the toes of a crouch run.
const JOG_HIPS_FORWARD := 0.04
## The jog's pelvis pitched forward, degrees: the hip hinge of a crouch walk. The legs are solved
## against it, so the feet land where they did; everything above the hips tips with it.
## scripts/crouch_lean.gd adds the rest on the spine and takes this back out while aiming.
const JOG_HIPS_PITCH := 32.0
## Peak swing-foot lift, metres.
const SWING_LIFT := 0.14
## Vertical bob (lowest at each mid-stance) and side sway toward the planted foot, metres.
const BOB := 0.02
const SWAY := 0.025
## Feet either side of centre, metres, and how far the sideways cycles stagger them fore/aft so the
## swinging leg passes the planted one instead of going through it.
const FOOT_SPREAD := 0.13
const SIDE_STAGGER := 0.12
## Forward cycle's foot roll: toes up at touchdown, heel up at toe-off, degrees.
const HEEL_STRIKE_PITCH := 12.0
const TOE_OFF_PITCH := 35.0
## Every other cycle: toes dropped mid-swing, degrees.
const SWING_TOE_DROP := 12.0
## Foot length in front of the Foot bone's origin, metres. pilot9's Foot bone sits at the heel, so
## pitching toes-down lifts the origin by this x sin(pitch) to keep the toes on the ground.
const FOOT_FRONT := 0.13
const FPS := 30.0

const SIDES := ["Left", "Right"]
const PREFIX := "%GeneralSkeleton:"
## The legs' bones these clips key (with the Hips position).
const LEG_BONES := ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot"]
## The arms, keyed by add_arms(): the run clip's arm pump in the jog, the idle's arms in the kneel.
const ARM_BONES := ["LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
## Every bone these clips key. The crouch state's filter is exactly this list.
const BONES := LEG_BONES + ARM_BONES
## How much of the run's arm pump each jog direction gets (0 = the idle's arms).
## Rev 4: a little only - the user's DayZ reference has the arms hanging, barely swinging.
const ARM_SWING := {&"crouch_jog_forward": 0.25, &"crouch_jog_back": 0.2,
	&"crouch_jog_left": 0.12, &"crouch_jog_right": 0.12}

## Library names, travel direction (skeleton space) and blend-space position (RC's convention:
## +x = his right, +y = forward).
const JOGS := {
	&"crouch_jog_forward": {dir = Vector3(0, 0, 1), at = Vector2(0, 1)},
	&"crouch_jog_back": {dir = Vector3(0, 0, -1), at = Vector2(0, -1)},
	&"crouch_jog_left": {dir = Vector3(1, 0, 0), at = Vector2(-1, 0)},
	&"crouch_jog_right": {dir = Vector3(-1, 0, 0), at = Vector2(1, 0)},
}
const KNEEL := &"crouch_kneel"


## Everything the solve needs from the skeleton and the idle, measured once. Empty on a rig that
## is missing a bone or an idle without a Hips track.
static func rig(skel: Skeleton3D, idle: Animation) -> Dictionary:
	for b in BONES:
		if skel.find_bone(b) < 0:
			return {}
	var hp := idle.find_track(NodePath(PREFIX + "Hips"), Animation.TYPE_POSITION_3D)
	var hr := idle.find_track(NodePath(PREFIX + "Hips"), Animation.TYPE_ROTATION_3D)
	if hp < 0 or hr < 0:
		return {}
	var r := {
		hips_pos = idle.position_track_interpolate(hp, 0.0),
		hips_rot = idle.rotation_track_interpolate(hr, 0.0).normalized(),
	}
	for side in SIDES:
		var ul := skel.find_bone(side + "UpperLeg")
		var ll := skel.find_bone(side + "LowerLeg")
		var ft := skel.find_bone(side + "Foot")
		var g_ul := skel.get_bone_global_rest(ul)
		var g_ll := skel.get_bone_global_rest(ll)
		var g_ft := skel.get_bone_global_rest(ft)
		r[side] = {
			offset = skel.get_bone_rest(ul).origin,
			l1 = g_ul.origin.distance_to(g_ll.origin),
			l2 = g_ll.origin.distance_to(g_ft.origin),
			ul = g_ul.basis.orthonormalized(),
			ll = g_ll.basis.orthonormalized(),
			ft = g_ft.basis.orthonormalized(),
			d_ul = (g_ll.origin - g_ul.origin).normalized(),
			d_ll = (g_ft.origin - g_ll.origin).normalized(),
		}
	r.ground = _idle_ground(skel, idle, r)
	return r


## The Foot origin's height when he stands in the idle: the bake's ground. Read off the idle rather
## than assumed, so the crouch sinks his feet exactly as far as standing does.
static func _idle_ground(skel: Skeleton3D, idle: Animation, r: Dictionary) -> float:
	var sum := 0.0
	var hips := Transform3D(Basis(r.hips_rot), r.hips_pos)
	for side in SIDES:
		var xf := hips
		for b in ["UpperLeg", "LowerLeg", "Foot"]:
			var bone := skel.find_bone(side + b)
			var t := idle.find_track(NodePath(PREFIX + side + b), Animation.TYPE_ROTATION_3D)
			var q := idle.rotation_track_interpolate(t, 0.0) if t >= 0 \
				else skel.get_bone_rest(bone).basis.get_rotation_quaternion()
			xf = xf * Transform3D(Basis(q), skel.get_bone_rest(bone).origin)
		sum += xf.origin.y
	return sum * 0.5


## The kneel: right knee on the ground, left foot planted ahead, both still.
static func kneel(r: Dictionary) -> Animation:
	var hb := Basis(r.hips_rot)
	var R: Dictionary = r.Right
	var L: Dictionary = r.Left
	# The rear knee fixes the hips' height: the knee on the ground, the thigh leaning back.
	var back := deg_to_rad(KNEEL_THIGH_BACK)
	var hip_off: Vector3 = hb * R.offset
	var hips_y: float = r.ground + KNEEL_KNEE_HEIGHT + R.l1 * cos(back) - hip_off.y
	var hips := Vector3(r.hips_pos.x, hips_y, r.hips_pos.z + KNEEL_HIPS_FORWARD)

	var h_r: Vector3 = hips + hip_off
	# Right is -X, so in toward the middle is +X.
	var knee := h_r + Vector3(KNEEL_KNEE_IN, -R.l1 * cos(back), -R.l1 * sin(back))
	knee.y = r.ground + KNEEL_KNEE_HEIGHT
	# The shin lies back along the ground to an ankle lifted by the pitched foot.
	var pitch := deg_to_rad(KNEEL_REAR_FOOT_PITCH)
	var ankle_y: float = r.ground + FOOT_FRONT * sin(pitch)
	var drop: float = knee.y - ankle_y
	var run := sqrt(maxf(R.l2 * R.l2 - drop * drop, 0.0))
	var ankle := knee + Vector3(0.0, -drop, -run)
	var right := _fk_leg(R, hb, h_r, knee, ankle, Basis(Vector3.RIGHT, pitch))

	var h_l: Vector3 = hips + hb * L.offset
	var foot := Vector3(h_l.x - KNEEL_FRONT_IN, r.ground, h_l.z + KNEEL_FRONT_REACH)
	var left := _ik_leg(L, hb, h_l, foot, Vector3(0.0, 0.3, 1.0).normalized(),
		Basis(Vector3.UP, deg_to_rad(KNEEL_FRONT_TOE_OUT)))

	var anim := _new_anim(KNEEL, 1.0)
	for t in [0.0, 1.0]:
		_key(anim, t, hips, r.hips_rot, {Left = left, Right = right})
	return anim


## One crouch-jog cycle travelling `dir` (skeleton space, unit, horizontal).
static func jog(r: Dictionary, name: StringName, dir: Vector3) -> Animation:
	var hips_rot: Quaternion = (Basis(Vector3.RIGHT, deg_to_rad(JOG_HIPS_PITCH)) * Basis(r.hips_rot)) 		.get_rotation_quaternion()
	var hb := Basis(hips_rot)
	var anim := _new_anim(name, CYCLE)
	var n := int(round(CYCLE * FPS))
	var half := DESIGN_SPEED * CYCLE * STANCE * 0.5   # a planted foot's travel either side of neutral
	var forward := dir.z > 0.5
	var sideways := absf(dir.x) > 0.5
	for i in n + 1:
		var t := CYCLE * float(i) / float(n)
		var p := t / CYCLE
		var hips := Vector3(r.hips_pos.x, r.hips_pos.y - JOG_HIPS_DROP, r.hips_pos.z + JOG_HIPS_FORWARD)
		# Lowest at each mid-stance (left at p = STANCE/2, right half a cycle later), swaying
		# over whichever foot is down.
		var mid := STANCE * 0.5
		hips.y -= BOB * cos(TAU * 2.0 * (p - mid))
		hips.x += SWAY * cos(TAU * (p - mid))
		var legs := {}
		for side in SIDES:
			var S: Dictionary = r[side]
			var side_sign := 1.0 if side == "Left" else -1.0
			var f := fposmod(p + (0.0 if side == "Left" else 0.5), 1.0)
			# Fixed in skeleton space, not riding the sway: the skeleton itself is what travels.
			var neutral := Vector3(side_sign * FOOT_SPREAD, r.ground,
				r.hips_pos.z + JOG_HIPS_FORWARD + (hb * S.offset).z + JOG_FOOT_AHEAD)
			if sideways:
				neutral.z += side_sign * SIDE_STAGGER
			var along: float
			var lift := 0.0
			var pitch := 0.0   # toes-down positive
			if f < STANCE:
				var u := f / STANCE
				along = lerpf(half, -half, u)
				if forward:
					pitch = -HEEL_STRIKE_PITCH * (1.0 - smoothstep(0.0, 0.25, u)) \
						+ TOE_OFF_PITCH * smoothstep(0.6, 1.0, u)
			else:
				var u := (f - STANCE) / (1.0 - STANCE)
				along = lerpf(-half, half, smoothstep(0.0, 1.0, u))
				# Peaks early: the heel kicks up behind him off the toe-off instead of the shin
				# dragging flat along the floor while the knee comes through.
				lift = SWING_LIFT * sin(PI * pow(u, 0.6))
				if forward:
					# Heel-up off the toe-off, toes rising for the next touchdown.
					pitch = lerpf(TOE_OFF_PITCH, -HEEL_STRIKE_PITCH, smoothstep(0.0, 0.8, u))
				else:
					pitch = SWING_TOE_DROP * sin(PI * u)
			var foot := neutral + dir * along + Vector3(0.0, lift, 0.0)
			# The Foot origin is the heel: pitching the toes down lifts it to keep them up.
			foot.y += FOOT_FRONT * sin(deg_to_rad(maxf(pitch, 0.0)))
			var h: Vector3 = hips + hb * S.offset
			legs[side] = _ik_leg(S, hb, h, foot, Vector3(side_sign * 0.15, 0.0, 1.0).normalized(),
				Basis(Vector3.RIGHT, deg_to_rad(pitch)))
		_key(anim, t, hips, hips_rot, legs)
	return anim


## Two-bone IK: hip joint `h`, ankle target `a`, knee bending toward `pole`. Unreachable targets
## are pulled in along the hip-ankle line.
static func _ik_leg(S: Dictionary, hb: Basis, h: Vector3, a: Vector3, pole: Vector3,
		foot_turn: Basis) -> Dictionary:
	var l1: float = S.l1
	var l2: float = S.l2
	var to := a - h
	var dist := clampf(to.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var d := to.normalized()
	var cos_a := (l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist)
	var sin_a := sqrt(maxf(1.0 - cos_a * cos_a, 0.0))
	var perp := (pole - d * pole.dot(d)).normalized()
	var knee := h + (d * cos_a + perp * sin_a) * l1
	return _fk_leg(S, hb, h, knee, h + d * dist, foot_turn)


## The leg's three local rotations for a hip joint `h`, knee `k` and ankle `a` (k and a already at
## the bone lengths), the foot turned by `foot_turn` from its rest (flat, toes forward).
static func _fk_leg(S: Dictionary, hb: Basis, h: Vector3, k: Vector3, a: Vector3,
		foot_turn: Basis) -> Dictionary:
	var d_ul := (k - h).normalized()
	var d_ll := (a - k).normalized()
	# The knee's hinge. +X with the knee bent forward, the same as rest's slight forward bend.
	var hinge := d_ul.cross(d_ll)
	if hinge.length() < 0.01:
		hinge = Vector3.RIGHT
	hinge = hinge.normalized()
	var g_ul: Basis = _aim(S.d_ul, d_ul, hinge) * S.ul
	var g_ll: Basis = _aim(S.d_ll, d_ll, hinge) * S.ll
	var g_ft: Basis = foot_turn * S.ft
	return {
		ul = (hb.inverse() * g_ul).get_rotation_quaternion(),
		ll = (g_ul.inverse() * g_ll).get_rotation_quaternion(),
		ft = (g_ll.inverse() * g_ft).get_rotation_quaternion(),
		knee = k, ankle = a,
	}


## The rotation that carries a bone lying along `rest_dir` (hinge +X) onto `dir` with `hinge`.
static func _aim(rest_dir: Vector3, dir: Vector3, hinge: Vector3) -> Basis:
	return _frame(dir, hinge) * _frame(rest_dir, Vector3.RIGHT).inverse()


static func _frame(dir: Vector3, side: Vector3) -> Basis:
	var x := (side - dir * side.dot(dir)).normalized()
	return Basis(x, dir, x.cross(dir))


static func _new_anim(name: StringName, length: float) -> Animation:
	var anim := Animation.new()
	anim.resource_name = name
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR
	var t := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(t, NodePath(PREFIX + "Hips"))
	for b in LEG_BONES:
		t = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath(PREFIX + b))
	return anim


static func _key(anim: Animation, t: float, hips: Vector3, hips_rot: Quaternion, legs: Dictionary) -> void:
	anim.position_track_insert_key(0, t, hips)
	_rot_key(anim, 1, t, hips_rot)
	var i := 2
	for side in SIDES:
		for part in ["ul", "ll", "ft"]:
			_rot_key(anim, i, t, legs[side][part])
			i += 1


## Keeps consecutive keys in one hemisphere, so the slerp between them takes the short way.
static func _rot_key(anim: Animation, track: int, t: float, q: Quaternion) -> void:
	var n := anim.track_get_key_count(track)
	if n > 0:
		var prev: Quaternion = anim.track_get_key_value(track, n - 1)
		if prev.dot(q) < 0.0:
			q = -q
	anim.rotation_track_insert_key(track, t, q)


## Keys the arms onto a baked crouch clip. The jog gets the run clip's arm pump (`run`, one cycle of
## two steps) re-timed onto its own cycle, phased so each arm swings forward with the opposite leg,
## mixed `amount` of the way from the idle's arms. With `run` null (the kneel) it holds the idle's.
static func add_arms(skel: Skeleton3D, anim: Animation, idle: Animation, run: Animation,
		amount: float) -> void:
	var phase := _left_contact(skel, run) if run != null else 0.0
	var n := int(round(anim.length * FPS)) if run != null else 1
	for b in ARM_BONES:
		var path := NodePath(PREFIX + b)
		var bone := skel.find_bone(b)
		if bone < 0:
			continue
		var it := idle.find_track(path, Animation.TYPE_ROTATION_3D)
		var rest := skel.get_bone_rest(bone).basis.get_rotation_quaternion()
		var still: Quaternion = idle.rotation_track_interpolate(it, 0.0) if it >= 0 else rest
		var rt := run.find_track(path, Animation.TYPE_ROTATION_3D) if run != null else -1
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, path)
		for i in n + 1:
			var t := anim.length * float(i) / float(n)
			var q := still
			if rt >= 0:
				var rtime := fposmod(phase + t / anim.length * run.length, run.length)
				q = still.slerp(run.rotation_track_interpolate(rt, rtime), amount)
			_rot_key(anim, track, t, q)


## When in `run` the left foot is furthest forward (its touchdown) - where the jog's own cycle
## starts - by forward kinematics on the clip's Hips and left leg.
static func _left_contact(skel: Skeleton3D, run: Animation) -> float:
	var best := 0.0
	var best_z := -INF
	var steps := 60
	for i in steps:
		var t := run.length * float(i) / float(steps)
		var xf := Transform3D.IDENTITY
		for b in ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]:
			var bone := skel.find_bone(b)
			var path := NodePath(PREFIX + b)
			var rt := run.find_track(path, Animation.TYPE_ROTATION_3D)
			var pt := run.find_track(path, Animation.TYPE_POSITION_3D)
			var q := run.rotation_track_interpolate(rt, t) if rt >= 0 				else skel.get_bone_rest(bone).basis.get_rotation_quaternion()
			var o := run.position_track_interpolate(pt, t) if pt >= 0 else skel.get_bone_rest(bone).origin
			xf = xf * Transform3D(Basis(q), o)
		if xf.origin.z > best_z:
			best_z = xf.origin.z
			best = t
	return best
