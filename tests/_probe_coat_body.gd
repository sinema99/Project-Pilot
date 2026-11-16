extends SceneTree

# Throwaway probe, headless: measures pilot9's body as it stands in the skeleton's REST pose (his
# rest is not his bind pose), for fitting the trench coat. Prints bone rest origins and the body's
# cross-sections by height, per region. Run:
#   godot --headless --path . --script tests/_probe_coat_body.gd [-- decimate]

const BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]

func _initialize() -> void:
	var decimate := OS.get_cmdline_user_args().has("decimate")
	var pilot := (load("res://scenes/pilot9.tscn") as PackedScene).instantiate()
	var skel := pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	print("bones: ", skel.get_bone_count())
	for n: String in BONES:
		var b := skel.find_bone(n)
		if b < 0:
			print("  MISSING ", n)
			continue
		var g := skel.get_bone_global_rest(b)
		print("  %-14s %s  x=%s y=%s z=%s" % [n, _v(g.origin), _v(g.basis.x), _v(g.basis.y), _v(g.basis.z)])
	var all := []
	for b in skel.get_bone_count():
		all.append(skel.get_bone_name(b))
	print("all bones: ", all)
	var meshes: Array = []
	if decimate:
		var src := (load("res://assets/pilot9_decimate.glb") as PackedScene).instantiate()
		meshes = src.find_children("*", "MeshInstance3D", true, false)
	else:
		meshes = skel.find_children("*", "MeshInstance3D", true, false)
	# region -> Array of rest-pose points
	var pts := {"torso": [], "armL": [], "armR": [], "legs": [], "head": [], "handL": []}
	for mi: MeshInstance3D in meshes:
		var mesh := mi.mesh as ArrayMesh
		if mesh == null or mi.skin == null:
			print("unskinned mesh ", mi.name)
			continue
		var skin := mi.skin
		var bind_bone := PackedInt32Array()
		for i in skin.get_bind_count():
			var bi := skin.get_bind_bone(i)
			if bi < 0 or skin.get_bind_name(i) != &"":
				bi = skel.find_bone(skin.get_bind_name(i))
			bind_bone.append(bi)
		var count := 0
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		var hist := {}
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(verts.size(), 1)
			count += verts.size()
			for i in verts.size():
				var p := Vector3.ZERO
				var best := -1
				var best_w := 0.0
				for j in per:
					var w := weights[i * per + j]
					if w <= 0.0:
						continue
					var bind := bones[i * per + j]
					var bone := bind_bone[bind]
					p += (skel.get_bone_global_rest(bone) * (skin.get_bind_pose(bind) * verts[i])) * w
					if w > best_w:
						best_w = w
						best = bone
				var bn := skel.get_bone_name(best)
				lo = lo.min(p)
				hi = hi.max(p)
				hist[bn] = hist.get(bn, 0) + 1
				var region := "torso"
				if bn.begins_with("Left") and (bn.contains("Arm") or bn.contains("Shoulder")):
					region = "armL"
				elif bn.begins_with("Right") and (bn.contains("Arm") or bn.contains("Shoulder")):
					region = "armR"
				elif bn.contains("Leg") or bn.contains("Foot") or bn.contains("Toe"):
					region = "legs"
				elif bn == "Head" or bn == "Neck":
					region = "head"
				elif bn.begins_with("Left") or bn.begins_with("Right"):
					region = "handL"
				(pts[region] as Array).append(p)
		print("mesh %-14s verts %d surfaces %d  %s .. %s  %s" % [mi.name, count, mesh.get_surface_count(), _v(lo), _v(hi), hist])
	for region: String in ["torso", "legs", "head"]:
		print("== ", region, " by height: y  x[min,max]  z[min,max]  n")
		_slices(pts[region], 1, 0.05)
	if OS.get_cmdline_user_args().has("profile"):
		# The torso's outline per height band: for each 2.5 cm of |x|, its front and back z.
		print("== torso profile: y | per |x| bin from 0, 0.025 wide: zmin/zmax (cm)")
		var bands := {}
		for v: Vector3 in pts["torso"]:
			var yk := int(floorf(v.y / 0.05))
			var xk := int(floorf(absf(v.x) / 0.025))
			if not bands.has(yk):
				bands[yk] = {}
			var r: Vector2 = bands[yk].get(xk, Vector2(INF, -INF))
			bands[yk][xk] = Vector2(minf(r.x, v.z), maxf(r.y, v.z))
		var yks := bands.keys()
		yks.sort()
		for yk: int in yks:
			var line := "  %4.2f |" % (float(yk) * 0.05)
			for xk in 13:
				if bands[yk].has(xk):
					var r: Vector2 = bands[yk][xk]
					line += " %3d/%-3d" % [roundi(r.x * 100.0), roundi(r.y * 100.0)]
				else:
					line += "    .   "
			print(line)
	print("== armL along x: x  y[min,max]  z[min,max]  n")
	_slices(pts["armL"], 0, 0.05)
	print("== handL bounds")
	_slices(pts["handL"], 0, 0.05)
	quit()

func _slices(p: Array, axis: int, step: float) -> void:
	var bins := {}
	for v: Vector3 in p:
		var k := int(floorf(v[axis] / step))
		if not bins.has(k):
			bins[k] = [Vector3(INF, INF, INF), Vector3(-INF, -INF, -INF), 0]
		bins[k][0] = (bins[k][0] as Vector3).min(v)
		bins[k][1] = (bins[k][1] as Vector3).max(v)
		bins[k][2] += 1
	var keys := bins.keys()
	keys.sort()
	for k: int in keys:
		var lo: Vector3 = bins[k][0]
		var hi: Vector3 = bins[k][1]
		var a := (axis + 1) % 3
		var b := (axis + 2) % 3
		print("  %5.2f  %s[%6.3f,%6.3f]  %s[%6.3f,%6.3f]  %d" % [float(k) * step, "xyz"[a], lo[a], hi[a], "xyz"[b], lo[b], hi[b], bins[k][2]])

func _v(v: Vector3) -> String:
	return "(%6.3f,%6.3f,%6.3f)" % [v.x, v.y, v.z]
