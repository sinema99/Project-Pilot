## pilot9's crouch lean (2026-11-15, docs/specs/pilot9-crouch-kneel.md). The crouch walk's lean is
## two parts: the jog clip pitches the pelvis (crouch_bake.gd JOG_HIPS_PITCH, the hip hinge), and
## this adds more on Spine / Chest / UpperChest. The kneel gets only this one's small lean. The neck
## and head turn back by the whole amount so his gaze stays level. The arms keep their
## parent-relative pose, so the gun dips with the chest.
##
## Off while aiming: the spine also takes the pelvis pitch back out, so the aim IK
## (scripts/items/arm_pose_modifier.gd) starts from an upright chest and bends to the camera itself.
##
## A SkeletonModifier3D built BEFORE the item holder's (scripts/pilot9.gd::_setup_idle_arm), so the
## arm hold and the aim IK read the leaned chest.
extends SkeletonModifier3D

const _BAKE := preload("res://scripts/crouch_bake.gd")

## Lean ON THE SPINE at a full crouch jog / in the kneel, degrees.
@export_range(0.0, 45.0, 0.5) var jog_degrees := 18.0
@export_range(0.0, 45.0, 0.5) var kneel_degrees := 10.0
## How much of the lean the neck and head take back, 0..1. 1 keeps his gaze level but juts the
## head out on a long neck; half reads as looking ahead and down, the way a crouch run does.
@export_range(0.0, 1.0, 0.05) var head_counter := 0.8
## How far the upper arms swing FORWARD, as a fraction of the chest's lean (0 = they keep the idle
## hang relative to the chest). Rev 5 (2026-11-15, the user's red line): 1.2 hangs the hands out
## ahead of the front knee, the DayZ crouch walk. (Rev 4 called this `arm_hang` and read the sign
## backwards in its comments - a hanging arm turned about +X goes BACK, so the code turns by -angle.)
@export_range(0.0, 2.0, 0.05) var arm_forward := 1.2
## Both upper arms swung out to the side, away from the waist, degrees (rev 6, user: "a little
## wider"). Crouched only, off while aiming.
@export_range(0.0, 45.0, 0.5) var arm_out_degrees := 6.0
## Seconds a full fade in or out of the crouch takes. The state's own 0.25 s crossfade.
@export_range(0.01, 1.0, 0.01) var blend_time := 0.25

## Written every frame by scripts/pilot9_animation.gd::_drive_crouch.
## crouch_target: 1 while the `crouch` state should be showing. move: the kneel (0) <-> jog (1)
## mix the state is playing. aim: the aim IK's weight, 0..1.
var crouch_target := 0.0
var move := 0.0
var aim := 0.0
## The eased crouch amount, 0..1.
var weight := 0.0

const SPINE := {&"Spine": 0.35, &"Chest": 0.35, &"UpperChest": 0.3}
const NECK := {&"Neck": 0.5, &"Head": 0.5}
const ARMS := [&"LeftUpperArm", &"RightUpperArm"]

var _bones := {}


func _ready() -> void:
	influence = 1.0
	var skel := get_skeleton()
	if skel == null:
		return
	for b in SPINE.keys() + NECK.keys() + ARMS:
		_bones[b] = skel.find_bone(b)


## Eases the crouch amount. Separate from the modification so a test can step it.
func step(delta: float) -> void:
	weight = move_toward(weight, crouch_target, delta / blend_time)


## The spine's own lean right now, degrees: kneel to jog by `move`, faded by the crouch and the aim.
func degrees() -> float:
	return lerpf(kneel_degrees, jog_degrees, clampf(move, 0.0, 1.0)) \
		* smoothstep(0.0, 1.0, weight) * (1.0 - clampf(aim, 0.0, 1.0))


## The pelvis pitch the jog clip is playing right now, degrees (estimated from the mix).
func hips_degrees() -> float:
	return _BAKE.JOG_HIPS_PITCH * clampf(move, 0.0, 1.0) * smoothstep(0.0, 1.0, weight)


func _process_modification_with_delta(delta: float) -> void:
	step(delta)
	var skel := get_skeleton()
	var a := clampf(aim, 0.0, 1.0)
	var hips := hips_degrees()
	var spine := degrees() - hips * a
	var total := degrees() + hips * (1.0 - a)   # the chest's whole pitch forward
	var head := -total * head_counter
	if skel == null or _bones.is_empty() or (absf(spine) < 0.001 and absf(head) < 0.001):
		return
	# Skeleton space: +X his left, so a positive turn about +X tips +Y toward +Z - forward.
	for b: StringName in SPINE:
		_rotate(skel, _bones[b], Basis(Vector3.RIGHT, deg_to_rad(spine) * SPINE[b]))
	for b: StringName in NECK:
		_rotate(skel, _bones[b], Basis(Vector3.RIGHT, deg_to_rad(head) * NECK[b]))
	var out := deg_to_rad(arm_out_degrees) * smoothstep(0.0, 1.0, weight) * (1.0 - a)
	for b: StringName in ARMS:
		# About +Z (his forward) a +angle swings a hanging arm toward +X - his LEFT - so the left
		# arm turns + and the right arm - to both go outward.
		var side := 1.0 if b == &"LeftUpperArm" else -1.0
		_rotate(skel, _bones[b], Basis(Vector3.BACK, out * side)
			* Basis(Vector3.RIGHT, deg_to_rad(-total * arm_forward)))


## Turns `bone` by `by` (skeleton space) about its own joint, on top of what it has.
static func _rotate(skel: Skeleton3D, bone: int, by: Basis) -> void:
	if bone < 0:
		return
	var gp := skel.get_bone_global_pose(bone)
	gp.basis = by * gp.basis
	skel.set_bone_global_pose(bone, gp)
