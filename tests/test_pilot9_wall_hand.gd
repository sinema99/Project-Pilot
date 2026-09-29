extends "res://tests/test_case.gd"

# docs/specs/pilot9-wall-run.md, "The wall hand". Which arm, the mirror, and that the staff is left
# alone. Whether the hand reaches the wall is judged in play.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const STAFF := "res://resources/items/staff.tres"
const WALL_HAND := preload("res://scripts/wall_hand.gd")

# One shared in-tree instance, for the reason tests/test_pilot9_dash.gd gives.
var _pilot: Node = null

func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	return _pilot

func _skel(pilot: Node) -> Skeleton3D:
	return pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D

func test_targets_follow_the_wall_side() -> void:
	eq(WALL_HAND.targets_for(false, true), Vector2.ZERO, "no run, no hand")
	eq(WALL_HAND.targets_for(true, true), Vector2(1, 0), "right wall -> right arm")
	eq(WALL_HAND.targets_for(true, false), Vector2(0, 1), "left wall -> left arm")

func test_built_with_two_modifiers_after_the_items() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var wh: Node = pilot.wall_hand
	check(wh != null, "pilot9 should build its wall hand in _ready")
	if wh == null:
		return
	var skel := _skel(pilot)
	eq(wh.right_modifier.get_parent(), skel, "right modifier lives on the skeleton")
	eq(wh.left_modifier.get_parent(), skel, "left modifier lives on the skeleton")
	var item_mod: Node = pilot.item_holder.arm_modifier
	check(wh.right_modifier.get_index() > item_mod.get_index(), "wall hand should run after the item's arm")

func test_default_pose_is_the_staff_hold() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	eq(pilot.wall_hand_rotations, load(STAFF).hold_rotations, "the wall hand starts as the staff's hold")

# Mirroring the rest pose must give the left rest pose - the rig is symmetric, so the right arm at
# rest mirrors to the left arm at rest.
func test_mirror_of_rest_is_rest() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var skel := _skel(pilot)
	var right := {}
	for n in ["RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]:
		var i := skel.find_bone(n)
		right[i] = skel.get_bone_rest(i).basis.get_rotation_quaternion()
	var left: Dictionary = WALL_HAND.mirror_to_left(right, skel)
	eq(left.size(), 4, "all four arm bones mirror")
	for l_idx in left:
		var rest := skel.get_bone_rest(l_idx).basis.get_rotation_quaternion()
		check((left[l_idx] as Quaternion).angle_to(rest) < 0.01,
			"%s rest should mirror onto itself" % skel.get_bone_name(l_idx))

# The hold's hand, mirrored, lands at the mirror image of the right hand's position.
func test_mirrored_hold_puts_the_hand_in_the_mirror_spot() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var skel := _skel(pilot)
	var right := preload("res://scripts/items/item_holder.gd").pose_from_rotations(pilot.wall_hand_rotations, skel)
	var left: Dictionary = WALL_HAND.mirror_to_left(right, skel)
	var r_hand := _chain_origin(skel, skel.find_bone("RightHand"), right)
	var l_hand := _chain_origin(skel, skel.find_bone("LeftHand"), left)
	check(Vector3(-r_hand.x, r_hand.y, r_hand.z).distance_to(l_hand) < 0.01,
		"left hand %s should mirror right hand %s" % [l_hand, r_hand])

# Skeleton-space transform of `bone` with `pose` rotations over the rest pose, UpperChest at rest.
func _chain_origin(skel: Skeleton3D, bone: int, pose: Dictionary) -> Vector3:
	var chain: Array[int] = []
	var b := bone
	while b >= 0 and pose.has(b):
		chain.push_front(b)
		b = skel.get_bone_parent(b)
	var t := skel.get_bone_global_rest(b)
	for i in chain:
		var local := skel.get_bone_rest(i)
		local.basis = Basis(pose[i] as Quaternion)
		t = t * local
	return t.origin

func test_wall_run_does_not_draw_the_staff() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	pilot.set_item(load(STAFF))
	if pilot.is_item_drawn():
		pilot.toggle_drawn()
	pilot.is_wall_running = true
	pilot.wall_hand._process(0.016)
	check(not pilot.is_item_drawn(), "a wall run should leave the staff holstered")
	pilot.is_wall_running = false
	pilot.wall_hand._process(0.016)
