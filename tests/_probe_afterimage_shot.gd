extends SceneTree

# Throwaway probe, WINDOWED (not headless - the bake needs a real renderer): boots the main
# scene, sprints pilot9 briefly, dashes him sideways to the camera, and saves screenshots to
# the path given after `--`. Run:
#   godot --path . --script tests/_probe_afterimage_shot.gd -- <out_dir>

var _pilot: Node
var _frames := 0
var _out := ""
var _dashed_at := -1

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		_pilot = _find_pilot(current_scene) if current_scene != null else null
		return _frames > 600
	if _frames == 60:
		# Look straight along his right, so a dash to his left runs across the frame.
		_pilot.camera_pivot.rotation.y = 0.0
	if _frames == 90:
		_pilot._start_dash(Vector3.LEFT)
		_dashed_at = _frames
	if _dashed_at > 0:
		var since := _frames - _dashed_at
		if since in [3, 8, 14, 20]:
			_shot("afterimage_%02d.png" % since)
		if since == 16:
			print("ghosts: ", _pilot._afterimage.ghost_count(), " dashing: ", _pilot.is_dashing)
		if since > 21:
			return true
	return false

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
