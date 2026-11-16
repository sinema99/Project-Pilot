extends "res://tests/test_case.gd"

# Covers pilot9's crouch: the C / controller-B toggle, the kneel and crouch-jog clips
# scripts/crouch_bake.gd generates (2026-11-15 - the Blender crouch_walk is scrapped), and the
# `crouch` state scripts/pilot9_build_scene.gd builds for them. docs/specs/pilot9-crouch-kneel.md.
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
const BAKE := preload("res://scripts/crouch_bake.gd")

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

# --- the generated clips ---------------------------------------------------

func _baked_names() -> Array:
	var names: Array = [BAKE.KNEEL]
	names.append_array(BAKE.JOGS.keys())
	return names

func test_the_blender_crouch_walk_is_gone() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	check(ap != null and not ap.has_animation(&"crouch_walk"),
		"crouch_walk is scrapped (user, 2026-11-15) - the builder should delete it from the library")
	check(not BUILDER.GLB_CLIPS.has("P_crouchwalk"), "P_crouchwalk is still lifted out of the GLB")

func test_the_generated_clips_are_in_the_library_and_loop() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	for name in _baked_names():
		check(ap.has_animation(name), "no '%s' in the library - _ensure_crouch_state did not run" % name)
		if ap.has_animation(name):
			eq(ap.get_animation(name).loop_mode, Animation.LOOP_LINEAR, "%s must loop" % name)
	for name in BAKE.JOGS:
		if ap.has_animation(name):
			approx(ap.get_animation(name).length, BAKE.CYCLE, 0.001,
				"%s must be one cycle long - the blend space keeps the four in step only if they match" % name)

# "Don't touch the upper body": the clips key nothing above the hips, and the state's filter is
# exactly the keyed bones, so the idle owns the spine, head and arms.
func test_the_clips_key_only_the_hips_and_legs() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skel := root.get_node_or_null("%GeneralSkeleton") as Skeleton3D
	for name in _baked_names():
		if not ap.has_animation(name):
			continue
		var a := ap.get_animation(name)
		var stray: PackedStringArray = []
		for t in a.get_track_count():
			var bone := str(a.track_get_path(t)).get_slice(":", 1)
			if not bone in BAKE.BONES or skel.find_bone(bone) < 0:
				stray.append(bone)
		check(stray.is_empty(), "%s keys bones outside the legs: %s" % [name, str(stray)])

func _pose_at(skel: Skeleton3D, a: Animation, t: float) -> void:
	skel.reset_bone_poses()
	for i in a.get_track_count():
		var bone := skel.find_bone(str(a.track_get_path(i)).get_slice(":", 1))
		if a.track_get_type(i) == Animation.TYPE_POSITION_3D:
			skel.set_bone_pose_position(bone, a.position_track_interpolate(i, t))
		else:
			skel.set_bone_pose_rotation(bone, a.rotation_track_interpolate(i, t))

func _global(skel: Skeleton3D, bone_name: String) -> Vector3:
	var i := skel.find_bone(bone_name)
	var xf := Transform3D()
	while i >= 0:
		xf = skel.get_bone_pose(i) * xf
		i = skel.get_bone_parent(i)
	return xf.origin

func test_the_kneel_is_right_knee_down_left_foot_forward() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skel := root.get_node_or_null("%GeneralSkeleton") as Skeleton3D
	if not ap.has_animation(BAKE.KNEEL):
		fail("no kneel clip")
		return
	var r := BAKE.rig(skel, ap.get_animation(&"idle"))
	_pose_at(skel, ap.get_animation(BAKE.KNEEL), 0.0)
	var r_knee := _global(skel, "RightLowerLeg")
	var l_knee := _global(skel, "LeftLowerLeg")
	var l_foot := _global(skel, "LeftFoot")
	approx(r_knee.y - r.ground, BAKE.KNEEL_KNEE_HEIGHT, 0.01, "the right knee is on the ground")
	approx(l_foot.y, r.ground, 0.01, "the left foot is planted")
	check(l_foot.z > r_knee.z + 0.5, "the left foot is ahead of the right knee")
	check(l_knee.y > 0.35, "the front knee is up (%.2f)" % l_knee.y)
	# Rev 2 (2026-11-15, the user's Arma reference): a tall kneel - the rear knee almost straight
	# under its hip, the legs close together, not the old splayed low tripod.
	var r_hip := _global(skel, "RightUpperLeg")
	check(absf(r_hip.z - r_knee.z) < 0.15, "the right knee is under its hip (%.2f)" % (r_hip.z - r_knee.z))
	check(absf(r_knee.x - l_foot.x) < 0.25, "the legs stay close together (%.2f)" % absf(r_knee.x - l_foot.x))
	check(r.hips_pos.y - _global(skel, "Hips").y < JOG_DEPTH_FLOOR,
		"the kneel stands taller than the jog")

const JOG_DEPTH_FLOOR := 0.36

