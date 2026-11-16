extends SceneTree

# Throwaway probe, WINDOWED: screenshots pilot9's gun poses in trial - hip, aim, a fired shot, then
# frames across a reload - each from the game camera and from a side camera. Run:
#   godot --path . --script tests/_probe_gunplay_pose.gd -- <out_dir> [weapon_slot 0 rifle, 1 revolver]
# Sets Inventory.persist = false first: windowed probes would write the real save.

var _pilot: Node
var _frames := 0
var _out := ""
var _slot := 0
var _side: Camera3D
var _want: String = ""
var _phase := 0
var _pitch := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_slot = int(args[1]) if args.size() > 1 else 0
	_pitch = float(args[2]) if args.size() > 2 else 0.0
	var inv := root.get_node_or_null("/root/Inventory")
	if inv != null:
		inv.persist = false
	change_scene_to_file("res://scenes/trial.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		_pilot = _find_pilot(current_scene) if current_scene != null else null
		return _frames > 900
	var g: Node = _pilot.gunplay
	if _frames == 40:
		var dummy: Node = get_nodes_in_group(&"range_dummy")[0]
		_pilot.global_position = dummy.global_position + Vector3(2.0, 0.3, 9.0)
		_pilot.camera_pivot.rotation.y = 0.0
		_pilot.draw_slot(_slot, true)
		_side = Camera3D.new()
		current_scene.add_child(_side)
	if _frames == 70:
		print("armed: ", g.armed(), " gun: ", g.gun().display_name if g.gun() != null else "none")
		_snap("hip")
	if _frames == 120:
		_pilot.camera_pivot.rotation.x = deg_to_rad(_pitch)
		Input.action_press(&"aim")
	if _frames == 260:
		_snap("aim")
	if _frames == 300:
		g.try_fire()
	if _frames == 303:
		_snap("fired")
	if _frames == 360:
		Input.action_release(&"aim")
		g.press_reload()
	if _frames > 362 and g.reload_progress() >= 0.0 and _frames % 20 == 0:
		_snap("reload_%03d" % int(g.reload_progress() * 100.0))
	_step_snap()
	if _frames == 560:
		quit()
		return true
	return false


## One moment, two views: the game camera now, the side camera over the next frames.
func _snap(tag: String) -> void:
	_want = tag
	_phase = 1
	_save("%s_game" % tag)


func _step_snap() -> void:
	if _phase == 1:
		var body: Node3D = _pilot.character
		var c := body.global_position + Vector3(0, 1.3, 0)
		_side.global_position = c + body.global_basis.x * 2.2 + Vector3(0, 0.1, -0.6)
		_side.look_at(c)
		_side.make_current()
		_phase = 2
	elif _phase == 2:
		_save("%s_side" % _want)
		_pilot.camera_3d.make_current()
		_phase = 0


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join("w%d_p%d_%s.png" % [_slot, int(_pitch), name]))


func _find_pilot(n: Node) -> Node:
	if n.has_method(&"press_weapon") and not n.frozen:
		return n
	for c in n.get_children():
		var r := _find_pilot(c)
		if r != null:
			return r
	return null
