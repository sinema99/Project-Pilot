## pilot9's sport tuck on a speeder (docs/specs/speeder1.md, "The rider"). No clip: every body bone
## is put back to rest and then posed here - hips and spine pitched forward into the tuck, head
## counter-pitched to look ahead and turned toward the camera, both arms two-bone solved onto the
## grips and both legs onto the pegs. The coat bones are left to the coat.
##
## Built by pilot9.gd::begin_ride() and kept as the LAST modifier on his skeleton, so it has the
## final word over the item, slide, wall-hand and tredge layers. `influence` is the mount blend
## (0 = whatever pose he stepped on with, 1 = riding). The speeder writes the live inputs below
## every frame; this only draws them.
##
## Skeleton space is his own frame: +Z his front, +Y up, +X his LEFT.
extends SkeletonModifier3D

const _TredgePose := preload("res://scripts/tredge_pose.gd")

## The body bones this owns (the coat's CoatU*/CoatL* are not in it).
const BODY := [&"Hips", &"Spine", &"Chest", &"UpperChest", &"Neck", &"Head",
	&"LeftShoulder", &"LeftUpperArm", &"LeftLowerArm", &"LeftHand",
	&"RightShoulder", &"RightUpperArm", &"RightLowerArm", &"RightHand",
	&"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot", &"LeftToes",
	&"RightUpperLeg", &"RightLowerLeg", &"RightFoot", &"RightToes"]
## Share of the spine's pitch (and of the turn lean) each spine bone takes.
const SPINE := {&"Spine": 0.3, &"Chest": 0.35, &"UpperChest": 0.35}

@export_group("Tuck")
## Fully tucked (tuck_share 1): pelvis pitched forward over the seat, degrees.
@export_range(0.0, 60.0, 0.5) var hip_pitch_degrees := 20.0
## Fully tucked: further forward through Spine / Chest / UpperChest, degrees.
@export_range(0.0, 80.0, 0.5) var spine_pitch_degrees := 46.0
## Upright (tuck_share 0), the same two.
@export_range(0.0, 60.0, 0.5) var hip_upright_degrees := 15.0
@export_range(0.0, 80.0, 0.5) var spine_upright_degrees := 34.0
## Of the total forward pitch, how much the neck + head take back so he looks ahead (0..1).
@export_range(0.0, 1.0, 0.01) var look_up_share := 0.8
## Shoulders rolled forward toward the grips, degrees.
@export_range(0.0, 30.0, 0.5) var shoulder_roll_degrees := 10.0
## Hands: palms tipped down from flat, degrees.
@export_range(-45.0, 60.0, 0.5) var wrist_down_degrees := 20.0
## Feet: toes pointed down from flat, degrees.
@export_range(-45.0, 80.0, 0.5) var toe_down_degrees := 30.0

@export_group("Poles")
## Elbows bend toward this (skeleton space, the LEFT arm; mirrored for the right): out, down, back.
@export var elbow_pole := Vector3(0.6, -0.5, -0.7)
## Knees bend toward this (the LEFT leg; mirrored): forward and out.
@export var knee_pole := Vector3(0.25, 0.3, 1.0)

## --- live inputs, written by the speeder every frame -------------------------------------
## World-space wrist and ankle targets.
var grip_left := Vector3.ZERO
var grip_right := Vector3.ZERO
var peg_left := Vector3.ZERO
var peg_right := Vector3.ZERO
## 0 = sitting upright (a crawl, getting on or off), 1 = the full sport tuck (at speed).
var tuck_share := 0.0
## Extra forward pitch on the spine at speed (the tighter tuck), degrees.
var tuck_degrees := 0.0
## Upper body hung into a turn, degrees: + leans him to his right (-X).
var lean_degrees := 0.0
## Head turned toward the camera, radians: + turns it to his left (+X).
var head_yaw := 0.0
## Grips / pegs only drive the limbs once the speeder has written them.
var has_targets := false

var _bones := {}
## Frames this has drawn (tests and probes).
var runs := 0
## Set true to keep `posed`: bone name -> its skeleton-space origin as this layer left it. The
## skeleton puts the un-modified pose back after each update, so this is the only place to read it.
var record := false
var posed := {}


func _init() -> void:
	influence = 0.0


func _ready() -> void:
	_cache()


func _cache() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for b in BODY:
		_bones[b] = skel.find_bone(b)


func bone(bone_name: StringName) -> int:
	return _bones.get(bone_name, -1)


func _process_modification_with_delta(_delta: float) -> void:
	runs += 1
	var skel := get_skeleton()
	_pose(skel)
	if record and skel != null:
		for b: StringName in BODY:
			if bone(b) >= 0:
				posed[b] = skel.get_bone_global_pose(bone(b)).origin


