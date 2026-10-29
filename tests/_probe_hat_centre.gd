extends SceneTree

# Throwaway probe, headless: prints the skull's front/back extent in Head-bone space per height
# slice (ears left out: |x| < 0.06), so the hat's z offset can centre the crown on his skull. Run:
#   godot --headless --path . --script tests/_probe_hat_centre.gd

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
	var slices := {}
	for mi in skel.get_children():
		if not mi is MeshInstance3D or mi.mesh == null or mi.skin == null:
			continue
		var skin: Skin = mi.skin
		var bind := -1
		for b in skin.get_bind_count():
			if skin.get_bind_bone(b) == head or skin.get_bind_name(b) == &"Head":
				bind = b
		if bind < 0:
			continue
		var to_bone: Transform3D = skin.get_bind_pose(bind)
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null:
				continue
			var per: int = bones.size() / verts.size()
			for i in verts.size():
				var w := 0.0
				for j in per:
					if int(bones[i * per + j]) == bind:
						w += float(weights[i * per + j])
				if w < 0.5:
					continue
				var p: Vector3 = to_bone * verts[i]
				if absf(p.x) > 0.06:
					continue
				var key := int(floor(p.y / 0.02))
				var r: Array = slices.get(key, [INF, -INF, 0])
				r[0] = minf(r[0], p.z)
				r[1] = maxf(r[1], p.z)
				r[2] += 1
				slices[key] = r
	var keys := slices.keys()
	keys.sort()
	for k in keys:
		var r: Array = slices[k]
		print("y %.2f..%.2f  z %.3f..%.3f  mid %.3f  n %d" % [k * 0.02, k * 0.02 + 0.02, r[0], r[1], (r[0] + r[1]) * 0.5, r[2]])
	print("hat_offset ", _pilot.hat_offset, " tilt ", _pilot.hat_tilt, " scale ", _pilot.hat_scale)
	return true
