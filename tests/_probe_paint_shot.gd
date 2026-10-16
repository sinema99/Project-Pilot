extends SceneTree

# Throwaway probe, WINDOWED: boots trial.tscn and saves the game camera's view with painted
# shading off and on, at full res and at the 3X pixel filter, plus an exaggerated shot so the
# patch shapes are easy to see. Drives the shader globals directly; writes nothing to
# settings.cfg. See docs/specs/painted-shading.md. Run:
#   godot --path . --script tests/_probe_paint_shot.gd -- <out_dir>

# name, pixel block, paint_strength, value multiplier (1 = the shipped paint_value)
const SHOTS := [
	["off_full", 0, 0.0, 1.0],
	["on_full", 0, 1.0, 1.0],
	["on_3x", 3, 1.0, 1.0],
	["off_3x", 3, 0.0, 1.0],
	["loud_full", 0, 1.0, 5.0],
	["close_off", 0, 0.0, 1.0],
	["close_on", 0, 1.0, 1.0],
	["close_on_3x", 3, 1.0, 1.0],
	["close_loud", 0, 1.0, 4.0],
]
# From this shot on, a probe camera frames pilot9 from the front-left at about 2 m.
const CLOSE_FROM := 5

var _frames := 0
var _out := ""
var _i := 0
var _world: Node
var _base_value := 0.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	if args.size() > 1:
		RenderingServer.global_shader_parameter_set(&"paint_uv_size", args[1].to_float())
	_base_value = ProjectSettings.get_setting("shader_globals/paint_value", {}).get("value", 0.06)
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null:
		return _frames > 600
	if _world == null:
		if _frames < 40:
			return false
		_world = current_scene.get_node(^"PixelWorld")
		_frames = 0
		return false
	var step := _frames % 15
	if step == 1 and _i == CLOSE_FROM:
		var pilot := get_first_node_in_group(&"player") as Node3D
		var cam := Camera3D.new()
		current_scene.add_child(cam)
		var focus := pilot.global_position + Vector3(0, 1.0, 0)
		cam.look_at_from_position(focus + pilot.global_basis.z * -1.9 + pilot.global_basis.x * 0.9
			+ Vector3(0, 0.3, 0), focus)
		cam.fov = 50.0
		cam.make_current()
	if step == 1 and _i < SHOTS.size():
		_world.apply_settings(SHOTS[_i][1], 0)
		RenderingServer.global_shader_parameter_set(&"paint_strength", SHOTS[_i][2])
		RenderingServer.global_shader_parameter_set(&"paint_value", _base_value * SHOTS[_i][3])
	if step == 12 and _i < SHOTS.size():
		var img := root.get_texture().get_image()
		var path := "%s/paint_%s.png" % [_out, SHOTS[_i][0]]
		print("saved ", path, " ", img.save_png(path))
		_i += 1
	return _i >= SHOTS.size()
