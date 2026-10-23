extends SceneTree

## Measures pilot9's shoulder caps in PLAY pose (arms down), expressed in the poncho's frame: UpperChest's
## bind space (bind space carried by UpperChest's current pose), so the rest shell's shoulder rows can
## be fitted to the arms he actually has hanging, not the T-pose. Prints, per angle around his left
## shoulder and per x slice, the highest arm surface. Frames 60 (idle) and, with `run`, after running.
##   godot --path . --script tests/_probe_poncho_shoulder.gd [-- run]

const ARM_BONES := ["LeftUpperArm", "LeftLowerArm", "LeftShoulder", "RightUpperArm", "RightLowerArm",
	"RightShoulder"]

var _frames := 0
var _pilot: Node

func _initialize() -> void:
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		if current_scene != null:
			_pilot = current_scene.get_node_or_null(^"Pilot9")
		return _frames > 600
	var run := OS.get_cmdline_user_args().has("run")
	if run and _frames == 20:
		Input.action_press(&"forward")
	if _frames == (110 if run else 60):
		_measure()
		return true
	return false

func _measure() -> void:
	var skel := _pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	var poncho: Pilot9Poncho = _pilot.poncho
	var uc := skel.find_bone(&"UpperChest")
	# bind space -> skeleton space for the poncho frame
	var frame := skel.get_bone_global_pose(uc) * poncho._bind(uc)
	var to_frame := frame.affine_inverse()
	var arm_ids := {}
	for b in ARM_BONES:
		arm_ids[skel.find_bone(b)] = true
	var pts: Array[Vector3] = []
	for child in skel.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or mi.skin == null or mi == poncho:
			continue
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(verts.size(), 1)
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
					p += w * (skel.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind) * verts[v])
					if arm_ids.has(bone):
						arm_w += w
				if arm_w >= 0.5:
					pts.append(to_frame * p)
	for side: float in [1.0, -1.0]:
		print("side %s: x slice -> top y, z range (y > 1.30 only)" % ("left" if side > 0 else "right"))
		for xi in range(14, 46, 2):
			var x0 := xi * 0.01
			var top := -INF
			var zlo := INF
			var zhi := -INF
			var xmax := -INF
			for p in pts:
				var x := p.x * side
				if x >= x0 and x < x0 + 0.02 and p.y > 1.30:
					top = maxf(top, p.y)
					zlo = minf(zlo, p.z)
					zhi = maxf(zhi, p.z)
			print("  x %.2f  top %.3f  z %.3f..%.3f" % [x0, top, zlo, zhi])
		var outer := -INF
		for yi in range(26, 32):
			var y0 := yi * 0.05
			outer = -INF
			for p in pts:
				if p.y >= y0 and p.y < y0 + 0.05:
					outer = maxf(outer, p.x * side)
			print("  y %.2f  outer x %.3f" % [y0, outer])
	var ua := skel.find_bone(&"LeftUpperArm")
	print("left upper arm joint (frame): ", to_frame * skel.get_bone_global_pose(ua).origin,
		"  down axis: ", (to_frame.basis * skel.get_bone_global_pose(ua).basis.y).normalized())
	quit()
