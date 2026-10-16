extends SceneTree

# Throwaway probe, WINDOWED: sprints pilot9, slides him, and shoots the hold pose from straight
# above and from the side, printing the right arm's skeleton-space positions. Run:
#   godot --path . --script tests/_probe_slide_arm.gd -- <out_dir>

var _pilot: Node
var _frames := 0
var _out := ""
var _slid_at := -1
var _cam: Camera3D

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		_pilot = _find_pilot(current_scene) if current_scene != null else null
		return _frames > 600
	if _frames == 60 and not _pilot.is_item_drawn():
		_pilot.toggle_drawn()
	if _frames == 90:
		_pilot.velocity = _pilot._facing() * _pilot.sprint_speed
		_pilot._start_slide(_pilot._facing())
		_slid_at = _frames
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
	if _slid_at > 0:
		var since := _frames - _slid_at
		var p: Vector3 = _pilot.global_position
		var f: Vector3 = _pilot._facing()
		if since == 30:
			_cam.global_position = p + Vector3.UP * 3.0
			_cam.look_at(p, f)
		if since == 32:
			_shot("slide_top.png")
			_dump()
		if since == 33:
			var side := f.cross(Vector3.UP)
			_cam.global_position = p + side * 2.5 + Vector3.UP * 0.4
			_cam.look_at(p + Vector3.UP * 0.3)
		if since == 35:
			_shot("slide_side.png")
		if since == 36:
			var side := f.cross(Vector3.UP)
			_cam.global_position = p + side * 2.0 + f * 2.0 + Vector3.UP * 1.2
			_cam.look_at(p + Vector3.UP * 0.3)
		if since == 38:
			_shot("slide_front.png")
			print("sliding ", _pilot.is_sliding, " holding ", _pilot.is_slide_holding)
			return true
	return false

func _dump() -> void:
	var sk: Skeleton3D = _pilot.get_node("character/Armature/GeneralSkeleton")
	print("skel basis ", sk.global_transform.basis, " origin ", sk.global_transform.origin, " pilot ", _pilot.global_position, " facing ", _pilot._facing())
	for b in ["Hips", "UpperChest", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand", "LeftHand", "RightFoot", "LeftFoot", "Head"]:
		var i := sk.find_bone(b)
		var g := sk.global_transform * sk.get_bone_global_pose(i)
		print(b, " world ", g.origin, " skel ", sk.get_bone_global_pose(i).origin)

func _shot(name_: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name_))
	print("saved ", name_)

func _find_pilot(n: Node) -> Node:
	if n == null:
		return null
	if n.get_script() != null and n.get_script().resource_path == "res://scripts/pilot9.gd":
		return n
	for c in n.get_children():
		var f := _find_pilot(c)
		if f != null:
			return f
	return null
