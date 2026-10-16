extends SceneTree

# Throwaway: floor-level view of the pipe hall with one light group switched off per shot.
const HALL := Vector3(-99, 0, 84)
const NAMES := ["warm", "p2", "p2noomni"]
const SPOTS := [Vector2(-20, 10), Vector2(0, 0), Vector2(20, -10), Vector2(-34, 14), Vector2(10, 14), Vector2(28, 8)]
var _cam: Camera3D
var _frames := 0
var _out := ""
var _i := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_user_data_dir()
	change_scene_to_file("res://scenes/trial.tscn")

func _all(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Light3D:
			out.append(c)
		_all(c, out)

func _meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_meshes(c, out)

func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null:
		return _frames > 600
	if _cam == null:
		if _frames < 20:
			return false
		_cam = Camera3D.new()
		_cam.fov = 75.0
		current_scene.add_child(_cam)
		_cam.make_current()
		return false
	var step := _frames % 14
	if step == 1 and _i < NAMES.size():
		var pl := current_scene.get_node("Pilot9") as Node3D
		pl.global_position = HALL + Vector3(SPOTS[1].x, 0.7, SPOTS[1].y)
		if pl is CharacterBody3D: (pl as CharacterBody3D).velocity = Vector3.ZERO
		_cam.global_position = HALL + Vector3(SPOTS[1].x + 3, 2.2, SPOTS[1].y + 4)
		_cam.look_at(HALL + Vector3(SPOTS[1].x, 1.4, SPOTS[1].y), Vector3.UP)
		var lights := []
		_all(current_scene, lights)
		for l: Light3D in lights:
			l.visible = not (_i == 2 and l is OmniLight3D and l.get_parent().name == "Lights")
	if step == 11 and _i < NAMES.size():
		var img := root.get_texture().get_image()
		print("saved ", img.save_png("%s/lt_%s.png" % [_out, NAMES[_i]]))
		_i += 1
	return _i >= NAMES.size()
