extends "res://tests/test_case.gd"

# Covers the slide -> crouch hand-off: a slide ends crouched, not standing, unless `jump`
# took him out of it. See docs/specs/pilot9-slide-crouch.md.
#
# The failure worth catching here is the same silent one the slide and the crouch already
# guard against a jump: two exits from the `slide` state go live on the same frame and the
# wrong one wins with nothing in the log. If `slide -> crouch` does not outrank
# `slide -> Locomotion`, the hand-off plays as a stand-up; if it is not outranked by
# `slide -> jump`, a jump out of a slide plays as a crouch. Both read as a working slide
# that feels wrong.
#
# Nothing here enters the tree - the transitions live on the baked pilot9.tscn and the two
# controller calls exercised (_start_slide, _end_slide) touch no nodes with camera_mode
# forced to FIRST_PERSON.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const BUILDER := preload("res://scripts/pilot9_build_scene.gd")

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

func _transition(sm: AnimationNodeStateMachine, from: String, to: String) -> AnimationNodeStateMachineTransition:
	for i in sm.get_transition_count():
		if str(sm.get_transition_from(i)) == from and str(sm.get_transition_to(i)) == to:
			return sm.get_transition(i)
	return null

# --- the hand-off transition ---------------------------------------------------

func test_slide_hands_off_into_the_crouch() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	check(sm.has_node(BUILDER.CROUCH_STATE), "the state machine has no 'crouch' state to hand off to")
	var t := _transition(sm, "slide", "crouch")
	check(t != null,
		"no slide -> crouch transition - a slide would end standing, which is the old rule")
	if t == null:
		return
	eq(t.advance_expression, "is_crouching", "slide -> crouch fires on the wrong expression")
	eq(t.advance_mode, AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO,
		"slide -> crouch must advance automatically; nothing calls travel() for it")

# The crouch has to win the hand-off over the plain stand-up, exactly as the jump does.
func test_the_hand_off_outranks_the_stand_up() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	var to_crouch := _transition(sm, "slide", "crouch")
	var to_loco := _transition(sm, "slide", "Locomotion")
	if to_crouch == null or to_loco == null:
		fail("missing slide -> crouch or slide -> Locomotion")
		return
	check(to_crouch.priority < to_loco.priority,
		("slide -> crouch must outrank slide -> Locomotion (priority %d vs %d): is_crouching " +
		"and not-is_sliding both go true on the completion frame, so the lower priority " +
		"would hand him to standing Locomotion and the crouch would never take") %
		[to_crouch.priority, to_loco.priority])

# ...and lose to the jump, which clears is_crouching the same frame: a jump out ends standing.
func test_a_jump_out_of_a_slide_still_ends_standing() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	var to_jump := _transition(sm, "slide", "jump")
	var to_crouch := _transition(sm, "slide", "crouch")
	if to_jump == null or to_crouch == null:
		fail("missing slide -> jump or slide -> crouch")
		return
	check(to_jump.priority < to_crouch.priority,
		("slide -> jump must outrank slide -> crouch (priority %d vs %d): _handle_gravity_and_jump " +
		"clears is_crouching and launches the leap on the same frame, so both are eligible " +
		"and a jump out would otherwise play as a crouch") % [to_jump.priority, to_crouch.priority])

# --- the controller side -----------------------------------------------------

# _end_slide() is also the ledge exit, the jump cancel, the freeze stop and the boarding
# stop, and every one of those must leave him standing. So the crouch is set at the
# completion call site, never inside _end_slide().
func test_end_slide_on_its_own_does_not_crouch_him() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.is_sliding = true
	root.is_crouching = false
	root._end_slide()
	check(not root.is_sliding, "_end_slide() did not clear is_sliding")
	check(not root.is_crouching,
		"_end_slide() set is_crouching - a slide ended off a ledge or cancelled into a jump " +
		"would now drag him into a crouch")

# Entry still clears the crouch: a slide is not a crouch, and the flag is re-set only at the
# natural exit.
func test_starting_a_slide_still_clears_the_crouch() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.camera_mode = 0                       # FIRST_PERSON - _start_slide takes the heading, touches no nodes
	root.is_crouching = true
	root._start_slide(Vector3(0.0, 0.0, 1.0))
	check(root.is_sliding, "_start_slide did not set is_sliding")
	check(not root.is_crouching, "starting a slide has to clear the crouch")

# The re-slide bug: coming out of the hand-off, sprint_toggled is still on, so a `crouch`
# press meant to stand up passed every test in _can_start_slide() and started another slide -
# he could never stand. Both slide-start predicates now bail on is_crouching. Asserted at the
# source, like test_pilot9_sprint_fov.gd's placement checks, because the behaviour it blocks
# needs is_on_floor() and a real Input and so is not reachable in a --script run.
func test_a_slide_cannot_be_started_while_crouched() -> void:
	var src := FileAccess.open("res://scripts/pilot9.gd", FileAccess.READ)
	if src == null:
		fail("could not read scripts/pilot9.gd")
		return
	var text := src.get_as_text()
	for fn in ["func _can_start_slide", "func _should_buffer_slide"]:
		var at := text.find(fn)
		check(at != -1, "pilot9.gd has no %s" % fn)
		if at == -1:
			continue
		var body_end := text.find("\nfunc ", at + 1)
		var body := text.substr(at, body_end - at if body_end != -1 else -1)
		check(body.contains("not is_crouching"),
			("%s no longer guards on `not is_crouching` - a `crouch` press to stand up after " +
			"a slide hand-off will re-enter the slide, because sprint_toggled is still on") % fn)
