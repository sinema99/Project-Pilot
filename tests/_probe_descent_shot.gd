extends SceneTree

# Throwaway probe, WINDOWED: opens the descent shot and saves screenshots at fixed shot times, to
# hold up against the user's sketch (docs/specs/cutscene-descent.md). Run:
#   godot --path . --script tests/_probe_descent_shot.gd -- <out_dir>

const SHOTS := [
	{name = "descent_0.3.png", t = 0.3},
	{name = "descent_flash.png", t = 0.55},
	{name = "descent_1.5.png", t = 1.5},
	{name = "descent_3.0.png", t = 3.0},
	{name = "descent_5.0.png", t = 5.0},
	{name = "descent_15.0.png", t = 15.0},
	{name = "descent_bolt_3.2.png", t = 3.21},
	{name = "descent_bolt_12.6.png", t = 12.69},
	{name = "descent_bolt_18.4.png", t = 18.41},
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
	change_scene_to_file("res://scenes/cutscene_descent.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 20:
		return false
	var shot: Dictionary = SHOTS[_view]
	var s := current_scene as DescentShot
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
