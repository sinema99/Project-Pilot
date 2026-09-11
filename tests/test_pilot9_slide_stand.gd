extends "res://tests/test_case.gd"

# Covers the slide's exit: every way out of a slide ends STANDING, and the run-out is what
# stands him up. See docs/specs/pilot9-slide-stand.md, which reverses
# docs/specs/pilot9-slide-crouch.md - this file replaces tests/test_pilot9_slide_crouch.gd.
#
# The failure worth catching is a silent one on two sides.
#
# On the tree: a `slide -> crouch` transition left in place (or added back) would fire the
# instant anything set is_crouching during a slide, and the slide would end in a 1.6 m/s
# crouch again with nothing in the log. `slide -> Locomotion` also has to stay outranked by
# `-> jump` and `-> fall`, or a jump out of a slide plays as a stand-up and a slide off a
# ledge plays as a landing.
#
# On the controller: the crouch hand-off was three `is_crouching = true` writes inside
# _handle_crouch_and_slide(). Those branches need is_on_floor() and a real Input, so they
# cannot be reached in a --script run - their absence is asserted against the source, the
# same way test_pilot9_sprint_fov.gd asserts placement.
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

func _source() -> String:
	var f := FileAccess.open("res://scripts/pilot9.gd", FileAccess.READ)
	return f.get_as_text() if f != null else ""

# The body of a named function, from its `func` line to the next top-level `func`.
func _body(text: String, fn: String) -> String:
	var at := text.find(fn)
	if at == -1:
		return ""
	var body_end := text.find("\nfunc ", at + 1)
	return text.substr(at, body_end - at if body_end != -1 else -1)

# --- the tree ------------------------------------------------------------------

# The whole of the reversal, on the animation side.
func test_there_is_no_slide_to_crouch_transition() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	check(sm.has_node(BUILDER.CROUCH_STATE), "the state machine lost its 'crouch' state entirely")
	check(_transition(sm, "slide", "crouch") == null,
		"there is a slide -> crouch transition again - a slide would hand off into a 1.6 m/s " +
		"crouch, which is the rule docs/specs/pilot9-slide-stand.md reverses. Rebuild " +
		"scenes/pilot9.tscn if _ensure_slide_state() no longer adds one.")

# The exit that replaced it, and the one every stand-up now takes.
func test_a_slide_exits_into_standing_locomotion() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	var t := _transition(sm, "slide", "Locomotion")
	check(t != null, "no slide -> Locomotion transition - a slide would have no way to end standing")
	if t == null:
		return
	eq(t.advance_expression, "not is_sliding", "slide -> Locomotion fires on the wrong expression")
	eq(t.advance_mode, AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO,
		"slide -> Locomotion must advance automatically; nothing calls travel() for it")

# The two priorities that still matter. Both are cases where the exit goes live on the same
# frame as a more specific one, and the stand-up must lose.
func test_the_stand_up_loses_to_the_jump_and_the_fall() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	var to_loco := _transition(sm, "slide", "Locomotion")
	var to_jump := _transition(sm, "slide", "jump")
	var to_fall := _transition(sm, "slide", "fall")
	if to_loco == null or to_jump == null or to_fall == null:
		fail("missing one of slide -> Locomotion / jump / fall")
		return
	check(to_jump.priority < to_loco.priority,
		("slide -> jump must outrank slide -> Locomotion (priority %d vs %d): a jump cancel " +
		"clears is_sliding and launches on the same frame, so both are eligible and the leap " +
		"would otherwise play as a stand-up") % [to_jump.priority, to_loco.priority])
	check(to_fall.priority < to_loco.priority,
		("slide -> fall must outrank slide -> Locomotion (priority %d vs %d): sliding off a " +
		"ledge clears is_sliding on the frame his feet leave the floor") %
		[to_fall.priority, to_loco.priority])

# --- the controller ------------------------------------------------------------

# The three deleted writes. Asserted at the source because the branches that held them need
# is_on_floor() and a real Input and so are not reachable in a --script run.
func test_no_slide_branch_crouches_him() -> void:
	var text := _source()
	if text == "":
		fail("could not read scripts/pilot9.gd")
		return
	var body := _body(text, "func _handle_crouch_and_slide")
	check(body != "", "pilot9.gd has no _handle_crouch_and_slide")
	if body == "":
		return
	check(not body.contains("is_crouching = true"),
		"_handle_crouch_and_slide() sets is_crouching = true again - the slide is handing off " +
		"into a crouch, and crouch_speed (1.6 m/s) eats everything the slide earned. Only the " +
		"`is_crouching = not is_crouching` toggle at the bottom may write it here.")
	check(body.contains("is_crouching = not is_crouching"),
		"the plain crouch toggle is gone from _handle_crouch_and_slide() - `crouch` outside a " +
		"slide no longer does anything")

# Leaving the hold is a resume, not an end: the run-out is the stand-up, and it is also what
# carries the speed out. Ending on the press instead would cut both.
func test_the_crouch_press_leaves_the_hold_rather_than_ending_the_slide() -> void:
	var text := _source()
	if text == "":
		fail("could not read scripts/pilot9.gd")
		return
	var body := _body(text, "func _handle_crouch_and_slide")
	var at := body.find("is_action_just_pressed(\"crouch\")")
	check(at != -1, "_handle_crouch_and_slide() no longer reads the `crouch` press")
	if at == -1:
		return
	# The hold's press is the FIRST one in the function; the toggle's fresh press is later.
	var branch := body.substr(at, 400)
	check(branch.contains("is_slide_holding = false"),
		"the `crouch` press out of a hold no longer clears is_slide_holding - it is supposed " +
		"to resume the clip so the run-out stands him up, not end the slide from the hold pose")

# _end_slide() is the ledge exit, the jump cancel, the freeze stop and the boarding stop, and
# every one of those leaves him standing. It must not touch the crouch either way.
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
		"_end_slide() set is_crouching - every exit from a slide is supposed to end standing")

# Entry still clears the crouch. Nothing on the slide path sets it again.
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

# The guard outlives the hand-off it was written for (see docs/specs/pilot9-slide-crouch.md's
# "re-slide bug"). It is independently right: the clip opens at 8 m/s with his feet planted,
# so a slide out of a 1.6 m/s crouch lurches, and crouched the press means stand up.
func test_a_slide_still_cannot_be_started_while_crouched() -> void:
	var text := _source()
	if text == "":
		fail("could not read scripts/pilot9.gd")
		return
	for fn in ["func _can_start_slide", "func _should_buffer_slide"]:
		var body := _body(text, fn)
		check(body != "", "pilot9.gd has no %s" % fn)
		if body == "":
			continue
		check(body.contains("not is_crouching"),
			("%s no longer guards on `not is_crouching` - a `crouch` press meant to stand him " +
			"up out of a crouch will start a slide from 1.6 m/s instead") % fn)
