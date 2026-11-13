extends SceneTree

# Throwaway probe, WINDOWED: shots of hub2 as it plays (AIRFRAME look, fog on).
#   godot --path . --script tests/_probe_hub2_wear_shot.gd -- <out_dir> <px py pz tx ty tz [fov]>...
# Positions are WORLD coordinates. Groups of 6 numbers (7 with a fov flag "f<deg>" as the 7th token
# is not supported: use the optional first group token `fov=70`).

var _frames := 0
var _out := ""
var _cam: Camera3D
var _shots: Array = []
var _shot := 0
var _fov := 75.0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0]
	var nums: Array = []
	for i in range(1, a.size()):
		if a[i].begins_with("fov="):
			_fov = float(a[i].substr(4))
		else:
			nums.append(float(a[i]))
	for i in range(0, nums.size() - 5, 6):
		_shots.append([Vector3(nums[i], nums[i + 1], nums[i + 2]), Vector3(nums[i + 3], nums[i + 4], nums[i + 5])])
	change_scene_to_file("res://scenes/hub2.tscn")

func _process(_d: float) -> bool:
	_frames += 1
	if current_scene == null or (_cam == null and _frames < 90):
		return false
	if _cam == null:
		var pilot := current_scene.get_node_or_null("Pilot9")
		if pilot != null:
			pilot.free()
		_cam = Camera3D.new()
		current_scene.add_child(_cam)
		_cam.current = true
		_cam.far = 3000.0
		_cam.fov = _fov
		_aim()
		_frames = 0
		return false
	if _frames == 25:
		var p := "%s/hub2_wear_%d.png" % [_out, _shot]
		root.get_texture().get_image().save_png(p)
		print("saved ", p)
		_shot += 1
		if _shot >= _shots.size():
			quit()
			return true
		_aim()
		_frames = 0
	return false

func _aim() -> void:
	_cam.global_position = _shots[_shot][0]
	_cam.look_at(_shots[_shot][1])
