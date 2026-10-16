extends SceneTree

# Throwaway probe, WINDOWED: opens the flyover shot and saves screenshots at fixed shot times, to
# hold up against the user's Blender screenshot (docs/specs/cutscene-flyover.md). Run:
#   godot --path . --script tests/_probe_flyover_shot.gd -- <out_dir>

const SHOTS := [
	{name = "flyover_0.0.png", t = 0.0},
	{name = "flyover_1.5.png", t = 1.5},
	{name = "flyover_2.5.png", t = 2.5},
	{name = "flyover_3.0.png", t = 3.0},
]

var _frames := 0
var _out := ""
var _view := 0
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1920, 1080)
	change_scene_to_file("res://scenes/cutscene_flyover.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 20:
		return false
	var shot: Dictionary = SHOTS[_view]
	var s := current_scene as FlyoverShot
	s.animation_player.pause()
	s.set_process(false)
	s.apply(shot.t)
	_wait += 1
	if _wait < 4:
		return false
	_wait = 0
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(shot.name))
	print("saved ", shot.name)
	_view += 1
	return _view >= SHOTS.size()
