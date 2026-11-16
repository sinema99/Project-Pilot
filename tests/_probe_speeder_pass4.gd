extends SceneTree
# Throwaway probe, HEADLESS: real physics on the pass-4 course (Speeder2). Slide, boost, jump, ramp
# launch, wall scrape and head-on bounce, printed as numbers.
#   godot --headless --path . --script tests/_probe_speeder_pass4.gd
var _f := 0
var _bike: Node
var _pilot: Node
var _step := -1
var _t := 0.0
var _max_y := -INF
var _max_speed := 0.0
var _max_lat := 0.0
var _air := false
var _air_t := 0.0
var _course: Node3D

# name, seconds, steer, throttle, boost, setup
func _steps() -> Array:
	return [
		["throttle", 3.2, 0.0, 1.0, false, ""],
		["turn_right_full_speed", 1.2, 1.0, 1.0, false, ""],
		["release_steer", 1.2, 0.0, 1.0, false, ""],
		["boost", 3.2, 0.0, 1.0, true, "reset_straight"],
		["boost_release_decay", 3.0, 0.0, 1.0, false, ""],
		["jump", 1.2, 0.0, 0.0, false, "jump_slow"],
		["ramp_B_launch", 5.0, 0.0, 1.0, false, "to_ramp_b"],
		["ramp_A_boost", 5.0, 0.0, 1.0, true, "to_ramp_a"],
		["hill", 6.0, 0.0, 1.0, false, "to_hill"],
		["scrape_corridor_glance", 3.0, 0.0, 1.0, false, "to_scrape"],
		["head_on_wall", 4.0, 0.0, 1.0, false, "to_headon"],
		["reverse_steer", 1.0, 1.0, -1.0, false, ""],
	]

func _initialize() -> void:
	change_scene_to_file("res://scenes/trial.tscn")

func _physics_process(delta: float) -> bool:
	_f += 1
	if _bike == null:
		if current_scene == null or _f < 90:
			return false
		_course = current_scene.get_node("SpeederCourse")
		_bike = _course.get_node("Speeder2")
		_bike.global_position = _course.global_position + Vector3(0, 0.45, -35)
		_bike.reset_physics_interpolation()
		_pilot = current_scene.get_node("Pilot9")
		print("course bike at ", _bike.global_position, " grounded=", _bike.grounded)
		_pilot.global_position = _bike.global_position + Vector3(1.8, 0.3, -0.8)
		_bike.mount(_pilot)
		_bike.mount_left = 0.0
		_next()
		return false
	_t += delta
	var s: Array = _steps()[_step]
	_bike.keys_override = Vector2(s[2], s[3])
	_bike.boost_override = s[4]
	_max_y = maxf(_max_y, _bike.global_position.y)
	_max_speed = maxf(_max_speed, _bike.speed)
	_max_lat = maxf(_max_lat, absf(_bike.lateral))
	if not _bike.grounded and not _air:
		_air = true
		_air_t = 0.0
	if _air:
		_air_t += delta
		if _bike.grounded:
			_air = false
			print("    air time %.2f s, apex y %.2f" % [_air_t, _max_y])
	if int(_t / 0.4) != int((_t - delta) / 0.4):
		print("    t=%.1f speed=%.1f lat=%.1f yaw=%.0f vy=%.1f y=%.2f pos=(%.0f,%.0f) boost=%.2f g=%s" % [_t, _bike.speed, _bike.lateral, rad_to_deg(_bike.rotation.y), _bike.vertical_speed, _bike.global_position.y, _bike.global_position.x - _course.global_position.x, _bike.global_position.z - _course.global_position.z, _bike.boost_meter, _bike.grounded])
	if _t >= s[1]:
		print("== %s done: speed=%.1f max_speed=%.1f max|lat|=%.1f max_y=%.2f crashes=%s" % [s[0], _bike.speed, _max_speed, _max_lat, _max_y, _bike._crash_log])
		_next()
	return false

func _next() -> void:
	_step += 1
	if _step >= _steps().size():
		quit(0)
		return
	var s: Array = _steps()[_step]
	_t = 0.0
	_max_y = -INF
	_max_speed = 0.0
	_max_lat = 0.0
	_bike._crash_log.clear()
	print("-- %s" % s[0])
	match s[5]:
		"reset_straight":
			_place(Vector3(0, 0.45, 0), 0.0)
		"jump_slow":
			_place(Vector3(0, 0.45, 20), 0.0)
			_bike.jump_override = true
		"to_ramp_b":
			_place(Vector3(14, 0.45, 20), 0.0)
		"to_ramp_a":
			_place(Vector3(-14, 0.45, 10), 0.0)
		"to_hill":
			_place(Vector3(0, 0.45, 60), 0.0)
		"to_scrape":
			_place(Vector3(10, 0.45, 270), 8.0)
		"to_headon":
			_place(Vector3(0, 0.45, 280), 0.0)
	_bike.boost_meter = 1.0
	_bike._boost_empty = false

func _place(local: Vector3, yaw_deg: float) -> void:
	_bike.global_position = _course.global_position + local
	_bike.rotation.y = deg_to_rad(yaw_deg)
	_bike.speed = 0.0
	_bike.velocity = Vector3.ZERO
	_bike.vertical_speed = 0.0
	_bike.reset_physics_interpolation()
