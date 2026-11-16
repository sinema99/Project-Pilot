extends SceneTree

# Top-down / oblique cutaway renders of hub2's map shell (and optionally the dressing) for layout work
# (docs/specs/hub2-final-pass.md). WINDOWED.
#   godot --path . --script tools/render_hub2_plan.gd -- <out_dir> <name> <cx> <cz> <size_m> <cut_y> [floor_y] [dressing 0/1] [yaw pitch]
# Ortho top-down when pitch is omitted: camera at cut_y looking straight down, so everything above
# cut_y is clipped away. Image is 1600 px square; 1 px = size_m / 1600 metres; +x right, +z down.

const WORLD_SCALE := 0.6

var _f := 0
var _a: PackedStringArray
var _cam: Camera3D


func _initialize() -> void:
	_a = OS.get_cmdline_user_args()
	root.size = Vector2i(1600, 1600)
	var w := Node3D.new()
	root.add_child(w)
	var glb: Node3D = (load("res://assets/hub2.glb") as PackedScene).instantiate()
	glb.scale = Vector3.ONE * WORLD_SCALE
	w.add_child(glb)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.72, 0.74)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for m in glb.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = mat
	if _a.size() > 7 and _a[7] == "1":
		var d: Node3D = (load("res://scenes/hub2_dressing.scn") as PackedScene).instantiate()
		w.add_child(d)
		var src := load("res://scenes/hub2_dressing_src.tscn") as PackedScene
		if src != null and _a.size() > 10 and _a[10] == "src":
			d.queue_free()
			w.add_child(src.instantiate())
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.47, 0.55)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_energy = 1.1
	w.add_child(sun)
	var sun2 := DirectionalLight3D.new()
	sun2.rotation_degrees = Vector3(-35, 200, 0)
	sun2.light_energy = 0.4
	w.add_child(sun2)
	_cam = Camera3D.new()
	w.add_child(_cam)
	var cx := float(_a[2])
	var cz := float(_a[3])
	var size := float(_a[4])
	var cut := float(_a[5])
	if _a.size() > 9:
		_cam.fov = 70
		_cam.position = Vector3(cx, cut, cz)
		_cam.rotation_degrees = Vector3(float(_a[9]), float(_a[8]), 0)
		_cam.near = 0.1
		_cam.far = 2000
	else:
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.size = size
		_cam.position = Vector3(cx, cut, cz)
		_cam.rotation_degrees = Vector3(-90, 0, 0)
		_cam.near = 0.05
		var fl := float(_a[6]) if _a.size() > 6 else -400.0
		_cam.far = cut - fl + 0.5
	_cam.current = true


func _process(_d: float) -> bool:
	_f += 1
	if _f == 30:
		root.get_texture().get_image().save_png("%s/%s.png" % [_a[0], _a[1]])
		return true
	return false
