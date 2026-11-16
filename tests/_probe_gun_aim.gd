extends SceneTree

# Throwaway probe, WINDOWED: the right-click aim of both guns at three camera pitches, each from the
# game camera, his right side and his front-left, plus numbers (gun-to-helmet clearance, how far each
# wrist is from its grip). Run:
#   godot --path . --script tests/_probe_gun_aim.gd -- <out_dir> [only_slot]
# Sets Inventory.persist = false: windowed probes would write the real save.

const PITCHES := [0.0, 40.0, -40.0]
const SETTLE := 150
## The helmet as a sphere around the Head bone (bone-local centre, radius), from the head mesh.
const HEAD_CENTER := Vector3(0.0, 0.13, -0.016)
const HEAD_RADIUS := 0.195

var _pilot: Node
var _frames := 0
var _out := ""
var _cam: Camera3D
var _runs: Array = []
var _run := -1
var _t := 0
var _persist_off := false
## Bone name -> world transform as the modifiers left it (outside skeleton_updated the skeleton
## hands back the unmodified animation pose).
var _posed := {}


func _capture() -> void:
	var skel: Skeleton3D = _pilot.item_holder._skeleton
	for n in [&"Head", &"RightHand", &"LeftHand"]:
		_posed[n] = skel.global_transform * skel.get_bone_global_pose(skel.find_bone(n))


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var only := int(args[1]) if args.size() > 1 else -1
	for slot in [0, 1]:
		if only >= 0 and slot != only:
			continue
		for p in PITCHES:
			_runs.append([slot, p])
	change_scene_to_file("res://scenes/trial.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if not _persist_off:
		var inv := root.get_node_or_null("/root/Inventory")
		if inv != null:
			inv.persist = false
			_persist_off = true
	if _pilot == null:
		_pilot = _find_pilot(current_scene) if current_scene != null else null
		return _frames > 900
	if _frames < 40:
		return false
	if _run < 0:
		var dummy: Node = get_nodes_in_group(&"range_dummy")[0]
		_pilot.global_position = dummy.global_position + Vector3(2.0, 0.3, 9.0)
		_pilot.camera_pivot.rotation.y = 0.0
		_pilot.item_holder._skeleton.skeleton_updated.connect(_capture)
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_next()
		return false
	_t += 1
	var slot: int = _runs[_run][0]
	var pitch: float = _runs[_run][1]
	var tag := "w%d_p%d" % [slot, int(pitch)]
	if _t == 2:
		_pilot.draw_slot(slot, true)
	if _t == 30:
		_pilot.camera_pivot.rotation.x = deg_to_rad(pitch)
		Input.action_press(&"aim")
	if _t > 30 and _t < SETTLE:
		_pilot.camera_pivot.rotation.x = deg_to_rad(pitch)
	if _t == SETTLE:
		_numbers(tag)
		_save(tag + "_game")
		_view(Vector3(-1.7, 0.2, 0.45))
	if _t == SETTLE + 2:
		_save(tag + "_side")
		_view(Vector3(1.0, 0.3, 1.6))
	if _t == SETTLE + 4:
		_save(tag + "_front")
		_view(Vector3(0.0, 2.1, 0.3))
	if _t == SETTLE + 6:
		_save(tag + "_top")
		_pilot.camera_3d.make_current()
		Input.action_release(&"aim")
	if _t == SETTLE + 30:
		if _run + 1 >= _runs.size():
			quit()
			return true
		_next()
	return false


func _next() -> void:
	_run += 1
	_t = 0


## A camera at `off` = (his left, up, his forward) metres from his chest, looking at it.
func _view(off: Vector3) -> void:
	var body: Node3D = _pilot.character
	var c := body.global_position + Vector3(0, 1.4, 0) + body.global_basis.z * (0.3 if absf(off.y) < 2.0 else 0.3)
	var b := body.global_basis.orthonormalized()
	_cam.global_position = c + b.x * off.x + b.y * off.y + b.z * off.z
	_cam.look_at(c, b.z if absf(off.y) > 2.0 else Vector3.UP)
	_cam.make_current()


func _numbers(tag: String) -> void:
	var holder: Node = _pilot.item_holder
	var skel: Skeleton3D = holder._skeleton
	var item: Node3D = holder.item_instance
	var held: HeldItem = holder.held_item
	var head: Transform3D = _posed[&"Head"]
	var center := head * HEAD_CENTER
	var clear := INF
	for n in item.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for i in range(0, idx.size() - 2, 3):
				var a := mi.global_transform * verts[idx[i]]
				var b := mi.global_transform * verts[idx[i + 1]]
				var c := mi.global_transform * verts[idx[i + 2]]
				for q in [a, b, c, (a + b) * 0.5, (b + c) * 0.5, (a + c) * 0.5, (a + b + c) / 3.0]:
					clear = minf(clear, (q as Vector3).distance_to(center) - HEAD_RADIUS)
	var gun: Transform3D = skel.global_transform * holder.arm_modifier.ik_last_frame
	var rh: Transform3D = _posed[&"RightHand"]
	var lh: Transform3D = _posed[&"LeftHand"]
	var r_err := rh.origin.distance_to((gun * held.hand_offset.affine_inverse()).origin)
	var l_err := lh.origin.distance_to((gun * held.aim_left_hand).origin)
	var cam: Camera3D = _pilot.camera_3d
	var barrel := -item.global_basis.z.normalized()
	print("%s  helmet clearance %.3f m  right wrist err %.3f  left wrist err %.3f  barrel vs camera %.1f deg  aim_pose %.2f" % [
		tag, clear, r_err, l_err, rad_to_deg(barrel.angle_to(-cam.global_basis.z)), _pilot.gunplay.aim_pose])


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.resize(1224, 689, Image.INTERPOLATE_BILINEAR)
	img.save_png(_out.path_join(name + ".png"))


func _find_pilot(n: Node) -> Node:
	if n.has_method(&"press_weapon") and not n.frozen:
		return n
	for c in n.get_children():
		var r := _find_pilot(c)
		if r != null:
			return r
	return null
