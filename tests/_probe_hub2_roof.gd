extends SceneTree

# Throwaway probe (headless ok): hub2 roof triangles around the planned hangar opening.
var _frames := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/hub2.tscn")
func _process(_d: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 10:
		return false
	for mi in current_scene.get_node("Map").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name == "WearDecals":
			continue
		var xf := m.global_transform
		var f := m.mesh.get_faces()
		print("MESH ", m.name, " tris ", f.size() / 3, " surfaces ", m.mesh.get_surface_count(), " fmt ", m.mesh.surface_get_format(0), " xf ", xf)
		var n_in := 0
		for i in range(0, f.size(), 3):
			var a := xf * f[i]; var b := xf * f[i + 1]; var c := xf * f[i + 2]
			var lo := Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z)))
			var hi := Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z)))
			if hi.y - lo.y > 0.05 or lo.y < 57.5 or lo.y > 58.7:
				continue
			if hi.x < -40 or lo.x > 40 or hi.z < -190 or lo.z > 90:
				continue
			n_in += 1
			var nn := (b - a).cross(c - a).normalized()
			print("  roof tri y%.2f n.y %.2f x %.1f..%.1f z %.1f..%.1f" % [lo.y, nn.y, lo.x, hi.x, lo.z, hi.z])
		print("  roof tris ", n_in)
	return true
