extends SceneTree
# Throwaway probe, WINDOWED: hub2 frame time at fixed held views (docs/specs/hub2-final-pass.md).
#   godot --path . --script tests/_probe_hub2_perf.gd -- <full|nodress|nowear>
const VIEWS := [
	["spawn", Vector3(0, 30.8, 84), Vector3(0, 30.0, 40)],
	["gallery", Vector3(16.5, 23.5, 4), Vector3(16.5, 23.0, -30)],
	["B_entry", Vector3(-64, 23.5, -129), Vector3(-110, 24.0, -100)],
	["B_aisle", Vector3(-106, 23.5, -125), Vector3(-106, 23.0, -95)],
	["C", Vector3(72, 33.0, -112), Vector3(105, 32.0, -110)],
	["plant", Vector3(80, 45.3, -32), Vector3(105, 46.0, -40)],
	["A_heap", Vector3(0, -271.0, -205), Vector3(10, -270.0, -255)],
]
var _f := 0
var _i := 0
var _t0 := 0
var _cam: Camera3D
func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	change_scene_to_file("res://scenes/hub2.tscn")
func _process(_d: float) -> bool:
	_f += 1
	if _f == 150:
		var pl := current_scene.get_node("Pilot9") as Node3D
		pl.process_mode = Node.PROCESS_MODE_DISABLED
		pl.visible = false
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
		_cam.fov = 70
		var mode: String = OS.get_cmdline_user_args()[0]
		if mode == "nodress":
			(current_scene.get_node("Dressing") as Node3D).visible = false
		if mode == "nowear":
			for m in current_scene.get_node("Map").find_children("*", "MeshInstance3D", true, false):
				(m as MeshInstance3D).visible = false
	if _f < 150 or _i >= VIEWS.size():
		return _i >= VIEWS.size()
	var k := _f - 150 - _i * 300
	var v: Array = VIEWS[_i]
	if k <= 1:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		_cam.current = true
		_cam.global_position = v[1]
		_cam.look_at(v[2])
	if k == 120:
		_t0 = Time.get_ticks_usec()
	if k == 300:
		var ms := (Time.get_ticks_usec() - _t0) / 180.0 / 1000.0
		print("PERF %s %s %.2f ms (%.0f fps) draws %d prims %d" % [OS.get_cmdline_user_args()[0], v[0], ms, 1000.0 / ms, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		_i += 1
	return false
