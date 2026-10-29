extends SceneTree

# Throwaway probe, headless: every head piece the hat cut sees - triangles, hat-space height range
# and x/z extent - for a given fit.
#   godot --headless --path . --script tests/_probe_hat_pieces.gd -- [y z tilt scale] [decimate]

const HOLDER := preload("res://scripts/items/hat_holder.gd")

var _pilot: Node
var _frames := 0
var _args: PackedStringArray

func _initialize() -> void:
	_args = OS.get_cmdline_user_args()
	_pilot = (load("res://scenes/pilot9.tscn") as PackedScene).instantiate()
	if "decimate" in _args:
		_pilot.body_glb = load("res://assets/pilot9_decimate.glb")
	root.add_child(_pilot)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	if _args.size() >= 4 and _args[0] != "decimate":
		_pilot.hat_offset = Vector3(0.0, float(_args[0]), float(_args[1]))
		_pilot.hat_tilt = float(_args[2])
		_pilot.hat_scale = float(_args[3])
	var h: Node = _pilot.hat_holder
	var skel := _pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	var head := skel.find_bone("Head")
	var to_hat: Transform3D = h.hat.transform.affine_inverse()
	for c in skel.get_children():
		var m := c as MeshInstance3D
		if m == null or m.skin == null:
			continue
		var binds := {}
		for b in m.skin.get_bind_count():
			if m.skin.get_bind_bone(b) == head or m.skin.get_bind_name(b) == &"Head":
				binds[b] = m.skin.get_bind_pose(b)
		if binds.is_empty():
			continue
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var index = arr[Mesh.ARRAY_INDEX]
			if index == null:
				index = PackedInt32Array(range(verts.size()))
			var per := bones.size() / verts.size()
			var hp := {}
			for i in verts.size():
				for j in per:
					if binds.has(bones[i * per + j]) and weights[i * per + j] > 0.5:
						hp[i] = to_hat * ((binds[bones[i * per + j]] as Transform3D) * verts[i])
			var island: PackedInt32Array = HOLDER._islands(verts, index)
			var pieces := {}
			for t in (index as PackedInt32Array).size() / 3:
				var a: int = index[t * 3]
				if not hp.has(a):
					continue
				var id := island[a]
				if not pieces.has(id):
					pieces[id] = {"n": 0, "lo": Vector3.INF, "hi": -Vector3.INF}
				var p: Dictionary = pieces[id]
				p["n"] += 1
				for k in 3:
					var v: int = index[t * 3 + k]
					if hp.has(v):
						p["lo"] = (p["lo"] as Vector3).min(hp[v])
						p["hi"] = (p["hi"] as Vector3).max(hp[v])
			for id in pieces:
				var p: Dictionary = pieces[id]
				print("%s s%d piece %d: %d tris  lo %s  hi %s" % [m.name, s, id, p["n"], p["lo"], p["hi"]])
	return true
