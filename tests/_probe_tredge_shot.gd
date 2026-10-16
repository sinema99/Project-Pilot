extends SceneTree

# Throwaway probe, WINDOWED: opens Ichi (he spawns out in the blizzard, so the tredge is on from
# the first tick), shoots the braced idle, then holds `forward` and shoots the tredge from the
# side, the front three-quarter and behind. Prints the tredge state as it goes. Run:
#   godot --path . --script tests/_probe_tredge_shot.gd -- <out_dir>

var _pilot: Node
var _frames := 0
var _out := ""
var _cam: Camera3D

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/operation_ichi.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		_pilot = _find_pilot(current_scene) if current_scene != null else null
		return _frames > 900
	if _frames == 30:
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
		print("tredging=%s drawn=%s weight=%.2f lantern=%.2f" % [_pilot.is_tredging,
			_pilot.is_item_drawn(), _pilot.tredge.pose.weight, _pilot.tredge.pose.lantern])
		var sl: Node3D = _pilot.tredge.staff_light
		print("light vis=%s fade=%.2f pos=%s energy=%.2f" % [sl.visible, sl.fade, sl.global_position - _pilot.global_position, sl.light.light_energy])
	if _frames == 60:
		_view("side", 0.0)
	if _frames == 62:
		_shot("idle_side.png")
		_view("front34", 0.0)
	if _frames == 64:
		_shot("idle_front34.png")
		_view("back", 0.0)
	if _frames == 66:
		_shot("idle_back.png")
		Input.action_press("forward")
	if _frames > 66 and _frames < 400 and _frames % 20 == 0:
		var state: String = _pilot.anim_tree.get("parameters/playback").get_current_node()
		print("f%d state=%s speed=%.2f gust=%.2f stagger=%.2f" % [_frames, state,
			Vector2(_pilot.velocity.x, _pilot.velocity.z).length(), _pilot.tredge.gust,
			_pilot.tredge.pose.stagger])
	for spec in [[180, "side"], [195, "side"], [210, "side"], [240, "front34"], [255, "front34"],
			[280, "back"], [300, "back"]]:
		if _frames == spec[0]:
			_view(spec[1], 0.0)
		if _frames == spec[0] + 2:
			_shot("walk_%s_f%d.png" % [spec[1], spec[0]])
	if _frames == 320:
		Input.action_release("forward")
		return true
	return false

func _view(kind: String, _unused: float) -> void:
	var p: Vector3 = _pilot.global_position
	var f: Vector3 = _pilot._facing()
	var right := f.cross(Vector3.UP).normalized()
	var at := p + Vector3.UP * 1.1
	match kind:
		"side":
			_cam.global_position = at + right * 3.0
		"front34":
			_cam.global_position = at + f * 2.4 + right * 1.6 + Vector3.UP * 0.2
		"back":
			_cam.global_position = at - f * 3.0 + Vector3.UP * 0.4
	_cam.look_at(at, Vector3.UP)

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name))

func _find_pilot(n: Node) -> Node:
	if n.has_method(&"begin_tredge"):
		return n
	for c in n.get_children():
		var r := _find_pilot(c)
		if r != null:
			return r
	return null
