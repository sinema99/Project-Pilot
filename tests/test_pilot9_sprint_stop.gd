extends "res://tests/test_case.gd"

# Covers the sprint toggle expiring on a complete stop. See docs/specs/pilot9-sprint-stop.md.
#
# Everything here is about the ONE thing that makes this an edge rather than a state:
# `_sprint_stop_armed`. A state test reads identically in every case a player will notice
# except the one that matters - `sprint` pressed while standing still, before the stick is
# pushed, which is how most runs actually start. That press would be eaten on the next frame
# and the failure would look like a dead button rather than a wrong condition.
#
# The other silent failure is the wall: clearing on speed alone rather than on speed AND a
# centred stick drops a sprint every time he runs into something, and gives it back only after
# a press he has no reason to think he owes.
#
# _update_sprint_stop() takes `on_floor` as an argument precisely so this file can exist -
# outside the tree is_on_floor() is false and unfakeable. Nothing here enters the tree; no
# node is touched, so camera_mode is irrelevant.

const PILOT_TSCN := "res://scenes/pilot9.tscn"

var _instances: Array[Node] = []

func _scene() -> Node:
	var ps := load(PILOT_TSCN) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate()
	_instances.append(n)
	return n

func end() -> void:
	for n in _instances:
		if is_instance_valid(n):
			n.free()
	_instances.clear()
	super()

# A pilot9 mid-sprint: toggle on, moving, and with the stop already armed by that movement.
func _sprinting() -> Node:
	var root := _scene()
	if root == null:
		return null
	root.sprint_toggled = true
	root._sprint_stop_armed = true
	root.velocity = Vector3(8.0, 0.0, 0.0)
	root.input_dir = Vector2(0.0, -1.0)
	return root

# One frame of the rule, with the state a frame of physics would have left behind.
func _step(root: Node, on_floor: bool, speed: float, stick: Vector2) -> void:
	root.velocity = Vector3(speed, 0.0, 0.0)
	root.input_dir = stick
	root._update_sprint_stop(on_floor)

func _source() -> String:
	var f := FileAccess.open("res://scripts/pilot9.gd", FileAccess.READ)
	return f.get_as_text() if f != null else ""

# The body of a named function, from its `func` line to the next top-level `func`.
func _body(text: String, header: String) -> String:
	var start := text.find(header)
	if start < 0:
		return ""
	var rest := text.substr(start + header.length())
	var stop := rest.find("\nfunc ")
	return rest if stop < 0 else rest.substr(0, stop)

# --- the stop itself -------------------------------------------------------

# The ask, in one test: run, stop, and the sprint is gone.
func test_coming_to_a_complete_stop_clears_the_sprint() -> void:
	var root := _sprinting()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_step(root, true, 0.0, Vector2.ZERO)
	check(not root.sprint_toggled,
		"a complete stop left sprint_toggled on - the next stick push will sprint without " +
		"the player asking for it")

# Spent once. A player standing still for a second is not clearing the toggle sixty times,
# and the frame after the stop has to leave a fresh press alone.
func test_the_stop_is_spent_once() -> void:
	var root := _sprinting()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_step(root, true, 0.0, Vector2.ZERO)
	check(not root._sprint_stop_armed, "the stop did not disarm itself")
	# The press a player makes while standing still, then a second stopped frame.
	root.sprint_toggled = true
	_step(root, true, 0.0, Vector2.ZERO)
	check(root.sprint_toggled,
		"a second stopped frame cleared the toggle again - the stop is being read as a state, " +
		"and a `sprint` press made while standing still is eaten the frame after it is made")

# Nothing to spend until he has moved. A rig that boots with the toggle somehow on and never
# moves must not have it taken away, or the first press of the session dies on frame two.
func test_a_stop_with_nothing_armed_leaves_the_toggle_alone() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	check(not root._sprint_stop_armed, "_sprint_stop_armed does not ship disarmed")
	root.sprint_toggled = true
	_step(root, true, 0.0, Vector2.ZERO)
	check(root.sprint_toggled, "a stop cleared the sprint without him ever having moved")

# --- what is not a stop ----------------------------------------------------

# Head-on into a wall: 0 m/s with the stick buried. He is still asking to run and the wall is
# not the player, so the sprint is there the moment he turns away.
func test_running_into_a_wall_is_not_a_stop() -> void:
	var root := _sprinting()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_step(root, true, 0.0, Vector2(0.0, -1.0))
	check(root.sprint_toggled,
		"pinned against a wall with the stick held cost him the sprint - the stick is the " +
		"request, and he never asked to stop")
	check(root._sprint_stop_armed, "the wall disarmed the stop, so the real halt after it will not clear")

# Moving is not stopping, and it is what arms the next stop.
func test_moving_keeps_the_sprint_and_arms_the_stop() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.sprint_toggled = true
	_step(root, true, 8.0, Vector2(0.0, -1.0))
	check(root.sprint_toggled, "a moving frame cleared the sprint")
	check(root._sprint_stop_armed, "a moving frame did not arm the stop")

