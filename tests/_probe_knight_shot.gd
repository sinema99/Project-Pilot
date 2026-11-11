extends SceneTree

# Throwaway probe, WINDOWED: opens the boss arena and saves the knight (docs/specs/knight-boss.md)
# from the front, his left, the back and close on the head, then the same in pilot9's idle (F6).
#   godot --path . --script tests/_probe_knight_shot.gd -- <out_dir> [idle]

var _frames := 0
var _out := ""
var _view := 0
var _wait := 0
var _cam: Camera3D
var _idle := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	_idle = args.size() > 1 and args[1] == "idle"
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1280, 1280)
	change_scene_to_file("res://Boss_Arena.tscn")


func _knight() -> Node3D:
	return current_scene.get_node(^"BossArena/KnightBoss") as Node3D


func _views(k: Node3D) -> Array:
	var o := k.global_position
	var f := k.global_basis.z
	var r := k.global_basis.x
	var mid := o + Vector3.UP * 2.4
	var head := o + Vector3.UP * 3.65
	return [
		["knight_front.png", mid + f * 6.0, mid],
		["knight_left.png", mid + r * 6.0, mid],
		["knight_back.png", mid - f * 6.0, mid],
		["knight_quarter.png", mid + (f + r * 0.8).normalized() * 6.0 + Vector3.UP * 0.6, mid],
		["knight_head.png", head + f * 1.6 + r * 0.4, head],
		# The player's view from the spawn side: low, behind where pilot9 stands (the user's shot).
		["knight_player.png", o + f * 11.0 + r * 1.5 + Vector3.UP * 2.0, mid + Vector3.UP * 0.4],
	]


func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 60:
		return false
	var k := _knight()
	if _frames == 60:
		var pilot := current_scene.get_node(^"BossArena/Pilot9") as Node3D
		pilot.visible = false
		pilot.process_mode = Node.PROCESS_MODE_DISABLED
		if _idle:
			k.set_idle(true)
		print("knight at ", k.global_position, " rig lift ", k.model.position.y)
	var views := _views(k)
	var v: Array = views[_view]
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 45.0
		current_scene.add_child(_cam)
	_cam.current = true
	_cam.look_at_from_position(v[1], v[2])
	_wait += 1
	if _wait < 12:
		return false
	_wait = 0
	var name: String = v[0]
	if _idle:
		name = name.replace(".png", "_idle.png")
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name))
	print("saved ", name)
	_view += 1
	return _view >= views.size()
