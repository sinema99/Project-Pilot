extends SceneTree

# Throwaway probe, WINDOWED: plays pilot9's draw in slow motion (time scale 0.1) and shoots it from
# straight behind at several timeline points, printing the turn's angles. Then the holster. Run:
#   godot --path . --script tests/_probe_equip_shot.gd -- <out_dir>

const SHOTS := [0.0, 0.12, 0.17, 0.21, 0.27, 0.33, 0.40, 0.47, 0.55]

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
		_cam.global_position = p - f * 3.2 + Vector3.UP * 1.5
		_cam.look_at(p + Vector3.UP * 1.0, Vector3.UP)
	if _frames == 70:
		Engine.time_scale = 0.1
		print("press_equip -> ", _pilot.press_equip())
		var anim: Node = _pilot.equip_anim
		var inv: Basis = anim._model_basis().inverse()
		var ab: float = anim.plane_angle(inv * anim.back_transform().basis.y)
		var ah: float = anim.plane_angle(inv * anim.hold_transform().basis.y)
		var hy: Vector3 = inv * anim.hold_transform().basis.y
		print("a_back %.1f deg, a_hold %.1f deg, end %.1f deg, hold axis (model) %s" % [rad_to_deg(ab),
			rad_to_deg(ah), rad_to_deg(anim.end_angle(ab, ah, anim.extra_turns)), hy])
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
		var hs := [0.5, 0.3, 0.2, 0.1]
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
