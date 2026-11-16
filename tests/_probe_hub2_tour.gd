extends SceneTree

# Throwaway probe, WINDOWED: hub2 with the real look + fog; camera at eye height in each room; shots + perf.
#   godot --path . --script tests/_probe_hub2_tour.gd -- <out_dir>
var _f := 0
var _i := 0
var _cam: Camera3D
var _out := ""
const SHOTS := [
	["A_landing", Vector3(0, 0, -196), Vector3(8, 0, -262)],
	["A_heap", Vector3(-30, 0, -225), Vector3(10, 0, -268)],
	["A_across", Vector3(-70, 0, -400), Vector3(10, 0, -240)],
	["A_crane", Vector3(60, 0, -130), Vector3(-30, 40, -250)],
	["A_wall", Vector3(60, 0, -300), Vector3(95, 3, -340)],
	["A_up", Vector3(0, 0, -200), Vector3(4, 60, -232)],
]
func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	change_scene_to_file("res://scenes/hub2.tscn")

func _floor(x: float, z: float, from_y: float) -> float:
	var ss: PhysicsDirectSpaceState3D = (current_scene as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -400, z))
	var r: Dictionary = ss.intersect_ray(q)
	return (r["position"] as Vector3).y if not r.is_empty() else NAN

func _process(_d: float) -> bool:
	_f += 1
	if _f == 150:
		print("saved ", root.get_texture().get_image().save_png(_out + "/0_spawn.png"))
		print("PERF spawn fps ", Engine.get_frames_per_second(), " draws ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " prims ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), " nodes ", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var pl := current_scene.get_node("Pilot9") as Node3D
		print("PILOT ", pl.global_position)
		pl.process_mode = Node.PROCESS_MODE_DISABLED
		pl.visible = false
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
		_cam.fov = 70
	if _f > 150 and _i < SHOTS.size():
		var k := _f - 151
		var s: Array = SHOTS[_i]
		if k == 0:
			var p: Vector3 = s[1]
			var tl: Vector3 = s[2]
			var hy := {"B": 60.0, "C": 45.0, "A": -170.0, "D": 35.0}[(s[0] as String).substr(0, 1)] as float
			p.y = _floor(p.x, p.z, hy) + 1.7
			tl.y = _floor(tl.x, tl.z, hy) + 1.7 + tl.y
			print("SHOT ", s[0], " cam ", p, " look ", tl)
			if is_nan(p.y):
				p.y = hy
			_cam.global_position = p
			if not is_nan(tl.y) and p.distance_to(tl) > 1: _cam.look_at(tl)
		if k == 40:
			print("saved ", root.get_texture().get_image().save_png("%s/%d_%s.png" % [_out, _i + 1, s[0]]))
			print("PERF ", s[0], " fps ", Engine.get_frames_per_second(), " draws ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " prims ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
			_i += 1
			_f = 150
	return _i >= SHOTS.size()
