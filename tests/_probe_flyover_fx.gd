extends SceneTree

# Throwaway probe, WINDOWED: the flyover at fixed shot times with the engine effects on and off
# (docs/specs/cutscene-flyover.md, "Speed lines + engine heat"), and how many embers it drew. Run:
#   godot --path . --script tests/_probe_flyover_fx.gd -- <out_dir>

const TIMES := [1.5, 3.0]

var _frames := 0
var _out := ""
var _step := 0
var _wait := 0
var _scene: FlyoverShot


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1920, 1080)
	_scene = (load("res://scenes/cutscene_flyover.tscn") as PackedScene).instantiate()
	_scene.autoplay = false
	root.add_child(_scene)
	_scene.set_process(false)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 20:
		return false
	var t: float = TIMES[_step / 2]
	var on := _step % 2 == 0
	_scene.set_process(false)
	# The snow runs on real time; hide it so on/off differ only by the effects.
	for n in _scene.storm.get_children():
		if n is GeometryInstance3D and (n as GeometryInstance3D).material_override != _scene.storm.fog_material:
			n.visible = false
	_scene.embers.visible = on
	for m in _scene._shimmers:
		m.set_shader_parameter(&"strength", _scene.shimmer_strength * (1.0 if on else 0.0))
	_scene.apply(t)
	_wait += 1
	if _wait < 10:
		return false
	_wait = 0
	var name := "fx_%.1f_%s.png" % [t, "on" if on else "off"]
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name))
	print("saved ", name, " embers ", _scene.embers.update_embers(t, _scene.ship_at, _scene.camera.global_position, Vector3.ZERO))
	_step += 1
	return _step >= TIMES.size() * 2
