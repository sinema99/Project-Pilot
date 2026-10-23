extends SceneTree

# Throwaway probe, headless: which meshes the hat's head cut touches, and how many triangles go.
#   godot --headless --path . --script tests/_probe_hat_cut.gd

var _pilot: Node
var _frames := 0

func _initialize() -> void:
	_pilot = (load("res://scenes/pilot9.tscn") as PackedScene).instantiate()
	if "decimate" in OS.get_cmdline_user_args():
		_pilot.body_glb = load("res://assets/pilot9_decimate.glb")
	root.add_child(_pilot)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var h: Node = _pilot.hat_holder
	var skel := _pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	var to_hat: Transform3D = h.hat.transform.affine_inverse()
	for c in skel.get_children():
		var m := c as MeshInstance3D
		if m == null or m.skin == null:
			continue
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / verts.size()
			var hi := -INF
			var best := 0.0
			for i in verts.size():
				for j in per:
					var bi := bones[i * per + j]
					if m.skin.get_bind_name(bi) == &"Head" or m.skin.get_bind_bone(bi) == skel.find_bone("Head"):
						best = maxf(best, weights[i * per + j])
						if weights[i * per + j] > 0.0:
							hi = maxf(hi, (to_hat * (m.skin.get_bind_pose(bi) * verts[i])).y)
			if best > 0.0:
				print(m.name, " surf ", s, ": max head weight ", best, " highest head-touched vert (hat y) ", hi)
	for mi: MeshInstance3D in h.hatted:
		var a: Mesh = h.hatted[mi][0]
		var b: Mesh = h.hatted[mi][1]
		for s in a.get_surface_count():
			var ia: int = (a.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var ib: int = (b.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			print(mi.name, " surf ", s, ": ", ia, " -> ", ib, " tris, mat ", a.surface_get_material(s))
	return true
