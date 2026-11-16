extends SceneTree

# Throwaway probe, WINDOWED: boots trial.tscn and saves the game camera's view in AIRFRAME (75 %),
# AIRFRAME at full strength, and RETRO, switching the look nodes directly (Settings is never
# written). See docs/specs/airframe-trial.md. Run:
#   godot --path . --script tests/_probe_airframe_shot.gd -- <out_dir> [x z yaw_deg]

var _frames := 0
var _out := ""
var _i := 0
var _airframe: AirframeLook
var _retro: Node
var _shots := ["airframe75", "airframe100", "retro"]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null:
		return _frames > 900
	if _airframe == null:
		if _frames < 120:
			return false
		_airframe = current_scene.get_node(^"AirframeLook")
		_retro = current_scene.get_node(^"RetroLook")
		var args := OS.get_cmdline_user_args()
		if args.size() >= 4:
			var pilot := current_scene.get_node(^"Pilot9") as Node3D
			pilot.global_position = Vector3(float(args[1]), pilot.global_position.y, float(args[2]))
			pilot.rotation.y = deg_to_rad(float(args[3]))
		print("airframe active ", _airframe.active, " slots ", _airframe._world_surfaces.size(),
			" bodies ", _airframe._mesh_swaps.size(), " materials ", _airframe._ps1_materials.size())
		_frames = 0
		return false
	var step := _frames % 40
	if step == 1 and _i < _shots.size():
		match _shots[_i]:
			"airframe75":
				_retro.apply_look(false)
				_airframe.set_active(true)
				_airframe.intensity = 0.75
				_airframe.apply()
			"airframe100":
				_airframe.intensity = 1.0
				_airframe.apply()
			"retro":
				_airframe.intensity = 0.75
				_airframe.set_active(false)
				_retro.apply_look(true)
	if step == 35 and _i < _shots.size():
		var img := root.get_texture().get_image()
		var path := "%s/trial_%s.png" % [_out, _shots[_i]]
		print("saved ", path, " ", img.save_png(path))
		_i += 1
	return _i >= _shots.size()
