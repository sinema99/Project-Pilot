extends SceneTree

# Throwaway probe, WINDOWED: boots trial.tscn in AIRFRAME and saves the game camera's view with the
# characters on the world's 2X grid (char block 0) and in their own 4X grid (char block 4), driving
# PixelWorld directly (Settings is never written). See docs/specs/airframe-character-pixels.md. Run:
#   godot --path . --script tests/_probe_airframe_character_pixels.gd -- <out_dir> [x z yaw_deg]

var _frames := 0
var _out := ""
var _i := 0
var _world: PixelWorld
var _shots := [4, 3, 6]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null:
		return _frames > 900
	if _world == null:
		if _frames < 120:
			return false
		_world = current_scene.get_node(^"PixelWorld")
		var airframe: AirframeLook = current_scene.get_node(^"AirframeLook")
		var args := OS.get_cmdline_user_args()
		if args.size() >= 4:
			var pilot := current_scene.get_node(^"Pilot9") as Node3D
			pilot.global_position = Vector3(float(args[1]), pilot.global_position.y, float(args[2]))
			pilot.rotation.y = deg_to_rad(float(args[3]))
		print("airframe active ", airframe.active, " boot block ", _world.block,
			" char block ", _world.char_block)
		_frames = 0
		return false
	var step := _frames % 40
	if step == 1 and _i < _shots.size():
		(current_scene.get_node(^"AirframeLook") as AirframeLook).filter_enabled = _i != 0 and false
		(current_scene.get_node(^"AirframeLook") as AirframeLook).apply()
		_world.apply_settings(2, 0, 2, _shots[_i])
	if step == 35 and _i < _shots.size():
		var img := root.get_texture().get_image()
		var path := "%s/char_px%d.png" % [_out, _shots[_i]]
		print("saved ", path, " ", img.save_png(path), " char view ", _world._char_view.size)
		_world._char_view.get_texture().get_image().save_png("%s/charview_%d.png" % [_out, _shots[_i]])
		_i += 1
	return _i >= _shots.size()
