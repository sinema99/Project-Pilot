extends SceneTree

# Throwaway probe, WINDOWED: pilot9 with the backpack on and the coat off (the fit is made on his
# bare back), held in a clip pose in trial.tscn, shot from four sides into one sheet per pose.
#   godot --path . --script tests/_probe_backpack_shot.gd -- <out_dir> [coat] [pose ...]
# "coat" as the second arg leaves the coat on. Poses default to idle + run.

const POSES := {
	"idle": ["idle", 0.0],
	"run": ["run_forward", 0.2],
	"sprint": ["sprint_forward", 0.3],
	"jump": ["jump", 0.2],
}
# [yaw off his facing (deg, 0 = in front of him), distance, camera height, look-at height]
const VIEWS := [[180.0, 2.6, 1.4, 1.25], [135.0, 2.6, 1.9, 1.25], [90.0, 2.6, 1.3, 1.25], [25.0, 2.6, 1.5, 1.25]]
const CROP := Vector2i(600, 820)
const SETTLE := 60

var _out := ""
var _coat := false
var _names: Array = []
var _pilot: Node
var _cam: Camera3D
var _frames := 0
var _pose := -1
var _sheet: Image


func _initialize() -> void:
	# Never write the user's real loadout.
	var inv := root.get_node_or_null(^"/root/Inventory")
	if inv != null:
		inv.persist = false
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_coat = args.size() > 1 and args[1] == "coat"
	_names = Array(args.slice(2)) if args.size() > 2 else ["idle", "run"]
	change_scene_to_file("res://scenes/trial.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _pilot == null:
		if current_scene == null or _frames < 120:
			return _frames > 900
		var all: Array[Node] = []
		_find(current_scene, all)
		_pilot = all[0]
		_pilot.frozen = true
		_pilot.anim_tree.active = false
		_cam = Camera3D.new()
		_cam.fov = 40.0
		current_scene.add_child(_cam)
		_cam.current = true
		_frames = 0
		_next_pose()
		return false
	if _pose >= _names.size():
		return true
	_pilot.backpack.set_on(true)
	_pilot.coat.set_on(_coat)
	var local := _frames % (SETTLE + VIEWS.size() * 4)
	_hold_clip()
	if local >= SETTLE:
		var v := (local - SETTLE) / 4
		if (local - SETTLE) % 4 == 0:
			_aim(v)
		elif (local - SETTLE) % 4 == 3:
			_grab(v)
			if v == VIEWS.size() - 1:
				var path := "%s/backpack_%s%s.png" % [_out, _names[_pose], "_coat" if _coat else ""]
				print("saved ", path, " ", _sheet.save_png(path))
				_next_pose()
	return false


func _next_pose() -> void:
	_pose += 1
	_frames = 0
	_sheet = Image.create(CROP.x * VIEWS.size(), CROP.y, false, Image.FORMAT_RGBA8)


func _hold_clip() -> void:
	if _pose >= _names.size():
		return
	var p: Array = POSES[_names[_pose]]
	var player: AnimationPlayer = _pilot.anim_player
	if player.has_animation(p[0]):
		player.play(p[0])
		player.seek(float(p[1]), true)
		player.pause()


func _aim(v: int) -> void:
	var view: Array = VIEWS[v]
	var p: Vector3 = _pilot.global_position
	var f: Vector3 = _pilot._facing().rotated(Vector3.UP, deg_to_rad(view[0]))
	_cam.global_position = p + f * float(view[1]) + Vector3.UP * float(view[2])
	_cam.look_at(p + Vector3.UP * float(view[3]), Vector3.UP)
	_cam.reset_physics_interpolation()


func _grab(v: int) -> void:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var size := img.get_size()
	var at := Vector2i((size.x - CROP.x) / 2, maxi((size.y - CROP.y) / 2, 0))
	_sheet.blit_rect(img, Rect2i(at, Vector2i(CROP.x, mini(CROP.y, size.y))), Vector2i(CROP.x * v, 0))


func _find(n: Node, out: Array[Node]) -> void:
	if n.has_method(&"toggle_coat"):
		out.append(n)
	for c in n.get_children():
		_find(c, out)
