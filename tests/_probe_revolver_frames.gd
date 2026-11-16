extends SceneTree

# Throwaway probe: prints pilot9's right arm rest frames in skeleton space (facing +Z).

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/pilot9.tscn")
	var p := scene.instantiate()
	root.add_child(p)
	var sk: Skeleton3D = p.get_node("character/Armature/GeneralSkeleton")
	for n in ["RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]:
		var i := sk.find_bone(n)
		var g := sk.get_bone_global_rest(i)
		print(n, " origin ", g.origin, " x ", g.basis.x.normalized(), " y ", g.basis.y.normalized(), " z ", g.basis.z.normalized())
	print("skeleton global basis ", sk.global_basis)
	quit()
