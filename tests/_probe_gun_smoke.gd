extends SceneTree

# Throwaway probe, WINDOWED: screenshots the barrel smoke. godot --path . --script tests/_probe_gun_smoke.gd -- <out_dir>

var _fx: Node
var _m: Node3D
var _f := 0
var _out := ""

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0] if a.size() > 0 else OS.get_user_data_dir()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.3, 0.38)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(1.2, 0.6, 1.8)
	cam.look_at_from_position(cam.position, Vector3(0, 0.5, 0))
	_m = Node3D.new()
	root.add_child(_m)
	_m.position = Vector3(0, 0.0, 0)
	_fx = load("res://scripts/items/gun_fx.gd").new()
	root.add_child(_fx)

func _process(_d: float) -> bool:
	_f += 1
	if _f <= 6 or (_f > 20 and _f < 70 and _f % 4 == 0):
		_fx.muzzle_flash(_m, false)
	if _f == 90 or _f == 130:
		root.get_viewport().get_texture().get_image().save_png("%s/smoke_%d.png" % [_out, _f])
	return _f > 170
