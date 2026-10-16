extends SceneTree

# Throwaway probe, headless: prints the ship's screen position (ndc -1..1, y up) through its flight
# in the intro space cutscene, to overlay on a sketch of the intended path, plus its camera-space
# position ("L" lines: x right, y up, z back) for a top-view overlay. Run:
#   godot --headless --path . --script tests/_probe_intro_space_path.gd

const ASPECT := 16.0 / 9.0

var _frames := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/cutscene_intro_space.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if current_scene == null or _frames < 3:
		return false
	var ap: AnimationPlayer = current_scene.get_node("AnimationPlayer")
	var cam: Camera3D = current_scene.get_node("CameraRig/Camera3D")
	var ship: Node3D = current_scene.get_node("CameraRig/ShipPath/ShipFollow/Ship")
	var tan_v := tan(deg_to_rad(cam.fov) * 0.5)
	ap.pause()
	var t := 7.0
	while t <= 12.3001:
		ap.seek(t, true)
		var local := cam.global_transform.affine_inverse() * ship.global_position
		print("L %.3f %.2f %.2f %.2f" % [t, local.x, local.y, local.z])
		if local.z < -0.5:
			print("P %.3f %.4f %.4f %.1f" % [t, local.x / -local.z / (tan_v * ASPECT),
					local.y / -local.z / tan_v, -local.z])
		else:
			print("P %.3f behind" % t)
		t += 0.05
	return true
