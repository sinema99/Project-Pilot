extends SceneTree

## Throwaway probe, WINDOWED: shoots pilot9's poncho in trial.tscn - standing from four sides, then
## running, sprinting, in a jump's fall and just after the landing, each from the side.
##   godot --path . --script tests/_probe_poncho_shot.gd -- <out_dir>

var _pilot: Node
var _frames := 0
var _out := ""
var _cam: Camera3D

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	_flush()
	if _pilot == null:
		if current_scene != null:
			_pilot = current_scene.get_node_or_null(^"Pilot9")
		return _frames > 900
	if _frames == 30:
		print("poncho: ", _pilot.poncho, " mesh surfaces: ",
			_pilot.poncho.mesh.get_surface_count() if _pilot.poncho else -1)
		var mi: MeshInstance3D = _pilot.poncho
		print("override: ", mi.get_surface_override_material(0))
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
	match _frames:
		40: _aim(0.0, 2.2, 1.3); _shot("idle_front")
		46: _aim(180.0, 2.2, 1.3); _shot("idle_back")
		52: _aim(90.0, 2.2, 1.3); _shot("idle_side")
		58: _aim(35.0, 1.6, 1.6); _shot("idle_34_high")
		64: _aim(-140.0, 1.8, 1.5); _shot("idle_back_34")
		70: Input.action_press(&"forward")
		130: _aim(90.0, 3.0, 1.3, true); _shot("run_side")
		134: _aim(90.0, 3.0, 1.3, true); _shot("run_side_b")
		140: Input.action_press(&"sprint")
		200: _aim(90.0, 3.0, 1.3, true); _shot("sprint_side")
		203: _aim(200.0, 3.0, 1.6, true); _shot("sprint_back")
		210: Input.action_press(&"jump")
		214: Input.action_release(&"jump")
		255: _aim(90.0, 3.5, 1.3, true); _shot("jump_fall_side")
	if _frames > 255 and _frames < 400 and _pilot.is_on_floor() and not has_meta(&"landed"):
		set_meta(&"landed", _frames)
	if has_meta(&"landed") and _frames == int(get_meta(&"landed")) + 5:
		_aim(90.0, 3.5, 1.3, true)
		_shot("landed_side")
	if _frames == 420:
		Input.action_release(&"forward")
		Input.action_release(&"sprint")
	if _frames == 424:
		_aim(90.0, 3.0, 1.3, true); _shot("stopping_side")
	return _frames > 470

## Camera `dist` m from him at `yaw` degrees around his facing (0 = in front), at `height`.
func _aim(yaw: float, dist: float, height: float, _moving := false) -> void:
	var p: Vector3 = _pilot.get_node(^"character").global_position
	var f: Vector3 = _pilot._facing()
	var dir := f.rotated(Vector3.UP, deg_to_rad(yaw))
	_cam.global_position = p + dir * dist + Vector3.UP * height
	_cam.look_at(p + Vector3.UP * 1.25, Vector3.UP)

## Saved three frames on, once the camera move has been drawn.
var _pending := {}

func _shot(name: String) -> void:
	_pending[_frames + 3] = name

func _flush() -> void:
	if not _pending.has(_frames):
		return
	var name: String = _pending[_frames]
	_pending.erase(_frames)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
