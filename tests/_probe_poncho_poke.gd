extends SceneTree

## Finds body geometry poking through pilot9's poncho. In trial.tscn, at idle and through a run, it
## takes the poncho's drawn inner face and his torso (non-arm) vertices into UpperChest's bind frame,
## bins both by angle around him and height, and reports every bin where the body reaches past the
## cloth's inner face.
##   godot --path . --script tests/_probe_poncho_poke.gd

const ARM_BONES := ["LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm",
	"RightHand", "Head", "Neck"]
const ANG := 48
const DY := 0.02

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
	if _frames == 60:
		_measure("idle")
		Input.action_press(&"forward")
	for f in [100, 104, 108, 112, 116]:
		if _frames == f:
			_measure("run %d" % f)
	if _frames == 117:
		Input.action_press(&"sprint")
	for f in [170, 174, 178]:
		if _frames == f:
			_measure("sprint %d" % f)
	return _frames > 180

func _bin(p: Vector3) -> int:
	var a := int(floor((atan2(p.x, p.z) + PI) / TAU * ANG)) % ANG
	var y := int(floor(p.y / DY))
	return y * ANG + a

func _measure(label: String) -> void:
	var skel := _pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	var poncho: Pilot9Poncho = _pilot.poncho
	var uc := skel.find_bone(&"UpperChest")
	var to_frame := (skel.get_bone_global_pose(uc) * poncho._bind(uc)).affine_inverse()
	# Poncho mesh is in skeleton space (it sits under the skeleton at identity).
	var verts: PackedVector3Array = poncho.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var inner_from := Pilot9Poncho.RV * Pilot9Poncho.RING
	var cloth := {}
	for k in Pilot9Poncho.RV * Pilot9Poncho.RING:
		var p := to_frame * verts[inner_from + k]
		var b := _bin(p)
		var r := Vector2(p.x, p.z).length()
		cloth[b] = minf(cloth.get(b, INF), r)
	var arm_ids := {}
	for b in ARM_BONES:
		arm_ids[skel.find_bone(b)] = true
	var worst := {}
	for child in skel.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or mi.skin == null or mi == poncho:
			continue
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(vs.size(), 1)
			var slot := mi.mesh.surface_get_material(s).resource_name if mi.mesh.surface_get_material(s) else "?"
			for v in vs.size():
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
					p += w * (skel.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind) * vs[v])
					if arm_ids.has(bone):
						arm_w += w
				if arm_w >= 0.5:
					continue
				p = to_frame * p
				var b := _bin(p)
				if not cloth.has(b):
					continue
				var depth := Vector2(p.x, p.z).length() - float(cloth[b])
				# Deeper than 5 cm is a leg swinging up in front of the hem, not through the cloth.
				if depth > 0.0 and depth < 0.05 and depth > float(worst.get(b, [0.0])[0]):
					worst[b] = [depth, p, slot]
	var keys := worst.keys()
	keys.sort_custom(func(a, b): return worst[a][0] > worst[b][0])
	print("%s: %d bins poke through" % [label, keys.size()])
	for k in keys.slice(0, 8):
		var w: Array = worst[k]
		var p: Vector3 = w[1]
		print("   %.1f mm  at (%.3f %.3f %.3f) angle %d deg  slot %s" % [w[0] * 1000.0, p.x, p.y, p.z,
			roundi(rad_to_deg(atan2(p.x, p.z))), w[2]])
