extends "res://tests/test_case.gd"

# Covers pilot9's crouch: the C / controller-B toggle, the crouch_walk clip lifted out of
# assets/pilot9.glb, and the `crouch` state scripts/pilot9_build_scene.gd builds for it.
#
# The failure mode these are pointed at is the quiet one. AnimationTree.set() stores an
# unknown parameter path without complaining, and an advance_expression naming a property
# that does not exist just never fires, so a rename on either side of the
# builder/pilot9_animation.gd seam leaves a crouch that transitions but never animates -
# no error, no log line, nothing to see except in game.
#
# See docs/reimport.md (pilot9) and docs/specs/pilot9-real-controller.md.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const BUILDER := preload("res://scripts/pilot9_build_scene.gd")
const ANIM_SCRIPT := preload("res://scripts/pilot9_animation.gd")

# From the 2026-09-06 PILOT9.glb export: the Blender action "P.crouchwalk", 0.983 s at
# 30 fps. Asserted loosely - the user re-authors this clip - but a collapse to zero is the
# documented import failure and has to stay red.
const CROUCH_CLIP_LENGTH := 0.983

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

# --- the input action ------------------------------------------------------

func test_crouch_action_exists() -> void:
	check(InputMap.has_action("crouch"),
		"project.godot declares no 'crouch' action - scripts/pilot9.gd calls Input.is_action_just_pressed on it")

func test_crouch_is_bound_to_C_and_to_controller_B() -> void:
	if not InputMap.has_action("crouch"):
		fail("no 'crouch' action to inspect")
		return
	var has_key := false
	var has_pad := false
	for e in InputMap.action_get_events("crouch"):
		if e is InputEventKey:
			# Bound by physical_keycode so it stays on the same physical key across
			# layouts, matching how forward/backward/left/right are bound.
			has_key = has_key or (e as InputEventKey).physical_keycode == KEY_C
		elif e is InputEventJoypadButton:
			has_pad = has_pad or (e as InputEventJoypadButton).button_index == JOY_BUTTON_B
	check(has_key, "'crouch' has no C key binding (physical_keycode KEY_C)")
	check(has_pad, "'crouch' has no controller B binding (JOY_BUTTON_B)")

# --- the clip came across from the GLB -------------------------------------

func test_crouch_walk_clip_is_in_the_library() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		fail("no AnimationPlayer")
		return
	check(ap.has_animation("crouch_walk"),
		"no 'crouch_walk' in the library - pilot9_build_scene.gd::_ensure_glb_clips did not " +
		"run, or the Blender action is no longer named P.crouchwalk (see GLB_CLIPS)")

func test_crouch_walk_loops_and_has_real_length() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation("crouch_walk"):
		fail("no crouch_walk clip to inspect")
		return
	var a := ap.get_animation("crouch_walk")
	check(a.length > 0.1,
		"crouch_walk is %.3fs - a zero-length clip is the documented import failure" % a.length)
	approx(a.length, CROUCH_CLIP_LENGTH, 0.5,
		"crouch_walk's duration moved a long way from the export it was wired against; " +
		"re-check the Blender action")
	eq(a.loop_mode, Animation.LOOP_LINEAR,
		"crouch_walk must loop - Godot's importer defaults every clip to LOOP_NONE, so " +
		"GLB_CLIPS has to set it or the cycle plays once and freezes mid-stride")

func test_crouch_walk_tracks_all_bind_to_real_bones() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skel := root.get_node_or_null("%GeneralSkeleton") as Skeleton3D
	if ap == null or skel == null or not ap.has_animation("crouch_walk"):
		fail("crouch_walk or the skeleton is missing")
		return
	var a := ap.get_animation("crouch_walk")
	check(a.get_track_count() > 0, "crouch_walk has no tracks at all")
	var broken: PackedStringArray = []
	for t in a.get_track_count():
		var path := str(a.track_get_path(t))
		# A GLB clip only plays unedited because the retargeter rewrites its track paths
		# onto the same unique-named skeleton RC's clips address. If an import stops doing
		# that they revert to Armature/Skeleton3D and resolve to nothing from root_node.
		if not path.begins_with("%GeneralSkeleton:"):
			broken.append("path '%s' lost its unique-name prefix" % path)
			continue
		var bone := path.get_slice(":", 1)
		if bone != "" and skel.find_bone(bone) == -1:
			broken.append(bone)
	check(broken.is_empty(),
		"crouch_walk tracks that do not land on the retargeted rig: %s" % str(broken))

