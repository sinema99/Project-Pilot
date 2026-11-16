extends SceneTree

# Throwaway probe, headless: drives EXIA's aim-forward control (docs/specs/exia-aim-control.md)
# through real physics with simulated keys and camera flicks, and prints what a unit test cannot
# make: the standing 180's time and pivot-foot drift on a real floor, the strafe / back speeds with
# the floor under it, the strafe let-go, a jump with the camera swung mid-air.
#   godot --headless --path . --script tests/_probe_mech_aim_drive.gd

const DT := 1.0 / 60.0

class StubPilot extends Node3D:
	var aboard := false
	func enter_vehicle(_v: Node) -> void:
		aboard = true
	func exit_vehicle(pos: Vector3, _yaw: float) -> void:
		aboard = false
		global_position = pos

var exia: CharacterBody3D
var pilot: StubPilot
var t := 0.0
var step := 0
var last_loco := -1
var turn_started := -1.0
var pivot_side := ""
var pivot_start := Vector3.ZERO
var pivot_drift := 0.0
var air_v := Vector3.ZERO
var notes: PackedStringArray = []

func _initialize() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	exia = load("res://scenes/mech.tscn").instantiate()
	root.add_child(exia)
	pilot = StubPilot.new()
	root.add_child(pilot)
	pilot.position = Vector3(0.0, 0.0, -6.0)

func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)

func _log(msg: String) -> void:
	print("%6.2f  %s" % [t, msg])

func _speed() -> float:
	return Vector2(exia.velocity.x, exia.velocity.z).length()

func _physics_process(_delta: float) -> bool:
	t += DT
	step += 1
	_script()
	if exia.pilot != null and exia.loco != last_loco:
		_log("%-6s clip=%-18s h=%5.2f y=%5.2f yaw=%6.1f" % [
			["STAND", "TURN", "RUN", "STOP", "CROUCH", "AIR", "LAND"][exia.loco],
			exia.anim_player.current_animation, _speed(), exia.global_position.y,
			rad_to_deg(exia.rotation.y)])
		if exia.loco == exia.Loco.TURN:
			turn_started = t
		elif last_loco == exia.Loco.TURN and turn_started >= 0.0:
			notes.append("standing 180: %.2f s, pivot drift %.3f m" % [t - turn_started, pivot_drift])
			turn_started = -1.0
		last_loco = exia.loco
	_watch_pivot()
	return t > 30.0

func _watch_pivot() -> void:
	if exia.loco != exia.Loco.TURN or exia.anim_player.current_animation != "MECH_turn_step":
		pivot_side = ""
		return
	var u: float = exia.anim_player.current_animation_position
	var side: String = ".L" if fposmod(u, 1.0) < 0.5 else ".R"
	var mid := fposmod(u, 0.5)
	var ball: Vector3 = exia._ball_world(side)
	if mid < 0.1 or mid > 0.4:
		pivot_side = ""
		return
	if side != pivot_side:
		pivot_side = side
		pivot_start = ball
		return
	pivot_drift = maxf(pivot_drift, Vector2(ball.x - pivot_start.x, ball.z - pivot_start.z).length())

func _script() -> void:
	match step:
		10:
			exia.player_in_range = pilot
			exia._enter_mech()
			_log("boarded")
		120:
			_log("camera flicked half a turn, no keys")
			exia.camera_yaw = exia.yaw_behind(exia.rotation.y + PI)
		300:
			_log("A held")
			_key(KEY_A, true)
		360:
			notes.append("strafe speed after 1 s: %.2f (want 6), clip %s, yaw %.1f" % [_speed(),
				exia.anim_player.current_animation, rad_to_deg(exia.rotation.y)])
			_key(KEY_A, false)
		380:
			notes.append("strafe let go, 0.33 s later: %.2f m/s, loco %d" % [_speed(), exia.loco])
			_key(KEY_S, true)
		440:
			notes.append("back speed after 1 s: %.2f (want 5), clip %s" % [_speed(),
				exia.anim_player.current_animation])
			_key(KEY_A, true)
		500:
			notes.append("S+A after 1 s: %.2f (want 5.5), clip %s" % [_speed(),
				exia.anim_player.current_animation])
			_key(KEY_S, false)
			_key(KEY_A, false)
		560:
			_key(KEY_W, true)
		650:
			_log("W held, camera flicked a quarter turn")
			exia.camera_yaw = exia.yaw_behind(exia.rotation.y + PI * 0.5)
		662:
			var nose: Vector3 = exia.facing_for(exia.rotation.y)
			var v := Vector2(exia.velocity.x, exia.velocity.z).normalized()
			notes.append("running chase: velocity . nose = %.4f" % v.dot(Vector2(nose.x, nose.z)))
		720:
			Input.action_press("jump")
		721:
			Input.action_release("jump")
		745:
			air_v = exia.velocity
			exia.camera_yaw = exia.yaw_behind(exia.rotation.y - PI * 0.5)
			_log("in the air, camera swung")
		775:
			notes.append("air velocity held: %s -> %s" % [Vector2(air_v.x, air_v.z),
				Vector2(exia.velocity.x, exia.velocity.z)])
		800:
			_key(KEY_W, false)
		900:
			print("")
			for n in notes:
				print("NOTE ", n)
			quit()
