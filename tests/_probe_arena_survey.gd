extends SceneTree
var _shot: Node
var _t0 := 0
var _frames := 0
func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	_shot = load("res://scenes/cutscene_arrival.tscn").instantiate()
	_shot.autoplay = false
	root.add_child(_shot)
	print("build ms ", Time.get_ticks_msec() - _t0)
func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	var base = _shot.base
	print("cap_tops ", base.cap_tops)
	for c in base.caps:
		print("cap y ", c.y, " pts ", c.poly.size(), " centroid-ish ", c.poly[0])
	for n in ["Land", "Base", "Spire", "Forest", "Growth", "Clouds"]:
		var node: Node = _shot.get_node(n)
		print("== ", n, " children ", node.get_child_count())
		for ch in node.get_children():
			_dump(ch, 1)
	return true
func _dump(n: Node, depth: int) -> void:
	var info := ""
	if n is MeshInstance3D and n.mesh != null:
		var v := 0
		for s in n.mesh.get_surface_count():
			v += n.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
		info = " mesh verts %d aabb %s" % [v, n.get_aabb()]
	elif n is MultiMeshInstance3D and n.multimesh != null:
		info = " multimesh count %d aabb %s" % [n.multimesh.instance_count, n.multimesh.get_aabb()]
	elif n is Node3D:
		info = " pos %s" % n.position
	print("  ".repeat(depth), n.name, " ", n.get_class(), info)
	if depth < 2:
		for ch in n.get_children():
			_dump(ch, depth + 1)
