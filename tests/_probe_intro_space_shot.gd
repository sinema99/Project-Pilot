extends SceneTree

# Throwaway probe, WINDOWED: opens the intro space cutscene, seeks to a list of times and saves a
# screenshot at each. Run:
#   godot --path . --script tests/_probe_intro_space_shot.gd -- <out_dir> [t1 t2 ...]

var _frames := 0
var _out := ""
var _times: Array[float] = [0.0, 6.0, 7.05, 7.15, 7.3, 7.6, 8.0, 9.0, 10.5, 12.0]
var _i := 0
var _wait := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	if args.size() > 1:
		_times.clear()
		for a in args.slice(1):
			_times.append(float(a))
	DirAccess.make_dir_recursive_absolute(_out)
	change_scene_to_file("res://scenes/cutscene_intro_space.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 10:
		return false
	var ap: AnimationPlayer = current_scene.get_node("AnimationPlayer")
	if _i >= _times.size():
		return true
	if _wait == 0:
		ap.pause()
		ap.seek(_times[_i], true)
	_wait += 1
	if _wait < 4:
		return false
	_wait = 0
	var name_ := "t%05.2f.png" % _times[_i]
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name_))
	print("saved ", name_)
	_i += 1
	return false
