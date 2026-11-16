extends SceneTree

# Throwaway probe, WINDOWED: boots trial.tscn in AIRFRAME and saves the game camera's view with the
# pixel filter OFF, at 2X (the default) and at 3X, driving PixelWorld directly (Settings is never
# written). See docs/specs/airframe-pixel-filter.md. Run:
#   godot --path . --script tests/_probe_airframe_pixels.gd -- <out_dir> [x z yaw_deg]

var _frames := 0
var _out := ""
var _i := 0
var _world: PixelWorld
var _shots := [0, 2, 3]

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
		print("airframe active ", airframe.active, " filter ", airframe.filter_visible(),
			" boot block ", _world.block)
		_frames = 0
		return false
	var step := _frames % 40
	if step == 1 and _i < _shots.size():
		_world.apply_settings(_shots[_i], 0, 1)
	if step == 35 and _i < _shots.size():
		var img := root.get_texture().get_image()
		var path := "%s/airframe_px%d.png" % [_out, _shots[_i]]
		print("saved ", path, " ", img.save_png(path))
		_i += 1
	return _i >= _shots.size()
