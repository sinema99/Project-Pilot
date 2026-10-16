extends RefCounted

## Turns RC's walk_forward into the tredge: a shorter stride, high knees through the swing and a
## slightly wider stance. Legs only - the hunch and the arms are the runtime pose layer
## (scripts/tredge_pose.gd). See docs/specs/pilot9-tredge.md, "The clip".
##
## Everything is a rotation on the clip's own keys, worked out against the skeleton's rest pose:
## no key is added, moved in time or removed, so the cycle keeps walk_forward's timing exactly.

const ARM_SWING := preload("res://scripts/arm_swing.gd")

## Fraction of the thigh's fore-aft swing kept. With the cycle played at 0.7x and 1.5 m/s that
## is walk's planted-foot speed, so the feet do not skate.
const STRIDE := 0.86
## Extra knee bend at the top of the swing, degrees.
const KNEE_EXTRA := 14.0
## Extra thigh lift at the top of the swing, degrees.
const HIP_EXTRA := 10.0
## Where the lift starts, as a fraction of the way from the knee's straightest key to its
## deepest. Stance never bends past ~28 deg on walk_forward (range 13-74), so a third keeps
## the planted foot untouched.
const LIFT_FROM := 0.33
## Each thigh turned outward the whole cycle, degrees: the wider stance.
const ABDUCT := 3.0

const SIDES := ["Left", "Right"]


## Bakes in place. `anim` is a deep copy of walk_forward; `skel` is pilot9's skeleton, whose rest
## pose the angles are measured against. Returns how many tracks were changed, 0 if the bones
## are missing.
static func bake(anim: Animation, skel: Skeleton3D) -> int:
	var hips := skel.find_bone(&"Hips")
	if hips < 0:
		return 0
	var parent_basis := skel.get_bone_global_rest(hips).basis.orthonormalized()

	# The knee's lift weight has to come from the authored knee, so read it before anything moves.
	var lift := {}
	for side in SIDES:
		var w := knee_lift(anim, skel, side)
		if w.is_empty():
			return 0
		lift[side] = w

	var touched := ARM_SWING.scale_swing(anim, [&"LeftUpperLeg", &"RightUpperLeg"], STRIDE)

	for side in SIDES:
		var info: Dictionary = lift[side]
		var ul := skel.find_bone(side + "UpperLeg")
		var ll := skel.find_bone(side + "LowerLeg")
		var ft := skel.find_bone(side + "Foot")
		var t_ul := _track(anim, side + "UpperLeg")
		var t_ll := _track(anim, side + "LowerLeg")
		var t_ft := _track(anim, side + "Foot")
		if ul < 0 or ll < 0 or ft < 0 or t_ul < 0 or t_ll < 0 or t_ft < 0:
			return 0
		var hinge: Vector3 = info.axis
		# The knee's hinge in skeleton space. Bending the knee turns the shin back about it, so
		# lifting the thigh is the opposite turn about the same line.
		var ll_rest := skel.get_bone_global_rest(ll).basis.orthonormalized()
		var g := (ll_rest * hinge).normalized()
		var hip_axis := (parent_basis.inverse() * g).normalized()
		# Outward: the axis that swings a leg hanging down toward its own side.
		var out := skel.get_bone_global_rest(ul).origin - skel.get_bone_global_rest(hips).origin
		out.y = 0.0
		var abduct_axis := Vector3.DOWN.cross(out.normalized())
		var abduct_p := (parent_basis.inverse() * abduct_axis).normalized()
		var abduct_foot := (ll_rest.inverse() * abduct_axis).normalized()

		for k in anim.track_get_key_count(t_ll):
			var w := lift_weight(info, knee_angle(info, anim.track_get_key_value(t_ll, k)))
			var q: Quaternion = anim.track_get_key_value(t_ll, k)
			anim.track_set_key_value(t_ll, k, (q * Quaternion(hinge, deg_to_rad(KNEE_EXTRA) * w)).normalized())
		for k in anim.track_get_key_count(t_ul):
			var w := lift_weight(info, info.angle_at.call(anim.track_get_key_time(t_ul, k)))
			var q: Quaternion = anim.track_get_key_value(t_ul, k)
			q = Quaternion(hip_axis, -deg_to_rad(HIP_EXTRA) * w) * q
			q = Quaternion(abduct_p, deg_to_rad(ABDUCT)) * q
			anim.track_set_key_value(t_ul, k, q.normalized())
		for k in anim.track_get_key_count(t_ft):
			var q: Quaternion = anim.track_get_key_value(t_ft, k)
			anim.track_set_key_value(t_ft, k, (Quaternion(abduct_foot, -deg_to_rad(ABDUCT)) * q).normalized())
		touched += 3
	return touched


## The knee's bend on one side: {axis (LowerLeg rest frame, signed so a bend is positive),
## rest, lo, hi (degrees), angle_at (Callable: time -> degrees, on the authored track)}.
## Empty when the side's knee has no track.
static func knee_lift(anim: Animation, skel: Skeleton3D, side: String) -> Dictionary:
	var ll := skel.find_bone(side + "LowerLeg")
	var t := _track(anim, side + "LowerLeg")
	if ll < 0 or t < 0 or anim.track_get_key_count(t) < 2:
		return {}
	var rest := skel.get_bone_rest(ll).basis.get_rotation_quaternion()
	# The hinge: the bend axis of the deepest key. A knee only folds one way.
	var deepest := Quaternion.IDENTITY
	var deepest_angle := -1.0
	for k in anim.track_get_key_count(t):
		var d := _delta(rest, anim.track_get_key_value(t, k))
		if d.get_angle() > deepest_angle:
			deepest_angle = d.get_angle()
			deepest = d
	var info := {axis = deepest.get_axis().normalized(), rest = rest}
	var lo := INF
	var hi := -INF
	for k in anim.track_get_key_count(t):
		var a := knee_angle(info, anim.track_get_key_value(t, k))
		lo = minf(lo, a)
		hi = maxf(hi, a)
	info.lo = lo
	info.hi = hi
	# A copy, so the knee keys rewritten later do not feed back into the thigh's weights.
	var src := anim.duplicate(true) as Animation
	info.angle_at = func(time: float) -> float:
		return knee_angle(info, src.rotation_track_interpolate(t, time))
	return info


## The knee's bend in degrees about its hinge: positive bent, about 0 straight.
static func knee_angle(info: Dictionary, q: Quaternion) -> float:
	var d := _delta(info.rest, q)
	return rad_to_deg(d.get_angle()) * signf(d.get_axis().dot(info.axis) + 1e-6)


## 0 through stance, rising to 1 at the deepest bend of the swing.
static func lift_weight(info: Dictionary, angle: float) -> float:
	var from: float = lerpf(info.lo, info.hi, LIFT_FROM)
	return smoothstep(from, info.hi, angle)


static func _delta(rest: Quaternion, q: Quaternion) -> Quaternion:
	var d := rest.inverse() * q
	return d if d.w >= 0.0 else -d


static func _track(anim: Animation, bone: String) -> int:
	return anim.find_track(NodePath("%GeneralSkeleton:" + bone), Animation.TYPE_ROTATION_3D)
