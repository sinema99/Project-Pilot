extends "res://tests/test_case.gd"

# Covers the double jump: `air_jumps` extra jumps taken with his feet already off the floor,
# each one restarting the existing jump clip from frame 0.
#
# The press itself is not reachable here - Input.is_action_just_pressed() and is_on_floor()
# both need a running frame and a body resting on a collider, which the headless runner has
# neither of. That is the same wall tests/test_pilot9_jump_slide.gd hits, and the user
# clears it on play. What IS reachable is the seam the feature hangs on: the `air_jumped`
# signal, the `jump` state it restarts, and the fact that no transition into `jump` exists
# from the air - which is the whole reason the signal is there instead of a condition.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const CONTROLLER := preload("res://scripts/pilot9.gd")
const ANIMATION := preload("res://scripts/pilot9_animation.gd")

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

func _state_machine(root: Node) -> AnimationNodeStateMachine:
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	if at == null:
		return null
	return at.tree_root as AnimationNodeStateMachine

# --- the signal both halves meet on ---------------------------------------

# scripts/pilot9_animation.gd connects `air_jumped` by name in _ready(), and has_signal()
# guards the connect - so renaming the signal on the controller does not error, it just
# silently stops restarting the clip. Exactly the CROUCH_SCALE failure mode, pinned the
# same way.
func test_the_controller_emits_air_jumped() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	check(body.has_signal("air_jumped"), "scripts/pilot9.gd declares an `air_jumped` signal")
	body.free()

func test_air_jumps_defaults_to_one() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	check(body.air_jumps == 1, "air_jumps defaults to 1 - one extra jump, i.e. a double jump")
	body.free()

# --- the state the restart names -----------------------------------------

# ANIMATION.JUMP_STATE is fed straight to playback.start(). A state machine that has no
# state by that name takes the call without complaining and nothing plays, so the const and
# the tree are checked against each other rather than trusted.
func test_the_tree_has_the_state_the_air_jump_restarts() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("scenes/pilot9.tscn has no AnimationTree with a state machine root")
		return
	check(sm.has_node(ANIMATION.JUMP_STATE),
		"the state machine has a \"%s\" state for playback.start()" % ANIMATION.JUMP_STATE)

# The reason the restart is a signal and not a transition condition. Airborne the tree sits
# in `jump` or `fall`; neither can re-enter `jump` on its own - `jump` is already current,
# and no fall -> jump transition exists. If one is ever added, this test fails and the
# signal path should be reconsidered rather than left to race the condition.
func test_no_transition_re_enters_jump_from_the_air() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("scenes/pilot9.tscn has no AnimationTree with a state machine root")
		return
	var found := false
	for i in sm.get_transition_count():
		if str(sm.get_transition_from(i)) == "fall" and str(sm.get_transition_to(i)) == ANIMATION.JUMP_STATE:
			found = true
	check(not found, "no fall -> %s transition - the air jump restarts the clip itself"
		% ANIMATION.JUMP_STATE)
