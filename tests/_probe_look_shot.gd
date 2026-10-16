extends SceneTree

# Throwaway probe, WINDOWED: boots trial.tscn and saves the game camera's view in the CEL and
# PIXEL looks, so the PIXEL look can be judged against today's. Drives PixelLook and PixelWorld
# directly; writes nothing to settings.cfg. See docs/specs/pixel-look.md. Run:
#   godot --path . --script tests/_probe_look_shot.gd -- <out_dir>

# name, pixel look, block, colour levels, supersample
const SHOTS := [
	["cel_3x", false, 3, 0, 1],
	["pixel_4x", true, 4, 24, 2],
	["pixel_4x_full", true, 4, 0, 2],
	["pixel_3x", true, 3, 24, 2],
	["pixel_6x", true, 6, 24, 2],
	["cel_again", false, 3, 0, 1],
]

var _frames := 0
var _out := ""
var _i := 0
var _world: Node
var _look: Node

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
		_look = current_scene.get_node(^"PixelLook")
		_frames = 0
		return false
	var step := _frames % 20
	if step == 1 and _i < SHOTS.size():
		var shot: Array = SHOTS[_i]
		_look.apply_look(shot[1])
		_world.apply_settings(shot[2], shot[3], shot[4])
	if step == 16 and _i < SHOTS.size():
		var img := root.get_texture().get_image()
		var path := "%s/look_%s.png" % [_out, SHOTS[_i][0]]
		print("saved ", path, " ", img.save_png(path), " swapped ", _look._swapped.size())
		_i += 1
	return _i >= SHOTS.size()
