extends SceneTree

# Throwaway probe, WINDOWED: stands a camera at a few vantage points around the pipe hall and saves
# a screenshot from each. Run:
#   godot --path . --script tests/_probe_hall_shot.gd -- <out_dir>

const HALL := Vector3(-99, 0, 84)
# name, camera position (hall-local), look-at (hall-local)
const VIEWS := [
	["warm", Vector3(0, 3, -52), Vector3(0, 12, 0)],
	["door", Vector3(0, 2.5, -46), Vector3(0, 10, 0)],
	["catwalk", Vector3(-36, 16.5, -1), Vector3(22, 14, 8)],
	["floor_up", Vector3(-30, 1.7, 8), Vector3(14, 30, -12)],
	["east", Vector3(40, 22.5, -6), Vector3(-20, 12, 6)],
	["aerial", Vector3(0, 90, -95), Vector3(0, 10, -20)],
]

var _cam: Camera3D
var _frames := 0
var _out := ""
var _i := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null:
		return _frames > 600
	if _cam == null:
		if _frames < 20:
			return false
		_cam = Camera3D.new()
		_cam.fov = 75.0
		_cam.far = 600.0
		current_scene.add_child(_cam)
		_cam.make_current()
		return false
	var step := _frames % 12
	if step == 1 and _i < VIEWS.size():
		var v: Array = VIEWS[_i]
		_cam.global_position = HALL + (v[1] as Vector3)
		_cam.look_at(HALL + (v[2] as Vector3), Vector3.UP)
	if step == 9 and _i < VIEWS.size():
		var img := root.get_texture().get_image()
		var path := "%s/hall_%s.png" % [_out, VIEWS[_i][0]]
		print("saved ", path, " ", img.save_png(path))
		_i += 1
	return _i >= VIEWS.size()
