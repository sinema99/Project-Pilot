## The wall-run hand: the arm on the wall's side trails back behind him in the staff's running
## hold, empty, as if gliding along the face. Two of the held item's ArmPoseModifiers, one per
## arm. Built at runtime by pilot9.gd::_setup_wall_hand() for the same reason as the item holder.
## See docs/specs/pilot9-wall-run.md, "The wall hand".
extends Node

const _ArmPoseModifier := preload("res://scripts/items/arm_pose_modifier.gd")
const _ItemHolder := preload("res://scripts/items/item_holder.gd")

## The skeleton's left/right mirror. The rig faces +Z with his right arm on -X.
const MIRROR := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

var right_modifier: SkeletonModifier3D = null
var left_modifier: SkeletonModifier3D = null

var _skeleton: Skeleton3D = null
## pilot9: is_wall_running, wall_run_on_right() and wall_hand_rotations.
var _body: Node = null


func setup(skeleton: Skeleton3D, body: Node) -> void:
	_skeleton = skeleton
	_body = body
	if _skeleton == null:
		push_error("wall_hand: no skeleton - no hand on the wall")
		return
	right_modifier = _make_modifier(&"WallHandRight")
	left_modifier = _make_modifier(&"WallHandLeft")


func _make_modifier(modifier_name: StringName) -> SkeletonModifier3D:
	var m := _ArmPoseModifier.new()
	m.name = modifier_name
	_skeleton.add_child(m)
	return m


## bone index -> Quaternion for the LEFT arm, mirrored from `right` (bone index -> Quaternion on
## the right arm). Each left bone's rotation is the right one's seen through the mirror, corrected
## by how its rest frame sits against the mirrored right rest - so it works whatever the bone rolls
## are, as long as the rest pose is symmetric. The chest is its own mirror partner.
static func mirror_to_left(right: Dictionary, skel: Skeleton3D) -> Dictionary:
	var out := {}
	if skel == null:
		return out
	for r_idx in right:
		var l_idx := skel.find_bone(skel.get_bone_name(r_idx).replace("Right", "Left"))
		if l_idx < 0 or l_idx == r_idx:
			continue
		var x_bone := _rest_flip(skel, r_idx, l_idx)
		var r_parent := skel.get_bone_parent(r_idx)
		var l_parent := skel.get_bone_parent(l_idx)
		var x_parent := _rest_flip(skel, r_parent, l_parent) if r_parent >= 0 and l_parent >= 0 \
			else MIRROR
		var q_left := x_parent.inverse() * Basis(right[r_idx] as Quaternion) * x_bone
		out[l_idx] = q_left.get_rotation_quaternion()
	return out


## The (improper) basis taking the mirrored right bone's rest frame onto the left bone's rest frame.
static func _rest_flip(skel: Skeleton3D, r_idx: int, l_idx: int) -> Basis:
	var r_rest := skel.get_bone_global_rest(r_idx).basis
	var l_rest := skel.get_bone_global_rest(l_idx).basis
	return (MIRROR * r_rest).inverse() * l_rest


## Which arm should be heading into the hold: Vector2(right, left), each 0 or 1.
static func targets_for(wall_running: bool, wall_on_right: bool) -> Vector2:
	if not wall_running:
		return Vector2.ZERO
	return Vector2(1.0, 0.0) if wall_on_right else Vector2(0.0, 1.0)


## Re-read every frame, like the item holder's pose, so wall_hand_rotations tunes live in the
## remote inspector. Four bones a side - nothing to cache.
func _process(_delta: float) -> void:
	if right_modifier == null or _body == null:
		return
	var right := _ItemHolder.pose_from_rotations(_body.wall_hand_rotations, _skeleton)
	right_modifier.pose = right
	left_modifier.pose = mirror_to_left(right, _skeleton)
	var t := targets_for(_body.is_wall_running, _body.wall_run_on_right())
	right_modifier.target = t.x
	left_modifier.target = t.y
