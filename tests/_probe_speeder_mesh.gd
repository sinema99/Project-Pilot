extends SceneTree
# Throwaway probe, WINDOWED: the bare speeder1.glb in trial, shot side / top / front / 3-4 with a
# 10 cm grid of marker balls along its centre line. Out: <out_dir>/speeder_mesh.png
var _out := ""
var _f := 0
var _cam: Camera3D
var _bike: Node3D
var _sheet: Image
const VIEWS := [[Vector3(-4.0, 0.3, 0.0), 30.0], [Vector3(-4.0, 0.3, 0.0), 30.0], [Vector3(0.01, 5.0, 0.0), 30.0], [Vector3(-2.0, 0.6, 2.0), 40.0], [Vector3(0.0, 0.6, -4.0), 30.0]]
const CROP := Vector2i(800, 600)
func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	change_scene_to_file("res://scenes/trial.tscn")
func _process(_d: float) -> bool:
	_f += 1
	if _f == 100:
		_bike = Node3D.new()
		current_scene.add_child(_bike)
		_bike.global_position = Vector3(6, 0, -8)
		var m: Node3D = (load("res://assets/speeder1.glb") as PackedScene).instantiate()
		m.rotation.y = PI * 0.5
		_bike.add_child(m)
		# Markers every 0.25 m along z at x=0 (red), at y = 0.6.
		for i in range(-6, 7):
			var mi := MeshInstance3D.new()
			var s := SphereMesh.new(); s.radius = 0.025; s.height = 0.05
			mi.mesh = s
			var mat := StandardMaterial3D.new(); mat.albedo_color = Color(1, 0, 0) if i != 0 else Color(0, 1, 0)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override = mat
			_bike.add_child(mi)
			mi.position = Vector3(0.0, 1.0, i * 0.25)
		for y in range(0, 5):
			var mi := MeshInstance3D.new()
			var s := SphereMesh.new(); s.radius = 0.025; s.height = 0.05
			mi.mesh = s
			var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0, 0.4, 1)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override = mat
			_bike.add_child(mi)
			mi.position = Vector3(0.0, y * 0.25, -1.75)
		_cam = Camera3D.new(); _cam.fov = 30.0
		current_scene.add_child(_cam); _cam.current = true
		_sheet = Image.create(CROP.x * 2, CROP.y * 2, false, Image.FORMAT_RGBA8)
	if _f > 110:
		var k := (_f - 110) / 6
		var sub := (_f - 110) % 6
		if k >= VIEWS.size():
			pass
		if k >= VIEWS.size():
			print("saved ", _sheet.save_png(_out + "/speeder_mesh.png"))
			return true
		if sub == 0:
			var v: Array = VIEWS[k]
			_cam.global_position = _bike.global_position + v[0] + Vector3(0, 0.4, 0)
			_cam.look_at(_bike.global_position + Vector3(0, 0.4, 0), Vector3.UP if k != 2 else Vector3.FORWARD)
			_cam.fov = v[1]
		if sub == 5:
			var img := root.get_texture().get_image(); img.convert(Image.FORMAT_RGBA8)
			var sz := img.get_size()
			_sheet.blit_rect(img, Rect2i((sz - CROP) / 2, CROP), Vector2i(((k + 3) % 2) * CROP.x, ((k + 3) % 4 / 2) * CROP.y))
	return false
