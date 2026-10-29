extends SceneTree

# Screenshots of the Internals greybox from fixed viewpoints (docs/specs/internals-map.md), for
# judging light and readability without playing. Needs a window (not --headless):
#
#   godot --path . --script tests/_probe_internals_shots.gd -- <out_dir>

const SCENE := "res://scenes/internals.tscn"
const SHOTS := [
	["fan_hall", Vector3(40, 46.5, 4), Vector3(100, 40, 25)],
	["vent_stack", Vector3(30, 39.5, 28), Vector3(10, 31, 50)],
	["overlook", Vector3(26, 31.7, 77), Vector3(90, 22, 77)],
	["turbines", Vector3(52, 32, 76), Vector3(110, 18, 77)],
	["undercroft", Vector3(72, 11.7, 104), Vector3(72, 20, 60)],
	["pump_gallery", Vector3(122, 19.7, 76), Vector3(140, 12, 98)],
	["vault", Vector3(32, 11.7, 110), Vector3(30, 12, 140)],
	["press_shaft", Vector3(122, 31.7, 33), Vector3(140, 18, 10)],
]

var _scene: Node
var _cam: Camera3D
var _i := -1
var _wait := 0
var _out := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_scene)
	_cam = Camera3D.new()
	_cam.fov = 70
	_cam.far = 400
	root.add_child(_cam)

func _process(_delta: float) -> bool:
	if _i == -1:
		_wait += 1
		if _wait < 40:
			return false
		var hud := _scene.get_node_or_null("MissionHud") as CanvasLayer
		if hud != null:
			hud.visible = false
		_next()
		return false
	_wait += 1
	if _wait < 12:
		return false
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, SHOTS[_i][0]])
	_next()
	return false

func _next() -> void:
	_i += 1
	_wait = 0
	if _i >= SHOTS.size():
		quit(0)
		return
	var s: Array = SHOTS[_i]
	_cam.position = s[1]
	_cam.look_at(s[2])
	_cam.make_current()