# The air is between things, not a halt. A stickless fall brakes to a straight vertical drop
# (air_momentum_brake), which is exactly the state this must not read as stopped - clearing
# there would undo the reason the toggle exists.
func test_falling_straight_down_is_not_a_stop() -> void:
	var root := _sprinting()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.velocity = Vector3(0.0, -12.0, 0.0)
	root.input_dir = Vector2.ZERO
	root._update_sprint_stop(false)
	check(root.sprint_toggled,
		"a sprint jump with the stick released lost the sprint in mid-air - the toggle is " +
		"supposed to outlive the jump")
	check(root._sprint_stop_armed, "airborne disarmed the stop, so the landing will not clear")

# --- the threshold ---------------------------------------------------------

# 0.1 m/s: under it he has stopped, over it he is still going somewhere. Both sides are
# asserted because the number is a guess and this is where a retune would land.
func test_the_threshold_is_a_tenth_of_a_metre_a_second() -> void:
	var root := _sprinting()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	approx(root.SPRINT_STOP_SPEED, 0.1, 0.0001, "SPRINT_STOP_SPEED moved off the spec's 0.1")
	_step(root, true, 0.2, Vector2.ZERO)
	check(root.sprint_toggled, "0.2 m/s counted as stopped - he is still travelling")
	_step(root, true, 0.09, Vector2.ZERO)
	check(not root.sprint_toggled, "0.09 m/s did not count as stopped")

# --- the freeze ------------------------------------------------------------

# A pause is not a stop, and the freeze looks exactly like one: handle_frozen_movement()
# zeroes both velocity and input_dir. Without the disarm the first unfrozen frame spends the
# clear on the pause, and the docstring's promise that the toggle survives one is a lie.
func test_a_freeze_does_not_read_as_a_stop() -> void:
	var root := _sprinting()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.frozen = true
	# What the freeze leaves behind, then the frame it is read on.
	root.velocity = Vector3.ZERO
	root.input_dir = Vector2.ZERO
	root._update_sprint_toggle()
	check(root.sprint_toggled, "the freeze itself cleared the sprint")
	check(not root._sprint_stop_armed, "the freeze did not disarm the stop")
	# Unpaused, still standing still: the pause must not have been the stop.
	root.frozen = false
	root._update_sprint_stop(true)
	check(root.sprint_toggled,
		"unpausing cleared the sprint - the pause was read as the stop, and a player who " +
		"paused mid-run comes back walking")

# --- the wiring ------------------------------------------------------------

# The stop is checked ABOVE the press so a press landing on the stop frame wins - that is the
# standing-still-then-pressing case. Input cannot be driven from a --script run, so the
# ordering is asserted against the source the way test_pilot9_sprint_fov.gd asserts placement.
func test_the_stop_is_checked_before_the_press() -> void:
	var text := _source()
	if text == "":
		fail("could not read scripts/pilot9.gd")
		return
	var body := _body(text, "func _update_sprint_toggle")
	check(body != "", "pilot9.gd has no _update_sprint_toggle()")
	if body == "":
		return
	var stop := body.find("_update_sprint_stop(")
	var press := body.find("is_action_just_pressed(\"sprint\")")
	check(stop >= 0, "_update_sprint_toggle() no longer calls _update_sprint_stop()")
	check(press >= 0, "_update_sprint_toggle() no longer reads the `sprint` press")
	if stop < 0 or press < 0:
		return
	check(stop < press,
		"the `sprint` press is handled before the stop - a press made while standing still " +
		"is flipped on and then cleared by the same frame's stop, and the button reads dead")
	check(body.contains("is_action_just_pressed(\"walk\")"),
		"`walk` no longer clears the sprint - the stop is an addition to it, not a replacement")
	check(body.contains("is_on_floor()"),
		"_update_sprint_stop() is no longer passed is_on_floor(), so the on-floor half of the " +
		"gate is dead and a fall now counts as a stop")

# The toggle is read by _apply_movement(), the FOV and three slide predicates, so a new place
# clearing it would be found by feel and not by log. Four writers, and all four are named: the
# press flip, the `walk` clear, the stop clear, and _end_verbs_for_boarding(), which ends every
# live verb on the way into EXIA - the sprint intent included.
func test_the_toggle_still_has_one_writer() -> void:
	var text := _source()
	if text == "":
		fail("could not read scripts/pilot9.gd")
		return
	var writes := 0
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("sprint_toggled ="):
			writes += 1
	eq(writes, 4,
		"sprint_toggled is written somewhere new - it should be assigned in exactly four " +
		"places: the press flip, the `walk` clear and the stop clear (all in " +
		"_update_sprint_toggle()/_update_sprint_stop()), plus _end_verbs_for_boarding()")
	var stop_body := _body(text, "func _update_sprint_stop")
	check(stop_body.contains("input_dir == Vector2.ZERO"),
		"_update_sprint_stop() no longer requires a centred stick - running into a wall now " +
		"costs the sprint")
