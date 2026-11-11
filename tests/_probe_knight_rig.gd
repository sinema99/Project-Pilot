extends SceneTree
# Dumps pilot9.glb's tree, bone rests (global, in the model's frame) and idle.res track paths.
func _initialize() -> void:
	var s: Node = (load("res://assets/pilot9.glb") as PackedScene).instantiate()
	_tree(s, "")
	var sk: Skeleton3D = s.find_children("*", "Skeleton3D", true, false)[0]
	print("skeleton path: ", s.get_path_to(sk), " xform ", sk.transform, " parent ", sk.get_parent().transform)
	for b in sk.get_bone_count():
		var g := sk.get_bone_global_rest(b)
		print(b, " ", sk.get_bone_name(b), " parent=", sk.get_bone_parent(b), " pos=", g.origin, " x=", g.basis.x, " y=", g.basis.y, " z=", g.basis.z)
	for m in s.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		print("mesh ", mi.name, " aabb ", mi.get_aabb())
	var idle: Animation = load("res://addons/real-controller/animations/idle.res")
	for t in idle.get_track_count():
		if t < 6: print("track ", idle.track_get_path(t), " type ", idle.track_get_type(t))
	print("idle len ", idle.length, " tracks ", idle.get_track_count())
	quit()
func _tree(n: Node, ind: String) -> void:
	print(ind, n.name, " (", n.get_class(), ")")
	for c in n.get_children():
		_tree(c, ind + "  ")
