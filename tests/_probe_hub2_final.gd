extends SceneTree

# Throwaway probe, WINDOWED: hub2 (real look) eye-height review shots of the final dressing + perf
# per shot (docs/specs/hub2-final-pass.md). Camera held still 40 frames per shot.
#   godot --path . --script tests/_probe_hub2_final.gd -- <out_dir> [only_index]
var _f := 0
var _i := 0
var _cam: Camera3D
var _out := ""
var _only := -1
var _t0 := 0
const SHOTS := [
	["spawn_fwd", Vector3(0, 30.8, 84), Vector3(0, 30.0, 40)],
	["neck_checkpoint", Vector3(2.5, 30.8, 66), Vector3(-1.0, 30.0, 48)],
	["spawn_side_gate", Vector3(4, 30.8, 30), Vector3(14, 26.0, 18)],
	["gallery_mid_E", Vector3(16.5, 23.5, 4), Vector3(16.5, 23.0, -30)],
	["gallery_blockage1", Vector3(16.5, 23.5, 1), Vector3(16.0, 22.5, -8)],
	["crossN_to_yard", Vector3(-25, 23.5, -129), Vector3(-60, 23.5, -129)],
	["yard_entry_N", Vector3(-64, 23.5, -129), Vector3(-110, 24.0, -100)],
	["yard_aisle", Vector3(-106, 23.5, -125), Vector3(-106, 23.0, -95)],
	["yard_girder", Vector3(-80, 24.0, -60), Vector3(-110, 22.5, -72)],
	["yard_camp", Vector3(-141, 23.5, -17), Vector3(-128, 22.5, -20)],
	["yard_rooms", Vector3(-140, 23.8, -48), Vector3(-160, 23.0, -62)],
	["yard_south", Vector3(-80, 24.0, 0), Vector3(-110, 22.5, 30)],
	["a_pile", Vector3(-12, -271.0, -300), Vector3(6, -269.5, -285)],
	["c_link_barricade", Vector3(45, 32.7, -108.5), Vector3(60, 31.5, -108.5)],
	["c_dock", Vector3(72, 33.0, -112), Vector3(105, 32.0, -110)],
	["c_dock_ledge", Vector3(80, 33.0, -125), Vector3(98, 34.0, -90)],
	["e_collapse", Vector3(30, 45.3, -41.5), Vector3(50, 45.0, -41.5)],
	["plant_room", Vector3(80, 45.3, -32), Vector3(105, 46.0, -40)],
	["plant_pumps", Vector3(90, 45.8, -48), Vector3(100, 45.0, -25)],
	["overlook", Vector3(-33, 45.3, -130), Vector3(-40, 44.5, -150)],
	["a_heap", Vector3(0, -271.0, -205), Vector3(10, -270.0, -255)],
	["a_heap_close", Vector3(-25, -271.0, -238), Vector3(5, -270.5, -258)],
	["a_coldstore", Vector3(70, -271.0, -262), Vector3(99, -271.0, -262)],
]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0]
	if a.size() > 1:
		_only = int(a[1])
		_i = _only
	_t0 = Time.get_ticks_msec()
	change_scene_to_file("res://scenes/hub2.tscn")

func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		print("FIRST_FRAME_MS ", Time.get_ticks_msec() - _t0)
	if _f == 120:
		var pl := current_scene.get_node("Pilot9") as Node3D
		pl.process_mode = Node.PROCESS_MODE_DISABLED
		pl.visible = false
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
		_cam.fov = 70
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
		if k == 40:
			root.get_texture().get_image().save_png("%s/%02d_%s.png" % [_out, _i, s[0]])
			print("PERF %s fps %d draws %d prims %d" % [s[0], Engine.get_frames_per_second(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
			_i += 1
			_f = 120
			if _only >= 0:
				return true
	return _i >= SHOTS.size()
