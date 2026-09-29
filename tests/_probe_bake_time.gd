extends SceneTree
const _ApplyStylized := preload("res://scripts/rendering/apply_stylized.gd")
var _pilot: Node
var _frames := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/trial.tscn")
func _process(_d: float) -> bool:
	_frames += 1
	if _pilot == null:
		_pilot = _find(current_scene) if current_scene != null else null
		if _frames % 30 == 0: print("frame ", _frames, " scene ", current_scene)
		return _frames > 600
	if _frames == 200:
		print("pilot found, char=", _pilot.character)
		var meshes: Array[MeshInstance3D] = []
		_ApplyStylized.collect_meshes(_pilot.character, meshes)
		for mi in meshes:
			var verts := 0
			if mi.mesh:
				for s in mi.mesh.get_surface_count():
					verts += mi.mesh.surface_get_array_len(s)
			print(mi.name, " skinned=", mi.skin != null, " verts=", verts, " surfaces=", mi.mesh.get_surface_count() if mi.mesh else 0)
		for rep in 3:
			for mi in meshes:
				if mi.skin == null: continue
				var t := Time.get_ticks_usec()
				var b := mi.bake_mesh_from_current_skeleton_pose()
				print("bake ", mi.name, ": ", (Time.get_ticks_usec() - t) / 1000.0, " ms")
		var t2 := Time.get_ticks_usec()
		_pilot._afterimage.begin(_pilot.character, true)
		_pilot._afterimage._drop(_pilot.character, Vector3.ZERO)
		print("full _drop: ", (Time.get_ticks_usec() - t2) / 1000.0, " ms")
	if _frames == 201:
		var t3 := Time.get_ticks_usec()
		_pilot._afterimage._drop(_pilot.character, Vector3.ZERO)
		print("second _drop: ", (Time.get_ticks_usec() - t3) / 1000.0, " ms")
	return _frames > 210
func _find(n: Node) -> Node:
	if n == null: return null
	if n.get_script() != null and n.get_script().resource_path == "res://scripts/pilot9.gd": return n
	for c in n.get_children():
		var f := _find(c)
		if f != null: return f
	return null
