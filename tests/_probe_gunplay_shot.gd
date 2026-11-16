extends SceneTree

# Throwaway probe, WINDOWED: screenshots the gun HUD in the trial scene - the hip crosshair, the
# aimed one (right mouse held), a fired shot at the dummy's slab, and the empty count. Run:
#   godot --path . --script tests/_probe_gunplay_shot.gd -- <out_dir>
# Sets Inventory.persist = false first: windowed probes would write the real save.

var _pilot: Node
var _frames := 0
var _out := ""
var _dummy: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var inv := root.get_node_or_null("/root/Inventory")
	if inv != null:
		inv.persist = false
	change_scene_to_file("res://scenes/trial.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		_pilot = _find_pilot(current_scene) if current_scene != null else null
		return _frames > 900
	if _frames == 40:
		_dummy = get_nodes_in_group(&"range_dummy")[0]
		_pilot.global_position = _dummy.global_position + Vector3(2.0, 0.3, 9.0)
		_pilot.camera_pivot.rotation.y = 0.0
		_pilot.draw_slot(1, true)
	if _frames == 70:
		_shot("gun_hip.png")
	if _frames == 71:
		Input.action_press(&"aim")
	if _frames == 100:
		_shot("gun_aim.png")
		_pilot.gunplay.try_fire()
	if _frames == 103:
		_shot("gun_fired.png")
	if _frames == 104:
		Input.action_release(&"aim")
		for i in 5:
			_pilot.gunplay.tick(0.4)
			_pilot.gunplay.try_fire()
	if _frames == 120:
		_shot("gun_empty.png")
		quit()
		return true
	return false


func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name))


func _find_pilot(n: Node) -> Node:
	if n.has_method(&"press_weapon") and not n.frozen:
		return n
	for c in n.get_children():
		var r := _find_pilot(c)
		if r != null:
			return r
	return null
