extends SceneTree
# Throwaway probe, HEADLESS: real physics in trial. Pilot9 walks up, RIDE, full throttle 3.5 s,
# hard right 1 s, brake, hold F to get off, then one off a ledge check (hover height in the air).
#   godot --headless --path . --script tests/_probe_speeder_drive.gd
var _f := 0
var _bike: Node
var _pilot: Node
var _t := 0.0
var _phase := ""
var _log_at := 0.0
func _initialize() -> void:
	change_scene_to_file("res://scenes/trial.tscn")
func _physics_process(delta: float) -> bool:
	_f += 1
	if _bike == null:
		if current_scene == null or _f < 60:
			return false
		_bike = current_scene.get_node("Speeder1")
		_pilot = current_scene.get_node("Pilot9")
		print("parked y=%.3f (hover target %.2f) boxes=%s stash=%d items" % [_bike.global_position.y, _bike.hover_height, _bike.boxes.visible, _bike.stash.items.size()])
		_pilot.global_position = _bike.global_position + Vector3(1.2, 0.3, 0)
		_bike.mount(_pilot)
		print("mounted: pilot.riding=", _pilot.riding == _bike, " frozen=", _pilot.frozen, " visible=", _pilot.visible, " phys=", _pilot.is_physics_processing())
		_phase = "throttle"
		_t = 0.0
		return false
	_t += delta
	match _phase:
		"throttle":
			_bike.keys_override = Vector2(0, 1)
			if _t > 3.5:
				_log("after 3.5 s throttle")
				_phase = "turn"; _t = 0.0
		"turn":
			_bike.keys_override = Vector2(1, 1)
			if _t > 1.0:
				_log("after 1 s right turn")
				_phase = "brake"; _t = 0.0
		"brake":
			_bike.keys_override = Vector2(0, -1)
			if absf(_bike.speed) < 0.5 or _t > 3.0:
				_bike.keys_override = Vector2.ZERO
				_log("braked in %.2f s" % _t)
				_phase = "hold"; _t = 0.0
				var ev := InputEventAction.new(); ev.action = &"interact"; ev.pressed = true
				Input.parse_input_event(ev)
				Input.action_press(&"interact")
		"hold":
			var off: bool = _bike.pilot == null
			if off or _t > 2.0:
				Input.action_release(&"interact")
				print("got off=", off, " after %.2f s; pilot riding=%s phys=%s cam_is_pilot=%s" % [_t, _pilot.riding, _pilot.is_physics_processing(), root.get_viewport().get_camera_3d() == _pilot.camera_3d or _bike._handover_to == _pilot.camera_3d])
				print("pilot at ", _pilot.global_position.snappedf(0.01), " bike at ", _bike.global_position.snappedf(0.01))
				_phase = "fall"; _t = 0.0
				_bike.global_position = Vector3(0, 30, 0)
				_bike.vertical_speed = 0.0
		"fall":
			if _t > 0.3 and _log_at == 0.0:
				_log_at = 1.0
				print("in the air: grounded=%s vy=%.2f" % [_bike.grounded, _bike.vertical_speed])
			if _bike.grounded and _t > 0.5:
				print("landed after %.2f s" % _t)
				_phase = "kill"; _t = 0.0
				_bike.global_position = Vector3(5000, -60, 5000)
		"kill":
			if _t > 0.2:
				print("respawned to ", _bike.global_position.snappedf(0.01))
				quit(0)
	return false
func _log(what: String) -> void:
	var ray := PhysicsRayQueryParameters3D.create(_bike.global_position + Vector3.UP, _bike.global_position + Vector3.DOWN * 5)
	ray.exclude = [_bike.get_rid()]
	var hit: Dictionary = _bike.get_world_3d().direct_space_state.intersect_ray(ray)
	var h: float = _bike.global_position.y - (hit.position.y if not hit.is_empty() else NAN)
	print("%s: speed=%.2f yaw=%.1f deg grounded=%s height-above-ground=%.3f pos=%s pilot_hips_near_seat=%s" % [what, _bike.speed, rad_to_deg(_bike.rotation.y), _bike.grounded, h, _bike.global_position.snappedf(0.1), _pilot.global_position.distance_to(_bike.global_position) < 2.0])
