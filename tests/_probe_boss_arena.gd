extends SceneTree

# Throwaway probe, WINDOWED: opens the boss arena and saves a few frames: the pilot's own camera at
# the spawn, then a free camera round the cap. Run:
#   godot --path . --script tests/_probe_boss_arena.gd -- <out_dir> [cel|pixel]

var _frames := 0
var _out := ""
var _view := 0
var _wait := 0
var _cam: Camera3D
var _t0 := 0
var _look := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_look = args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1920, 1080)
	_t0 = Time.get_ticks_msec()
	change_scene_to_file("res://Boss_Arena.tscn")


func _arena() -> BossArena:
	return current_scene.get_node(^"BossArena") as BossArena


## Views: [name, eye offset from the cap centre, look-at offset], or the pilot's camera.
func _views(a: BossArena) -> Array:
	var c := a.centre
	var spawn := a.map.get_node(^"spawn") as Node3D
	var s := spawn.global_position
	var f := -spawn.global_basis.z
	return [
		["arena_pilot.png", null, null],
		["arena_spawn_out.png", s + Vector3.UP * 1.7, s + Vector3.UP * 1.7 - f * 100.0],
		["arena_over.png", c + Vector3(0, 120, 330), c],
		["arena_edge_e.png", c + Vector3(140, 1.7, 0), c + Vector3(600, -60, 0)],
		["arena_edge_n.png", c + Vector3(0, 1.7, -140), c + Vector3(0, -60, -600)],
		["arena_edge_w.png", c + Vector3(-140, 1.7, 0), c + Vector3(-600, -40, 0)],
		["arena_centre_spire.png", c + Vector3.UP * 1.7, c + Vector3.UP * 1.7 + f * 100.0],
	]


func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 60:
		return false
	if _frames == 60:
		var a := _arena()
		print("loaded in ~", Time.get_ticks_msec() - _t0, " ms; centre ", a.centre, " wall pts ", a.wall_line.size(),
				" pilot ", a.pilot.global_position)
		if _look != "":
			(a.get_node(^"RetroLook") as PixelLook).apply_look(false)
			(a.get_node(^"PixelLook") as PixelLook).apply_look(_look == "pixel")
	var views := _views(_arena())
	var v: Array = views[_view]
	if _wait == 0 and v[1] != null:
		if _cam == null:
			_cam = Camera3D.new()
			_cam.fov = 60.0
			_cam.far = 4000.0
			current_scene.add_child(_cam)
		_cam.current = true
		_cam.look_at_from_position(v[1], v[2])
	_wait += 1
	if _wait < 15:
		return false
	_wait = 0
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(v[0]))
	print("saved ", v[0])
	_view += 1
	return _view >= views.size()
