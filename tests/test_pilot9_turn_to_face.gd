extends "res://tests/test_case.gd"

# Covers the facing rule. Since 2026-11-11 (docs/specs/pilot9-strafe-return.md) walk, run,
# sprint and the air are stock Real Controller strafe - camera-back, S backpedals - and only
# the forward-only-clip states (crouch, tredge, vault) turn him toward travel.
# face_travel_direction = true restores the 2026-09-07 turn-to-face everywhere
# (docs/specs/pilot9-turn-to-face.md), and the tests for that mode are kept.
#
# Two things here are worth more than the rest.
#
# The first is that the face-travel target is a GENERALISATION of the stock one: for
# straight-forward input, atan2(direction.x, direction.z) and camera_pivot.rotation.y + PI are
# the same angle. That equality is what says the 180 degree basis baked into the `character`
# node is respected by both, so it is asserted directly, at several camera yaws.
#
# The second is the X sign on the blend position. pilot9's mesh faces its own +Z but his
# local +X points to his LEFT, so travel toward his right is -basis.x. Get that backwards and
# he leans the wrong way through every turn, which on play reads as a bad blend space rather
# than as a wrong sign.
#
# The scene is driven without entering the SceneTree: @onready node references are wired by
# hand in _rig(), and input state is set the way _handle_movement_input would have.

const PILOT_TSCN := "res://scenes/pilot9.tscn"

# 300 steps at the shipping rotation_speed of 10.0 puts the lerp_angle far past any
# tolerance below; the settle is about convergence, not about the rate.
const SETTLE_STEPS := 300
const SETTLE_DELTA := 0.016
const ANGLE_TOL := 0.0001
const BLEND_TOL := 0.001

var _instances: Array[Node] = []

func _scene() -> Node:
	var ps := load(PILOT_TSCN) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate()
	_instances.append(n)
	_rig(n)
	return n

# The controller's @onready references, resolved by hand. Nothing here enters the tree, so
# _ready never runs and they would otherwise be null.
func _rig(n: Node) -> void:
	n.camera_pivot = n.get_node("CameraPivot")
	n.character = n.get_node("character")

func _anim(n: Node) -> Node:
	var a := n.get_node("Animation")
	a.player = n
	a.animation_tree = n.get_node("AnimationTree")
	return a

func end() -> void:
	for n in _instances:
		if is_instance_valid(n):
			n.free()
	_instances.clear()
	super()

# Sets the controller state _handle_movement_input would have produced for this camera yaw
# and this stick, without going near Input.
func _set_input(n: Node, yaw: float, input_dir: Vector2) -> void:
	n.camera_pivot.rotation.y = yaw
	n.input_dir = input_dir
	n.input_strength = minf(input_dir.length(), 1.0)
	var camera_basis := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO).basis
	n.direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

func _settle(n: Node) -> float:
	for i in SETTLE_STEPS:
		n._handle_character_rotation(SETTLE_DELTA)
	return n.character.rotation.y

func _angle_eq(actual: float, expected: float, msg: String) -> void:
	checks += 1
	var d := absf(angle_difference(actual, expected))
	if d > ANGLE_TOL:
		fail("%s\n      expected: %f\n      actual:   %f  (off by %f rad)" % [msg, expected, actual, d])

# --- the rotation target ---------------------------------------------------

# The equality the whole change rests on: running straight forward, turn-to-face aims at the
# same angle stock aimed at. If this goes red, the atan2 argument order or a sign is wrong,
# and every other test here is measuring the wrong thing.
func test_forward_input_aims_where_stock_aimed() -> void:
	for yaw in [0.0, 0.7, -2.1, 3.0]:
		var n := _scene()
		if n == null:
			fail("could not instantiate %s" % PILOT_TSCN)
			return
		_set_input(n, yaw, Vector2(0, -1))   # "forward"

		n.face_travel_direction = true
		n.character.rotation.y = 0.0
		var facing := _settle(n)

		n.face_travel_direction = false
		n.character.rotation.y = 0.0
		var stock := _settle(n)

		_angle_eq(facing, stock,
			"at camera yaw %f, running forward should settle where stock RC settled" % yaw)

