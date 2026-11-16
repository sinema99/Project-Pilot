extends SceneTree

# Throwaway probe, headless: measures what the rifle aim IK needs from the model, in the ITEM frame
# (origin at the pistol grip, -Z down the barrel, +Y up): how far the stock ends behind the grip, the
# muzzle's distance, and where the LEFT fist sits on the handguard at the hip pose. Prints values to
# paste into rifle.tres. Run:
#   godot --headless --path . --script tests/_probe_aim_ik_setup.gd

var _pilot: Node
var _frames := 0


func _initialize() -> void:
	var inv := root.get_node_or_null("/root/Inventory")
	if inv != null:
		inv.persist = false
	root.add_child((load("res://scenes/trial.tscn") as PackedScene).instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		_pilot = get_nodes_in_group(&"reflect_target")[0]
		_pilot.draw_slot(0, true)
	if _frames == 60:
		_measure()
		quit()
		return true
	return false


func _measure() -> void:
	var holder: Node = _pilot.item_holder
	var skel: Skeleton3D = holder._skeleton
	var item: Node3D = holder.item_instance
	var held: HeldItem = holder.held_item
	holder.arm_modifier.active = false
	# The hip pose on the arms, no twist.
	var pose := {}
	for k in held.hold_rotations:
		var d: Vector3 = held.hold_rotations[k]
		skel.set_bone_pose_rotation(skel.find_bone(k),
			Quaternion.from_euler(Vector3(deg_to_rad(d.x), deg_to_rad(d.y), deg_to_rad(d.z))))
	skel.force_update_all_bone_transforms()
	var rh := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(&"RightHand"))
	var xf := Transform3D(rh.basis.orthonormalized(), rh.origin) * held.hand_offset
	var lh := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(&"LeftHand"))
	var left_local := xf.affine_inverse() * Transform3D(lh.basis.orthonormalized(), lh.origin)
	print("left hand in item frame: origin ", left_local.origin, " basis ", left_local.basis)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for n in item.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var to_item := xf.affine_inverse() * mi.global_transform if false else item.global_transform.affine_inverse() * mi.global_transform
		var bb := mi.get_aabb()
		for i in 8:
			var corner := to_item * bb.get_endpoint(i)
			lo = lo.min(corner)
			hi = hi.max(corner)
	print("item bounds (item frame, grip origin) min ", lo, " max ", hi)
	var m := item.find_child("Muzzle", true, false)
	if m != null:
		print("muzzle at ", (item.global_transform.affine_inverse() * (m as Node3D).global_transform).origin)
	print("item origin vs hand-offset frame err ", (item.global_transform.origin - xf.origin).length())
	print("head bone (skeleton) ", skel.get_bone_global_pose(skel.find_bone(&"Head")).origin,
		" right upper arm ", skel.get_bone_global_pose(skel.find_bone(&"RightUpperArm")).origin)
	print("forearm len ", skel.get_bone_rest(skel.find_bone(&"RightHand")).origin.length(),
		" upper len ", skel.get_bone_rest(skel.find_bone(&"RightLowerArm")).origin.length())
	print("ClassDB TwoBoneIK3D: ", ClassDB.class_exists(&"TwoBoneIK3D"))
