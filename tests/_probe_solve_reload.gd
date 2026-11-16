extends SceneTree

# Throwaway SOLVER, headless: the reload's key poses for both guns. Same method as
# _probe_solve_aim.gd (an evolution strategy over the arm joints' euler degrees against a cost), but the
# targets are reload ones: the gun tilted at the chest and the left hand on the cylinder / magwell /
# charging handle. Writes res://scripts/items/gun_reload_poses.gd. Run:
#   godot --headless --path . --script tests/_probe_solve_reload.gd
# Targets are (forward, right, up) metres from the right shoulder for the grip, a (forward, right, up)
# direction for the muzzle, and a point in the gun's own frame for the left hand.

const RIGHT := [&"RightUpperArm", &"RightLowerArm", &"RightHand"]
const LEFT := [&"LeftUpperArm", &"LeftLowerArm", &"LeftHand"]

const SPECS := {
	"REVOLVER": {
		"slot": 1,
		"poses": {
			# Break and dump: muzzle up, the left hand on the cylinder.
			"R1": {"grip": Vector3(0.32, -0.02, -0.22), "dir": Vector3(0.5, 0.0, 0.85), "left": Vector3(0.05, 0.04, -0.07)},
			# The speedloader goes in: muzzle level-down, the hand a touch up the cylinder.
			"R2": {"grip": Vector3(0.32, -0.02, -0.22), "dir": Vector3(0.85, 0.0, -0.1), "left": Vector3(0.05, 0.07, -0.07)},
		},
	},
	"RIFLE": {
		"slot": 0,
		"poses": {
			# Tilted across the chest, the left hand low at the magwell to catch / hold the mag.
			"R1": {"grip": Vector3(0.30, -0.03, -0.30), "dir": Vector3(0.6, -0.1, 0.8), "left": Vector3(0.0, -0.22, -0.05)},
			# The fresh magazine up in the well.
			"R2": {"grip": Vector3(0.30, -0.03, -0.30), "dir": Vector3(0.6, -0.1, 0.8), "left": Vector3(0.0, -0.10, -0.05)},
			# The charging handle: hand forward on the receiver, then pulled back.
			"R3": {"grip": Vector3(0.30, -0.03, -0.30), "dir": Vector3(0.7, -0.1, 0.7), "left": Vector3(0.06, 0.08, -0.15)},
			"R4": {"grip": Vector3(0.30, -0.03, -0.30), "dir": Vector3(0.7, -0.1, 0.7), "left": Vector3(0.06, 0.08, 0.05)},
		},
	},
}

var _pilot: Node
var _frames := 0
var _stage := 0
var _skel: Skeleton3D
var _holder: Node
var _item: Node3D
var _base := {}
var _rng := RandomNumberGenerator.new()
var _spec: Dictionary
var _out := {}


func _initialize() -> void:
	var inv := root.get_node_or_null("/root/Inventory")
	if inv != null:
		inv.persist = false
	_rng.seed = 11
	root.add_child((load("res://scenes/trial.tscn") as PackedScene).instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 20:
		return false
	if _stage == 0:
		_pilot = get_nodes_in_group(&"reflect_target")[0]
		_pilot.global_position += Vector3(0, 0.3, 0)
		_pilot.camera_pivot.rotation.x = 0.0
		_stage = 1
		_frames = 20
		return false
	if _stage == 1 and _frames == 30:
		_solve_gun("REVOLVER")
		_pilot.draw_slot(0, true)
		_stage = 2
		return false
	if _stage == 1 and _frames > 30:
		return false
	if _stage == 2 and _frames == 60:
		_solve_gun("RIFLE")
		_write()
		quit()
		return true
	return false


func _solve_gun(gun_name: String) -> void:
	_spec = SPECS[gun_name]
	if gun_name == "REVOLVER":
		_pilot.draw_slot(1, true)
	_holder = _pilot.item_holder
	_skel = _holder._skeleton
	_item = _holder.item_instance
	_holder.arm_modifier.active = false
	var held: HeldItem = _holder.held_item
	# Baseline: the hip hold for the right arm; the left arm too if the gun holds it, else wherever
	# the animation has it now.
	_base = {}
	for k in RIGHT:
		_base[k] = held.hold_rotations[k]
	for k in LEFT:
		if held.hold_rotations.has(k):
			_base[k] = held.hold_rotations[k]
		else:
			var e := _skel.get_bone_pose_rotation(_skel.find_bone(k)).get_euler()
			_base[k] = Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))
	var results := {}
	for pose_name in _spec.poses:
		var best := _search(_spec.poses[pose_name])
		print(gun_name, " ", pose_name, " cost ", snappedf(best.cost, 0.001))
		var o := {}
		for k in best.params:
			o[k] = best.params[k]
		results[pose_name] = o
		_report(best.params, _spec.poses[pose_name])
	_out[gun_name] = results


