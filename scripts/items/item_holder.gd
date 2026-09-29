## pilot9's held item: two sockets on his skeleton, the item instance that moves between them, and
## the right-arm override while it is drawn. Built at runtime by pilot9.gd::_setup_item_holder()
## rather than saved into pilot9.tscn, so a rig swap by scripts/pilot9_build_scene.gd cannot drop
## it. Knows nothing about staffs - see docs/specs/pilot9-held-item.md.
extends Node

const _ArmPoseModifier := preload("res://scripts/items/arm_pose_modifier.gd")

const HAND_BONE := &"RightHand"
const BACK_BONE := &"UpperChest"

## The bones the hold pose may set. The blockout rig has no finger bones, so the fist is whatever
## the hand mesh is.
const ARM_BONES: PackedStringArray = ["RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]

## The per-move list: AnimationTree states the arm override may run in while drawn - and then
## only at running pace, see run_factor(). Anything not
## listed is off, so a move added later can never leave the arm stuck in the hold pose. Off keeps
## the item in his hand - it just follows whatever that move's clip does with it. The first split
## is a guess, to be tuned in play.
const ARM_OVERRIDE_STATES := {
	&"Locomotion": true,
	## Off in the air (user's call, 2026-09-26): a running jump opens both arms like a normal jump.
	&"jump": false,
	&"fall": false,
	&"jump_land": true,
	&"crouch": true,
	&"slide": true,
	&"climb": false,
	&"wall_run": false,
	&"rail": false,
}

var held_item: HeldItem = null
var is_drawn: bool = false
## The live instance of held_item.scene, or null with no item.
var item_instance: Node3D = null

var hand_socket: BoneAttachment3D = null
var back_socket: BoneAttachment3D = null
var arm_modifier: SkeletonModifier3D = null

var _skeleton: Skeleton3D = null
var _anim_player: AnimationPlayer = null
var _anim_tree: AnimationTree = null
## pilot9. Its velocity and its walk_speed / speed set run_factor(). Null means no speed gate.
var _body: Node = null


static func arm_override_for(state: StringName) -> bool:
	return ARM_OVERRIDE_STATES.get(state, false)


## How far into the running hold `horizontal` is: 0 at walking pace or slower, 1 at running pace
## or faster, linear between. Idle and walk keep the natural arm; run and sprint trail the item.
## The same gate covers the landing and the slide. The air is off the list entirely.
static func run_factor(horizontal: float, walk: float, run: float) -> float:
	if run <= walk:
		return 1.0 if horizontal >= run else 0.0
	return clampf((horizontal - walk) / (run - walk), 0.0, 1.0)


## bone index -> Quaternion from an item's hold_rotations (degrees), skipping names that are not
## arm bones or not on `skel`.
static func pose_from_rotations(rotations: Dictionary, skel: Skeleton3D) -> Dictionary:
	var out := {}
	if skel == null:
		return out
	for bone_name in rotations:
		if not ARM_BONES.has(String(bone_name)):
			continue
		var idx := skel.find_bone(bone_name)
		if idx < 0:
			continue
		var deg: Vector3 = rotations[bone_name]
		out[idx] = Quaternion.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z)))
	return out


func setup(skeleton: Skeleton3D, anim_player: AnimationPlayer, anim_tree: AnimationTree,
		body: Node = null) -> void:
	_skeleton = skeleton
	_anim_player = anim_player
	_anim_tree = anim_tree
	_body = body
	if _skeleton == null:
		push_error("item_holder: no skeleton - pilot9 will not be able to hold anything")
		return
	hand_socket = _make_socket(&"HandSocket", HAND_BONE)
	back_socket = _make_socket(&"BackSocket", BACK_BONE)
	arm_modifier = _ArmPoseModifier.new()
	arm_modifier.name = &"ArmPoseModifier"
	_skeleton.add_child(arm_modifier)


func _make_socket(socket_name: StringName, bone: StringName) -> BoneAttachment3D:
	var socket := BoneAttachment3D.new()
	socket.name = socket_name
	_skeleton.add_child(socket)
	# After add_child: BoneAttachment3D resolves the name against its parent skeleton.
	socket.bone_name = bone
	if socket.bone_idx < 0:
		push_error("item_holder: skeleton has no bone '%s' for %s" % [bone, socket_name])
	return socket


## Swaps the carried item. Keeps is_drawn, so a new staff lands where the old one was. null is
## "no item": the instance goes, the arm override goes to 0 and is_drawn drops to false.
func set_item(item: HeldItem) -> void:
	if item_instance != null:
		item_instance.queue_free()
		item_instance.get_parent().remove_child(item_instance)
		item_instance = null
	held_item = null
	if arm_modifier != null:
		arm_modifier.pose = {}
	if item == null or item.scene == null or _skeleton == null:
		is_drawn = false
		return
	held_item = item
	item_instance = item.scene.instantiate() as Node3D
	if item_instance == null:
		push_error("item_holder: %s's scene root is not a Node3D" % item.resource_path)
		held_item = null
		is_drawn = false
		return
	_refresh_pose()
	_place()


## Draw or holster. A snap: the item changes socket this frame. Does nothing with no item.
func toggle_drawn() -> void:
	if item_instance == null:
		return
	is_drawn = not is_drawn
	_place()


func _place() -> void:
	var socket := hand_socket if is_drawn else back_socket
	var offset := held_item.hand_offset if is_drawn else held_item.back_offset
	if item_instance.get_parent() != socket:
		if item_instance.get_parent() != null:
			item_instance.get_parent().remove_child(item_instance)
		socket.add_child(item_instance)
	item_instance.transform = offset


## Whether `node` is part of the held item - pilot9's rim light skips these, which stays pilot-only.
func owns(node: Node) -> bool:
	return item_instance != null and (item_instance == node or item_instance.is_ancestor_of(node))


## Where the arm override should be heading this frame.
func arm_target() -> float:
	if not is_drawn or arm_modifier == null or arm_modifier.pose.is_empty():
		return 0.0
	if _body == null:
		return 1.0 if arm_override_for(_current_state()) else 0.0
	var v: Vector3 = _body.velocity
	return arm_target_for(_current_state(), Vector2(v.x, v.z).length(), _body.walk_speed, _body.speed)


## The drawn arm's target in `state` at `horizontal` m/s: the per-move list, then the run gate.
static func arm_target_for(state: StringName, horizontal: float, walk: float, run: float) -> float:
	if not arm_override_for(state):
		return 0.0
	return run_factor(horizontal, walk, run)


func _current_state() -> StringName:
	if _anim_tree == null or not _anim_tree.active:
		return &""
	var playback := _anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	return playback.get_current_node() if playback != null else &""


## Re-read every frame, not once at set_item(), so editing hold_rotations in the remote inspector
## moves the arm live. Four bones - nothing to cache.
func _refresh_pose() -> void:
	if arm_modifier != null:
		arm_modifier.pose = pose_from_rotations(held_item.hold_rotations, _skeleton) 			if held_item != null else {}


func _process(_delta: float) -> void:
	_refresh_pose()
	if arm_modifier != null:
		arm_modifier.target = arm_target()
