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
	["warmup", Vector3(150, 200, 420), Vector3(150, 0, 150)],
	["aerial", Vector3(150, 330, 400), Vector3(150, 0, 140)],
	["row1", Vector3(60, 45, 90), Vector3(60, 5, 20)],
	["row2", Vector3(120, 70, 160), Vector3(120, 10, 100)],
	["land", Vector3(150, 60, 330), Vector3(150, 0, 270)],
	["plants", Vector3(80, 40, 420), Vector3(80, 0, 360)],
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
		_hab = current_scene.get_node("HabitatParts")
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
		var path := "%s/parts_%s.png" % [_out, VIEWS[_i][0]]
		print("saved ", path, " ", img.save_png(path))
		_i += 1
	return _i >= VIEWS.size()
