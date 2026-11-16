extends SceneTree

# Throwaway probe, WINDOWED: rifle on pilot9's bare back (no backpack, trench coat on), shot from
# behind, his right and above. Optional override of the bare slot to try values without editing:
#   godot_bg.ps1 --script tests/_probe_rifle_bare_shot.gd ++ <out_dir> [ox oy oz mx my mz tx ty tz]

var _pilot: Node
var _frames := 0
var _out := ""
var _cam: Camera3D
var _args: PackedStringArray

func _initialize() -> void:
	_args = OS.get_cmdline_user_args()
	_out = _args[0] if _args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		if current_scene != null and _frames > 20:
			var all: Array = []
			_all_pilots(current_scene, all)
			for p in all:
				print("pilot ", p.get_path(), " at ", p.global_position, " vis ", p.is_visible_in_tree(),
					" proc ", p.can_process())
			var cam := root.get_viewport().get_camera_3d()
			var best := INF
			for p in all:
				var d: float = (p.global_position - cam.global_position).length() if cam != null else 0.0
				if p.is_visible_in_tree() and d < best:
					best = d
					_pilot = p
		return _frames > 900
	if _frames == 25:
		var inv := root.get_node_or_null("/root/Inventory")
		if inv != null:
			inv.set("persist", false)
	if _frames == 45:
		if _pilot.backpack != null:
			_pilot.backpack.set_on(false)
		if _pilot.coat != null:
			_pilot.coat.set_on(true)
		for m in _pilot.weapon_mounts._mounts:
			var item: HeldItem = m.item
			if _args.size() >= 10 and item.slot_bare_muzzle_dir != Vector3.ZERO:
				item.slot_bare_origin = Vector3(float(_args[1]), float(_args[2]), float(_args[3]))
				item.slot_bare_muzzle_dir = Vector3(float(_args[4]), float(_args[5]), float(_args[6]))
				item.slot_bare_top_dir = Vector3(float(_args[7]), float(_args[8]), float(_args[9]))
			m["bare"] = null
	if _frames == 60:
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
		var sk: Skeleton3D = _pilot.weapon_mounts._skeleton
		print("skel xf: ", sk.global_transform, " pilot: ", _pilot.global_position)
		print("pack on: ", _pilot.is_backpack_on(), " mounts: ", _pilot.weapon_mounts._mounts.size())
		_cam.fov = 35.0
	# Shots trail the move by 3 frames: the grabbed image is the last finished render.
	var views := {62: [Vector3(0, 1.4, -3.4), "back"], 68: [Vector3(2.4, 1.3, -0.1), "his_left"],
		74: [Vector3(-2.4, 1.3, -0.1), "his_right"], 80: [Vector3(0.0, 3.6, -0.15), "top"],
		86: [Vector3(-1.6, 1.8, -1.9), "back_right"]}
	for f in views:
		if _frames == f:
			_aim(views[f][0])
		if _frames == f + 3:
			_shot("bare_%s.png" % views[f][1])
	return _frames > 92

## offset in skeleton space (+Z his front, -Z his back, +X one side).
func _aim(off: Vector3) -> void:
	var sk: Skeleton3D = _pilot.weapon_mounts._skeleton
	var xf := sk.global_transform
	_cam.global_position = xf * off
	var tgt := xf * Vector3(0, 1.2, -0.1)
	var up := Vector3.UP if absf(off.y - 1.2) < 1.5 else (xf.basis * Vector3(0, 0, 1)).normalized()
	_cam.look_at(tgt, up)

func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name))

func _all_pilots(n: Node, out: Array) -> void:
	if n.has_method(&"press_equip"):
		out.append(n)
	for c in n.get_children():
		_all_pilots(c, out)

func _find_pilot(n: Node) -> Node:
	if n.has_method(&"press_equip"):
		return n
	for c in n.get_children():
		var r := _find_pilot(c)
		if r != null:
			return r
	return null
