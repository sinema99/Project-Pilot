extends SceneTree

# Throwaway probe, WINDOWED: solves the rifle's two arm poses from the rig's rest with a two-bone
# solve per arm, prints them as resources/items/rifle.tres lines, applies them live and shoots
# them. IDLE = two-handed low-ready carry (walking pace or slower); HOLD = the sprint's one-handed
# side carry. Run:
#   godot --path . --script tests/_probe_rifle_shot.gd -- <out_dir>
# Tunables below (character space: +X his left, +Y up, +Z his front).

const EquipAnim := preload("res://scripts/items/equip_anim.gd")
const ItemHolder := preload("res://scripts/items/item_holder.gd")

## Idle carry: grip position relative to the right shoulder, barrel direction, left fist on the
## handguard (item-frame point), and elbow hints.
## Chest carry (2026-11-14): muzzle 35 deg down, pointing straight across to his left (yaw 90).
var idle_grip_off := Vector3(0.20, -0.28, 0.20)
var idle_barrel := Vector3(0.819, -0.574, 0.0)
var idle_left_fist := Vector3(0.0, -0.02, -0.45)
var left_palm_up := true

const SHOTS := [
	["idle_right.png", Vector3(-3.0, 1.3, 0.3), Vector3(0, 0.9, 0.1)],
	["idle_left.png", Vector3(3.0, 1.3, 0.3), Vector3(0, 0.9, 0.1)],
	["idle_front.png", Vector3(-1.4, 1.4, 3.0), Vector3(0, 0.9, 0.1)],
	["idle_front_left.png", Vector3(1.6, 1.3, 2.2), Vector3(0, 1.0, 0.3)],
	["idle_close.png", Vector3(0.9, 1.3, 1.5), Vector3(-0.05, 1.05, 0.35)],
	["idle_game_cam.png", Vector3.ZERO, Vector3.ZERO, true],
]