# The knee scrapes the floor if the jog is too deep for the rig (found at 0.40, 2026-11-15).
func test_the_jog_keeps_the_knees_and_feet_off_the_floor() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skel := root.get_node_or_null("%GeneralSkeleton") as Skeleton3D
	var r := BAKE.rig(skel, ap.get_animation(&"idle"))
	for name in BAKE.JOGS:
		if not ap.has_animation(name):
			fail("no %s" % name)
			continue
		var a := ap.get_animation(name)
		var lowest_knee := INF
		var lowest_foot := INF
		for i in 31:
			_pose_at(skel, a, a.length * i / 30.0)
			for side in ["Left", "Right"]:
				lowest_knee = minf(lowest_knee, _global(skel, side + "LowerLeg").y)
				lowest_foot = minf(lowest_foot, _global(skel, side + "Foot").y)
		check(lowest_knee - r.ground > 0.1, "%s folds a knee into the floor (%.3f)" % [name, lowest_knee])
		check(lowest_foot > r.ground - 0.02, "%s sinks a foot (%.3f)" % [name, lowest_foot])

# Strafing crouched: the planted foot slides back under him at the design speed, so a TimeScale of
# ground speed / DESIGN_SPEED keeps it still on the ground.
func test_a_planted_foot_moves_at_the_design_speed() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skel := root.get_node_or_null("%GeneralSkeleton") as Skeleton3D
	var a := ap.get_animation(&"crouch_jog_forward")
	var t0 := BAKE.CYCLE * BAKE.STANCE * 0.25
	var t1 := BAKE.CYCLE * BAKE.STANCE * 0.5
	_pose_at(skel, a, t0)
	var z0 := _global(skel, "LeftFoot").z
	_pose_at(skel, a, t1)
	var z1 := _global(skel, "LeftFoot").z
	approx((z0 - z1) / (t1 - t0), BAKE.DESIGN_SPEED, 0.2, "the planted left foot's speed back under him")

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

func test_the_crouch_state_is_legs_over_the_idle() -> void:
	var root := _scene()
	var sm := _state_machine(root) if root != null else null
	if sm == null or not sm.has_node("crouch"):
		fail("no crouch state to inspect")
		return
	var bt := sm.get_node("crouch") as AnimationNodeBlendTree
	var idle := bt.get_node("Idle") as AnimationNodeAnimation
	check(idle != null and idle.animation == &"idle", "the crouch's upper body is not the standing idle")
	var legs := bt.get_node(BUILDER.CROUCH_LEGS_NODE) as AnimationNodeBlend2
	check(legs != null and legs.filter_enabled, "the legs layer is not a filtered Blend2")
	if legs:
		for b in BAKE.BONES:
			check(legs.is_path_filtered(NodePath(BAKE.PREFIX + b)), "%s is not in the legs filter" % b)
		check(not legs.is_path_filtered(NodePath(BAKE.PREFIX + "Spine")), "the spine must stay the idle's")
	var jog := bt.get_node(BUILDER.CROUCH_JOG_NODE) as AnimationNodeBlendSpace2D
	check(jog != null and jog.get_blend_point_count() == 4, "the jog is not a four-way blend space")
	check(bt.get_node(BUILDER.CROUCH_SCALE_NODE) is AnimationNodeTimeScale, "no jog TimeScale")
	check(bt.get_node(BUILDER.CROUCH_MOVE_NODE) is AnimationNodeBlend2, "no kneel/jog Blend2")

# The seam that fails silently: pilot9_animation.gd writes hard-coded parameter paths every
# frame, and AnimationTree.set() on a path that does not exist is a no-op, not an error.
func test_the_parameter_paths_match_what_the_feed_writes() -> void:
	var st := BUILDER.CROUCH_STATE
	eq(ANIM_SCRIPT.CROUCH_LEGS, "parameters/%s/%s/blend_amount" % [st, BUILDER.CROUCH_LEGS_NODE], "legs path")
	eq(ANIM_SCRIPT.CROUCH_MOVE, "parameters/%s/%s/blend_amount" % [st, BUILDER.CROUCH_MOVE_NODE], "move path")
	eq(ANIM_SCRIPT.CROUCH_JOG, "parameters/%s/%s/blend_position" % [st, BUILDER.CROUCH_JOG_NODE], "jog path")
	eq(ANIM_SCRIPT.CROUCH_SCALE, "parameters/%s/%s/scale" % [st, BUILDER.CROUCH_SCALE_NODE], "scale path")

func test_the_tree_actually_exposes_those_parameters() -> void:
	var root := _scene()
	var at := root.get_node_or_null("AnimationTree") as AnimationTree if root != null else null
	if at == null:
		fail("no AnimationTree")
		return
	var names := {}
	for p in at.get_property_list():
		names[String(p.name)] = true
	for path in [ANIM_SCRIPT.CROUCH_LEGS, ANIM_SCRIPT.CROUCH_MOVE, ANIM_SCRIPT.CROUCH_JOG, ANIM_SCRIPT.CROUCH_SCALE]:
		check(names.has(path), "the AnimationTree exposes no '%s'" % path)

func test_crouched_he_strafes_like_he_does_standing() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.is_crouching = true
	check(not root._faces_travel(), "the crouch is four-way now - it must not turn him to face travel")

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
	if props.has("crouch_speed") and props.has("speed"):
		# 2026-11-15 rev 4: the crouch walks at walking pace (the DayZ crouch walk).
		check(is_equal_approx(root.get("crouch_speed"), root.get("walk_speed")),
			"crouch_speed (%s) should match the walk speed (%s)"
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
