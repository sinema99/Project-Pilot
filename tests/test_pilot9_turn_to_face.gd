extends "res://tests/test_case.gd"

# Covers turn-to-face: pilot9 aims his body at where he is travelling instead of welding it
# to camera-back, so a forward-only clip (the crouch walk, and whatever follows it) is
# correct in every direction. See docs/specs/pilot9-turn-to-face.md.
#
# Two things here are worth more than the rest.
#
# The first is that the new rotation target is a GENERALISATION of the stock one, not a
# replacement: for straight-forward input, atan2(direction.x, direction.z) and
# camera_pivot.rotation.y + PI are the same angle. That equality is what says the 180 degree
# basis baked into the `character` node is still being respected, and a sign slip in the
# atan2 breaks it - so it is asserted directly, at several camera yaws, rather than trusted.
#
# The second is the X sign on the blend position. pilot9's mesh faces its own +Z but his
# local +X points to his LEFT, so travel toward his right is -basis.x. Get that backwards and
# he leans the wrong way through every turn, which on play reads as a bad blend space rather
# than as a wrong sign - the kind of failure that gets debugged in the wrong file for an hour.
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

func test_strafe_mode_feeds_input_space() -> void:
	var n := _scene()
	if n == null:
		fail("could not instantiate %s" % PILOT_TSCN)
		return
	_set_input(n, 0.7, Vector2(1, -1))
	n.face_travel_direction = false
	var blend: Vector2 = _anim(n)._travel_blend()
	approx(blend.x, 1.0, BLEND_TOL, "strafe mode feeds input_dir.x straight through")
	approx(blend.y, 1.0, BLEND_TOL, "strafe mode feeds -input_dir.y straight through")
