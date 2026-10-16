## The tredge's body: the hunch into the wind, the staff held up as a torch in his right hand,
## his left forearm across his face, and the gust stumble. Everything the baked `tredge` clip
## (legs only) does not carry. Built at runtime by scripts/pilot9_tredge.gd, added after every
## other modifier on the skeleton so it has the last word on the arms. See
## docs/specs/pilot9-tredge.md, "The pose layer".
##
## All in skeleton space, which is his own frame: +Z his front, +Y up, -X his right. The weights
## are set by the controller every physics tick; this only draws them.
extends SkeletonModifier3D

const _SlideHand := preload("res://scripts/slide_hand.gd")

@export_group("Hunch")
## Forward lean across Spine / Chest / UpperChest, degrees.
@export_range(0.0, 45.0, 0.5) var hunch_degrees := 18.0
## Extra on the neck and head together (head down), degrees.
@export_range(0.0, 30.0, 0.5) var neck_degrees := 10.0
## Both shoulders rolled forward, degrees.
@export_range(0.0, 20.0, 0.5) var shoulder_roll_degrees := 8.0

@export_group("Lantern arm")
## The right wrist, from the right shoulder joint (skeleton space: +X his left, +Z his front).
@export var lantern_offset := Vector3(-0.08, -0.05, 0.45)
## Bends the right elbow toward this: out to his right, down, a little back.
@export var lantern_elbow_pole := Vector3(-1.0, -1.0, -0.3)
## The staff tipped forward from upright, degrees.
@export_range(-30.0, 45.0, 0.5) var lantern_tilt_forward := 10.0
## The staff's top tipped out to his right, degrees. Negative tips the top in, so the bottom end
## points out away from his legs.
@export_range(-30.0, 45.0, 0.5) var lantern_tilt_out := -16.0
## Up-down bob of the wrist with his steps, metres.
@export_range(0.0, 0.1, 0.001) var lantern_bob := 0.015

@export_group("Shield arm")
## The left wrist, from the head joint: in front of his face and across to his right.
@export var shield_offset := Vector3(-0.10, 0.07, 0.20)
## Bends the left elbow toward this: out to his left, down, a little forward.
@export var shield_elbow_pole := Vector3(1.0, -0.6, 0.3)

@export_group("Gust stumble")
## At a full stagger: pitched back, rolled with the wind, the head nodded, degrees.
@export_range(0.0, 20.0, 0.5) var stagger_pitch := 5.0
@export_range(0.0, 20.0, 0.5) var stagger_roll := 6.0
@export_range(0.0, 20.0, 0.5) var stagger_nod := 3.0

## The whole layer, 0..1 (the 0.5 s blend).
var weight := 0.0
## The lantern arm, 0..1. Already includes `weight`; held at 0 while the draw plays.
var lantern := 0.0
## The gust spring: about 0 between gusts, about 1 at a peak, overshooting on the jolt.
var stagger := 0.0
## +1 when the wind pushes him toward his right, -1 toward his left.
var stagger_side := 1.0
## Step-cycle phase for the lantern's bob, radians; `bob_amount` 0 standing still.
var bob_phase := 0.0
var bob_amount := 0.0
## The staff's long axis in the right hand's bone frame: the item's hand_offset.basis * Y.
var staff_axis := Vector3.UP

const SPINE := {&"Spine": 0.35, &"Chest": 0.35, &"UpperChest": 0.3}
const NECK := {&"Neck": 0.5, &"Head": 0.5}
const RIGHT_ARM := [&"RightUpperArm", &"RightLowerArm", &"RightHand"]
const LEFT_ARM := [&"LeftUpperArm", &"LeftLowerArm", &"LeftHand"]

var _bones := {}


func _ready() -> void:
	influence = 1.0
	var skel := get_skeleton()
	if skel == null:
		return
	for b in [&"Spine", &"Chest", &"UpperChest", &"Neck", &"Head", &"LeftShoulder",
			&"RightShoulder"] + RIGHT_ARM + LEFT_ARM:
		_bones[b] = skel.find_bone(b)


func _bone(bone_name: StringName) -> int:
	return _bones.get(bone_name, -1)


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _bones.is_empty() or (weight <= 0.0 and lantern <= 0.0):
		return
	var w := weight
	var pitch := deg_to_rad(hunch_degrees - stagger_pitch * stagger) * w
	var roll := deg_to_rad(stagger_roll * stagger * stagger_side) * w
	# Forward pitch is about +X (it tips +Y toward +Z); a positive roll about +Z leans him to his
	# right (-X).
	for b: StringName in SPINE:
		_rotate(skel, _bone(b), Basis(Vector3.RIGHT, pitch * SPINE[b]) * Basis(Vector3.BACK, roll * SPINE[b]))
	var nod := deg_to_rad(neck_degrees + stagger_nod * stagger) * w
	for b: StringName in NECK:
		_rotate(skel, _bone(b), Basis(Vector3.RIGHT, nod * NECK[b]))
	var sr := deg_to_rad(shoulder_roll_degrees) * w
	_rotate(skel, _bone(&"RightShoulder"), Basis(Vector3.UP, sr))
	_rotate(skel, _bone(&"LeftShoulder"), Basis(Vector3.UP, -sr))

	if lantern > 0.0:
		var s := skel.get_bone_global_pose(_bone(&"RightUpperArm")).origin
		var target := s + lantern_offset + Vector3.UP * lantern_bob * bob_amount * sin(bob_phase)
		_arm(skel, RIGHT_ARM, target, lantern_elbow_pole, lantern, true)
	if w > 0.0:
		var head := skel.get_bone_global_pose(_bone(&"Head")).origin
		_arm(skel, LEFT_ARM, head + shield_offset, shield_elbow_pole, w, false)