func test_settles_facing_the_travel_direction() -> void:
	# Strafe-right input at a yaw that is not axis-aligned: stock would have held
	# camera-back, turn-to-face must end up pointing along the travel.
	var n := _scene()
	if n == null:
		fail("could not instantiate %s" % PILOT_TSCN)
		return
	_set_input(n, 0.7, Vector2(1, 0))
	n.face_travel_direction = true
	n.character.rotation.y = 0.0
	var facing := _settle(n)
	_angle_eq(facing, atan2(n.direction.x, n.direction.z),
		"body should settle facing its travel direction, not camera-back")

func test_strafe_mode_still_welds_to_camera_back() -> void:
	# The seam: face_travel_direction = false has to be stock RC exactly, including for
	# sideways input, or an aim mode built on this flag inherits a broken fallback.
	var n := _scene()
	if n == null:
		fail("could not instantiate %s" % PILOT_TSCN)
		return
	_set_input(n, 0.7, Vector2(1, 0))
	n.face_travel_direction = false
	n.character.rotation.y = 0.0
	_angle_eq(_settle(n), wrapf(0.7 + PI, -PI, PI),
		"with face_travel_direction off the body must still weld to camera-back")

func test_first_person_never_rotates_the_body() -> void:
	var n := _scene()
	if n == null:
		fail("could not instantiate %s" % PILOT_TSCN)
		return
	_set_input(n, 0.7, Vector2(0, -1))
	n.face_travel_direction = true
	n.camera_mode = n.CameraMode.FIRST_PERSON
	n.character.rotation.y = 1.234
	_angle_eq(_settle(n), 1.234, "FIRST_PERSON must leave the body facing alone")

# --- the blend position ----------------------------------------------------

func test_zero_lag_blends_to_pure_forward() -> void:
	# Steady state. Anything but (0, 1) here is a permanent slight strafe underneath every
	# run in the game.
	var n := _scene()
	if n == null:
		fail("could not instantiate %s" % PILOT_TSCN)
		return
	_set_input(n, 0.7, Vector2(1, 0))
	n.face_travel_direction = true
	n.character.rotation.y = atan2(n.direction.x, n.direction.z)
	var blend: Vector2 = _anim(n)._travel_blend()
	approx(blend.x, 0.0, BLEND_TOL, "no lag should mean no sideways blend")
	approx(blend.y, 1.0, BLEND_TOL, "no lag should mean full forward blend (run_forward sits at (0, 1))")

func test_travel_to_the_bodys_right_asks_for_run_right() -> void:
	# The measured sign. His right is -basis.x; run_right sits at blend +1.
	var n := _scene()
	if n == null:
		fail("could not instantiate %s" % PILOT_TSCN)
		return
	_set_input(n, 0.0, Vector2(1, 0))
	n.face_travel_direction = true
	n.character.rotation.y = 0.9
	var b: Basis = n.character.transform.basis
	n.direction = -b.x            # straight out to his right
	n.input_strength = 1.0
	var blend: Vector2 = _anim(n)._travel_blend()
	approx(blend.x, 1.0, BLEND_TOL, "travel to his right must blend toward run_right at (1, 0)")
	approx(blend.y, 0.0, BLEND_TOL, "travel square to his right has no forward component")

func test_travel_to_the_bodys_left_asks_for_run_left() -> void:
	var n := _scene()
	if n == null:
		fail("could not instantiate %s" % PILOT_TSCN)
		return
	_set_input(n, 0.0, Vector2(1, 0))
	n.face_travel_direction = true
	n.character.rotation.y = 0.9
	var b: Basis = n.character.transform.basis
	n.direction = b.x
	n.input_strength = 1.0
	approx(_anim(n)._travel_blend().x, -1.0, BLEND_TOL,
		"travel to his left must blend toward run_left at (-1, 0)")

