extends "res://tests/test_case.gd"

# Covers the land-and-slide buffer: a `crouch` press made any time in the air is remembered
# until pilot9 lands and spent the instant he does, so a jump into a slide does not need the
# press to hit the single frame of touchdown. Also that `sprint` is a toggle, which is what
# keeps that remembered press meaning "slide" and not "let go by accident". See
# docs/specs/pilot9-jump-slide.md.
#
# The happy-path consumption (buffer + is_on_floor() + a live sprint = a slide from the
# landing frame) needs a real Input state and a body that reports a floor, neither of which
# the headless runner has - the same wall docs/specs/pilot9-slide.md's _can_start_slide()
# happy path hits, and the same one the user clears on play. What is reachable here is the
# animation wiring that lets the slide be entered from the air at all, and the buffer's
# bookkeeping in _handle_crouch_and_slide().

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

# --- the slide can be entered from the air --------------------------------

# A buffered slide flips is_sliding on the landing frame, when the tree is in `fall` or
# `jump_land`. Without an is_sliding exit on each, the entry routes
# fall -> jump_land -> Locomotion -> slide over three stacked cross-fades and a beat of
# jump_land playing first. These are the transitions that make "land and slide cleanly" one
# fade from wherever he is.
func test_the_slide_can_be_entered_from_fall_and_jump_land() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	for from in ["fall", "jump_land"]:
		var t := _transition(sm, from, "slide")
		check(t != null,
			"no %s -> slide transition - a slide buffered off a jump would route through " % from +
			"jump_land and Locomotion first instead of entering cleanly (see the spec)")
		if t:
			eq(t.advance_expression, "is_sliding",
				"%s -> slide must fire on is_sliding, like every other way into the slide" % from)
			eq(t.advance_mode, AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO,
				"%s -> slide must advance automatically; nothing calls travel() for it" % from)

# Priority only orders transitions that share a `from`. On the landing frame both
# `fall -> jump_land` (is_on_floor()) and `fall -> slide` (is_sliding) are eligible; the
# slide has to win or jump_land plays for a frame before it. Same for jump_land's own exit.
func test_the_air_slide_entry_outranks_the_plain_landing() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return

	var fall_to_slide := _transition(sm, "fall", "slide")
	var fall_to_land := _transition(sm, "fall", "jump_land")
	if fall_to_slide and fall_to_land:
		check(fall_to_slide.priority < fall_to_land.priority,
			("fall -> slide (priority %d) must outrank fall -> jump_land (priority %d), or a " +
			"buffered slide plays a frame of jump_land on touchdown")
			% [fall_to_slide.priority, fall_to_land.priority])
	else:
		fail("missing a fall -> slide or fall -> jump_land transition to compare")

	var land_to_slide := _transition(sm, "jump_land", "slide")
	var land_to_loco := _transition(sm, "jump_land", "Locomotion")
	if land_to_slide and land_to_loco:
		check(land_to_slide.priority < land_to_loco.priority,
			("jump_land -> slide (priority %d) must outrank jump_land -> Locomotion " +
			"(priority %d)") % [land_to_slide.priority, land_to_loco.priority])
	else:
		fail("missing a jump_land -> slide or jump_land -> Locomotion transition to compare")

# The old lone way in stays, so a grounded slide is untouched.
func test_the_locomotion_entry_is_still_there() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	var t := _transition(sm, "Locomotion", "slide")
	check(t != null, "the Locomotion -> slide entry went missing - the grounded slide is broken")
	if t:
		eq(t.advance_expression, "is_sliding", "Locomotion -> slide fires on the wrong expression")

# --- the controller side -------------------------------------------------------

func test_the_controller_exposes_the_slide_buffer() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var props := {}
	for p in root.get_property_list():
		props[String(p.name)] = true
	check(props.has("can_buffer_slide"),
		"scripts/pilot9.gd has no 'can_buffer_slide' - the air-press buffer has no off switch")
	if props.has("can_buffer_slide"):
		check(bool(root.get("can_buffer_slide")),
			"can_buffer_slide ships off - a jump into a slide is back to a frame-perfect press")
	check(props.has("_slide_buffered"),
		"scripts/pilot9.gd has no '_slide_buffered' - nothing is holding the queued press")
	if props.has("_slide_buffered"):
		check(bool(root.get("_slide_buffered")) == false, "pilot9 must not start with a queued slide")

# The buffer no longer decays: a `crouch` press made at the apex is still live at touchdown,
# however long the fall. Driven off the tree - not frozen, not sliding, not on a floor and
# no fresh press - so _handle_crouch_and_slide() falls straight through and must leave the
# flag alone rather than counting anything down.
func test_the_buffer_does_not_lapse_in_the_air() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.frozen = false
	root.is_sliding = false
	root.set("_slide_buffered", true)

	for i in 30:
		root._handle_crouch_and_slide(0.1)
	check(bool(root.get("_slide_buffered")),
		"the queued air press was dropped before landing - a jump-slide now needs the press " +
		"late in the fall again, which is the strictness this change removed")

# Freezing ends a running slide because nothing advances its clock while frozen; a queued
# air press has the same fix - it is dropped, not held.
func test_freezing_clears_a_queued_buffer() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.is_sliding = false
	root.set("_slide_buffered", true)
	root.frozen = true

	root._handle_crouch_and_slide(0.016)
	check(bool(root.get("_slide_buffered")) == false,
		"a queued slide survived a freeze - it will fire on the frame he unfreezes")

# can_buffer_slide is an inspector switch and must survive a rig swap, so - like slide_scale
# and slide_cooldown - the builder must never write it.
func test_can_buffer_slide_is_not_a_baked_property() -> void:
	check(not BUILDER.SLIDE_BAKED.has("can_buffer_slide"),
		"can_buffer_slide is in SLIDE_BAKED, so pilot9_build_scene.gd overwrites it on every sync")

# --- sprint is a toggle ------------------------------------------------------------

# Sprint toggles rather than being held, so an accidental release mid-jump does not drop him
# out of a run and a buffered jump-slide keeps the sprint it launched with. The flip itself
# needs a live Input edge and a physics frame - play-tested, like the slide's happy path -
# but the state it flips has to exist and start clear, and is_sprinting has to be driven by
# it, not by Input.is_action_pressed("sprint").
func test_sprint_is_a_toggle_not_a_hold() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var props := {}
	for p in root.get_property_list():
		props[String(p.name)] = true
	check(props.has("sprint_toggled"),
		"scripts/pilot9.gd has no 'sprint_toggled' - sprint is still a hold, so letting go " +
		"mid-jump drops him out of a run")
	if props.has("sprint_toggled"):
		check(bool(root.get("sprint_toggled")) == false, "pilot9 must not start already sprinting")
	check(root.has_method("_update_sprint_toggle"),
		"scripts/pilot9.gd has no _update_sprint_toggle() - nothing flips the toggle")
	var src := FileAccess.get_file_as_string("res://scripts/pilot9.gd")
	check(src.contains("is_sprinting = sprint_toggled and"),
		"_apply_movement() still reads Input.is_action_pressed(\"sprint\") for is_sprinting - " +
		"the toggle is exposed but not actually driving the gait")
