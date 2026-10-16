extends SceneTree

# Throwaway probe, WINDOWED: stands a camera at the cab vantage and a few other points around the
# habitat and saves a screenshot from each. Run:
#   godot --path . --script tests/_probe_habitat_shot.gd -- <out_dir>

var _cam: Camera3D
var _frames := 0
var _out := ""
var _i := 0
var _hab: Node3D
# name, camera position (habitat-local), look-at (habitat-local)
const VIEWS := [
	["warmup", Vector3(0, 17.7, 114), Vector3(0, 6, -80)],
	["cab", Vector3(0, 17.7, 114), Vector3(0, 6, -80)],
	["cab_low", Vector3(0, 17.7, 114), Vector3(0, 2, -10)],
	["left", Vector3(-70, 14, 90), Vector3(0, 12, -30)],
	["bridge", Vector3(-95, 28, -40), Vector3(40, 30, -58)],
	["tower", Vector3(20, 16, 40), Vector3(40, 50, -58)],
	["aerial", Vector3(0, 130, 260), Vector3(0, 0, -40)],
]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null:
		return _frames > 900
	if _cam == null:
		if _frames < 30:
			return false
		_hab = current_scene.get_node("Habitat")
		_cam = Camera3D.new()
		_cam.fov = 62.0
		_cam.far = 2000.0
		current_scene.add_child(_cam)
		_cam.make_current()
		return false
	var step := _frames % 14
	if step == 1 and _i < VIEWS.size():
		var v: Array = VIEWS[_i]
		_cam.global_position = _hab.to_global(v[1] as Vector3)
		_cam.look_at(_hab.to_global(v[2] as Vector3), Vector3.UP)
	if step == 10 and _i < VIEWS.size():
		var img := root.get_texture().get_image()
		var path := "%s/habitat_%s.png" % [_out, VIEWS[_i][0]]
		print("saved ", path, " ", img.save_png(path))
		_i += 1
	return _i >= VIEWS.size()
