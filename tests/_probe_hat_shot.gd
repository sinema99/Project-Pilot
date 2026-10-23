extends SceneTree

# Throwaway probe, WINDOWED: puts the cowboy hat on pilot9 in trial.tscn and shoots his head from
# the front, side, back and three-quarter, plus the game camera. Run:
#   godot --path . --script tests/_probe_hat_shot.gd -- <out_dir> [pilot_index]

# [name, yaw from his facing (deg), distance, height above his feet]
const SHOTS := [
	["front_off", 0.0, 1.1, 1.75],
	["front", 0.0, 1.1, 1.75],
	["three_quarter", 40.0, 1.1, 1.85],
	["side", 90.0, 1.1, 1.75],
	["back", 180.0, 1.1, 1.85],
	["above", 30.0, 1.0, 2.4],
]

var _pilot: Node
var _frames := 0
var _out := ""
var _cam: Camera3D
var _i := 0
var _which := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_which = int(args[1]) if args.size() > 1 else 0
	change_scene_to_file("res://scenes/trial.tscn")

func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		if current_scene != null:
			var all: Array[Node] = []
			_find_pilots(current_scene, all)
			_pilot = all[_which] if all.size() > _which else null
		return _frames > 900
	if _frames == 60:
		_shot("game_off.png")
	if _frames == 62:
		_pilot.toggle_hat()
	if _frames == 66:
		_shot("game_on.png")
		_cam = Camera3D.new()
		_cam.fov = 40.0
		current_scene.add_child(_cam)
		_cam.current = true
	if _frames >= 70 and (_frames - 70) % 4 == 0 and _i < SHOTS.size():
		var s: Array = SHOTS[_i]
		if s[0] == "front_off":
			_pilot.hat_holder.set_on(false)
		else:
			_pilot.hat_holder.set_on(true)
		var p: Vector3 = _pilot.global_position
		var f: Vector3 = _pilot._facing().rotated(Vector3.UP, deg_to_rad(s[1]))
		_cam.global_position = p + f * float(s[2]) + Vector3.UP * float(s[3])
		_cam.look_at(p + Vector3.UP * 1.8, Vector3.UP)
	if _frames >= 72 and (_frames - 72) % 4 == 0 and _i < SHOTS.size():
		_shot("%s.png" % SHOTS[_i][0])
		_i += 1
	return _i >= SHOTS.size() or _frames > 3000

func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name))

func _find_pilots(n: Node, out: Array[Node]) -> void:
	if n.has_method(&"toggle_hat"):
		out.append(n)
	for c in n.get_children():
		_find_pilots(c, out)