func _pose(skel: Skeleton3D) -> void:
	if skel == null:
		return
	if _bones.is_empty():
		_cache()
	if bone(&"Hips") < 0:
		return
	# A clean slate: the AnimationTree is off while he rides, so the incoming pose is whatever
	# frame he boarded on.
	for b: StringName in BODY:
		var i := bone(b)
		if i >= 0:
			skel.set_bone_pose(i, skel.get_bone_rest(i))

	# The tuck. Forward pitch is about +X (it tips +Y toward +Z); a positive roll about +Z leans
	# him to his right.
	var hip := deg_to_rad(lerpf(hip_upright_degrees, hip_pitch_degrees, tuck_share))
	_rotate(skel, bone(&"Hips"), Basis(Vector3.RIGHT, hip))
	var spine := deg_to_rad(lerpf(spine_upright_degrees, spine_pitch_degrees, tuck_share) + tuck_degrees)
	var lean := deg_to_rad(lean_degrees)
	for b: StringName in SPINE:
		_rotate(skel, bone(b), Basis(Vector3.BACK, lean * SPINE[b]) * Basis(Vector3.RIGHT, spine * SPINE[b]))
	var back := -(hip + spine) * look_up_share
	_rotate(skel, bone(&"Neck"), Basis(Vector3.RIGHT, back * 0.4))
	_rotate(skel, bone(&"Head"), Basis(Vector3.UP, head_yaw) * Basis(Vector3.RIGHT, back * 0.6)
		* Basis(Vector3.BACK, -lean * 0.5))
	var sr := deg_to_rad(shoulder_roll_degrees)
	_rotate(skel, bone(&"LeftShoulder"), Basis(Vector3.UP, -sr))
	_rotate(skel, bone(&"RightShoulder"), Basis(Vector3.UP, sr))

	if not has_targets:
		return
	var to_skel := skel.global_transform.affine_inverse()
	var mirror := Vector3(-1.0, 1.0, 1.0)

	# Knees: pre-bent so the solve reads the right bend direction off the incoming pose (a nearly
	# straight rest leg gives it nothing to read).
	for side in [[&"LeftUpperLeg", &"LeftLowerLeg", &"LeftFoot", peg_left, knee_pole],
			[&"RightUpperLeg", &"RightLowerLeg", &"RightFoot", peg_right, knee_pole * mirror]]:
		var lo := bone(side[1])
		if lo >= 0:
			_rotate(skel, lo, Basis(Vector3.RIGHT, deg_to_rad(70.0)))
		_limb(skel, side[0], side[1], side[2], to_skel * (side[3] as Vector3), side[4])
	for f in [&"LeftFoot", &"RightFoot"]:
		var i := bone(f)
		if i >= 0:
			var gp := skel.get_bone_global_pose(i)
			gp.basis = Basis(Vector3.RIGHT, deg_to_rad(toe_down_degrees)) * skel.get_bone_global_rest(i).basis
			skel.set_bone_global_pose(i, gp)

	_limb(skel, &"LeftUpperArm", &"LeftLowerArm", &"LeftHand", to_skel * grip_left, elbow_pole)
	_limb(skel, &"RightUpperArm", &"RightLowerArm", &"RightHand", to_skel * grip_right,
		elbow_pole * mirror)
	# Hands along the grips: the bone's +Y (down the arm in rest) turned to point forward, palms
	# tipped down.
	var wrist := Basis(Vector3.RIGHT, deg_to_rad(wrist_down_degrees))
	for h in [[&"LeftHand", -PI * 0.5], [&"RightHand", PI * 0.5]]:
		var i := bone(h[0])
		if i >= 0:
			var gp := skel.get_bone_global_pose(i)
			gp.basis = wrist * Basis(Vector3.UP, h[1]) * skel.get_bone_global_rest(i).basis
			skel.set_bone_global_pose(i, gp)


## Turns `bone_index` by `by` (skeleton space) about its own joint, on top of what it has.
func _rotate(skel: Skeleton3D, bone_index: int, by: Basis) -> void:
	if bone_index < 0:
		return
	var gp := skel.get_bone_global_pose(bone_index)
	gp.basis = by * gp.basis
	skel.set_bone_global_pose(bone_index, gp)


func _limb(skel: Skeleton3D, upper: StringName, lower: StringName, end: StringName,
		target: Vector3, pole: Vector3) -> void:
	var u := bone(upper)
	var l := bone(lower)
	var e := bone(end)
	if u < 0 or l < 0 or e < 0:
		return
	_TredgePose.solve_arm(skel, u, l, e, target, pole.normalized())
