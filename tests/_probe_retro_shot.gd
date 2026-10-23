extends SceneTree

# Throwaway probe, WINDOWED: boots trial.tscn and saves the game camera's view in CEL and RETRO,
# so RETRO can be judged against today's look. Drives PixelLook / RetroLook directly; writes nothing
# to settings.cfg. See docs/specs/retro-look.md. Run:
#   godot --path . --script tests/_probe_retro_shot.gd -- <out_dir>

const SHOTS := ["cel", "retro", "retro_raw", "cel_again"]

var _frames := 0
var _out := ""
var _i := 0
var _pixel: Node
var _retro: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null:
		return _frames > 600
	if _retro == null:
		if _frames < 60:
			return false
		_pixel = current_scene.get_node(^"PixelLook")
		_retro = current_scene.get_node(^"RetroLook")
		_frames = 0
		return false
	var step := _frames % 30
	if step == 1 and _i < SHOTS.size():
		_pixel.apply_look(false)
		_retro.apply_look(SHOTS[_i].begins_with("retro"))
		if SHOTS[_i] == "retro_raw":
			# The video pass without its soften / bleed, to read the ink as drawn.
			var post = current_scene.get_node(^"WorldEnvironment").compositor.compositor_effects[0]
			post.soften = 0.0
			post.bleed_amount = 0.0
			post.grain = 0.0
	if step == 25 and _i < SHOTS.size():
		var img := root.get_texture().get_image()
		var path := "%s/retro_%s.png" % [_out, SHOTS[_i]]
		print("saved ", path, " ", img.save_png(path), " swapped ", _retro._swapped.size())
		_i += 1
	return _i >= SHOTS.size()