func test_no_input_blends_to_idle_even_with_stale_direction() -> void:
	# handle_frozen_movement clears input_dir and leaves `direction` and `input_strength`
	# holding last frame's values, so a blend read straight off them marches on the spot.
	var n := _scene()
	if n == null:
		fail("could not instantiate %s" % PILOT_TSCN)
		return
	_set_input(n, 0.0, Vector2(0, -1))
	n.face_travel_direction = true
	n.input_dir = Vector2.ZERO     # what freezing does; direction is deliberately left stale
	var blend: Vector2 = _anim(n)._travel_blend()
	approx(blend.length(), 0.0, BLEND_TOL, "no input must blend to idle at (0, 0)")

func test_strafe_steady_state_blend_is_input_space() -> void:
	# Welded to camera-back, the body-frame blend reads exactly what stock RC's input-space
	# feed read - including S at (0, -1), which is the backpedal.
	for stick in [Vector2(0, -1), Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0),
			Vector2(1, 1).normalized(), Vector2(-1, -1).normalized()]:
		var n := _scene()
		if n == null:
			fail("could not instantiate %s" % PILOT_TSCN)
			return
		_set_input(n, 0.7, stick)
		n.character.rotation.y = wrapf(0.7 + PI, -PI, PI)
		var blend: Vector2 = _anim(n)._travel_blend()
		approx(blend.x, stick.x, BLEND_TOL, "strafe blend x for stick %s" % stick)
		approx(blend.y, -stick.y, BLEND_TOL, "strafe blend y for stick %s" % stick)

# --- the strafe default ----------------------------------------------------

func test_strafe_is_the_default() -> void:
	var n := _scene()
	if n == null:
		fail("could not instantiate %s" % PILOT_TSCN)
		return
	check(not n.face_travel_direction, "face_travel_direction should ship false (strafe)")
	check(not n._faces_travel(), "standing locomotion should not face travel by default")

func test_backpedal_keeps_him_facing_the_camera_way() -> void:
	var n := _scene()
	if n == null:
		fail("could not instantiate %s" % PILOT_TSCN)
		return
	_set_input(n, -2.1, Vector2(0, 1))   # S
	n.character.rotation.y = 0.0
	_angle_eq(_settle(n), wrapf(-2.1 + PI, -PI, PI),
		"S must backpedal (camera-back facing), not turn him toward the camera")

# The crouch left this list 2026-11-15 (four-way crouch jog, docs/specs/pilot9-crouch-kneel.md).
func test_tredge_faces_travel() -> void:
	for flag in ["is_tredging"]:
		var n := _scene()
		if n == null:
			fail("could not instantiate %s" % PILOT_TSCN)
			return
		_set_input(n, 0.7, Vector2(1, 0))
		n.set(flag, true)
		n.character.rotation.y = 0.0
		_angle_eq(_settle(n), atan2(n.direction.x, n.direction.z),
			"%s has a forward-only clip and must face travel" % flag)

func test_vault_faces_the_vault_line_not_the_camera() -> void:
	var n := _scene()
	if n == null:
		fail("could not instantiate %s" % PILOT_TSCN)
		return
	_set_input(n, 0.7, Vector2(1, 0))
	n.is_vaulting = true
	n._vault_dir = Vector3(-1, 0, 0)
	n.character.rotation.y = 0.0
	_angle_eq(_settle(n), atan2(-1.0, 0.0), "the vault must face _vault_dir")

func test_backward_sprint_is_a_run() -> void:
	var n := _scene()
	if n == null:
		fail("could not instantiate %s" % PILOT_TSCN)
		return
	for stick in [Vector2(0, 1), Vector2(1, 1).normalized(), Vector2(-0.3, 0.2)]:
		n.input_dir = stick
		check(not n._sprint_direction_ok(), "stick %s has a backward part - no sprint clip for it" % stick)
	for stick in [Vector2(0, -1), Vector2(1, 0), Vector2(-1, -1).normalized()]:
		n.input_dir = stick
		check(n._sprint_direction_ok(), "stick %s should still sprint" % stick)
	n.input_dir = Vector2(0, 1)
	n.is_tredging = true
	check(n._sprint_direction_ok(), "facing travel there is no backward")
