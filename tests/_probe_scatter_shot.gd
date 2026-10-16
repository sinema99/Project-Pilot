extends SceneTree

# Throwaway probe, WINDOWED: a blue-grey pipe (cylinder) and a wall lit by a shadowed
# directional light, shot with the cel scatter off, at its shipped strength and exaggerated, so
# the chipped band edges can be compared against the reference. Drives the shader globals
# directly; writes nothing to settings.cfg. See docs/specs/cel-scatter.md. Run:
#   godot --path . --script tests/_probe_scatter_shot.gd -- <out_dir> [reach] [world_size]

# name, scatter_strength, reach multiplier
const SHOTS := [
	["off", 0.0, 1.0],
	["on", 1.0, 1.0],
	["loud", 1.0, 3.0],
]

var _frames := 0
var _out := ""
var _i := 0
var _base_reach := 0.12

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_base_reach = ProjectSettings.get_setting("shader_globals/scatter_reach", {}).get("value", 0.12)
	if args.size() > 1:
		_base_reach = args[1].to_float()
	if args.size() > 2:
		RenderingServer.global_shader_parameter_set(&"scatter_world_size", args[2].to_float())
	var mat := load("res://resources/cel_ground.tres").duplicate() as ShaderMaterial
	mat.set_shader_parameter(&"color", Color(0.45, 0.52, 0.62))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.04, 0.06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.environment.ambient_light_energy = 0.1
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.rotation_degrees = Vector3(-14, 55, 0)
	root.add_child(sun)
	var pipe := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 0.7
	cyl.height = 4.0
	pipe.mesh = cyl
	pipe.material_override = mat
	pipe.position = Vector3(0, 2, 0)
	root.add_child(pipe)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(10, 0.2, 10)
	floor_mesh.mesh = plane
	floor_mesh.material_override = mat
	floor_mesh.position = Vector3(0, -0.1, 0)
	root.add_child(floor_mesh)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(-1.5, 1.4, 3.0), Vector3(0, 1.2, 0))
	cam.fov = 55.0
	cam.make_current()

func _process(_delta: float) -> bool:
	_frames += 1
	var step := _frames % 10
	if step == 1 and _i < SHOTS.size():
		RenderingServer.global_shader_parameter_set(&"scatter_strength", SHOTS[_i][1])
		RenderingServer.global_shader_parameter_set(&"scatter_reach", _base_reach * SHOTS[_i][2])
	if step == 8 and _i < SHOTS.size() and _frames > 20:
		var img := root.get_texture().get_image()
		var path := "%s/scatter_%s.png" % [_out, SHOTS[_i][0]]
		print("saved ", path, " ", img.save_png(path))
		_i += 1
	return _i >= SHOTS.size()
