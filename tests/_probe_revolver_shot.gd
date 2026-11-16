extends SceneTree

# Throwaway probe, WINDOWED: solves the revolver's low-ready hold from the rig's rest (the same
# shortest-arc aim as equip_anim.gd's arm-out pose), prints it as hold_rotations for
# resources/items/revolver.tres, applies it live, then shoots the hold (idle, side + front + game
# camera) and the materialize in slow motion. Run:
#   godot --path . --script tests/_probe_revolver_shot.gd -- <out_dir> [out fwd elbow barrel_down]

const EquipAnim := preload("res://scripts/items/equip_anim.gd")
const ItemHolder := preload("res://scripts/items/item_holder.gd")
const SHOTS := [0.16, 0.19, 0.23, 0.28, 0.35]

var _pilot: Node
var _frames := 0
var _out := ""
var _cam: Camera3D
var _next := 0
var _angles := [6.0, 8.0, 40.0, 50.0]
var _phase := 0
var _trail_angle := 90.0
var _idle := {}
var _trail := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	for i in range(1, mini(args.size(), 5)):
		_angles[i - 1] = float(args[i])
	if args.size() > 5:
		_trail_angle = float(args[5])
	change_scene_to_file("res://scenes/trial.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		_pilot = _find_pilot(current_scene) if current_scene != null else null
		return _frames > 900
	if _frames == 40:
		_solve()
		_pilot.draw_slot(1, true)
		print("slot ", _pilot.current_slot(), " drawn ", _pilot.is_item_drawn())
		_cam = Camera3D.new()
		_cam.fov = 40.0
		current_scene.add_child(_cam)
	if _frames == 68:
		var gun: Node3D = _pilot.item_holder.item_instance
		var m: Node3D = gun.get_node("Muzzle")
		var fwd: Vector3 = _pilot.character.global_basis.z.normalized()
		var bd := (m.global_position - gun.global_position).normalized()
		print("barrel dir ", bd, " fwd ", fwd, " below level deg ", rad_to_deg(asin(-bd.y)), " fwd dot ", bd.dot(fwd))
		print("gun length check ", m.global_position.distance_to(gun.global_position), " arm influence ", _pilot.item_holder.arm_modifier.influence)
	if _frames == 70:
		_place_cam(Vector3(-3.4, 1.3, 0.3), Vector3(0, 0.9, 0.1))  # his right side
	if _frames == 72:
		_shot("hold_side.png")
	if _frames == 74:
		_place_cam(Vector3(-1.6, 1.3, 3.4), Vector3(0, 0.9, 0.1))  # front, off his right
	if _frames == 76:
		_shot("hold_front.png")
	if _frames == 78:
		_place_cam(Vector3(-0.35, 1.05, 0.55), Vector3(-0.25, 0.85, 0.15))  # close on the hand
	if _frames == 80:
		_shot("hold_close.png")
	if _frames == 82:
		_cam.current = false
	if _frames == 86:
		_shot("hold_game_cam.png")
	if _frames == 90:
		_cam.current = true
		_pilot.item_holder.held_item.idle_rotations.clear()  # trail pose only, as at a sprint
		_place_cam(Vector3(-3.4, 1.3, 0.3), Vector3(0, 0.9, 0.1))
	if _frames == 94:
		_shot("trail_side.png")
		_place_cam(Vector3(-1.6, 1.3, -3.4), Vector3(0, 0.9, -0.1))  # from behind
	if _frames == 97:
		_shot("trail_back.png")
		_cam.current = false
	if _frames == 101:
		_shot("trail_game_cam.png")
	return _frames > 103


func _solve() -> void:
	var sk: Skeleton3D = _pilot.get_node("character/Armature/GeneralSkeleton")
	var idx: Array[int] = []
	for n in ["RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]:
		idx.append(sk.find_bone(n))
	var g_parent := sk.get_bone_global_rest(sk.get_bone_parent(idx[0])).basis
	var item: HeldItem = load("res://resources/items/revolver.tres")
	# IDLE: wide gunslinger arm from the shortest-arc aim (out, fwd, elbow), barrel angle below level.
	var g_sh := g_parent * sk.get_bone_rest(idx[0]).basis
	var d_up: Vector3 = EquipAnim.upper_arm_dir(_angles[0], _angles[1])
	var d_fo: Vector3 = EquipAnim.forearm_dir(d_up, _angles[2])
	var g_up: Basis = EquipAnim._aim(g_sh * sk.get_bone_rest(idx[1]).basis, d_up)
	var g_lo: Basis = EquipAnim._aim(g_up * sk.get_bone_rest(idx[2]).basis, d_fo)
	var idle := _pack(sk, item, idx, g_sh, g_up, g_lo, _angles[3], sk.get_bone_rest(idx[0]).basis.get_rotation_quaternion())
	# TRAIL: the staff's own three arm bones, hand solved so the barrel sits at `_trail_angle`.
	var staff: HeldItem = load("res://resources/items/staff.tres")
	var q := ItemHolder.pose_from_rotations(staff.hold_rotations, sk)
	var t_sh: Basis = g_parent * Basis(q[idx[0]])
	var t_up: Basis = t_sh * Basis(q[idx[1]])
	var t_lo: Basis = t_up * Basis(q[idx[2]])
	var trail := _pack(sk, item, idx, t_sh, t_up, t_lo, _trail_angle, q[idx[0]])
	if OS.get_environment("HIP") != "":
		# Hip carry: the same narrow arm as the idle, barrel angled by _trail_angle.
		trail = _pack(sk, item, idx, g_sh, g_up, g_lo, _trail_angle, sk.get_bone_rest(idx[0]).basis.get_rotation_quaternion())
	print("angles ", _angles, " trail ", _trail_angle)
	print("idle_rotations ", idle)
	print("hold_rotations ", trail)
	item.idle_rotations = idle
	item.hold_rotations = trail
	_idle = idle
	_trail = trail


# Hand local rotation so the gun's barrel points `ang` degrees below level (negative = up), +Z fwd.
func _pack(sk: Skeleton3D, item: HeldItem, idx: Array[int], g_sh: Basis, g_up: Basis, g_lo: Basis,
		ang: float, q_sh: Quaternion) -> Dictionary[StringName, Vector3]:
	var a := deg_to_rad(ang)
	var barrel := Vector3(0.0, -sin(a), cos(a))
	var top := Vector3(0.0, cos(a), sin(a))
	var gun := Basis(top.cross(-barrel), top, -barrel)
	var g_hand := gun * item.hand_offset.basis.orthonormalized().inverse()
	var rots := {
		&"RightShoulder": q_sh,
		&"RightUpperArm": EquipAnim._local(g_sh, g_up),
		&"RightLowerArm": EquipAnim._local(g_up, g_lo),
		&"RightHand": EquipAnim._local(g_lo, g_hand),
	}
	var out: Dictionary[StringName, Vector3] = {}
	for k in rots:
		var e: Vector3 = (rots[k] as Quaternion).get_euler()
		out[k] = Vector3(snappedf(rad_to_deg(e.x), 0.1), snappedf(rad_to_deg(e.y), 0.1), snappedf(rad_to_deg(e.z), 0.1))
	return out


func _place_cam(off: Vector3, look: Vector3) -> void:
	# Offsets in his own frame: x = his left, z = his front.
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
