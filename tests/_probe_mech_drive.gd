extends SceneTree

# Throwaway probe, headless: drives EXIA through real physics with simulated keys - board, step-turn,
# run, sprint, stop, jump, exit, and an exit with the back spot blocked - and prints every state
# change with the speed, height and clip, plus the checks a unit test cannot make (the turn's pivot
# foot staying put, the jump's apex, where the pilot is put down).
#   godot --headless --path . --script tests/_probe_mech_drive.gd

const DT := 1.0 / 60.0

class StubPilot extends Node3D:
	var aboard := false
	var exited_at := Vector3.INF
	var exited_yaw := 0.0
	func enter_vehicle(_v: Node) -> void:
		aboard = true
	func exit_vehicle(pos: Vector3, yaw: float) -> void:
		aboard = false
		exited_at = pos
		exited_yaw = yaw
		global_position = pos

var exia: CharacterBody3D
var pilot: StubPilot
var blocker: StaticBody3D
var t := 0.0
var step := 0
var last_loco := -1
var peak := -INF
var pivot_side := ""
var pivot_start := Vector3.ZERO
var pivot_drift := 0.0
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

func _tap(action: String) -> void:
	Input.action_press(action)

func _release(action: String) -> void:
	Input.action_release(action)

func _log(msg: String) -> void:
	print("%6.2f  %s" % [t, msg])

func _physics_process(_delta: float) -> bool:
	t += DT
	step += 1
	_script()
	if exia.pilot != null and exia.loco != last_loco:
		var h := Vector2(exia.velocity.x, exia.velocity.z).length()
		_log("%-6s clip=%-17s h=%5.2f y=%5.2f yaw=%6.1f" % [Mech_loco_name(exia.loco),
			exia.anim_player.current_animation, h, exia.global_position.y, rad_to_deg(exia.rotation.y)])
		last_loco = exia.loco
	if exia.loco == exia.Loco.AIR:
		peak = maxf(peak, exia.global_position.y)
	_watch_pivot()
	return t > 30.0

func Mech_loco_name(l: int) -> String:
	return ["STAND", "TURN", "RUN", "STOP", "CROUCH", "AIR", "LAND"][l]

func _watch_pivot() -> void:
	if exia.loco != exia.Loco.TURN or exia.anim_player.current_animation != "MECH_turn_step":
		pivot_side = ""
		return
	var u: float = exia.anim_player.current_animation_position / 1.0
	var side: String = ".L" if fposmod(u, 1.0) < 0.5 else ".R"
	# Only the middle of each half: the pivot hands over at the edges.
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

func _speed() -> float:
	return Vector2(exia.velocity.x, exia.velocity.z).length()

func _script() -> void:
	match step:
		10:
			exia.player_in_range = pilot
			exia._enter_mech()
			_log("boarded (stub pilot aboard: %s)" % pilot.aboard)
		160:
			_log("S held - straight back, so it should step round first")
			_key(KEY_S, true)
		340:
			_log("speed after 3 s of W: %.2f (want 9)" % _speed())
			notes.append("run speed %.2f" % _speed())
			notes.append("turn pivot drift %.3f m" % pivot_drift)
			_tap("sprint")
		341:
			_release("sprint")
		400:
			notes.append("sprint speed after 1 s %.2f" % _speed())
			_log("sprinting: %.2f (want 14)" % _speed())
			_key(KEY_S, false)
			_log("let go")
		470:
			_log("after the stop: %.2f m/s, clip %s" % [_speed(), exia.anim_player.current_animation])
			notes.append("stopped speed %.2f" % _speed())
		480:
			_key(KEY_S, true)
		540:
			peak = -INF
			_tap("jump")
			_log("jump at %.2f m/s" % _speed())
		541:
			_release("jump")
		660:
			notes.append("jump apex %.2f m" % peak)
			_log("apex was %.2f" % peak)
		700:
			_key(KEY_S, false)
		800:
			_log("F at %.2f m/s" % _speed())
			exia._request_exit()
			var off: Vector3 = pilot.global_position - exia.global_position
			notes.append("exit 1: pilot out %s, offset in mech space %s" % [not pilot.aboard,
				exia.global_transform.basis.inverse() * off])
		830:
			exia.player_in_range = pilot
			exia._enter_mech()
			_key(KEY_W, true)
		960:
			_tap("sprint")
		961:
			_release("sprint")
		1050:
			_log("F while sprinting at %.2f" % _speed())
			exia._request_exit()
			notes.append("F at a sprint: pending %s, still aboard %s" % [exia.exit_pending, pilot.aboard])
		1051, 1055, 1060, 1065, 1070, 1080:
			_log("pending=%s aboard=%s speed=%.2f" % [exia.exit_pending, pilot.aboard, _speed()])
		1100:
			_key(KEY_W, false)
			notes.append("exit 2 (after braking): pilot out %s" % (not pilot.aboard))
		1200:
			# A wall right behind the mech: the pilot should come out at the side.
			blocker = StaticBody3D.new()
			var s := CollisionShape3D.new()
			var b := BoxShape3D.new()
			b.size = Vector3(3.0, 4.0, 3.0)
			s.shape = b
			blocker.add_child(s)
			root.add_child(blocker)
			blocker.global_position = exia.exit_point.global_position + Vector3(0.0, 2.0, 0.0)
			exia.player_in_range = pilot
			exia._enter_mech()
		1300:
			exia._request_exit()
			var off: Vector3 = exia.global_transform.basis.inverse() * (pilot.global_position - exia.global_position)
			notes.append("exit 3 (back blocked): offset in mech space %s, yaw to mech %.1f" % [off,
				rad_to_deg(wrapf(pilot.exited_yaw - atan2(exia.global_position.x - pilot.global_position.x,
				exia.global_position.z - pilot.global_position.z), -PI, PI))])
		1400:
			print("")
			for n in notes:
				print("NOTE ", n)
			quit()