var _pilot: Node
var _frames := 0
var _out := ""
var _cam: Camera3D
var _idle := {}
var _dbg := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	if args.size() > 1 and args[1] == "flip":
		left_palm_up = false
	change_scene_to_file("res://scenes/trial.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	var inv := root.get_node_or_null("/root/Inventory")
	if inv != null:
		inv.persist = false  # never write the real loadout from a probe
	if _pilot == null:
		_pilot = _find_pilot(current_scene) if current_scene != null else null
		return _frames > 900
	if _frames == 40:
		_solve()
		_pilot.draw_slot(0, true)
		_cam = Camera3D.new()
		_cam.fov = 40.0
		current_scene.add_child(_cam)
	if _frames == 69:
		var sk2: Skeleton3D = _pilot.get_node("character/Armature/GeneralSkeleton")
		sk2.skeleton_updated.connect(_report.bind(sk2), CONNECT_ONE_SHOT)
	if _frames >= 70 and _frames < 70 + SHOTS.size() * 4:
		var k := (_frames - 70) / 4
		var step := (_frames - 70) % 4
		var sh: Array = SHOTS[k]
		if step == 0:
			if sh.size() > 3:
				_cam.current = false
			else:
				_place_cam(sh[1], sh[2])
		if step == 3:
			_shot(sh[0])
	return _frames > 70 + SHOTS.size() * 4 + 2


func _report(sk: Skeleton3D) -> void:
	for n in ["LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"]:
		var i := sk.find_bone(n)
		print("FINAL ", n, " pose deg ", (sk.get_bone_pose_rotation(i).get_euler() * 57.2958).snapped(Vector3(0.1, 0.1, 0.1)),
			" origin ", sk.get_bone_global_pose(i).origin.snapped(Vector3(0.001, 0.001, 0.001)))
	print("INTENDED idle LeftHand ", _idle.get(&"LeftHand"), " RightHand ", _idle.get(&"RightHand"),
		" LeftUpperArm ", _idle.get(&"LeftUpperArm"))
	var rifle: Node3D = _pilot.item_holder.item_instance
	var hg := rifle.to_global(idle_left_fist)
	var lh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftHand"))
	var fist := lh * Vector3(0.0, 0.08, 0.03)
	print("HANDGUARD world ", hg, " left fist world ", fist, " gap ", hg.distance_to(fist),
		" rifle origin ", rifle.global_position, " barrel dir ", (-rifle.global_basis.z).snapped(Vector3(0.01, 0.01, 0.01)))
	print("arm lengths L ", sk.get_bone_global_rest(sk.find_bone("LeftUpperArm")).origin.distance_to(sk.get_bone_global_rest(sk.find_bone("LeftLowerArm")).origin),
		" ", sk.get_bone_global_rest(sk.find_bone("LeftLowerArm")).origin.distance_to(sk.get_bone_global_rest(sk.find_bone("LeftHand")).origin))
	print("INTENDED grip world ", sk.global_transform * _dbg["grip"], " actual rifle ", rifle.global_position,
		" | intended fist world ", sk.global_transform * _dbg["fist"], " actual fist ", fist,
		" | wrist target dist from L shoulder ", (_dbg["fist"] as Vector3).distance_to(_shoulder_frame(sk, "Left").origin))
	print("INTENDED targets: right grip ", sk.get_bone_global_rest(sk.find_bone("RightUpperArm")).origin + idle_grip_off)


func _fmt(d: Dictionary) -> String:
	var parts: PackedStringArray = []
	var keys := d.keys()
	keys.sort()
	for k in keys:
		var v: Vector3 = d[k]
		parts.append("&\"%s\": Vector3(%s, %s, %s)" % [k, v.x, v.y, v.z])
	return "Dictionary[StringName, Vector3]({\n" + ",\n".join(parts) + "\n})"


func _solve() -> void:
	var sk: Skeleton3D = _pilot.get_node("character/Armature/GeneralSkeleton")
	var item: HeldItem = load("res://resources/items/rifle.tres")
	var idle := _eulers(_pose(sk, item, idle_grip_off, idle_barrel, true, idle_left_fist))
	# One chest carry at every pace: hold_rotations is the same dictionary as idle_rotations.
	print("idle_rotations = hold_rotations = ", _fmt(idle))
	item.idle_rotations.clear()
	item.idle_rotations.merge(idle)
	item.hold_rotations.clear()
	item.hold_rotations.merge(idle)
	_idle = idle


func _eulers(q: Dictionary) -> Dictionary:
	var out := {}
	for k in q:
		var e: Vector3 = (q[k] as Quaternion).get_euler()
		out[k] = Vector3(snappedf(rad_to_deg(e.x), 0.1), snappedf(rad_to_deg(e.y), 0.1), snappedf(rad_to_deg(e.z), 0.1))
	return out


## One carry pose, bone -> Quaternion. The arms are solved, put on the skeleton, the real fist
## positions measured, and the targets nudged by the miss - a few rounds, since the bones' rest
## offsets are not exactly along their own +Y.
func _pose(sk: Skeleton3D, item: HeldItem, grip_off: Vector3, barrel_dir: Vector3, two_hand: bool,
		left_fist_item: Vector3) -> Dictionary:
	var grip := _shoulder_frame(sk, "Right").origin + grip_off
	var gun := _gun_basis(barrel_dir.normalized())
	var hang := _shoulder_frame(sk, "Left").origin + Vector3(-0.02, -0.44, 0.16)
	var left_fist := grip + gun * left_fist_item
	var corr_r := Vector3.ZERO
	var corr_l := Vector3.ZERO
	var q := {}
	var r_pole := Vector3(-0.4, -1.0, -0.5) if two_hand else Vector3(-0.3, -1.0, -0.6)
	for it in 10:
		q = _right(sk, item, grip, gun, r_pole, corr_r)
		if two_hand:
			q.merge(_left(sk, left_fist, gun, Vector3(0.4, -1.0, -0.5), left_palm_up, corr_l))
		else:
			q.merge(_arm(sk, "Left", hang + corr_l, Vector3(-0.1, -1.0, -0.7), null))
		for k in q:
			sk.set_bone_pose_rotation(sk.find_bone(k), q[k])
		var fist_r := sk.get_bone_global_pose(sk.find_bone("RightHand")) * item.hand_offset.origin
		corr_r += grip - fist_r
		if two_hand:
			var fist_l := sk.get_bone_global_pose(sk.find_bone("LeftHand")) * Vector3(0.0, 0.08, 0.03)
			corr_l += left_fist - fist_l
		else:
			corr_l += hang - sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin
	if two_hand:
		_dbg["grip"] = grip
		_dbg["fist"] = left_fist
	print("pose miss  right ", (grip - (sk.get_bone_global_pose(sk.find_bone("RightHand")) * item.hand_offset.origin)).length(),
		"  corrections ", corr_r.length(), " / ", corr_l.length())
	return q


## The shoulder joint's position and its parent's pose as the animation has them now (not the rest
## pose: the idle clip leans the chest a little, and a pose solved from rest lands off the target).
func _shoulder_frame(sk: Skeleton3D, side: String) -> Transform3D:
	var i_sh := sk.find_bone(side + "Shoulder")
	var t_par := sk.get_bone_global_pose(sk.get_bone_parent(i_sh))
	var t_sh := t_par * Transform3D(sk.get_bone_rest(i_sh).basis, sk.get_bone_rest(i_sh).origin)
	return t_sh * sk.get_bone_rest(sk.find_bone(side + "UpperArm"))


func _gun_basis(barrel: Vector3) -> Basis:
	var top := (Vector3.UP - barrel * barrel.dot(Vector3.UP)).normalized()
	return Basis(top.cross(-barrel), top, -barrel)


func _right(sk: Skeleton3D, item: HeldItem, grip: Vector3, gun: Basis, pole: Vector3, corr: Vector3) -> Dictionary:
	var g_hand := gun * item.hand_offset.basis.orthonormalized().inverse()
	var wrist := grip - g_hand * item.hand_offset.origin + corr
	return _arm(sk, "Right", wrist, pole, g_hand)


func _left(sk: Skeleton3D, fist: Vector3, gun: Basis, pole: Vector3, palm_up: bool, corr: Vector3) -> Dictionary:
	# Fingers across to the gun's right (item -X), palm toward the underside (item +Y) - or the
	# opposite palm when the rig's left hand has +Z the other way round.
	var y := -gun.x
	var z := gun.y if palm_up else -gun.y
	var x := y.cross(z)
	var g_hand := Basis(x, y, z).orthonormalized()
	var wrist := fist - g_hand * Vector3(0.0, 0.08, 0.03) + corr
	return _arm(sk, "Left", wrist, pole, g_hand)


## Two-bone solve: shoulder joint fixed at rest, the wrist put at `wrist`, the elbow bent toward
## `pole`. `g_hand` null leaves the hand pointing down the forearm.
func _arm(sk: Skeleton3D, side: String, wrist: Vector3, pole: Vector3, g_hand) -> Dictionary:
	var i_sh := sk.find_bone(side + "Shoulder")
	var i_up := sk.find_bone(side + "UpperArm")
	var i_lo := sk.find_bone(side + "LowerArm")
	var i_ha := sk.find_bone(side + "Hand")
	var sh := _shoulder_frame(sk, side).origin
	var el0 := sk.get_bone_global_rest(i_lo).origin
	var wr0 := sk.get_bone_global_rest(i_ha).origin
	var l1 := sh.distance_to(el0)
	var l2 := el0.distance_to(wr0)
	var d := wrist - sh
	var dist := clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dh := d.normalized()
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := pole - dh * pole.dot(dh)
	perp = perp.normalized()
	var elbow := sh + dh * a + perp * h
	var real_wrist := sh + dh * dist
	var g_parent := sk.get_bone_global_pose(sk.get_bone_parent(i_sh)).basis
	var g_sh := g_parent * sk.get_bone_rest(i_sh).basis
	var g_up := EquipAnim._aim(g_sh * sk.get_bone_rest(i_up).basis, (elbow - sh).normalized())
	var g_lo := EquipAnim._aim(g_up * sk.get_bone_rest(i_lo).basis, (real_wrist - elbow).normalized())
	var g_ha: Basis = g_hand if g_hand != null else EquipAnim._aim(g_lo * sk.get_bone_rest(i_ha).basis, (real_wrist - elbow).normalized())
	var rots := {
		StringName(side + "Shoulder"): sk.get_bone_rest(i_sh).basis.get_rotation_quaternion(),
		StringName(side + "UpperArm"): EquipAnim._local(g_sh, g_up),
		StringName(side + "LowerArm"): EquipAnim._local(g_up, g_lo),
		StringName(side + "Hand"): EquipAnim._local(g_lo, g_ha),
	}
	return rots


func _place_cam(off: Vector3, look: Vector3) -> void:
	var f: Vector3 = _pilot.character.global_basis.z.normalized()
	var left := Vector3.UP.cross(f).normalized()
	var p: Vector3 = _pilot.global_position
	_cam.global_position = p + left * off.x + Vector3.UP * off.y + f * off.z
	_cam.look_at(p + left * look.x + Vector3.UP * look.y + f * look.z, Vector3.UP)
	_cam.current = true


func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name))


func _find_pilot(n: Node) -> Node:
	if n.has_method(&"press_weapon") and not n.frozen:
		return n
	for c in n.get_children():
		var r := _find_pilot(c)
		if r != null:
			return r
	return null
