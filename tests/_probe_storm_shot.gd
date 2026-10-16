extends SceneTree

# Throwaway probe, WINDOWED: boots Ichi.tscn and saves the game camera's view at a few moments,
# so the storm's fog, sky and snow can be judged by eye. See docs/specs/ichi-snowstorm.md. Run:
#   godot --path . --script tests/_probe_storm_shot.gd -- <out_dir>

var _frames := 0
var _out := ""
var _i := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://Ichi.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null:
		return _frames > 600
	if _frames > 90 and _frames % 90 == 0:
		var img := root.get_texture().get_image()
		var path := "%s/storm_%d.png" % [_out, _i]
		# The shaders' TIME is about the engine's uptime: log the gust curve to pair a shot with
		# calm or whiteout (storm_gust.gdshaderinc).
		var t := Time.get_ticks_msec() / 1000.0
		var w1 := TAU / 8.0
		var gust := 0.6 * sin(w1 * t) + 0.4 * sin(w1 * 0.61 * t + 1.3)
		print("saved ", path, " ", img.save_png(path), "  t %.1f gust %.2f" % [t, gust])
		_i += 1
	return _i >= 6
