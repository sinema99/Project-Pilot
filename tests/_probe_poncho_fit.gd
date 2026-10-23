extends SceneTree

## Measures pilot9's torso in skeleton space, CPU-skinned through the bind poses (his REST pose is
## not his BIND pose), so the poncho's rest shell can be fitted to the body. Prints key bone
## positions, each mesh's skinned bounds, and the torso's radius per height slice and angle.
##   godot --headless --path . --script tests/_probe_poncho_fit.gd

const ARM_BONES := ["LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm",
	"RightHand", "Head", "mixamorig_HeadTop_End", "Neck"]
const SECTORS := 16

var _frames := 0
var raw := OS.get_cmdline_user_args().has("raw")
var _pilot: Node

func _initialize() -> void:
	_pilot = (load("res://scenes/pilot9.tscn") as PackedScene).instantiate()
	root.add_child(_pilot)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	var skel := _pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	for b in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder",
			"LeftUpperArm", "RightShoulder", "RightUpperArm"]:
		var i := skel.find_bone(b)
		var g := skel.get_bone_global_pose(i)
		print("%-14s pos %s  y-axis %s" % [b, g.origin, g.basis.y.normalized()])
	var arm_ids := {}
	for b in ARM_BONES:
		arm_ids[skel.find_bone(b)] = true
	var torso: Array[Vector3] = []
	for child in skel.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(verts.size(), 1)
			var slot := mi.mesh.surface_get_material(s).resource_name if mi.mesh.surface_get_material(s) else "?"
			for v in verts.size():
				var p := Vector3.ZERO
				var arm_w := 0.0
				for k in per:
					var w := weights[v * per + k]
					if w <= 0.0:
						continue
					var bind := bones[v * per + k]
					var bone := mi.skin.get_bind_bone(bind)
					if bone < 0:
						bone = skel.find_bone(mi.skin.get_bind_name(bind))
					p += w * (verts[v] if raw else skel.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind) * verts[v])
					if arm_ids.has(bone):
						arm_w += w
				lo = lo.min(p)
				hi = hi.max(p)
				if arm_w < 0.5:
					torso.append(p)
			print("%-12s surf %d slot %-10s verts %5d" % [mi.name, s, slot, verts.size()])
		print("   %s bounds %s .. %s" % [mi.name, lo, hi])
		for bind in mi.skin.get_bind_count():
			var bb := mi.skin.get_bind_bone(bind)
			if bb < 0:
				bb = skel.find_bone(mi.skin.get_bind_name(bind))
			if skel.get_bone_name(bb) in ["UpperChest", "Chest", "Spine"]:
				print("      bind %s: %s" % [skel.get_bone_name(bb), mi.skin.get_bind_pose(bind)])
	# Radius per slice (5 cm) and sector, around x = 0, z = 0.
	# Per slice: front (max z), back (min z), right (min x), left (max x) of the torso.
	for yi in range(20, 34):
		var y0 := yi * 0.05
		var lo := Vector3(INF, 0, INF)
		var hi := Vector3(-INF, 0, -INF)
		for p in torso:
			if p.y >= y0 and p.y < y0 + 0.05:
				lo = lo.min(p)
				hi = hi.max(p)
		print("y %.2f  x %.3f..%.3f  z %.3f..%.3f" % [y0, lo.x, hi.x, lo.z, hi.z])
	for yi in range(20, 34):
		var y0 := yi * 0.05
		var r := PackedFloat32Array()
		r.resize(SECTORS)
		for p in torso:
			if p.y < y0 or p.y >= y0 + 0.05:
				continue
			var a := atan2(p.x, p.z)
			var sec := int(floor((a + PI) / TAU * SECTORS)) % SECTORS
			r[sec] = maxf(r[sec], Vector2(p.x, p.z).length())
		var line := "y %.2f:" % y0
		for sec in SECTORS:
			line += " %4.2f" % r[sec]
		print(line)
	print("sectors start at angle -180 (behind, -Z) and go via -X (his right) ... ; +Z is front")
	quit()
	return true
