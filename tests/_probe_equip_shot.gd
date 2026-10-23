extends SceneTree

# Throwaway probe, WINDOWED: plays pilot9's staff materialize in slow motion (time scale 0.1) and
# shoots it from behind his right shoulder at several timeline points, then the holster. Run:
#   godot --path . --script tests/_probe_equip_shot.gd -- <out_dir>

const SHOTS := [0.0, 0.08, 0.15, 0.19, 0.23, 0.28, 0.35, 0.42, 0.5]

var _pilot: Node
var _frames := 0
var _out := ""
var _cam: Camera3D
var _next := 0
var _holster_at := -1
var _hnext := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		_pilot = _find_pilot(current_scene) if current_scene != null else null
		return _frames > 900
	if _frames == 60:
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
		var p: Vector3 = _pilot.global_position
		var f: Vector3 = _pilot._facing()
		var right := f.cross(Vector3.UP).normalized()
		_cam.global_position = p - f * 1.6 + right * 1.6 + Vector3.UP * 1.5
		_cam.look_at(p + Vector3.UP * 1.1, Vector3.UP)
	if _frames == 70:
		Engine.time_scale = 0.1
		print("press_equip -> ", _pilot.press_equip())
	var anim: Node = _pilot.equip_anim
	if _frames > 70 and _holster_at < 0:
		if _next < SHOTS.size() and anim.t >= SHOTS[_next] - 0.001:
			_shot("equip_%02d_t%.2f.png" % [_next, anim.t])
			print("equip t=%.3f weight=%.2f drawn=%s" % [anim.t, anim.arm_modifier.influence, _pilot.is_item_drawn()])
			_next += 1
		if not anim.is_playing() and _next > 0:
			_shot("equip_done.png")
			print("equip done, drawn=", _pilot.is_item_drawn())
			_holster_at = _frames
	if _holster_at > 0 and _frames == _holster_at + 20:
		print("press_equip (holster) -> ", _pilot.press_equip())
	if _holster_at > 0 and _frames > _holster_at + 20:
		var hs := [0.4, 0.3, 0.22, 0.1]
		if _hnext < hs.size() and anim.t <= hs[_hnext]:
			_shot("holster_%02d_t%.2f.png" % [_hnext, anim.t])
			_hnext += 1
		if not anim.is_playing():
			_shot("holster_done.png")
			print("holster done, drawn=", _pilot.is_item_drawn())
			Engine.time_scale = 1.0
			return true
	return _frames > 3000

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name))

func _find_pilot(n: Node) -> Node:
	if n.has_method(&"press_equip"):
		return n
	for c in n.get_children():
		var r := _find_pilot(c)
		if r != null:
			return r
	return null