func _apply(params: Dictionary) -> void:
	for name in params:
		var d: Vector3 = params[name]
		_skel.set_bone_pose_rotation(_skel.find_bone(name),
			Quaternion.from_euler(Vector3(deg_to_rad(d.x), deg_to_rad(d.y), deg_to_rad(d.z))))
	_skel.force_update_all_bone_transforms()


func _item_xf() -> Transform3D:
	var hand := _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(&"RightHand"))
	return Transform3D(hand.basis.orthonormalized(), hand.origin) * _holder.held_item.hand_offset


func _world(spec: Dictionary) -> Dictionary:
	var ch: Node3D = _pilot.character
	var f := ch.global_basis.z
	var r := ch.global_basis.x
	var shoulder := (_skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(&"RightUpperArm"))).origin
	var g: Vector3 = spec.grip
	var d: Vector3 = spec.dir
	return {"grip": shoulder + f * g.x + r * g.y + Vector3.UP * g.z,
		"dir": (f * d.x + r * d.y + Vector3.UP * d.z).normalized()}


func _cost(params: Dictionary, spec: Dictionary) -> float:
	_apply(params)
	var w := _world(spec)
	var xf := _item_xf()
	var c: float = ((-xf.basis.z) - w.dir).length_squared() * 40.0
	c += (xf.origin - w.grip).length_squared() * 12.0
	var lh := (_skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(&"LeftHand"))).origin
	c += (xf * (spec.left as Vector3) - lh).length_squared() * 18.0
	for k in params:
		var q := Quaternion.from_euler(Vector3(deg_to_rad(params[k].x), deg_to_rad(params[k].y), deg_to_rad(params[k].z)))
		var h: Vector3 = _base[k]
		var qh := Quaternion.from_euler(Vector3(deg_to_rad(h.x), deg_to_rad(h.y), deg_to_rad(h.z)))
		c += pow(q.angle_to(qh), 2.0) * 0.03
	return c


func _search(spec: Dictionary) -> Dictionary:
	var best_params := {}
	var best_cost := INF
	for restart in 8:
		var cur := {}
		for k in _base:
			cur[k] = _base[k] + (Vector3.ZERO if restart == 0 else Vector3(_rng.randfn(0, 40), _rng.randfn(0, 40), _rng.randfn(0, 40)))
		var cur_cost := _cost(cur, spec)
		var sigma := 30.0
		for i in 3500:
			var cand := {}
			for k in cur:
				cand[k] = cur[k] + Vector3(_rng.randfn(0, sigma), _rng.randfn(0, sigma), _rng.randfn(0, sigma)) * (1.0 if _rng.randf() < 0.5 else 0.0)
			var c := _cost(cand, spec)
			if c < cur_cost:
				cur = cand
				cur_cost = c
			if i % 250 == 249:
				sigma = maxf(sigma * 0.7, 0.4)
		if cur_cost < best_cost:
			best_cost = cur_cost
			best_params = cur
	return {"params": best_params, "cost": best_cost}


func _report(params: Dictionary, spec: Dictionary) -> void:
	_cost(params, spec)
	var w := _world(spec)
	var xf := _item_xf()
	var lh := (_skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(&"LeftHand"))).origin
	print("    muzzle err deg ", snappedf(rad_to_deg((-xf.basis.z).angle_to(w.dir)), 0.1), "  grip err m ",
		snappedf((xf.origin - w.grip).length(), 0.001), "  left err m ", snappedf((xf * (spec.left as Vector3) - lh).length(), 0.001))


func _write() -> void:
	var s := "## GENERATED by tests/_probe_solve_reload.gd - do not edit by hand. The reload's key poses:\n"
	s += "## gun -> pose -> bone -> euler degrees (YXZ), parent-relative like HeldItem.hold_rotations.\n"
	s += "class_name GunReloadPoses\n\nconst POSES := {\n"
	for gun in _out:
		s += "\t\"%s\": {\n" % gun
		for pose in _out[gun]:
			s += "\t\t\"%s\": {\n" % pose
			for bone in _out[gun][pose]:
				var v: Vector3 = _out[gun][pose][bone]
				s += "\t\t\t&\"%s\": Vector3(%.1f, %.1f, %.1f),\n" % [bone, v.x, v.y, v.z]
			s += "\t\t},\n"
		s += "\t},\n"
	s += "}\n"
	var f := FileAccess.open("res://scripts/items/gun_reload_poses.gd", FileAccess.WRITE)
	f.store_string(s)
	f.close()
	print("wrote gun_reload_poses.gd")
