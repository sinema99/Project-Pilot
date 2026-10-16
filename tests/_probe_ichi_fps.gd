extends SceneTree

# Throwaway probe, WINDOWED: boots Ichi.tscn, stands the pilot outside and then inside the building
# and measures the GPU frame time with each expensive thing switched off in turn, to find what
# costs more indoors. Run:
#   godot --path . --script tests/_probe_ichi_fps.gd

const SAMPLE := 90

var _frames := 0
var _started := false

func _initialize() -> void:
	change_scene_to_file("res://Ichi.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null:
		return _frames > 900
	var storm: Storm = current_scene.find_child("Storm", true, false)
	if storm == null or storm.roof_image == null:
		return _frames > 900
	if _frames < 120 or _started:
		return false
	_started = true
	_run(storm)
	return false

func _gpu_ms() -> float:
	var vp := root.get_viewport_rid()
	var total := 0.0
	for i in SAMPLE:
		await process_frame
		total += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	# PixelWorld renders through its own SubViewport; add those too.
	return total / SAMPLE

func _all_viewports_ms() -> float:
	var vps: Array = [root]
	vps.append_array(root.find_children("*", "SubViewport", true, false))
	for v in vps:
		RenderingServer.viewport_set_measure_render_time((v as Viewport).get_viewport_rid(), true)
	for i in 10:
		await process_frame
	var total := 0.0
	var cpu := 0.0
	var t0 := Time.get_ticks_usec()
	for i in SAMPLE:
		await process_frame
		cpu += Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		for v in vps:
			total += RenderingServer.viewport_get_measured_render_time_gpu((v as Viewport).get_viewport_rid())
	var wall := (Time.get_ticks_usec() - t0) / 1000.0 / SAMPLE
	print("    frame %.2f ms (%.0f fps), script cpu %.2f ms" % [wall, 1000.0 / wall, cpu * 1000.0 / SAMPLE])
	return total / SAMPLE

func _place(pilot: Node3D, pos: Vector3) -> void:
	pilot.global_position = pos
	if pilot is CharacterBody3D:
		(pilot as CharacterBody3D).velocity = Vector3.ZERO

func _run(storm: Storm) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var pilot: Node3D = current_scene.find_child("Pilot9", true, false)
	var outside := pilot.global_position
	# Inside = the sheltered spot nearest the spawn with at least 3 m of headroom.
	var space := storm.get_world_3d().direct_space_state
	var best := Vector3.INF
	for i in 200:
		for j in 200:
			var xz := storm.roof_rect.position + storm.roof_rect.size * Vector2((i + 0.5) / 200.0, (j + 0.5) / 200.0)
			var roof := storm.roof_height(xz)
			if roof == -INF:
				continue
			var rq := PhysicsRayQueryParameters3D.create(Vector3(xz.x, roof - 0.5, xz.y), Vector3(xz.x, roof - 100.0, xz.y))
			var h := space.intersect_ray(rq)
			if h.is_empty() or roof - (h.position as Vector3).y < 3.0:
				continue
			var cand: Vector3 = h.position
			if best == Vector3.INF or cand.distance_to(outside) < best.distance_to(outside):
				best = cand
	var hit := {"position": best}
	var inside: Vector3 = (hit.position as Vector3) + Vector3.UP * 0.2
	print("outside ", outside, " inside ", inside)

	var sun: DirectionalLight3D = current_scene.find_child("Sun", true, false)
	var op1: Node3D = current_scene.find_child("OP_1", true, false)
	var meshes: Array[MeshInstance3D] = []
	for n in op1.find_children("*", "MeshInstance3D", true, false):
		meshes.append(n)
	var saved := {}
	for m in meshes:
		saved[m] = m.material_override
	var plain := StandardMaterial3D.new()

	var configs := {
		"all on": func(on: bool) -> void: pass,
		"no fog": func(on: bool) -> void: storm.get_node("Fog").visible = on,
		"no snow": func(on: bool) -> void:
			storm.get_node("FineSnow").visible = on
			storm.get_node("NearSnow").visible = on
			storm.get_node("Drift").visible = on,
		"no sun shadow": func(on: bool) -> void: sun.shadow_enabled = on,
		"no cel passes on level": func(on: bool) -> void:
			for m in meshes:
				var mat: Material = saved[m]
				if mat is ShaderMaterial:
					var c := (mat as ShaderMaterial).duplicate() as ShaderMaterial
					if not on:
						c.next_pass = null
					m.material_override = c if not on else mat,
		"plain material on level": func(on: bool) -> void:
			for m in meshes:
				m.material_override = saved[m] if on else plain,
	}
	for where in ["outside", "inside"]:
		_place(pilot, outside if where == "outside" else inside)
		for i in 30:
			await process_frame
		for name in configs:
			var f: Callable = configs[name]
			f.call(false)
			var ms: float = await _all_viewports_ms()
			f.call(true)
			print("%-8s %-26s %6.2f ms  (%d draws, %d prims)" % [where, name, ms,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		root.get_texture().get_image().save_png(OS.get_user_data_dir() + "/fps_" + where + ".png")
	print("shots in ", OS.get_user_data_dir())
	quit()
