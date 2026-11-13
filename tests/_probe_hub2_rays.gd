extends SceneTree

# Throwaway probe (headless ok): straight-down rays on hub2's map, prints the surface heights.
#   godot --headless --path . --script tests/_probe_hub2_rays.gd -- x z [x z ...]

var _frames := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/hub2.tscn")

func _process(_d: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 10:
		return false
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i + 1 < a.size():
		var x := float(a[i]); var z := float(a[i + 1])
		var hits := []
		for mi in current_scene.get_node("Map").find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var inv := m.global_transform.affine_inverse()
			var tm := m.mesh.generate_triangle_mesh()
			# collect every crossing by marching the ray down repeatedly
			var from := Vector3(x, 1000, z)
			for k in 8:
				var r := tm.intersect_ray(inv * from, (inv.basis * Vector3.DOWN).normalized())
				if r.is_empty():
					break
				var w: Vector3 = m.global_transform * (r["position"] as Vector3)
				hits.append(snappedf(w.y, 0.1))
				from = w + Vector3.DOWN * 0.05
		print("RAY ", x, " ", z, " -> ", hits)
		i += 2
	return true
