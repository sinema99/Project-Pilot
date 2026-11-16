extends SceneTree

# Throwaway probe, headless: prints what the aim placement needs - bone positions in skeleton space,
# the body's axes in skeleton space, the head mesh's extent around the Head bone, each gun's bounds
# in its item frame. Run:
#   godot --headless --path . --script tests/_probe_aim_measure.gd

var _pilot: Node
var _frames := 0
var _slot := 0


func _initialize() -> void:
	root.add_child((load("res://scenes/trial.tscn") as PackedScene).instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		var inv := root.get_node_or_null("/root/Inventory")
		if inv != null:
			inv.persist = false
	if _frames == 20:
		_pilot = get_nodes_in_group(&"reflect_target")[0]
		_pilot.draw_slot(0, true)
	if _frames == 60:
		_bones()
		_item()
		_pilot.draw_slot(1, true)
	if _frames == 100:
		_item()
		quit()
		return true
	return false


func _bones() -> void:
	var holder: Node = _pilot.item_holder
	var skel: Skeleton3D = holder._skeleton
	var names := []
	for i in skel.get_bone_count():
		names.append("%d:%s<%d" % [i, skel.get_bone_name(i), skel.get_bone_parent(i)])
	print("bones: ", " ".join(names))
	var body: Node3D = _pilot.character
	var to_skel := skel.global_transform.basis.orthonormalized().inverse()
	var cb := body.global_basis.orthonormalized()
	print("skel scale ", skel.global_transform.basis.get_scale(), " body x(left?) in skel ", to_skel * cb.x,
		" y ", to_skel * cb.y, " z ", to_skel * cb.z)
	for n in [&"Hips", &"Spine", &"Chest", &"UpperChest", &"Neck", &"Head", &"RightShoulder",
			&"RightUpperArm", &"RightLowerArm", &"RightHand", &"LeftShoulder", &"LeftUpperArm",
			&"LeftLowerArm", &"LeftHand"]:
		var b := skel.find_bone(n)
		if b < 0:
			print(n, " MISSING")
			continue
		var g := skel.get_bone_global_pose(b)
		print(n, " origin ", g.origin, " x ", g.basis.x.normalized(), " y ", g.basis.y.normalized(),
			" z ", g.basis.z.normalized(), " restlen ", skel.get_bone_rest(b).origin.length())
	# Head mesh extent: vertices mostly weighted to Head (and its children), in skeleton space
	# relative to the Head bone origin, at the current pose approximated by the rest bind.
	var head := skel.find_bone(&"Head")
	var head_set := {head: true}
	for i in skel.get_bone_count():
		var p := skel.get_bone_parent(i)
		while p >= 0:
			if p == head:
				head_set[i] = true
				break
			p = skel.get_bone_parent(p)
	print("head children: ", head_set.keys().map(func(i): return skel.get_bone_name(i)))
	for mi: MeshInstance3D in skel.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null:
			continue
		var skin := mi.skin
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var count := 0
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty():
				continue
			var per := bones.size() / verts.size()
			for v in verts.size():
				var w_head := 0.0
				var only_head := 0.0
				for k in per:
					var bind := bones[v * per + k]
					var bn := skin.get_bind_name(bind)
					var bi := skel.find_bone(bn) if bn != &"" else skin.get_bind_bone(bind)
					if head_set.has(bi):
						w_head += wts[v * per + k]
					if bi == head:
						only_head += wts[v * per + k]
				if only_head > 0.5:
					# bind-space vertex -> head-bone-relative, skeleton axes (rest pose)
					var p := verts[v] - skel.get_bone_global_rest(head).origin
					lo = lo.min(p)
					hi = hi.max(p)
					count += 1
		if count > 0:
			print("mesh ", mi.name, " visible ", mi.visible, " head verts ", count, " rel head bone min ", lo, " max ", hi)


func _item() -> void:
	var holder: Node = _pilot.item_holder
	var item: Node3D = holder.item_instance
	var held: HeldItem = holder.held_item
	print("ITEM ", held.resource_path, " hand_offset ", held.hand_offset)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for n in item.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var to_item := item.global_transform.affine_inverse() * mi.global_transform
		var bb := mi.get_aabb()
		var mlo := Vector3(INF, INF, INF)
		var mhi := Vector3(-INF, -INF, -INF)
		for i in 8:
			var corner := to_item * bb.get_endpoint(i)
			mlo = mlo.min(corner)
			mhi = mhi.max(corner)
		print("  part ", mi.name, " min ", mlo, " max ", mhi)
		lo = lo.min(mlo)
		hi = hi.max(mhi)
	print("  bounds min ", lo, " max ", hi)
	# Profile: per 5 cm slice along the barrel, the x and y extent of the vertices in it.
	var slices := {}
	for n in item.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var to_item := item.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var q := to_item * v
				var k := int(floor(q.z / 0.05))
				if not slices.has(k):
					slices[k] = [q.x, q.x, q.y, q.y]
				var e: Array = slices[k]
				slices[k] = [minf(e[0], q.x), maxf(e[1], q.x), minf(e[2], q.y), maxf(e[3], q.y)]
	var keys := slices.keys()
	keys.sort()
	for k in keys:
		var e: Array = slices[k]
		print("  z %.2f  x %.3f..%.3f  y %.3f..%.3f" % [k * 0.05, e[0], e[1], e[2], e[3]])
	var m := item.find_child("Muzzle", true, false)
	if m != null:
		print("  muzzle ", (item.global_transform.affine_inverse() * (m as Node3D).global_transform).origin)
