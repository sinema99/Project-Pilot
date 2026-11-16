extends SceneTree

# Throwaway probe, WINDOWED: eye-height shots of hub2's crane control room (docs/specs/hub2-control-room.md).
#   godot --path . --script tests/_probe_control_room.gd -- <out_dir> [only_index] [open_door]
var _f := 0
var _i := 0
var _cam: Camera3D
var _out := ""
var _only := -1
var _open := false
const SHOTS := [
	["in_south", Vector3(-63.5, 45.2, -45.0), Vector3(-67.0, 45.0, -78.0)],
	["in_console", Vector3(-65.5, 45.6, -40.0), Vector3(-68.5, 45.0, -58.0)],
	["in_stations", Vector3(-65.2, 45.4, -69.0), Vector3(-68.5, 45.0, -52.0)],
	["in_north", Vector3(-66.0, 45.2, -40.0), Vector3(-65.5, 45.4, -23.5)],
	["in_door_inside", Vector3(-67.0, 45.2, -40.3), Vector3(-58.0, 45.0, -40.3)],
	["in_windows", Vector3(-66.0, 45.4, -52.0), Vector3(-73.0, 46.5, -58.0)],
	["corridor_door", Vector3(-40.0, 45.2, -40.3), Vector3(-58.0, 45.2, -40.3)],
	["corridor_door_close", Vector3(-52.0, 45.0, -40.3), Vector3(-58.4, 45.0, -40.3)],
	["yard_up", Vector3(-90.0, 33.0, -66.0), Vector3(-70.0, 47.0, -56.0)],
	["yard_up_far", Vector3(-95.0, 30.0, -100.0), Vector3(-70.0, 47.0, -60.0)],
	["level_west", Vector3(-65.0, 45.3, -52.0), Vector3(-90.0, 45.3, -52.0)],
	["in_south2", Vector3(-65.0, 45.2, -70.0), Vector3(-62.0, 45.0, -82.0)],
]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0]
	if a.size() > 1 and a[1] != "-1":
		_only = int(a[1])
		_i = _only
	_open = a.size() > 2 and a[2] == "open"
	change_scene_to_file("res://scenes/hub2.tscn")

func _process(_d: float) -> bool:
	_f += 1
	if _f == 120:
		var inv := root.get_node_or_null("Inventory")
		if inv != null:
			inv.set("persist", false)
		var pl := current_scene.get_node("Pilot9") as Node3D
		pl.process_mode = Node.PROCESS_MODE_DISABLED
		pl.visible = false
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
		_cam.fov = 75
		if OS.get_cmdline_user_args().size() > 2 and OS.get_cmdline_user_args()[2] == "noroom":
			current_scene.get_node("ControlRoom").queue_free()
		if _open:
			(current_scene.get_node("ControlRoom") as Hub2ControlRoom).door.toggle()
	if _f > 120 and _i < SHOTS.size():
		var k := _f - 121
		var s: Array = SHOTS[_i]
		var ui := root.get_node_or_null("UI")
		if ui != null:
			while not (ui.stack as Array).is_empty():
				ui.close()
		paused = false
		if k == 0:
			_cam.global_position = s[1]
			_cam.look_at(s[2])
		if k == 45:
			root.get_texture().get_image().save_png("%s/%02d_%s.png" % [_out, _i, s[0]])
			print("SHOT ", s[0])
			_i += 1
			_f = 120
			if _only >= 0:
				return true
	return _i >= SHOTS.size()