# --- the state machine -----------------------------------------------------

func test_state_machine_has_a_crouch_state() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no AnimationNodeStateMachine on the AnimationTree")
		return
	check(sm.has_node("crouch"), "the locomotion state machine has no 'crouch' state")

func test_crouch_state_plays_crouch_walk_through_a_timescale() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null or not sm.has_node("crouch"):
		fail("no crouch state to inspect")
		return
	var bt := sm.get_node("crouch") as AnimationNodeBlendTree
	check(bt != null, "the crouch state is not a blend tree")
	if bt == null:
		return
	var scale_node := bt.get_node(BUILDER.CROUCH_SCALE_NODE) as AnimationNodeTimeScale
	check(scale_node != null,
		"the crouch state has no '%s' AnimationNodeTimeScale - pilot9 has a crouch walk " % BUILDER.CROUCH_SCALE_NODE +
		"and no crouch idle, so standing still is a scale of 0 rather than a second clip")
	var clip := bt.get_node("Clip") as AnimationNodeAnimation
	check(clip != null, "the crouch state has no 'Clip' animation node")
	if clip:
		eq(str(clip.animation), "crouch_walk", "the crouch state plays the wrong clip")

# The seam that fails silently: pilot9_animation.gd writes one hard-coded parameter path
# every frame, and AnimationTree.set() on a path that does not exist is a no-op, not an
# error. Rebuild the path from the builder's own constants and demand the two still meet.
func test_the_timescale_parameter_path_matches_what_the_feed_writes() -> void:
	var expected := "parameters/%s/%s/scale" % [BUILDER.CROUCH_STATE, BUILDER.CROUCH_SCALE_NODE]
	eq(ANIM_SCRIPT.CROUCH_SCALE, expected,
		"scripts/pilot9_animation.gd writes a TimeScale parameter the builder does not " +
		"create; the crouch would transition but never advance, with nothing in the log")

func test_the_tree_actually_exposes_that_parameter() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	if at == null:
		fail("no AnimationTree")
		return
	var found := false
	for p in at.get_property_list():
		if String(p.name) == ANIM_SCRIPT.CROUCH_SCALE:
			found = true
			break
	check(found, "the AnimationTree exposes no '%s' - nothing drives the crouch cycle" % ANIM_SCRIPT.CROUCH_SCALE)

# --- the transitions in and out --------------------------------------------

func test_crouch_is_entered_and_left_on_is_crouching() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	var into := _transition(sm, "Locomotion", "crouch")
	check(into != null, "no Locomotion -> crouch transition")
	if into:
		eq(into.advance_expression, "is_crouching", "Locomotion -> crouch fires on the wrong expression")
		eq(into.advance_mode, AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO,
			"Locomotion -> crouch must advance automatically; nothing calls travel() for the crouch")
	var out := _transition(sm, "crouch", "Locomotion")
	check(out != null, "no crouch -> Locomotion transition - the crouch would be a one-way trip")
	if out:
		eq(out.advance_expression, "not is_crouching", "crouch -> Locomotion fires on the wrong expression")

# is_crouching is read by the tree, not by code a rename could carry along: an
# advance_expression naming a property that does not exist simply never fires.
func test_the_controller_exposes_is_crouching_and_crouch_speed() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var props := {}
	for p in root.get_property_list():
		props[String(p.name)] = true
	check(props.has("is_crouching"),
		"scripts/pilot9.gd has no 'is_crouching' - every crouch advance_expression silently never fires")
	check(props.has("crouch_speed"), "scripts/pilot9.gd has no 'crouch_speed'")
	if props.has("crouch_speed") and props.has("walk_speed"):
		check(root.get("crouch_speed") < root.get("walk_speed"),
			"crouch_speed (%s) should be slower than walk_speed (%s)"
			% [root.get("crouch_speed"), root.get("walk_speed")])
	if props.has("is_crouching"):
		check(root.get("is_crouching") == false, "pilot9 must not start crouched")

func test_the_expression_base_node_is_the_controller() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	if at == null:
		fail("no AnimationTree")
		return
	var base := at.get_node_or_null(at.advance_expression_base_node)
	check(base == root,
		"advance_expression_base_node must resolve to the pilot9 controller or 'is_crouching' " +
		"resolves against the wrong node; got %s" % str(at.advance_expression_base_node))

