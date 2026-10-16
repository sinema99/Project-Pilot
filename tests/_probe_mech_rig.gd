extends SceneTree
var _n := 0
func _process(_d: float) -> bool:
	_n += 1
	if _n == 1:
		var m: Node3D = load("res://scenes/mech.tscn").instantiate()
		root.add_child(m)
		return false
	var m: Node3D = root.get_child(root.get_child_count() - 1)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var model: Node3D = m.get_node("Model")
	var ap: AnimationPlayer = m.get_node("Model/AnimationPlayer")
	print("model xf ", model.global_transform)
	print("skel xf ", sk.global_transform)
	print("skel in model ", model.global_transform.affine_inverse() * sk.global_transform)
	print("anims ", ap.get_animation_list())
	ap.play("MECH_standing"); ap.seek(0.0, true)
	var C: Transform3D = model.global_transform.affine_inverse() * sk.global_transform
	for b in sk.get_bone_count():
		var g := C * sk.get_bone_global_pose(b)
		var par := sk.get_bone_parent(b)
		print(b, " ", sk.get_bone_name(b), " par=", (sk.get_bone_name(par) if par >= 0 else "-"), " head=", g.origin, " yaxis=", g.basis.y.normalized(), " rest_loc=", sk.get_bone_rest(b).origin)
	var st := ap.get_animation("MECH_standing")
	for t in st.get_track_count():
		print("track ", st.track_get_path(t), " type ", st.track_get_type(t), " keys ", st.track_get_key_count(t))
	var w := ap.get_animation("MECH_walk")
	print("walk len ", w.length)
	return true
