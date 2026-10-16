extends SceneTree

# Throwaway probe, WINDOWED: boots trial.tscn and saves the game camera's view at each pixel
# setting, so the low-res world can be looked at. Writes nothing to settings.cfg - it drives
# PixelWorld directly. Run:
#   godot --path . --script tests/_probe_pixel_shot.gd -- <out_dir>

# name, block, colour steps
const SHOTS := [
	["off", 0, 0],
	["3x", 3, 0],
	["2x", 2, 0],
	["4x", 4, 0],
	["3x_c8", 3, 8],
	["off_c16", 0, 16],
]

var _frames := 0
var _out := ""
var _i := 0
var _world: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null:
		return _frames > 600
	if _world == null:
		if _frames < 40:
			return false
		_world = current_scene.get_node(^"PixelWorld")
		print("window ", root.size, " root cam ", root.get_camera_3d())
		_frames = 0
		return false
	var step := _frames % 15
	if step == 1 and _i < SHOTS.size():
		_world.apply_settings(SHOTS[_i][1], SHOTS[_i][2])
	if step == 12 and _i < SHOTS.size():
		var view := _world.get_node(^"WorldView") as SubViewport
		var img := root.get_texture().get_image()
		var path := "%s/pixel_%s.png" % [_out, SHOTS[_i][0]]
		print("saved ", path, " ", img.save_png(path), " world view ", view.size,
			" disable_3d ", root.disable_3d)
		_i += 1
	return _i >= SHOTS.size()
