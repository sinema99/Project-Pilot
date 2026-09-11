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
const ANIM_SCRIPT := preload("res://scripts/pilot9_animation.gd")

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

# --- the landing yields, and the clip is seeked -------------------------------
#
# The 2026-09-11 bug, and the two halves of its fix. A fade in progress blocks every
# transition in the machine until it finishes. The tree sees is_on_floor() up to a frame
# before _handle_crouch_and_slide() spends the buffered press, so it would open a 0.2 s fade
# into `jump_land`, and `jump_land -> slide` could not fire until that fade had run out: the
# clip started a fifth of a second late, and at slide_time_scale 2.0 the hold froze it 20-odd
# frames short of SLIDE_HOLD_FRAME - the pose out of the middle of his entry the player saw.

# Half one: the landing transitions stand aside for a press already waiting for the ground,
# so the machine never starts the fade that would block the slide.
func test_the_landing_yields_to_a_buffered_slide() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	for from in ["fall", "jump"]:
		var t := _transition(sm, from, "jump_land")
		check(t != null, "no %s -> jump_land transition - RC's landing went missing" % from)
		if t:
			check(t.advance_expression.contains("slide_pending()"),
				("%s -> jump_land fires on `%s`, which does not stand aside for a queued " +
				"slide: the landing opens a %.2f s fade, and nothing - jump_land -> slide " +
				"included - can transition until it ends")
				% [from, t.advance_expression, t.xfade_time])
			check(t.advance_expression.contains("is_on_floor()"),
				"%s -> jump_land must still need the floor" % from)

func test_the_controller_answers_slide_pending() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	check(root.has_method("slide_pending"),
		"scripts/pilot9.gd has no slide_pending() - the two `-> jump_land` expressions name " +
		"a method that does not exist, and an expression that cannot be evaluated never fires")
	if not root.has_method("slide_pending"):
		return
	root.set("_slide_buffered", false)
	check(root.call("slide_pending") == false, "slide_pending() is true with nothing queued")
	root.set("_slide_buffered", true)
	check(root.call("slide_pending") == true,
		"slide_pending() does not follow _slide_buffered, so the landing never yields")

# Half two, and the one that does not depend on getting the timing right: whenever the state
# machine opens the `slide` state late, the clip is dragged onto the controller's clock. The
# freeze frame is then the baked one however late the state arrived.
func test_the_slide_state_has_a_timeseek_before_its_timescale() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	var bt := sm.get_node(BUILDER.SLIDE_STATE) as AnimationNodeBlendTree
	if bt == null:
		fail("the slide state is not a blend tree - _ensure_slide_state() did not run")
		return
	check(bt.has_node(BUILDER.SLIDE_SEEK_NODE),
		"the slide state has no '%s' AnimationNodeTimeSeek - a slide entered late (out of a " % BUILDER.SLIDE_SEEK_NODE +
		"jump, mostly) plays from frame 0 against a clock already part-way through, and the " +
		"hold freezes it on whatever frame it had reached")
	if not bt.has_node(BUILDER.SLIDE_SEEK_NODE):
		return
	check(bt.get_node(BUILDER.SLIDE_SEEK_NODE) is AnimationNodeTimeSeek,
		"'%s' is not an AnimationNodeTimeSeek" % BUILDER.SLIDE_SEEK_NODE)
	# Clip -> SlideSeek -> SlideScale -> output. The seek has to sit inside the scale: a
	# request is a clip position, and it must reach the clip whatever the scale is doing -
	# including the 0 the hold pins it with.
	var wired := _input_zero(bt)
	eq(str(wired.get(BUILDER.SLIDE_SEEK_NODE, "")), "Clip",
		"the TimeSeek does not feed off the slide clip")
	eq(str(wired.get(BUILDER.SLIDE_SCALE_NODE, "")), BUILDER.SLIDE_SEEK_NODE,
		"the TimeScale does not read through the TimeSeek, so a seek cannot reach the clip")
	eq(str(wired.get("output", "")), BUILDER.SLIDE_SCALE_NODE,
		"the blend tree's output does not come through the TimeScale")

# Blend tree connections come back as one flat array of (to, input index, from) triples -
# there is no per-node accessor on AnimationNodeBlendTree - so this reduces it to
# "what feeds each node's input 0", which is all a single chain has.
func _input_zero(bt: AnimationNodeBlendTree) -> Dictionary:
	var out := {}
	var flat: Array = bt.get("node_connections")
	for i in range(0, flat.size(), 3):
		if int(flat[i + 1]) == 0:
			out[str(flat[i])] = str(flat[i + 2])
	return out

# The same silent seam CROUCH_SCALE and SLIDE_SCALE are pinned on: AnimationTree.set() stores
# an unknown parameter path without complaining, so a rename on either side leaves the clip
# unseeked and the bug back, with nothing in the log.
func test_the_animation_script_seeks_the_path_the_builder_built() -> void:
	var expected := "parameters/%s/%s/seek_request" % [BUILDER.SLIDE_STATE, BUILDER.SLIDE_SEEK_NODE]
	eq(ANIM_SCRIPT.SLIDE_SEEK, expected,
		"pilot9_animation.gd seeks a path the builder does not build")

func test_the_tree_exposes_the_slide_seek_parameter() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	if at == null:
		fail("no AnimationTree on pilot9.tscn")
		return
	var found := false
	for p in at.get_property_list():
		if String(p.name) == ANIM_SCRIPT.SLIDE_SEEK:
			found = true
			break
	check(found, "the AnimationTree exposes no '%s' - nothing can put the clip back in step" %
		ANIM_SCRIPT.SLIDE_SEEK)

# What the seek is aimed at. `_slide_time` is the clip's clock and the controller freezes it
# at slide_hold_time for a hold, which is what makes one seek right in every case - including
# a state that opens after the hold has already begun.
func test_the_controller_reports_the_clip_clock() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	check(root.has_method("slide_clip_time"),
		"scripts/pilot9.gd has no slide_clip_time() - the animation script cannot see the " +
		"clock it is meant to seek the clip onto")
	if not root.has_method("slide_clip_time"):
		return
	root.set("_slide_time", 0.375)
	approx(float(root.call("slide_clip_time")), 0.375, 0.0001,
		"slide_clip_time() does not report _slide_time")

# Once per entry, not once per frame. A seek every frame would step the clip at the rate
# _process runs at instead of letting it play - the stutter the TimeScale arrangement exists
# to avoid - and the flag has to re-arm whenever `slide` is not the state playing, or a slide
# the machine enters twice is only ever seeked once.
func test_the_clip_is_seeked_once_per_entry() -> void:
	var text := FileAccess.get_file_as_string("res://scripts/pilot9_animation.gd")
	var at := text.find("func _sync_slide_clip")
	check(at != -1, "pilot9_animation.gd has no _sync_slide_clip() - nothing seeks the clip")
	if at == -1:
		return
	var body := text.substr(at)
	check(body.contains("player.slide_clip_time()"),
		"_sync_slide_clip() seeks to something other than the controller's clip clock")
	check(body.contains("get_current_node() == SLIDE_STATE"),
		"_sync_slide_clip() does not wait for `slide` to be the state playing, so it seeks a " +
		"clip that has not started yet")
	check(body.contains("_slide_clip_synced = false"),
		"_sync_slide_clip() never re-arms, so a slide the machine enters twice runs unseeked " +
		"the second time")
	check(text.find("_sync_slide_clip()") < at,
		"_drive_slide() does not call _sync_slide_clip() - the seek is dead code")

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
