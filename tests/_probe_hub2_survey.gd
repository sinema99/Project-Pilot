extends SceneTree

# Throwaway probe, WINDOWED: oblique shots of hub2's map; picks a pixel and prints the world hit.
#   godot --path . --script tests/_probe_hub2_survey.gd -- <out_dir> <cx> <cy> <cz> <dx> <dy> <dz> [px py]

var _frames := 0
var _out := ""
var _cam: Camera3D
var _a: PackedStringArray

func _initialize() -> void:
	_a = OS.get_cmdline_user_args()
	_out = _a[0]
	change_scene_to_file("res://scenes/hub2.tscn")

func _hit(px: float, py: float) -> Variant:
	var o := _cam.project_ray_origin(Vector2(px, py))
	var d := _cam.project_ray_normal(Vector2(px, py))
	var best: Variant = null
	var bd := INF
	for mi in current_scene.get_node("Map").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var tm := m.mesh.generate_triangle_mesh()
		var inv := m.global_transform.affine_inverse()
		var r := tm.intersect_ray(inv * o, (inv.basis * d).normalized())
		if not r.is_empty():
			var w: Vector3 = m.global_transform * (r["position"] as Vector3)
			if o.distance_to(w) < bd:
				bd = o.distance_to(w)
				best = w
	return best

func _process(_d: float) -> bool:
	_frames += 1
	if current_scene == null or (_cam == null and _frames < 60):
		return false
	if _cam == null:
		current_scene.get_node("Pilot9").free()
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
		current_scene.get_node("AirframeLook").set_active(false)
		current_scene.get_node("WorldEnvironment").environment.fog_enabled = false
		_cam.far = 8000.0
		var mk := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 2.0
		sp.height = 4.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0, 0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sp.material = mat
		mk.mesh = sp
		current_scene.add_child(mk)
		mk.global_position = current_scene.get_node("Map/spawn").global_position + Vector3.UP * 2.0
		var c := Vector3(float(_a[1]), float(_a[2]), float(_a[3]))
		_cam.global_position = c + Vector3(float(_a[4]), float(_a[5]), float(_a[6]))
		if _a.size() >= 10:
			_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			_cam.size = float(_a[9])
			_cam.look_at(c, Vector3(0, 0, -1))
		else:
			_cam.look_at(c)
		_frames = 0
		return false
	if _frames == 20:
		if _a.size() >= 9:
			print("HIT ", _hit(float(_a[7]), float(_a[8])))
		var p := "%s/hub2_top.png" % _out
		print("saved ", root.get_texture().get_image().save_png(p))
	return _frames > 25
