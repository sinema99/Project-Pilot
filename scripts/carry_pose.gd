## The crate carry's body: both arms bent round a box held at his chest. Built at runtime by
## scripts/pilot9_carry.gd and added after every other modifier on the skeleton, so it has the
## last word on the arms. See docs/specs/pilot9-crate-carry.md.
##
## All in skeleton space (his own frame: +Z front, +Y up, -X his right), in skeleton UNITS - the
## controller passes `unit` (skeleton units per metre) so a scaled rig still holds a 0.6 m box.
extends SkeletonModifier3D

const _TredgePose := preload("res://scripts/tredge_pose.gd")

## The box's centre from the chest joint, metres: ahead and up (negative = down).
@export var box_ahead := 0.38
@export var box_up := -0.12
## The wrists sit this far either side of the box's centre, metres.
@export var hand_half := 0.31
## Bends the elbows toward these (right, left): out to the side, down, a little back.
@export var right_pole := Vector3(-1.0, -0.8, -0.2)
@export var left_pole := Vector3(1.0, -0.8, -0.2)

## 0..1, the blend in and out (set by the controller each tick).
var weight := 0.0
## Skeleton units per metre.
var unit := 1.0
## The carried box (a child of the skeleton); placed here, after the animation, so it never lags.
var box: Node3D = null

const RIGHT_ARM := [&"RightUpperArm", &"RightLowerArm", &"RightHand"]
const LEFT_ARM := [&"LeftUpperArm", &"LeftLowerArm", &"LeftHand"]

var _bones := {}


func _ready() -> void:
	influence = 1.0
	var skel := get_skeleton()
	if skel == null:
		return
	for b in [&"Chest"] + RIGHT_ARM + LEFT_ARM:
		_bones[b] = skel.find_bone(b)


## Where the box's centre is, in skeleton space, for the pose the skeleton is in right now.
func box_center(skel: Skeleton3D) -> Vector3:
	var chest: int = _bones.get(&"Chest", -1)
	var base := skel.get_bone_global_pose(chest).origin if chest >= 0 else Vector3(0, 1.2 * unit, 0)
	return base + Vector3(0.0, box_up * unit, box_ahead * unit)


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _bones.is_empty() or weight <= 0.0:
		return
	var c := box_center(skel)
	if box != null:
		box.position = c
	var h := hand_half * unit
	_arm(skel, RIGHT_ARM, c + Vector3(-h, 0, 0), right_pole)
	_arm(skel, LEFT_ARM, c + Vector3(h, 0, 0), left_pole)


func _arm(skel: Skeleton3D, names: Array, target: Vector3, pole: Vector3) -> void:
	var up_i: int = _bones[names[0]]
	var lo_i: int = _bones[names[1]]
	var hand_i: int = _bones[names[2]]
	if up_i < 0 or lo_i < 0 or hand_i < 0:
		return
	var bones := [up_i, lo_i, hand_i]
	var before := []
	for b in bones:
		before.append(skel.get_bone_pose_rotation(b))
	_TredgePose.solve_arm(skel, up_i, lo_i, hand_i, target, pole.normalized())
	if weight >= 1.0:
		return
	for i in 3:
		skel.set_bone_pose_rotation(bones[i], (before[i] as Quaternion).slerp(
			skel.get_bone_pose_rotation(bones[i]), weight))
