extends SceneTree
var p
var f := 0
func _initialize() -> void:
	p = load("res://scenes/pilot9.tscn").instantiate()
	root.add_child(p)
func _process(_d: float) -> bool:
	f += 1
	if f < 3: return false
	var sk: Skeleton3D = p.get_node("character/Armature/GeneralSkeleton")
	print("char ", p.get_node("character").transform, " skel_global ", sk.global_transform, " body ", p.global_transform)
	for b in sk.get_bone_count():
		var r := sk.get_bone_global_rest(b)
		print(b, " ", sk.get_bone_name(b), " par=", sk.get_bone_parent(b), " pos=", r.origin.snappedf(0.001), " x=", r.basis.x.snappedf(0.01), " y=", r.basis.y.snappedf(0.01))
	for c in sk.get_children():
		print("child ", c.name, " ", c.get_class(), " ", c.get_script().resource_path if c.get_script() else "")
	return true
