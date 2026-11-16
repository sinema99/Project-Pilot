extends SceneTree
# Throwaway probe, WINDOWED: the textured revolver up close, two sides. Run:
#   godot --path . --script tests/_probe_revolver_texture.gd -- <out_dir>
var _f := 0
var _cam: Camera3D
var _gun: Node3D
var _out := ""
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0] if a.size() > 0 else OS.get_user_data_dir()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.45, 0.47)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	root.add_child(env)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-40, 35, 0)
	root.add_child(l)
	_gun = (load("res://scenes/items/revolver.tscn") as PackedScene).instantiate()
	root.add_child(_gun)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.current = true
func _process(_d: float) -> bool:
	_f += 1
	if _f == 5:
		_cam.global_position = Vector3(0.9, 0.35, -0.2)
		_cam.look_at(Vector3(0, 0.0, -0.25))
	if _f == 8:
		root.get_viewport().get_texture().get_image().save_png(_out.path_join("rev_a.png"))
		_cam.global_position = Vector3(-0.9, 0.35, -0.5)
		_cam.look_at(Vector3(0, 0.0, -0.25))
	if _f == 11:
		root.get_viewport().get_texture().get_image().save_png(_out.path_join("rev_b.png"))
		return true
	return false
