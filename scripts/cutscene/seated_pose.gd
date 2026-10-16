@tool
class_name SeatedPose
extends SkeletonModifier3D

# Sits pilot9 in the cockpit seat: hips on the seat with the backrest's recline, two-bone IK for
# each leg (ankles to the footrest) and each arm (wrists to the grips), feet flat, face level.
# There is no sitting clip, so the pose is solved here every skeleton update, from rest, out of
# the seat's targets - move a target on the seat and he follows, in the editor too. See
# docs/specs/cutscene-cockpit.md.
#
# solve() is pure (skeleton rests + targets in, bone poses out) so tests can check it without a
# rendered frame.

## The CockpitSeat whose targets he sits to.
@export var seat_path: NodePath
## Extra forward pitch on the neck, degrees, on top of undoing the recline at the head.
@export_range(-30.0, 30.0, 0.5) var neck_pitch_degrees := 0.0
## Knee pole, seat space: knees bend toward this.
@export var knee_pole := Vector3(0.0, 1.0, 1.0)
## Elbow pole, seat space, for his left arm (mirrored on X for the right): out, down, a bit back.
@export var elbow_pole := Vector3(1.0, -1.0, -0.4)
## The re-entry shake's lean of his spine off the seat (euler radians, seat axes), spread up the
## spine before the arms are solved, so the hands stay on the grips. Set by CockpitReentry.
var body_sway := Vector3.ZERO
## Extra head rotation on the neck (euler radians, seat axes): whiplash and the buzz nod.
var head_sway := Vector3.ZERO
## Moves each wrist target (seat space) on top of the seat's: the swipe and the sticks' push. Set by
## CockpitReentry.
var left_wrist_shift := Transform3D()
var right_wrist_shift := Transform3D()
## The Head bone's position in seat space as of the last skeleton update (INF until the first).
## CockpitReentry hangs the startle "!" off it.
var head_position := Vector3.INF

## How body_sway is shared up the spine.
const SPINE_SHARE := {&"Spine": 0.4, &"Chest": 0.3, &"UpperChest": 0.3}

const LIMBS := {
	&"left_leg": [&"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot"],
	&"right_leg": [&"RightUpperLeg", &"RightLowerLeg", &"RightFoot"],
	&"left_arm": [&"LeftUpperArm", &"LeftLowerArm", &"LeftHand"],
	&"right_arm": [&"RightUpperArm", &"RightLowerArm", &"RightHand"],
}


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	var seat := get_node_or_null(seat_path) as CockpitSeat
	if skel == null or seat == null or not seat.is_inside_tree():
		return
	var pose := solve(skel, seat)
	for bone: int in pose.rotations:
		skel.set_bone_pose_rotation(bone, pose.rotations[bone])
	skel.set_bone_pose_position(pose.hips, pose.hips_position)
	var head_world := skel.global_transform * bone_position(skel, pose, &"Head")
	head_position = seat.global_transform.affine_inverse() * head_world


## The seated pose: {hips, hips_position (parent space), rotations: bone -> local Quaternion}.
## Every bone not in `rotations` stays at rest.
func solve(skel: Skeleton3D, seat: CockpitSeat) -> Dictionary:
	# Skeleton space <- seat space.
	var to_skel := skel.global_transform.affine_inverse() * seat.global_transform
	var axis := (to_skel.basis * Vector3.RIGHT).normalized()
	var p := _Pose.new(skel)

	# Hips on the seat, leaning back with the backrest.
	var hips := skel.find_bone(&"Hips")
	p.local[hips].origin = to_skel * seat.hip_target
	p.rotate_global(hips, Quaternion(axis, -deg_to_rad(seat.recline_degrees)))

	# The shake's throw, before the arms: the shoulders move and the arms re-reach the grips.
	if body_sway != Vector3.ZERO:
		for bone_name: StringName in SPINE_SHARE:
			var b := skel.find_bone(bone_name)
			if b >= 0:
				p.rotate_global(b, _seat_rotation(to_skel, body_sway * SPINE_SHARE[bone_name]))

	# Legs to the footrest, then feet back to flat (their rest orientation, in seat space).
	var pole := (to_skel.basis * knee_pole).normalized()
	_two_bone(p, LIMBS[&"left_leg"], to_skel * seat.left_foot_target, pole)
	_two_bone(p, LIMBS[&"right_leg"], to_skel * seat.right_foot_target, pole)
	for foot: StringName in [&"LeftFoot", &"RightFoot"]:
		var f := skel.find_bone(foot)
		p.set_global_basis(f, to_skel.basis.orthonormalized() * skel.get_bone_global_rest(f).basis)

	# Arms to the grips.
	var e := elbow_pole
	_two_bone(p, LIMBS[&"left_arm"], to_skel * (left_wrist_shift * seat.left_wrist_target),
			(to_skel.basis * e).normalized())
	_two_bone(p, LIMBS[&"right_arm"], to_skel * (right_wrist_shift * seat.right_wrist_target),
			(to_skel.basis * Vector3(-e.x, e.y, e.z)).normalized())

	# Face level: the neck takes back the recline, plus any extra pitch.
	var neck := skel.find_bone(&"Neck")
	p.rotate_global(neck, Quaternion(axis, deg_to_rad(seat.recline_degrees + neck_pitch_degrees)))
	if head_sway != Vector3.ZERO:
		p.rotate_global(skel.find_bone(&"Head"), _seat_rotation(to_skel, head_sway))

	var rotations := {}
	for b in p.changed:
		rotations[b] = p.local[b].basis.get_rotation_quaternion()
	return {hips = hips, hips_position = p.local[hips].origin, rotations = rotations}


