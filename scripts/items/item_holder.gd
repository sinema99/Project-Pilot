## pilot9's held item: a hand socket on his skeleton, the item instance in it (hidden while
## holstered - he materializes it, see docs/specs/pilot9-staff-materialize.md), and the right-arm
## override while it is drawn. Built at runtime by pilot9.gd::_setup_item_holder()
## rather than saved into pilot9.tscn, so a rig swap by scripts/pilot9_build_scene.gd cannot drop
## it. Knows nothing about staffs - see docs/specs/pilot9-held-item.md.
extends Node

const _ArmPoseModifier := preload("res://scripts/items/arm_pose_modifier.gd")

const HAND_BONE := &"RightHand"
## The camera pitch the up / down aim poses were solved at, degrees.
const AIM_POSE_PITCH_DEG := 40.0

## The bones the hold pose may set. The blockout rig has no finger bones, so the fist is whatever
## the hand mesh is.
## The first four are the right arm and must stay first (equip_anim.gd indexes them); the left arm
## follows, used only by a two-handed item like the rifle.
const ARM_BONES: PackedStringArray = ["RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand"]

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
	&"wall_climb": false,
	&"rail": false,
}

var held_item: HeldItem = null
var is_drawn: bool = false
## The live instance of held_item.scene, or null with no item.
var item_instance: Node3D = null

var hand_socket: BoneAttachment3D = null
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


## Draw or holster. A snap: the item shows or hides this frame. Does nothing with no item.
func toggle_drawn() -> void:
	set_drawn(not is_drawn)


## Shows the item in the hand (true) or hides it, as a snap. Does nothing with no item. The
## equip animation (scripts/items/equip_anim.gd) calls this at its handovers.
func set_drawn(drawn: bool) -> void:
	if item_instance == null:
		return
	is_drawn = drawn
	_place()


func _place() -> void:
	if item_instance.get_parent() != hand_socket:
		if item_instance.get_parent() != null:
			item_instance.get_parent().remove_child(item_instance)
		hand_socket.add_child(item_instance)
	item_instance.transform = held_item.hand_offset
	item_instance.visible = is_drawn


## Whether `node` is part of the held item - pilot9's rim light skips these, which stays pilot-only.
func owns(node: Node) -> bool:
	return item_instance != null and (item_instance == node or item_instance.is_ancestor_of(node))


## Where the arm override should be heading this frame.
func arm_target() -> float:
	if not is_drawn:
		return 0.0
	# A placed aim (aim_ik) holds in every move he can aim in, the air included: the per-move off
	# list is about the hip carry, and an aim with the arms left to the jump clip points nowhere.
	var gp: Node = _body.get(&"gunplay") if _body != null else null
	if gp != null and held_item != null and held_item.aim_ik and gp.aim_pose > 0.001:
		return 1.0
	return drawn_arm_target()


## Where the arm override would be heading this frame if the item were drawn. The equip animation
## settles into this before is_drawn turns true.
func drawn_arm_target() -> float:
	if item_instance == null or arm_modifier == null or arm_modifier.pose.is_empty():
		return 0.0
	if _body == null:
		return 1.0 if item_holds_in(held_item, _current_state()) else 0.0
	var v: Vector3 = _body.velocity
	return item_target_for(held_item, _current_state(), Vector2(v.x, v.z).length(),
		_body.walk_speed, _body.speed)


## The drawn arm's target for `item` in `state` at `horizontal` m/s: the per-move list, the item's
## own off list, then the run gate unless the item holds at any pace.
static func item_target_for(item: HeldItem, state: StringName, horizontal: float, walk: float,
		run: float) -> float:
	if not item_holds_in(item, state):
		return 0.0
	if item != null and item.hold_at_any_speed:
		return 1.0
	return run_factor(horizontal, walk, run)


## Whether `item`'s hold may run in `state`: the holder's per-move list, minus the item's own
## off list. The pace gate is separate (run_factor), and skipped by hold_at_any_speed.
static func item_holds_in(item: HeldItem, state: StringName) -> bool:
	if not arm_override_for(state):
		return false
	return item == null or not item.hold_off_states.has(state)


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
		arm_modifier.pose = current_pose() if held_item != null else {}
		arm_modifier.weights = gun_weights()
		arm_modifier.twist = aim_twist()
		_refresh_ik()


## Feeds the aim IK: on for an item with aim_ik, weighted by the gun's aim pose (it lets go across a
## reload), aimed at what the crosshair is on - never nearer than 6 m (a close wall does not
## cross the barrel's eyes) and never further than 25 m, where the barrel converges.
func _refresh_ik() -> void:
	var gp: Node = _body.get(&"gunplay") if _body != null else null
	if gp == null or held_item == null or not held_item.aim_ik:
		arm_modifier.ik_item = null
		arm_modifier.ik_weight = 0.0
		return
	arm_modifier.ik_item = held_item
	arm_modifier.ik_weight = gp.aim_pose
	arm_modifier.ik_body = _body.get(&"character")
	arm_modifier.ik_aim_point = aim_point_world()


