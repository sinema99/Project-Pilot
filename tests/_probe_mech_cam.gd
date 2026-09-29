extends SceneTree
var scene; var mech; var pilot; var frame := 0
func _initialize():
	scene = load("res://scenes/trial.tscn").instantiate()
	root.add_child(scene)
func _process(_d):
	frame += 1
	if frame == 3:
		mech = scene.get_node("EXIA"); pilot = scene.get_node("Pilot9")
		pilot.global_position = mech.global_position + Vector3(0,0,-4)
	if frame == 10:
		print("in_range=", mech.player_in_range)
		mech.player_in_range = pilot
		mech._enter_mech()
	if frame in [11, 20, 40, 80, 120]:
		var cam = root.get_viewport().get_camera_3d()
		print("f", frame, " cam=", cam.get_path(), " pos=", cam.global_position, " mech=", mech.global_position,
			" pivot=", mech.camera_pivot.global_position, " arm_len=", mech.spring_arm.spring_length, " hit=", mech.spring_arm.get_hit_length(),
			" cam_local=", mech.camera.position, " fov=", cam.fov, " proc=", mech.is_processing(), " handover=", mech._handover_to)
	if frame == 60:
		var ev := InputEventMouseMotion.new(); ev.relative = Vector2(200, 50)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mech._unhandled_input(ev)
		print("yaw after mouse=", mech.camera_yaw, " pitch=", mech.camera_pitch)
	if frame == 130:
		quit()
	return false
