extends SceneTree

# Throwaway probe, WINDOWED (the bake needs a real renderer): why does the afterimage dash lag?
# Times a real dash's frames against idle frames, then times _drop() and its pieces on their own,
# with MOVEMENT EFFECTS (the ghosts) on and off. Run:
#   godot --path . --script tests/_probe_dash_lag.gd

const _ApplyStylized := preload("res://scripts/rendering/apply_stylized.gd")

var _pilot: Node
var _frames := 0
var _last_us := 0
var _phase := ""
var _samples := {}
var _dash_at := -1
var _plan := [[240, "idle"], [300, "dash_ghosts"], [360, "dash_no_ghosts"], [420, "dash_ghosts"],
	[480, "pieces"]]

func _initialize() -> void:
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_d: float) -> bool:
	_frames += 1
	var now := Time.get_ticks_usec()
	var dt := (now - _last_us) / 1000.0
	_last_us = now
	if _pilot == null:
		_pilot = _find(current_scene) if current_scene != null else null
		return _frames > 600
	if _phase != "" and _frames > 200:
		_samples.get_or_add(_phase, []).append(dt)
	for step in _plan:
		if _frames == step[0]:
			_begin(step[1])
	if _dash_at > 0 and _frames - _dash_at == 25:
		_phase = "idle"
		_dash_at = -1
	return _frames > 520

func _begin(what: String) -> void:
	if what == "idle":
		_phase = "idle"
	elif what.begins_with("dash"):
		_pilot._afterimage.clear()
		var ghosts := what == "dash_ghosts"
		_set_effects(ghosts)
		_phase = what + "#%d" % _frames
		_dash_at = _frames
		_pilot._start_dash(Vector3.LEFT)
	elif what == "pieces":
		_phase = ""
		_report()
		_pieces()

func _set_effects(on: bool) -> void:
	# Straight into the dictionary, not set_value(): that would save over the player's settings.
	var s := root.get_node_or_null("/root/Settings")
	s._values[&"movement_effects"] = "on" if on else "off"

func _report() -> void:
	for k in _samples:
		var a: Array = _samples[k]
		var worst := 0.0
		var total := 0.0
		for v in a:
			worst = maxf(worst, v)
			total += v
		print("%-22s frames=%3d  avg=%6.2f ms  worst=%6.2f ms" % [k, a.size(), total / a.size(), worst])

func _pieces() -> void:
	var meshes: Array[MeshInstance3D] = []
	_ApplyStylized.collect_meshes(_pilot.character, meshes)
	for mi in meshes:
		if not mi.mesh is ArrayMesh:
			print("mesh %s (%s, not skinned)" % [mi.name, mi.mesh])
			continue
		var verts := 0
		for s in mi.mesh.get_surface_count():
			verts += mi.mesh.surface_get_array_len(s)
		print("mesh %s skinned=%s verts=%d surfaces=%d" % [mi.name, mi.skin != null, verts,
			mi.mesh.get_surface_count()])
		if mi.skin == null:
			continue
		for rep in 1:
			var t := Time.get_ticks_usec()
			for s in mi.mesh.get_surface_count():
				mi.mesh.surface_get_arrays(s)
			var t_read := Time.get_ticks_usec()
			mi.bake_mesh_from_current_skeleton_pose()
			var t_bake := Time.get_ticks_usec()
			print("  surface_get_arrays (GPU readback): %.2f ms   full bake: %.2f ms" % [
				(t_read - t) / 1000.0, (t_bake - t_read) / 1000.0])
	_pilot._afterimage.clear()
	_pilot._afterimage.begin(_pilot.character, true)
	var skinned := 0
	var total_verts := 0
	for mi in meshes:
		if mi.skin != null and mi.mesh is ArrayMesh:
			skinned += 1
			for s in mi.mesh.get_surface_count():
				total_verts += mi.mesh.surface_get_array_len(s)
	print("TOTAL: %d meshes, %d skinned, %d skinned verts" % [meshes.size(), skinned, total_verts])
	for rep in 3:
		var t := Time.get_ticks_usec()
		_pilot._afterimage._drop(_pilot.character, Vector3.ZERO)
		print("full _drop: %.2f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	_pilot._afterimage.clear()

func _find(n: Node) -> Node:
	if n == null: return null
	if n.get_script() != null and n.get_script().resource_path == "res://scripts/pilot9.gd": return n
	for c in n.get_children():
		var f := _find(c)
		if f != null: return f
	return null
