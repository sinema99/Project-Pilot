## Holds a fixed set of bone rotations on top of whatever the AnimationTree posed, weighted by
## `influence`, which eases toward `target` over `blend_time`. The held item's arm layer - built
## as a SkeletonModifier3D rather than a filtered blend in the tree because the tree's root IS
## the locomotion state machine, and wrapping it would move every `parameters/...` path in the
## project. See docs/specs/pilot9-held-item.md, "How it is built".
extends SkeletonModifier3D

const _AimIK := preload("res://scripts/items/aim_ik.gd")
## The most the upper body bends for an aim up or down, radians.
const BEND_LIMIT := deg_to_rad(60.0)

## bone index -> the rotation (bone pose, parent-relative) to hold it at. Empty holds nothing.
var pose: Dictionary = {}
## bone index -> 0..1: how far a bone goes from the animation's own rotation to `pose`. Absent = 1.
var weights: Dictionary = {}
## 0 or 1 - where influence is heading. Set by scripts/items/item_holder.gd every frame.
var target: float = 0.0
## Seconds a full 0 -> 1 fade takes. The spec's ~0.15 s.
var blend_time: float = 0.15


## bone index -> yaw radians about the skeleton's up axis, added on top of the animation after the
## arm pose. The bladed aim stance. Empty adds nothing.
var twist: Dictionary = {}
## The aim IK (scripts/items/aim_ik.gd), applied after the twist. `ik_item` null or `ik_weight` 0
## does nothing. `ik_aim_point` is in WORLD space, `ik_body` is the character node (its basis gives
## his up / left).
var ik_item: HeldItem = null
var ik_weight: float = 0.0
var ik_aim_point: Vector3 = Vector3.ZERO
var ik_body: Node3D = null
## The rifle's frame the last solve used, skeleton space (for probes and tests).
var ik_last_frame: Transform3D = Transform3D.IDENTITY


func _init() -> void:
	influence = 0.0


## Eases influence toward target. Separate from the modification itself so a test can step it
## without a skeleton update.
func step(delta: float) -> void:
	if blend_time <= 0.0:
		influence = target
	else:
		influence = move_toward(influence, target, delta / blend_time)


func _process_modification_with_delta(delta: float) -> void:
	step(delta)
	var skel := get_skeleton()
	if skel == null:
		return
	for bone in pose:
		var w: float = weights.get(bone, 1.0)
		if w >= 0.999:
			skel.set_bone_pose_rotation(bone, pose[bone])
		elif w > 0.001:
			skel.set_bone_pose_rotation(bone,
				skel.get_bone_pose_rotation(bone).slerp(pose[bone], w))
	apply_twist(skel, twist)
	if ik_item != null and ik_weight > 0.001 and ik_body != null:
		var sk_basis := skel.global_transform.basis.orthonormalized()
		var to_skel := sk_basis.inverse()
		var cb := ik_body.global_basis.orthonormalized()
		var up := to_skel * cb.y
		var left := to_skel * cb.x
		var aim_pt := skel.global_transform.affine_inverse() * ik_aim_point
		apply_bend(skel, ik_item, aim_pt, up, left, ik_weight)
		ik_last_frame = _AimIK.apply(skel, {
			"item": ik_item, "weight": ik_weight, "aim_pt": aim_pt, "up": up, "left": left})


## The upper body bends with the aim: the pitch from his chest to the aim point, shared over spine,
## chest and upper chest, so the arms and the gun keep one arrangement at every camera angle.
static func apply_bend(skel: Skeleton3D, item: HeldItem, aim_pt: Vector3, up: Vector3, left: Vector3,
		weight: float) -> void:
	var chest := skel.find_bone(&"UpperChest")
	if chest < 0 or item.aim_bend <= 0.0:
		return
	var pitch := _AimIK.pitch_to(skel.get_bone_global_pose(chest).origin, aim_pt, up)
	var total := clampf(pitch, -BEND_LIMIT, BEND_LIMIT) * item.aim_bend * weight
	# About his RIGHT axis a positive angle tips forward-facing things up.
	_AimIK.bend(skel, [skel.find_bone(&"Spine"), skel.find_bone(&"Chest"), chest], -left,
		[total * 0.3, total * 0.35, total * 0.35])


## Yaws each bone in `yaws` (index -> radians) about the skeleton's up axis. Every parent's
## ORIGINAL global basis is read before any bone changes, so the order does not matter: yaws about
## one axis commute, and a child's local change only needs its parent's untouched basis.
static func apply_twist(skel: Skeleton3D, yaws: Dictionary) -> void:
	if yaws.is_empty():
		return
	var parents := {}
	for bone in yaws:
		var p := skel.get_bone_parent(bone)
		parents[bone] = skel.get_bone_global_pose(p).basis if p >= 0 else Basis()
	for bone in yaws:
		var pg: Basis = parents[bone]
		var delta := pg.inverse() * Basis(Vector3.UP, yaws[bone]) * pg
		skel.set_bone_pose_rotation(bone,
			(delta * Basis(skel.get_bone_pose_rotation(bone))).get_rotation_quaternion())

