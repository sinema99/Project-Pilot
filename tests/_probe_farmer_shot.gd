extends SceneTree

# Throwaway probe, WINDOWED: the firing-range farmer up close (spheres, windows, charge glow, lean).
#   godot --path . --script tests/_probe_farmer_shot.gd -- <out_dir>

var _range: Node
var _cam: Camera3D
var _frames := 0
var _out := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 30:
		return false
	_range = current_scene.get_node("FiringRange")
	var d = _range.dummy
	if _frames == 30:
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
		d.state = 2
		d.frozen = true
	var c: Vector3 = d.global_position
	if _frames == 40:
		_cam.look_at_from_position(c + Vector3(5.5, 3.2, 6.5), c + Vector3(0, 1.6, 0))
	if _frames == 60:
		_shot("farmer_front.png")
		d._charge = d.charge_time * 0.9
	if _frames == 62:
		_shot("farmer_charge.png")
		d._charge = -1.0
		d.take_hit(50.0, &"reflect_perfect", c)
	if _frames == 64:
		_shot("farmer_hit.png")
	if _frames == 100:
		_cam.look_at_from_position(c + Vector3(-1.0, 6.5, -5.5), c + Vector3(0, 1.4, 0))
		d._velocity = Vector3(4, 0, 0)
		d._lean = d.lean_target(d.global_basis.inverse() * d._velocity, 4.0, deg_to_rad(4.0))
	if _frames == 104:
		_shot("farmer_back_lean.png")
		return true
	if _frames > 100:
		d._velocity = Vector3(4, 0, 0)
	return false

func _shot(name_: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name_))
	print("saved ", name_)