# A crouch walked off a ledge still has to fall, and a jump out of one still has to read
# as a jump. Both exits go live on the same frame as `not is_crouching` when the jump
# clears the toggle, so jump has to outrank the stand-up.
func test_crouch_can_still_fall_and_jump() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	var to_fall := _transition(sm, "crouch", "fall")
	check(to_fall != null, "no crouch -> fall transition - walking off a ledge crouched would not fall")
	var to_jump := _transition(sm, "crouch", "jump")
	check(to_jump != null, "no crouch -> jump transition")
	var to_loco := _transition(sm, "crouch", "Locomotion")
	if to_jump and to_loco:
		check(to_jump.priority < to_loco.priority,
			("crouch -> jump must outrank crouch -> Locomotion (priority %d vs %d): the jump " +
			"clears is_crouching on the same frame it launches, so both are eligible and the " +
			"leap would play as a stand-up") % [to_jump.priority, to_loco.priority])

func test_landing_while_crouched_returns_to_the_crouch() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	var t := _transition(sm, "jump_land", "crouch")
	check(t != null,
		"no jump_land -> crouch transition - jump_land's only other exit needs velocity, so " +
		"landing still while crouched would strand him standing in the landing pose")
	if t:
		eq(t.advance_expression, "is_crouching", "jump_land -> crouch fires on the wrong expression")

# --- the sitting clip is present but deliberately unwired ------------------

func test_sit_down_is_imported_but_not_in_the_state_machine() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		fail("no AnimationPlayer")
		return
	check(ap.has_animation("sit_down"),
		"'sit_down' (the Blender action P.sitting) is missing from the library")
	if ap.has_animation("sit_down"):
		eq(ap.get_animation("sit_down").loop_mode, Animation.LOOP_NONE,
			"sit_down is a one-shot climb-in, not a cycle")
	var sm := _state_machine(root)
	if sm:
		check(not sm.has_node("sit"),
			"the mech handover exists (docs/specs/pilot9-mech-mount.md) and is deliberately " +
			"animation-free: boarding is a cut, so sit_down stays imported and unwired")

# --- standing back up ------------------------------------------------------

# The 2026-09-06 bug: crouch once and pilot9 stood back up hunched forward, for good.
#
# An AnimationTree with `deterministic` off - which is how Real Controller ships it, and not
# Godot's own default - leaves a bone wherever the last clip that animated it put it, rather
# than returning it to rest, once no playing clip drives it any more. crouch_walk rotates
# UpperChest ~22 degrees and none of RC's 27 clips touch that bone, so the stand-up blended
# the crouch out of every bone the two share and stranded that one, for the life of the scene.
#
# Asserted as the invariant rather than as the flag: a clip animating a bone the others
# ignore is normal and unavoidable with mixed-source clips, so the blending has to be the
# kind that puts the bone back.
func test_no_clip_can_strand_a_bone_the_others_never_animate() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	if ap == null or at == null:
		fail("no AnimationPlayer or AnimationTree")
		return

	var clips: PackedStringArray = []
	for lib_name in ap.get_animation_library_list():
		for clip in ap.get_animation_library(lib_name).get_animation_list():
			clips.append(clip)
	var owners := {}          # "path|track type" -> how many clips animate it
	for clip in clips:
		var a := ap.get_animation(clip)
		for t in a.get_track_count():
			var key := "%s|%d" % [str(a.track_get_path(t)), a.track_get_type(t)]
			owners[key] = owners.get(key, 0) + 1

	var strandable: PackedStringArray = []
	for key in owners:
		if owners[key] < clips.size():
			strandable.append(key)
	strandable.sort()
	var shown := strandable.slice(0, 6)
	if strandable.size() > shown.size():
		shown.append("... and %d more" % (strandable.size() - shown.size()))
	check(at.deterministic or strandable.is_empty(),
		("AnimationTree.deterministic is off and %d tracks are missing from at least one " +
		"clip, so whichever clip owns one leaves that bone stuck where it left it - the " +
		"permanent forward tilt after a crouch. Turn it back on in " +
		"pilot9_build_scene.gd::_ensure_deterministic_blending(). Strandable: %s")
		% [strandable.size(), ", ".join(shown)])
