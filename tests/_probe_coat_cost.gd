extends SceneTree

# Throwaway probe, headless: the trench coat's triangle count and its spring tick's cost, in the
# same debug / headless setup that measured the poncho at 6-8 ms. Loads trial (both pilots), walks
# the played pilot's hips through a run, a sprint and a dash by hand and times tick().
#   godot --headless --path . --script tests/_probe_coat_cost.gd

var _frames := 0
var _pilots: Array[Node] = []

func _initialize() -> void:
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _pilots.is_empty():
		if current_scene != null:
			_find(current_scene)
		return _frames > 600
	if _frames < 30:
		return false
	for pilot in _pilots:
		var coat: Node = pilot.coat
		if coat == null or coat.mesh_instance == null:
			print("no coat on ", pilot.name)
			return true
		var mesh: Mesh = coat.mesh_instance.mesh
		var tris := 0
		for s in mesh.get_surface_count():
			tris += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		print("%s: coat on %s, %d triangles, %d bones, arm pieces hidden: %s" % [pilot.name, coat.is_on, tris,
			coat.skeleton.get_bone_count(), coat.arm_meshes.map(func(m: Node) -> String: return m.name)])
	# The cost: 2000 ticks per case, the pilot shoved along so the springs are working and the
	# floor plane is live.
	for case: Array in [["standing", 0.0], ["run 5 m/s", 5.0], ["sprint 7.5 m/s", 7.5], ["dash 40 m/s", 40.0]]:
		var total := 0
		var worst := 0
		for pilot in _pilots:
			var coat: Node = pilot.coat
			coat.reset()
			var start: Vector3 = pilot.global_position
			var n := 2000
			var sum := 0
			for i in n:
				pilot.global_position += Vector3(0.0, 0.0, -float(case[1]) / 60.0)
				if pilot.global_position.distance_to(start) > 2.0:
					# Keep him near the floor he stands on; the coat drops its history on the jump.
					pilot.global_position = start
				var t0 := Time.get_ticks_usec()
				coat.tick(1.0 / 60.0)
				var dt := Time.get_ticks_usec() - t0
				sum += dt
				worst = maxi(worst, dt)
			pilot.global_position = start
			total += sum / n
		print("%-16s both pilots %.3f ms a tick (worst single tick %.3f ms)" % [case[0], total / 1000.0, worst / 1000.0])
	return true

func _find(n: Node) -> void:
	if n.has_method(&"toggle_coat"):
		_pilots.append(n)
	for c in n.get_children():
		_find(c)