## Turns `bone` by `by` (skeleton space) about its own joint, on top of what it has.
func _rotate(skel: Skeleton3D, bone: int, by: Basis) -> void:
	if bone < 0:
		return
	var gp := skel.get_bone_global_pose(bone)
	gp.basis = by * gp.basis
	skel.set_bone_global_pose(bone, gp)


## The direction the staff stands in: up, tipped forward and out to his right.
func lantern_direction() -> Vector3:
	var f := deg_to_rad(lantern_tilt_forward)
	var o := deg_to_rad(lantern_tilt_out)
	return (Vector3.UP + Vector3.BACK * tan(f) + Vector3.LEFT * tan(o)).normalized()


## Two-bone IK of one arm onto `target`, elbow toward `pole`, blended over the incoming pose by
## `amount`. With `aim_staff` the hand then turns so the staff stands along lantern_direction().
func _arm(skel: Skeleton3D, names: Array, target: Vector3, pole: Vector3, amount: float,
		aim_staff: bool) -> void:
	var up_i := _bone(names[0])
	var lo_i := _bone(names[1])
	var hand_i := _bone(names[2])
	if up_i < 0 or lo_i < 0 or hand_i < 0:
		return
	var before := [skel.get_bone_pose_rotation(up_i), skel.get_bone_pose_rotation(lo_i),
		skel.get_bone_pose_rotation(hand_i)]
	solve_arm(skel, up_i, lo_i, hand_i, target, pole.normalized())
	if aim_staff:
		var hp := skel.get_bone_global_pose(hand_i)
		var have := (hp.basis * staff_axis).normalized()
		var want := lantern_direction()
		if have.length() > 0.5 and not have.is_equal_approx(want):
			hp.basis = Basis(Quaternion(have, want)) * hp.basis
			skel.set_bone_global_pose(hand_i, hp)
	if amount >= 1.0:
		return
	var bones := [up_i, lo_i, hand_i]
	var after := []
	for b in bones:
		after.append(skel.get_bone_pose_rotation(b))
	for i in 3:
		skel.set_bone_pose_rotation(bones[i], (before[i] as Quaternion).slerp(after[i], amount))


## The slide hand's twist-aware fold (scripts/slide_hand.gd), for either arm. The bend's sign
## is read off the incoming pose rather than assumed, so the mirrored arm folds the right way.
static func solve_arm(skel: Skeleton3D, up_i: int, lo_i: int, hand_i: int, target: Vector3,
		pole: Vector3) -> void:
	var up := skel.get_bone_global_pose(up_i)
	var s := up.origin
	var lo := skel.get_bone_global_pose(lo_i)
	var e0 := lo.origin
	var h0 := skel.get_bone_global_pose(hand_i).origin
	var n0 := lo.basis.x.normalized()
	var bend := (e0 - s).cross(h0 - e0)
	var sgn := -1.0 if bend.length() > 1e-4 and bend.dot(n0) < 0.0 else 1.0
	var got := _SlideHand.solve(s, target, (e0 - s).length(), (h0 - e0).length(), pole)
	var elbow: Vector3 = got[0]
	var hand: Vector3 = got[1]
	var u0 := (e0 - s).normalized()
	var u1 := (elbow - s).normalized()
	var n1 := (elbow - s).cross(hand - elbow) * sgn
	if n1.length() < 1e-5:
		n1 = n0
	up.basis = _SlideHand._frame(u1, n1.normalized()) * _SlideHand._frame(u0, n0).inverse() * up.basis
	skel.set_bone_global_pose(up_i, up)
	# Fold the forearm about its own hinge onto the hand.
	lo = skel.get_bone_global_pose(lo_i)
	var hinge := lo.basis.x.normalized()
	var want := hand - lo.origin
	want -= hinge * want.dot(hinge)
	var have := skel.get_bone_global_pose(hand_i).origin - lo.origin
	have -= hinge * have.dot(hinge)
	if want.length() > 1e-4 and have.length() > 1e-4:
		# The forearm is not square to its hinge, so the projected angle leaves the wrist a couple
		# of centimetres short of the reach. Newton on the shoulder-to-wrist distance from there.
		var forearm := skel.get_bone_global_pose(hand_i).origin - lo.origin
		var reach := (hand - s).length()
		var phi := have.signed_angle_to(want, hinge)
		for i in 6:
			var f := (lo.origin + Basis(hinge, phi) * forearm - s).length() - reach
			var df := ((lo.origin + Basis(hinge, phi + 0.001) * forearm - s).length() - reach - f) / 0.001
			if absf(f) < 1e-4 or absf(df) < 1e-6:
				break
			phi -= clampf(f / df, -0.3, 0.3)
		lo.basis = Basis(hinge, phi) * lo.basis
		skel.set_bone_global_pose(lo_i, lo)
	# The hinge is not quite square to the upper arm: swing the arm about the shoulder onto it.
	var h2 := skel.get_bone_global_pose(hand_i).origin
	if (h2 - s).length() > 1e-4 and (hand - s).length() > 1e-4:
		up = skel.get_bone_global_pose(up_i)
		up.basis = Basis(Quaternion((h2 - s).normalized(), (hand - s).normalized())) * up.basis
		skel.set_bone_global_pose(up_i, up)
