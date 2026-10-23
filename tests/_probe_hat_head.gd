extends SceneTree

# Throwaway probe, headless: prints pilot9's Head bone frame in skeleton space and the highest
# skinned vertices near it, so the hat offset can be fitted. Run:
#   godot --headless --path . --script tests/_probe_hat_head.gd

var _pilot: Node
var _frames := 0

func _initialize() -> void:
	var ps := load("res://scenes/pilot9.tscn") as PackedScene
	_pilot = ps.instantiate()
	root.add_child(_pilot)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var skel := _pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	var head := skel.find_bone("Head")
	var hp := skel.get_bone_global_rest(head)
	print("Head rest (skeleton space): ", hp)
	var pose := skel.get_bone_global_pose(head)
	print("Head pose (skeleton space): ", pose)
	var inv := pose.affine_inverse()
	var slices := {}
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for mi in skel.get_children():
		if not mi is MeshInstance3D or mi.mesh == null:
			continue
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			if bones == null:
				continue
			var per := (bones as PackedInt32Array).size() / verts.size()
			var n := 0
			for i in verts.size():
				# Mostly the Head bone, through the skin's bind -> bone index.
				var heavy := false
				for j in per:
					var bi: int = bones[i * per + j]
					var w: float = weights[i * per + j]
					if w > 0.5 and m.skin != null and bi < m.skin.get_bind_count() \
							and m.skin.get_bind_name(bi) == &"Head":
						heavy = true
				if heavy:
					var bind_pose := skel.get_bone_global_rest(head)
					# Rest-pose vertex -> head-local.
					var local := bind_pose.affine_inverse() * verts[i]
					lo = lo.min(local)
					hi = hi.max(local)
					var band := int(floor(local.y / 0.04))
					if not slices.has(band):
						slices[band] = [local, local]
					slices[band][0] = (slices[band][0] as Vector3).min(local)
					slices[band][1] = (slices[band][1] as Vector3).max(local)
					n += 1
			if n > 0:
				print(m.name, " surf ", s, ": ", n, " head verts")
	print("Head-local vertex bounds: ", lo, " .. ", hi)
	var keys := slices.keys()
	keys.sort()
	for k in keys:
		print("y %.2f: " % (k * 0.04), slices[k][0], " .. ", slices[k][1])
	return true