## The world point the crosshair is on: the camera ray's first hit within 80 m, else 40 m out.
func aim_point_world() -> Vector3:
	var cam: Camera3D = _body.get(&"camera_3d") if _body != null else null
	if cam == null:
		return Vector3.ZERO
	# Under free-look the frame frozen at the press, so the gun keeps aiming where it was.
	var view: Transform3D = _body.aim_view_transform() if _body.has_method(&"aim_view_transform") \
		else cam.global_transform
	var from := view.origin
	var dir := -view.basis.z
	var dist := 40.0
	var world: World3D = cam.get_world_3d()
	if world != null and world.direct_space_state != null:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 80.0, 1 | 256)
		q.exclude = [_body.get_rid()] if _body is CollisionObject3D else []
		var hit := world.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			dist = from.distance_to(hit.position)
	return from + dir * clampf(dist, 6.0, 25.0)


## The bladed stance this frame: the item's aim_twist_deg scaled by the gun's aim pose (it lets go
## across a reload and eases in with the arms). Bone index -> radians.
func aim_twist() -> Dictionary:
	var gp: Node = _body.get(&"gunplay") if _body != null else null
	if gp == null or held_item == null or held_item.aim_twist_deg.is_empty() or _skeleton == null:
		return {}
	var out := {}
	for bone_name in held_item.aim_twist_deg:
		var idx := _skeleton.find_bone(bone_name)
		if idx >= 0:
			out[idx] = deg_to_rad(held_item.aim_twist_deg[bone_name]) * gp.aim_pose
	return out


## The hold pose at this frame's pace: hold_rotations, or - for an item with idle_rotations - the
## idle pose blended into it by run_factor (0 at walking pace or slower, 1 running).
func current_pose() -> Dictionary:
	var pose := hip_pose()
	var gp: Node = _body.get(&"gunplay") if _body != null else null
	if gp == null or held_item.gun == null:
		return pose
	if gp.aim_pose > 0.001 and not held_item.aim_rotations.is_empty() and not held_item.aim_ik:
		pose = blend_poses(pose, aim_pose_at(held_item, _skeleton, _pitch_deg()), gp.aim_pose)
	var progress: float = gp.reload_progress()
	if progress >= 0.0 and gp.reload_fx != null:
		pose = gp.reload_fx.overlay(pose, held_item.gun.display_name, progress,
			gp._reload_empty, _skeleton)
	return pose


## The aim pose for a camera `pitch_deg` up (positive) or down: the middle pose blended toward the
## up or down one by pitch / AIM_POSE_PITCH_DEG, either missing leaves the middle pose.
static func aim_pose_at(item: HeldItem, skel: Skeleton3D, pitch_deg: float) -> Dictionary:
	var mid := pose_from_rotations(item.aim_rotations, skel)
	var side: Dictionary = item.aim_rotations_up if pitch_deg >= 0.0 else item.aim_rotations_down
	if side.is_empty():
		return mid
	return blend_poses(mid, pose_from_rotations(side, skel),
		clampf(absf(pitch_deg) / AIM_POSE_PITCH_DEG, 0.0, 1.0))


## The camera's pitch in degrees, up positive (the orbit pivot's own x rotation).
func _pitch_deg() -> float:
	if _body == null or _body.get(&"camera_pivot") == null:
		return 0.0
	return rad_to_deg(_body.camera_pivot.rotation.x)


## Per-bone fade weights the reload asks for (empty when none is running).
func gun_weights() -> Dictionary:
	var gp: Node = _body.get(&"gunplay") if _body != null else null
	if gp == null or gp.reload_fx == null or gp.reload_progress() < 0.0:
		return {}
	return gp.reload_fx.weights


## The hip hold at this frame's pace (the pose before the aim and the reload).
func hip_pose() -> Dictionary:
	var run := pose_from_rotations(held_item.hold_rotations, _skeleton)
	if held_item.idle_rotations.is_empty():
		return run
	var w := 1.0
	if _body != null:
		var v: Vector3 = _body.velocity
		w = run_factor(Vector2(v.x, v.z).length(), _body.walk_speed, _body.speed)
	return blend_poses(pose_from_rotations(held_item.idle_rotations, _skeleton), run, w)


## bone index -> Quaternion, `a` slerped toward `b` by `w`. A bone only one of them has is kept as is.
static func blend_poses(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := {}
	for bone in a:
		out[bone] = (a[bone] as Quaternion).slerp(b[bone], w) if b.has(bone) else a[bone]
	for bone in b:
		if not out.has(bone):
			out[bone] = b[bone]
	return out


func _process(_delta: float) -> void:
	_refresh_pose()
	if arm_modifier != null:
		arm_modifier.target = arm_target()
