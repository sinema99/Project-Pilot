extends SceneTree

# Throwaway probe, WINDOWED: the main menu with ScreenPixel off and on, so the whole-screen PIXEL
# pass can be judged on the UI. Drives ScreenPixel directly; writes nothing to settings.cfg. See
# docs/specs/pixel-look.md, "Whole screen". Run:
#   godot --path . --script tests/_probe_screen_pixel.gd -- <out_dir>

# name, block, colour levels
const SHOTS := [["off", 0, 0], ["4x_banded", 4, 24], ["4x_full", 4, 0], ["6x_banded", 6, 24]]

var _frames := 0
var _out := ""
var _i := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 40:
		return false
	var step := _frames % 20
	var screen := root.get_node(^"ScreenPixel")
	if step == 1 and _i < SHOTS.size():
		screen.apply_settings(SHOTS[_i][1], SHOTS[_i][2])
	if step == 16 and _i < SHOTS.size():
		var path := "%s/screen_%s.png" % [_out, SHOTS[_i][0]]
		print("saved ", path, " ", root.get_texture().get_image().save_png(path))
		_i += 1
	return _i >= SHOTS.size()
