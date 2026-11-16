extends SceneTree

# Throwaway SOLVER, headless: finds the arm rotations that raise a gun to the aim line, at three
# camera pitches, and prints them as .tres Dictionary lines. The bones' axes are not guessable, so a
# (1+1) evolution strategy searches the arm joints' euler degrees against a cost: the muzzle points at
# the crosshair's aim point, the grip sits in front of the shoulder, the gun is upright, and (rifle)
# the left hand stays on the same spot of the gun it holds at the hip. Run:
#   godot --headless --path . --script tests/_probe_solve_aim.gd -- <weapon_slot 0 rifle | 1 revolver>
# Sets Inventory.persist = false first.

const PITCHES := [-40.0, 0.0, 40.0]
const RIGHT := [&"RightUpperArm", &"RightLowerArm", &"RightHand"]
const LEFT := [&"LeftUpperArm", &"LeftLowerArm", &"LeftHand"]

var _pilot: Node
var _frames := 0
var _slot := 0
var _stage := 0
var _skel: Skeleton3D
var _holder: Node
var _item: Node3D
var _hip := {}
var _left_local := Vector3.ZERO
var _cam_pos := Vector3.ZERO
var _cam_fwd := Vector3.ZERO
var _two_handed := false
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_slot = int(args[0]) if args.size() > 0 else 0
	var inv := root.get_node_or_null("/root/Inventory")
	if inv != null:
		inv.persist = false
	_rng.seed = 7
	var ps := load("res://scenes/trial.tscn") as PackedScene
	root.add_child(ps.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 20:
		return false
	if _stage == 0:
		var pilots := get_nodes_in_group(&"reflect_target")
		if pilots.is_empty():
			print("no pilot")
			quit(1)
			return true
		_pilot = pilots[0]
		_pilot.global_position += Vector3(0, 0.3, 0)
		_pilot.camera_pivot.rotation.x = 0.0
		_pilot.draw_slot(_slot, true)
		_stage = 1
		_frames = 20
		return false
	if _stage == 1 and _frames == 40:
		_pilot.camera_pivot.rotation.x = 0.0
		Input.action_press(&"aim")
		_stage = 2
		return false
	if _stage == 2 and _frames == 110:
		_solve_all()
		quit()
		return true
	return false


func _solve_all() -> void:
	_holder = _pilot.item_holder
	_skel = _holder._skeleton
	_item = _holder.item_instance
	var held: HeldItem = _holder.held_item
	_two_handed = held.hold_rotations.has(&"LeftUpperArm")
	_holder.arm_modifier.active = false
	# The bladed stance goes on once, before any arm solve: the arms hang off the turned chest.
	var yaws := {}
	for bone_name in held.aim_twist_deg:
		yaws[_skel.find_bone(bone_name)] = deg_to_rad(held.aim_twist_deg[bone_name])
	_holder.arm_modifier.apply_twist(_skel, yaws)
	_skel.force_update_all_bone_transforms()
	_cam_pos = _pilot.camera_3d.global_position
	_cam_fwd = -_pilot.camera_3d.global_basis.z
	print("slot ", _slot, " gun ", held.gun.display_name, " two-handed ", _two_handed)
	# The hip pose is the baseline: apply it, record the left hand's spot on the gun.
	_hip = ItemHolder_pose(held.hold_rotations)
	_apply(_hip)
	var xf := _item_xf()
	var hand := _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(&"LeftHand"))
	_left_local = xf.affine_inverse() * hand.origin
	var muzzle_dir := -xf.basis.z
	var fwd: Vector3 = _pilot.character.global_basis.z
	print("hip muzzle dir ", muzzle_dir, " character +z ", fwd, " cam fwd ", _cam_fwd)
	var result := {}
	for pitch in PITCHES:
		var best := _search(pitch)
		var o := {}
		for k in best.params:
			o[k] = [best.params[k].x, best.params[k].y, best.params[k].z]
		result[str(int(pitch))] = o
		print("--- pitch ", pitch, " cost ", best.cost)
		for k in best.params:
			print("&\"", k, "\": Vector3(", snappedf(best.params[k].x, 0.1), ", ",
				snappedf(best.params[k].y, 0.1), ", ", snappedf(best.params[k].z, 0.1), "),")
		_report(best.params, pitch)
	var f := FileAccess.open(OS.get_cmdline_user_args()[1], FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()


func ItemHolder_pose(rot: Dictionary) -> Dictionary:
	var out := {}
	for k in rot:
		out[k] = rot[k]
	return out


func _bones() -> Array:
	var b: Array = []
	b.append_array(RIGHT)
	if _two_handed:
		b.append_array(LEFT)
	return b


func _apply(params: Dictionary) -> void:
	for name in params:
		var d: Vector3 = params[name]
		_skel.set_bone_pose_rotation(_skel.find_bone(name),
			Quaternion.from_euler(Vector3(deg_to_rad(d.x), deg_to_rad(d.y), deg_to_rad(d.z))))
	_skel.force_update_all_bone_transforms()


func _item_xf() -> Transform3D:
	var hand := _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(&"RightHand"))
	var held: HeldItem = _holder.held_item
	return Transform3D(hand.basis.orthonormalized(), hand.origin) * held.hand_offset


