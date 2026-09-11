extends SceneTree

# Throwaway measurement pass: prints every MeshInstance3D under pilot9's
# GeneralSkeleton with its bounds in skeleton space and the bone that owns most
# of its weight. Used to write the slot -> baked mesh hide-map by measurement
# rather than by guessing at Blender's export names.
#
#   godot --headless --path . --script tools/measure_pilot9_meshes.gd

const PILOT := "res://scenes/pilot9.tscn"

func _initialize() -> void:
	var packed := load(PILOT) as PackedScene
	if packed == null:
		push_error("could not load %s" % PILOT)
		quit(1)
		return
	var root := packed.instantiate()
	var skel := root.get_node_or_null("character/Armature/GeneralSkeleton") as Skeleton3D
	if skel == null:
		push_error("no GeneralSkeleton")
		quit(1)
		return

	print("bones: %d" % skel.get_bone_count())
	print("")
	print("%-14s %8s %8s %8s   %8s %8s %8s   %s" % ["mesh", "min.y", "max.y", "height", "ctr.x", "ctr.y", "ctr.z", "dominant bones"])
	print("-".repeat(110))

	var rows: Array = []
	for mi: MeshInstance3D in skel.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var aabb := mi.get_aabb()
		var ctr := aabb.get_center()
		rows.append({
			"name": mi.name,
			"aabb": aabb,
			"ctr": ctr,
			"bones": _dominant_bones(mi, skel),
		})

	rows.sort_custom(func(a, b): return a["ctr"].y > b["ctr"].y)
	for r: Dictionary in rows:
		var a: AABB = r["aabb"]
		var c: Vector3 = r["ctr"]
		print("%-14s %8.3f %8.3f %8.3f   %8.3f %8.3f %8.3f   %s" % [
			r["name"], a.position.y, a.position.y + a.size.y, a.size.y,
			c.x, c.y, c.z, ", ".join(r["bones"])])
	quit()

# Sums vertex weight per bone across every surface, and returns the bone names
# holding at least 10% of the total, heaviest first. The blockout is rigidly
# weighted, so most meshes come back with exactly one name.
func _dominant_bones(mi: MeshInstance3D, skel: Skeleton3D) -> Array:
	var totals: Dictionary = {}
	var grand := 0.0
	for s in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(s)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones.is_empty() or weights.is_empty():
			continue
		for i in bones.size():
			var w := weights[i]
			if w <= 0.0:
				continue
			var idx := bones[i]
			totals[idx] = float(totals.get(idx, 0.0)) + w
			grand += w
	if grand <= 0.0:
		return ["<unweighted>"]

	var pairs: Array = []
	for idx: int in totals:
		pairs.append([idx, float(totals[idx]) / grand])
	pairs.sort_custom(func(a, b): return a[1] > b[1])

	var out: Array = []
	for p: Array in pairs:
		if p[1] < 0.10:
			continue
		out.append("%s %d%%" % [_bone_name(mi, skel, p[0]), roundi(p[1] * 100.0)])
	return out

# A mesh's bone indices address its own Skin's bind list, not the skeleton's
# bone order, so the index has to go through the skin to become a name.
func _bone_name(mi: MeshInstance3D, skel: Skeleton3D, bind: int) -> String:
	var skin := mi.skin
	if skin == null or bind >= skin.get_bind_count():
		return "bind%d?" % bind
	var n := skin.get_bind_name(bind)
	if n != &"":
		return String(n)
	var b := skin.get_bind_bone(bind)
	return skel.get_bone_name(b) if b >= 0 else "bind%d?" % bind