## Where bone `name` would be (skeleton space) with `pose` applied. For tests.
static func bone_position(skel: Skeleton3D, pose: Dictionary, bone_name: StringName) -> Vector3:
	var p := _Pose.new(skel)
	p.local[pose.hips].origin = pose.hips_position
	for b: int in pose.rotations:
		p.local[b].basis = Basis(pose.rotations[b]) * Basis.from_scale(p.local[b].basis.get_scale())
	return p.global(skel.find_bone(bone_name)).origin


# A seat-axes euler rotation as a skeleton-space quaternion.
static func _seat_rotation(to_skel: Transform3D, euler: Vector3) -> Quaternion:
	var b := to_skel.basis.orthonormalized()
	return (b * Basis.from_euler(euler) * b.inverse()).get_rotation_quaternion()


# Upper bone aims at the knee/elbow found from the pole, the lower bone at the target.
func _two_bone(p: _Pose, names: Array, target: Vector3, pole: Vector3) -> void:
	var upper := p.skel.find_bone(names[0])
	var lower := p.skel.find_bone(names[1])
	var end := p.skel.find_bone(names[2])
	var root := p.global(upper).origin
	var a := root.distance_to(p.global(lower).origin)
	var b := p.global(lower).origin.distance_to(p.global(end).origin)
	var to_target := target - root
	var d := clampf(to_target.length(), absf(a - b) + 1e-4, (a + b) * 0.9999)
	var n := to_target.normalized()
	var m := (pole - n * pole.dot(n)).normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var joint := root + n * a * cos_a + m * a * sqrt(1.0 - cos_a * cos_a)
	p.aim(upper, lower, joint)
	p.aim(lower, end, root + n * d)


# Local bone transforms with forward kinematics, starting from rest.
class _Pose:
	var skel: Skeleton3D
	var local: Array[Transform3D] = []
	var changed: Array[int] = []

	func _init(s: Skeleton3D) -> void:
		skel = s
		for i in s.get_bone_count():
			local.append(s.get_bone_rest(i))

	func global(bone: int) -> Transform3D:
		var t := local[bone]
		var parent := skel.get_bone_parent(bone)
		while parent >= 0:
			t = local[parent] * t
			parent = skel.get_bone_parent(parent)
		return t

	func _parent_global(bone: int) -> Transform3D:
		var parent := skel.get_bone_parent(bone)
		return global(parent) if parent >= 0 else Transform3D()

	func set_global_basis(bone: int, basis: Basis) -> void:
		local[bone].basis = _parent_global(bone).basis.inverse() * basis
		if not changed.has(bone):
			changed.append(bone)

	func rotate_global(bone: int, q: Quaternion) -> void:
		set_global_basis(bone, Basis(q) * global(bone).basis)

	# Turns `bone` (shortest arc) so its child lands on the line toward `point`.
	func aim(bone: int, child: int, point: Vector3) -> void:
		var g := global(bone)
		var from := (global(child).origin - g.origin).normalized()
		var to := (point - g.origin).normalized()
		if from.is_equal_approx(to):
			return
		var axis := from.cross(to)
		if axis.length_squared() < 1e-10:
			return
		rotate_global(bone, Quaternion(axis.normalized(), from.angle_to(to)))