## The aim target for `pitch` degrees of camera pitch: direction and grip point.
func _targets(pitch: float) -> Dictionary:
	var right: Vector3 = _pilot.character.global_basis.x
	var rot := Basis(right, deg_to_rad(pitch))
	var dir := rot * _cam_fwd
	var aim_point := _cam_pos + dir * 25.0
	var shoulder := (_skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(&"RightUpperArm"))).origin
	var grip: Vector3 = shoulder + rot * (_cam_fwd * (0.34 if _two_handed else 0.42) + Vector3(0, -0.05, 0))
	if _two_handed:
		# Shouldered (the reference photo): the pistol grip sits level with the shoulder joint,
		# 0.40 m ahead of it and 0.10 m toward the chest centre, the stock in the shoulder pocket.
		# The model faces +Z, so its local +X is his LEFT.
		var left: Vector3 = _pilot.character.global_basis.x
		grip = shoulder + rot * (_cam_fwd * 0.40 + left * 0.10 + Vector3(0, 0.0, 0))
	return {"point": aim_point, "grip": grip, "dir": dir}


func _cost(params: Dictionary, t: Dictionary) -> float:
	_apply(params)
	var xf := _item_xf()
	var muzzle: Vector3 = xf * _item.find_child("Muzzle", true, false).position
	var want: Vector3 = (t.point - muzzle).normalized()
	var have := -xf.basis.z
	var up_want: Vector3 = (Vector3.UP - want * Vector3.UP.dot(want)).normalized()
	var c := (have - want).length_squared() * 40.0
	c += (xf.origin - t.grip).length_squared() * (30.0 if _two_handed else 12.0)
	c += (xf.basis.y - up_want).length_squared() * 3.0
	if _two_handed:
		var lh := (_skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(&"LeftHand"))).origin
		c += (xf * _left_local - lh).length_squared() * 14.0
	if _two_handed:
		var gt := _skel.global_transform
		var head: Vector3 = (gt * _skel.get_bone_global_pose(_skel.find_bone(&"Head"))).origin
		# Cheek weld: the barrel line passes close to the eye (just above the head bone's origin).
		var eye := head + Vector3(0, 0.08, 0)
		var axis := -xf.basis.z
		var off := eye - xf.origin
		var closest := off - axis * off.dot(axis)
		c += closest.length_squared() * 30.0
		# Elbows hang: both sit well below their shoulder, not flared up.
		for pair in [[&"RightLowerArm", &"RightUpperArm"], [&"LeftLowerArm", &"LeftUpperArm"]]:
			var elbow: Vector3 = (gt * _skel.get_bone_global_pose(_skel.find_bone(pair[0]))).origin
			var sh: Vector3 = (gt * _skel.get_bone_global_pose(_skel.find_bone(pair[1]))).origin
			c += pow(maxf(0.0, elbow.y - (sh.y - 0.2)), 2.0) * 6.0
	# Stay near the hip pose: no corkscrewed arms.
	for k in params:
		var q := Quaternion.from_euler(Vector3(deg_to_rad(params[k].x), deg_to_rad(params[k].y), deg_to_rad(params[k].z)))
		var h: Vector3 = _hip[k]
		var qh := Quaternion.from_euler(Vector3(deg_to_rad(h.x), deg_to_rad(h.y), deg_to_rad(h.z)))
		c += pow(q.angle_to(qh), 2.0) * (0.004 if _two_handed else 0.03)
	return c


func _search(pitch: float) -> Dictionary:
	var t := _targets(pitch)
	var best_params := {}
	var best_cost := INF
	for restart in 6:
		var cur := {}
		for k in _bones():
			var h: Vector3 = _hip[k]
			cur[k] = h + (Vector3.ZERO if restart == 0 else Vector3(_rng.randfn(0, 40), _rng.randfn(0, 40), _rng.randfn(0, 40)))
		var cur_cost := _cost(cur, t)
		var sigma := 30.0
		for i in 3500:
			var cand := {}
			for k in cur:
				cand[k] = cur[k] + Vector3(_rng.randfn(0, sigma), _rng.randfn(0, sigma), _rng.randfn(0, sigma)) * (1.0 if _rng.randf() < 0.5 else 0.0)
			var c := _cost(cand, t)
			if c < cur_cost:
				cur = cand
				cur_cost = c
			if i % 250 == 249:
				sigma = maxf(sigma * 0.7, 0.4)
		if cur_cost < best_cost:
			best_cost = cur_cost
			best_params = cur
	return {"params": best_params, "cost": best_cost}


func _report(params: Dictionary, pitch: float) -> void:
	var t := _targets(pitch)
	_cost(params, t)
	var xf := _item_xf()
	var muzzle: Vector3 = xf * _item.find_child("Muzzle", true, false).position
	var want: Vector3 = (t.point - muzzle).normalized()
	print("    muzzle err deg ", rad_to_deg((-xf.basis.z).angle_to(want)), "  grip err m ", (xf.origin - t.grip).length(),
		"  upness ", xf.basis.y.dot(Vector3.UP))
	if _two_handed:
		var gt := _skel.global_transform
		var lh := (gt * _skel.get_bone_global_pose(_skel.find_bone(&"LeftHand"))).origin
		var head: Vector3 = (gt * _skel.get_bone_global_pose(_skel.find_bone(&"Head"))).origin
		var axis := -xf.basis.z
		var off := head + Vector3(0, 0.08, 0) - xf.origin
		var sr: Vector3 = (gt * _skel.get_bone_global_pose(_skel.find_bone(&"RightUpperArm"))).origin
		var sl: Vector3 = (gt * _skel.get_bone_global_pose(_skel.find_bone(&"LeftUpperArm"))).origin
		print("    left hand err m ", (xf * _left_local - lh).length(),
			"  eye-to-barrel m ", (off - axis * off.dot(axis)).length(),
			"  grip-to-R-shoulder ", xf.origin - sr, "  L-shoulder-to-R ", sl - sr)
