extends SceneTree

# Throwaway probe, WINDOWED: opens the pause menu on pilot9 and screenshots the open, the settled
# shot and the close, then reports the tree pause state. Run:
#   godot --path . --script tests/_probe_hologram.gd -- <out_dir>

var _pilot: Node
var _frames := 0
var _out := ""
var _at := -1
var _closed_at := -1

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		_pilot = _find_pilot(current_scene) if current_scene != null else null
		return _frames > 600
	if _frames == 55:
		_shot("before.png")
	if _frames == 60:
		root.get_node("UI").open(&"shell")
		_at = _frames
		print("holo active: ", _pilot.hologram.is_active(), " paused: ", paused)
	if _at > 0:
		var since := _frames - _at
		if since == 60:
			_pilot.hologram.screen_host().get_texture().get_image().save_png(_out.path_join("ui_tex.png"))
		if since in [8, 20, 60]:
			_shot("holo_%02d.png" % since)
		if since == 62:
			print("live: ", _pilot.hologram.is_live(), " t: ", _pilot.hologram.t)
			root.get_node("UI").close()
		if since > 62 and _closed_at < 0:
			print("close frame ", since, " paused ", paused, " t ", _pilot.hologram.t)
			if not paused:
				_closed_at = since
		if since > 100:
			print("final paused ", paused, " cam local ", _pilot.camera_3d.transform, " fov ", _pilot.camera_3d.fov)
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
