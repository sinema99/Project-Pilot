extends SceneTree

# Throwaway probe, WINDOWED: shoots pilot9's body-slot weapons (rifle on the backpack, revolver on the
# right thigh) from behind-left and from the right, then a draw in slow motion. Run:
#   godot --path . --script tests/_probe_mounts_shot.gd -- <out_dir>

var _pilot: Node
var _frames := 0
var _out := ""
var _cam: Camera3D
var _stage := 0
var _anim_shots := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		_pilot = _find_pilot(current_scene) if current_scene != null else null
		return _frames > 900
	if _frames == 5:
		var inv := root.get_node_or_null("/root/Inventory")
		if inv != null:
			inv.set("persist", false)
	if _frames == 60:
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
		print("slots: ", _pilot.weapon_slots, " mounts: ", _pilot.weapon_mounts._mounts.size(),
			" pack on: ", _pilot.is_backpack_on())
	if _frames == 62:
		_aim_cam(-1.0, 0.0, -2.6)   # behind (pilot back is -facing), slightly to his left
		_shot("mounts_back.png")
	if _frames == 66:
		_aim_cam(-1.0, 2.2, 0.0)
		_shot("mounts_right.png")
	if _frames == 70:
		_aim_cam(1.0, 0.0, -2.6)
		_shot("mounts_back_left.png")
	if _frames == 74:
		_aim_cam(-1.0, 1.6, 1.6)
		_shot("mounts_front_right.png")
	if _frames == 80:
		_aim_cam(-1.0, 1.8, -1.2)
		Engine.time_scale = 0.1
		print("press_weapon(0) -> ", _pilot.press_weapon(0))
	if _frames > 80 and _stage == 0:
		var anim: Node = _pilot.equip_anim
		if anim.is_playing() and _frames % 6 == 0 and _anim_shots < 6:
			_shot("draw_%d_t%.2f.png" % [_anim_shots, anim.t])
			_anim_shots += 1
		if not anim.is_playing():
			_shot("draw_done.png")
			Engine.time_scale = 1.0
			return true
	return _frames > 2500

## side: +1 his left, -1 his right; dist: along his right axis; fwd: along his facing
func _aim_cam(side: float, right_dist: float, fwd: float) -> void:
	var p: Vector3 = _pilot.global_position
	var f: Vector3 = _pilot._facing()
	var right := f.cross(Vector3.UP).normalized()
	_cam.global_position = p + f * fwd + right * (right_dist * -side if side < 0 else -right_dist) + Vector3.UP * 1.3
	_cam.look_at(p + Vector3.UP * 1.1, Vector3.UP)

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
