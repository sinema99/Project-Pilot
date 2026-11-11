extends SceneTree

# Throwaway probe, WINDOWED: boots Jetpack.tscn and saves the game camera's view in each look
# state, so the look can be checked without playing. See docs/specs/jetpack-look.md. Run:
#   godot --path . --script tests/_probe_jetpack_shot.gd -- <out_dir> [yaw_deg]

# name -> [look, snap, affine, texels, filter]
const SHOTS := {
	"look": [true, true, false, 16.0, true],
	"no_filter": [true, true, false, 16.0, false],
	"affine": [true, true, true, 16.0, true],
	"texels8": [true, true, false, 8.0, true],
	"plain": [false, true, false, 16.0, true],
}

var _frames := 0
var _out := ""
var _i := 0
var _look: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://Jetpack.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null:
		return _frames > 600
	if _look == null:
		if _frames < 90:
			return false
		_look = current_scene.get_node(^"JetpackLook")
		print("pilot swapped ", _look.is_pilot_swapped(), " surfaces ", _look._pilot_surfaces.size(),
			" world ", _look._world_surfaces.size())
		_frames = 0
		return false
	var names := SHOTS.keys()
	var step := _frames % 30
	if step == 1 and _i < names.size():
		var s: Array = SHOTS[names[_i]]
		_look.look_enabled = s[0]
		_look.snap_enabled = s[1]
		_look.affine_enabled = s[2]
		_look.texels_per_metre = s[3]
		_look.filter_enabled = s[4]
		_look.apply()
	if step == 25 and _i < names.size():
		var img := root.get_texture().get_image()
		var path := "%s/jetpack_%s.png" % [_out, names[_i]]
		print("saved ", path, " ", img.save_png(path))
		_i += 1
	return _i >= names.size()
