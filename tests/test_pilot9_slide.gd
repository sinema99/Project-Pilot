extends "res://tests/test_case.gd"

# Covers pilot9's slide: the two clips that arrived in the 2026-09-06 PILOT9.glb export,
# the root motion the builder takes apart into a curve, the `slide` state, and the
# `climb_up` clip that is imported and deliberately left unwired.
#
# The slide is unusual among his moves in that no number in scripts/pilot9.gd says how fast
# it goes. The clip's own Hips travel is baked to `slide_motion` by
# pilot9_build_scene.gd::_ensure_slide_motion() and differentiated at runtime, so most of
# what is worth asserting is that the bake and the lock both happened - a curve that failed
# to land leaves a slide that plays the animation and does not move, and a lock that failed
# leaves a mesh that flies 7.8 m backwards through the exit cross-fade.
#
# See docs/specs/pilot9-slide.md and docs/reimport.md.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const BUILDER := preload("res://scripts/pilot9_build_scene.gd")

# From the 2026-09-06 17:58 PILOT9.glb export: the Blender action "P.slide" runs 1.550 s
# (93 frames) and its hips travel 7.796 m forward. The builder cuts it to its first 75
# frames, so what pilot9.tscn actually carries is the shortened clip - 1.250 s and the
# 6.462 m the hips had reached by then. Asserted loosely: the user re-authors these clips,
# and a changed distance is correct rather than broken. A collapse to zero is not.
const SLIDE_CLIP_LENGTH := 1.250
const SLIDE_CLIP_DISTANCE := 6.462
const SLIDE_SOURCE_LENGTH := 1.550
const CLIMB_CLIP_LENGTH := 1.150

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

# The controller's @onready references, resolved by hand - nothing here enters the tree, so
# _ready never runs and they are null until this does. Only the steering tests need them.
func _rig(root: Node) -> void:
	root.camera_pivot = root.get_node("CameraPivot")
	root.character = root.get_node("character")

# The controller state _handle_movement_input would have produced for this stick, at camera
# yaw 0 so a stick vector and a world direction are the same thing.
func _set_stick(root: Node, stick: Vector2) -> void:
	root.camera_pivot.rotation.y = 0.0
	root.input_dir = stick
	root.input_strength = minf(stick.length(), 1.0)
	root.direction = Vector3(stick.x, 0.0, stick.y).normalized()

func _heading_angle(root: Node) -> float:
	var d: Vector3 = root.get("_slide_direction")
	return atan2(d.x, d.z)

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

# The Hips track is where Mixamo puts locomotion, and where the builder both reads the
# travel from and locks it out. Returns [] if the clip or the track is missing.
func _hips_z(root: Node, clip: String) -> PackedFloat32Array:
	var out: PackedFloat32Array = []
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(clip):
		return out
	var a := ap.get_animation(clip)
	var track := a.find_track(NodePath(BUILDER.SLIDE_MOTION_TRACK), Animation.TYPE_POSITION_3D)
	if track == -1:
		return out
	for k in a.track_get_key_count(track):
		out.append((a.track_get_key_value(track, k) as Vector3).z)
	return out

# --- the clips came across from the GLB ------------------------------------

func test_both_new_clips_are_in_the_library() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		fail("no AnimationPlayer")
		return
	check(ap.has_animation(BUILDER.SLIDE_CLIP),
		"no 'slide' in the library - pilot9_build_scene.gd::_ensure_glb_clips did not run, " +
		"or the Blender action is no longer named P.slide (see GLB_CLIPS)")
	check(ap.has_animation(BUILDER.CLIMB_CLIP),
		"no 'climb_up' in the library - the Blender action P.climbing did not come across")

func test_the_clips_are_one_shots_of_a_plausible_length() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(BUILDER.SLIDE_CLIP) or not ap.has_animation(BUILDER.CLIMB_CLIP):
		fail("the slide or climb clip is missing")
		return

	var slide := ap.get_animation(BUILDER.SLIDE_CLIP)
	check(slide.length > 0.1,
		"slide is %.3fs - a zero-length clip is the documented import failure" % slide.length)
	approx(slide.length, SLIDE_CLIP_LENGTH, 0.5,
		"slide's duration moved a long way from the export it was wired against")
	# Neither is a cycle. A slide left on LOOP_LINEAR would restart mid-move rather than
	# hand back to Locomotion, and it would re-run the distance curve with it.
	eq(slide.loop_mode, Animation.LOOP_NONE, "slide is a one-shot verb, not a cycle")

	var climb := ap.get_animation(BUILDER.CLIMB_CLIP)
	approx(climb.length, CLIMB_CLIP_LENGTH, 0.5, "climb_up's duration moved a long way")
	eq(climb.loop_mode, Animation.LOOP_NONE, "climb_up is a one-shot mantle, not a cycle")

# The trim is a cut to Animation.length and nothing else, which makes it exactly the kind of
# change that can silently not happen: the keys stay put either way, so a clip that failed to
# be shortened still plays, still moves him, and only feels wrong. Measured against the raw
# GLB rather than a literal, so a re-export moves both sides together.
func test_the_slide_is_cut_to_its_first_75_frames() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(BUILDER.SLIDE_CLIP):
		fail("no slide clip to measure")
		return
	var trimmed := ap.get_animation(BUILDER.SLIDE_CLIP).length

	var src := (load("res://assets/pilot9.glb") as PackedScene).instantiate()
	_instances.append(src)
	var src_ap := src.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if src_ap == null or not src_ap.has_animation("P_slide"):
		fail("assets/pilot9.glb carries no P_slide to compare the trim against")
		return
	var authored := src_ap.get_animation("P_slide").length

	approx(authored, SLIDE_SOURCE_LENGTH, 0.5,
		"the authored P.slide moved a long way; the 75-frame cut was chosen against 93 frames")
	check(trimmed < authored - 0.01,
		("the slide in the library is %.3fs and the GLB's is %.3fs - the cut did not " +
		"happen. _trim_slide() only moves Animation.length, so nothing else looks wrong")
		% [trimmed, authored])
	approx(trimmed, float(BUILDER.SLIDE_KEEP_FRAMES) / BUILDER.SLIDE_SOURCE_FPS, 0.001,
		"the trimmed length is not SLIDE_KEEP_FRAMES at SLIDE_SOURCE_FPS")

# The trap _trim_slide() exists to avoid, asserted from the other side. Godot's interpolation
# ignores keys past Animation.length rather than clamping to it, so cutting by moving the
# length alone leaves every track holding its last in-range key - here from 1.200 s to
# 1.250 s, a frozen tail on a cut made specifically to remove one. It is invisible in the
# scene file and it flattens the baked curve with it, which stops the body dead just as his
# feet come down. Every track must therefore end ON the length, not before it.
func test_the_trimmed_slide_animates_all_the_way_to_its_new_end() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(BUILDER.SLIDE_CLIP):
		fail("no slide clip to measure")
		return
	var a := ap.get_animation(BUILDER.SLIDE_CLIP)

	var worst := 0.0
	var worst_track := -1
	for i in a.get_track_count():
		var n := a.track_get_key_count(i)
		if n == 0:
			continue
		var gap: float = a.length - a.track_get_key_time(i, n - 1)
		if gap > worst:
			worst = gap
			worst_track = i
	check(worst < 0.001,
		("track %d's last key is %.4fs before the clip ends - _trim_slide() dropped keys " +
		"past the cut without re-keying the boundary, so the slide freezes on its last pose")
		% [worst_track, worst])

	# And the same failure read off the curve the body is actually driven by: a flat last
	# segment is a slide that stops before the animation does.
	var curve: Curve = root.get("slide_motion")
	if curve == null:
		fail("no baked slide_motion to check for a flat tail")
		return
	check(curve.sample(1.0) - curve.sample(0.96) > 0.001,
		"slide_motion is flat over its last 4%% - the body stops while the clip is still " +
		"running him out, which is the frozen-tail failure showing up in the motion")

func test_slide_tracks_all_bind_to_real_bones() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skel := root.get_node_or_null("%GeneralSkeleton") as Skeleton3D
	if ap == null or skel == null or not ap.has_animation(BUILDER.SLIDE_CLIP):
		fail("slide or the skeleton is missing")
		return
	var a := ap.get_animation(BUILDER.SLIDE_CLIP)
	check(a.get_track_count() > 0, "slide has no tracks at all")
	var broken: PackedStringArray = []
	for t in a.get_track_count():
		# Same check the crouch clip gets: a GLB clip only plays unedited because the
		# retargeter rewrote its paths onto the unique-named skeleton RC's clips address.
		var path := str(a.track_get_path(t))
		if not path.begins_with("%GeneralSkeleton:"):
			broken.append("path '%s' lost its unique-name prefix" % path)
			continue
		var bone := path.get_slice(":", 1)
		if bone != "" and skel.find_bone(bone) == -1:
			broken.append(bone)
	check(broken.is_empty(),
		"slide tracks that do not land on the retargeted rig: %s" % str(broken))

# --- the root motion was taken out of the pose and put in the curve --------

# The failure this is pointed at is not subtle in game but is invisible in the scene text:
# a slide clip that kept its 7.8 m of Hips travel plays fine in isolation and drags the
# mesh backwards through the exit cross-fade, because a root-motion track cannot be blended.
func test_the_slide_pose_is_locked_in_place() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var z := _hips_z(root, BUILDER.SLIDE_CLIP)
	check(not z.is_empty(),
		"slide has no %s position track - _ensure_slide_motion() could not have run"
		% BUILDER.SLIDE_MOTION_TRACK)
	if z.is_empty():
		return
	var lo := z[0]
	var hi := z[0]
	for v in z:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	check(hi - lo < 0.01,
		("slide's hips still travel %.3f m in Z. _ensure_slide_motion() did not lock the " +
		"clip, so the body will be driven by the curve AND the mesh by the clip - double " +
		"the distance, and a mesh that snaps back over the exit cross-fade.") % (hi - lo))

# The other half of the same operation, and the one that would strand the feature: locking
# the clip without baking the curve leaves a slide that animates perfectly and does not move.
func test_the_travel_curve_was_baked_onto_the_controller() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var curve := root.get("slide_motion") as Curve
	check(curve != null,
		"slide_motion is null - the slide would play its animation and travel nowhere. " +
		"Object.set() drops an unknown property silently, so check the name still matches " +
		"pilot9_build_scene.gd::SLIDE_BAKED")
	if curve == null:
		return
	check(curve.point_count > 8,
		"slide_motion has only %d points - too coarse to differentiate smoothly" % curve.point_count)
	approx(curve.sample(0.0), 0.0, 0.001, "slide_motion must start at zero distance")
	approx(curve.sample(1.0), 1.0, 0.001,
		"slide_motion must end at the full distance - it is normalised, and slide_distance " +
		"is the metres it is scaled by")

func test_the_travel_curve_never_goes_backwards() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var curve := root.get("slide_motion") as Curve
	if curve == null:
		fail("no slide_motion curve to inspect")
		return
	# _apply_slide_velocity differentiates this, so a dip is a frame of reverse velocity -
	# he would twitch backwards mid-slide. Bezier tangents overshoot exactly like that,
	# which is why the builder sets every point to TANGENT_LINEAR.
	var worst := 0.0
	var prev := curve.sample(0.0)
	for i in range(1, 129):
		var v := curve.sample(float(i) / 128.0)
		worst = minf(worst, v - prev)
		prev = v
	check(worst > -0.0001,
		("slide_motion goes backwards by %.5f between samples - one frame of reverse " +
		"velocity mid-slide. Are the curve's points still TANGENT_LINEAR?") % -worst)

func test_the_baked_duration_and_distance_match_the_clip() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(BUILDER.SLIDE_CLIP):
		fail("no slide clip to compare against")
		return
	var duration: float = root.get("slide_duration")
	var distance: float = root.get("slide_distance")
	approx(duration, ap.get_animation(BUILDER.SLIDE_CLIP).length, 0.001,
		"slide_duration and the clip disagree. They are separate clocks - the state machine " +
		"plays the clip and _physics_process runs the curve - and this is the only thing " +
		"holding them together")
	approx(distance, SLIDE_CLIP_DISTANCE, 2.0,
		"slide_distance moved a long way from the export the feel was tuned against; " +
		"re-check the Blender action (and slide_scale, if it was tuned)")
	check(distance > 0.5,
		("slide_distance is %.3f m - the clip was exported In Place and there is no travel " +
		"left to drive the body with") % distance)

# The climb's own root motion used to be asserted here, still intact, because the mantle
# that would consume it did not exist. It does now, and climb_up is locked on two axes -
# the inverse assertion lives in tests/test_pilot9_climb.gd.

# --- the state machine -----------------------------------------------------

func test_state_machine_has_a_slide_state_playing_the_slide_clip() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no AnimationNodeStateMachine on the AnimationTree")
		return
	check(sm.has_node(BUILDER.SLIDE_STATE), "the locomotion state machine has no 'slide' state")
	if not sm.has_node(BUILDER.SLIDE_STATE):
		return
	# A plain animation node, not the crouch's blend tree: a TimeScale here would advance the
	# clip at a rate the distance curve knows nothing about, and the two clocks would part
	# company with nothing in the log.
	var node := sm.get_node(BUILDER.SLIDE_STATE)
	var clip := node as AnimationNodeAnimation
	check(clip != null,
		"the slide state is a %s, not a plain AnimationNodeAnimation - if that is on " % node.get_class() +
		"purpose, check nothing in it rescales time (see docs/specs/pilot9-slide.md risk 1)")
	if clip:
		eq(str(clip.animation), str(BUILDER.SLIDE_CLIP), "the slide state plays the wrong clip")

func test_slide_is_entered_and_left_on_is_sliding() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	var into := _transition(sm, "Locomotion", "slide")
	check(into != null, "no Locomotion -> slide transition")
	if into:
		eq(into.advance_expression, "is_sliding", "Locomotion -> slide fires on the wrong expression")
		eq(into.advance_mode, AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO,
			"Locomotion -> slide must advance automatically; nothing calls travel() for it")
	var out := _transition(sm, "slide", "Locomotion")
	check(out != null, "no slide -> Locomotion transition - the slide would be a one-way trip")
	if out:
		eq(out.advance_expression, "not is_sliding", "slide -> Locomotion fires on the wrong expression")

# Same shape of bug the crouch had: cancelling into a jump clears is_sliding on the frame it
# launches, so both exits are eligible at once and the leap has to outrank the stand-up.
func test_slide_can_be_jumped_out_of_and_fallen_out_of() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	var to_jump := _transition(sm, "slide", "jump")
	check(to_jump != null, "no slide -> jump transition - the slide could not be cancelled")
	var to_fall := _transition(sm, "slide", "fall")
	check(to_fall != null, "no slide -> fall transition - sliding off a ledge would not fall")
	var to_loco := _transition(sm, "slide", "Locomotion")
	if to_jump and to_loco:
		check(to_jump.priority < to_loco.priority,
			("slide -> jump must outrank slide -> Locomotion (priority %d vs %d): the jump " +
			"clears is_sliding on the same frame it launches, so both are eligible and the " +
			"leap would play as a stand-up") % [to_jump.priority, to_loco.priority])

# The assertion that climb_up stayed out of the state machine used to sit here. The map has
# a ledge now and the `climb` state is built - see tests/test_pilot9_climb.gd.

# --- the controller side ---------------------------------------------------

# is_sliding is read by the tree through advance_expression, not by code a rename would
# carry along: an expression naming a property that does not exist simply never fires.
func test_the_controller_exposes_the_slide_properties() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var props := {}
	for p in root.get_property_list():
		props[String(p.name)] = true
	check(props.has("is_sliding"),
		"scripts/pilot9.gd has no 'is_sliding' - every slide advance_expression silently never fires")
	check(props.has("can_slide"), "scripts/pilot9.gd has no 'can_slide'")
	check(props.has("slide_scale"), "scripts/pilot9.gd has no 'slide_scale' - the tuning dial")
	check(props.has("slide_cooldown"), "scripts/pilot9.gd has no 'slide_cooldown'")
	if props.has("is_sliding"):
		check(root.get("is_sliding") == false, "pilot9 must not start mid-slide")
	if props.has("slide_cooldown"):
		check(root.get("slide_cooldown") > 0.0,
			"slide_cooldown is 0 - sprint on and crouch tapped would re-enter the slide " +
			"on the frame it leaves and he would never stand up")

# The dial the user tunes on play. The builder writes slide_motion/_duration/_distance on
# every sync and must not write this one, or a tuned value is lost on the next re-export.
func test_slide_scale_is_not_a_baked_property() -> void:
	check(not BUILDER.SLIDE_BAKED.has("slide_scale"),
		"slide_scale is in SLIDE_BAKED, so pilot9_build_scene.gd overwrites it on every " +
		"sync - it is the one slide value meant to survive a rig swap")

# --- the motion the curve actually produces --------------------------------

# Integrates _apply_slide_velocity() over a whole slide, off the tree, and demands the
# distance come back out. This is the one test that exercises the differentiation rather
# than the bake: the curve can be perfect and a factor dropped in that function still
# leaves him travelling the wrong distance at plausible-looking speeds.
func _integrate_slide(root: Node, steps: int) -> Dictionary:
	root.set("_slide_direction", Vector3(0.0, 0.0, 1.0))
	root.set("_slide_time", 0.0)
	root.set("is_sliding", true)
	var duration: float = root.get("slide_duration")
	var delta := duration / float(steps)
	var travelled := 0.0
	var peak := 0.0
	for i in steps:
		root.call("_apply_slide_velocity", delta)
		var speed: float = (root.get("velocity") as Vector3).z
		travelled += speed * delta
		peak = maxf(peak, speed)
	return {"travelled": travelled, "peak": peak}

func test_the_slide_travels_exactly_the_distance_it_baked() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	if float(root.get("slide_duration")) <= 0.0:
		fail("no baked slide to integrate")
		return
	var result := _integrate_slide(root, 200)
	approx(result["travelled"], float(root.get("slide_distance")), 0.05,
		"integrating _apply_slide_velocity over the whole clip does not come back to " +
		"slide_distance - the curve is differentiated wrong, or a factor was dropped")
	# The run-in is the fastest part of the clip and the window where his feet are planted,
	# so this is also the number that has to match a sprint for the entry not to skate.
	check(result["peak"] > 6.0,
		"the slide peaks at only %.2f m/s - the run-in should open near a sprint" % result["peak"])

func test_slide_scale_stretches_the_distance() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	if float(root.get("slide_duration")) <= 0.0:
		fail("no baked slide to integrate")
		return
	var base := _integrate_slide(root, 100)["travelled"] as float
	root.set("slide_scale", 2.0)
	var doubled := _integrate_slide(root, 100)["travelled"] as float
	approx(doubled, base * 2.0, 0.05,
		"slide_scale does not scale the distance - it is the only dial the user has, and " +
		"the builder overwrites everything else on the next sync")

# The slide runs at the clip's own speed, which opens around 8 m/s. Anything the player can
# reach on foot has to be slower, or the slide is a deceleration.
func test_the_slide_is_faster_than_running() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var duration: float = root.get("slide_duration")
	var distance: float = root.get("slide_distance")
	if duration <= 0.0:
		fail("slide_duration is 0 - nothing to compare")
		return
	var average := distance / duration
	check(average > float(root.get("speed")),
		"the slide averages %.2f m/s, slower than his run at %s - it would read as tripping"
		% [average, root.get("speed")])


# --- steering ----------------------------------------------------------------
#
# The slide used to run on a heading locked at entry. It steers now: a 1.25 s move the player
# aims blind reads as the controls having been taken away, not as a bad call. What these
# guard is the invariant that replaced the lock - one heading, turned by the stick, with the
# mesh welded to it - because the failure mode of getting it wrong is skate, which is a thing
# you see rather than a thing that errors.

# The turn rate is the point: "normally" means the number a run turns at, not a slide-specific
# one. Run the two paths side by side off the same start angle and demand the same answer.
func test_a_slide_turns_at_exactly_the_running_turn_rate() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_rig(root)
	var start := 0.0
	var steps := 12
	var delta := 1.0 / 60.0
	_set_stick(root, Vector2(1, 0))          # hard right of a body facing +Z

	root.face_travel_direction = true
	root.is_sliding = false
	root.character.rotation.y = start
	for i in steps:
		root._handle_character_rotation(delta)
	var running: float = root.character.rotation.y

	root.is_sliding = true
	root.set("_slide_direction", Vector3(sin(start), 0.0, cos(start)))
	for i in steps:
		root._steer_slide(delta)
	var sliding := _heading_angle(root)

	approx(absf(angle_difference(sliding, running)), 0.0, 0.0001,
		("after %d frames the slide has turned to %f and a run to %f. They share " +
		"rotation_speed and must share the lerp: a second lerp anywhere in the slide path " +
		"halves the turn rate, which is the difference between steering and drifting")
		% [steps, sliding, running])

func test_a_slide_steers_all_the_way_to_the_stick() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_rig(root)
	root.is_sliding = true
	root.set("_slide_direction", Vector3(0.0, 0.0, 1.0))
	_set_stick(root, Vector2(-1, 0))
	for i in 300:
		root._steer_slide(1.0 / 60.0)
	approx(absf(angle_difference(_heading_angle(root), atan2(root.direction.x, root.direction.z))),
		0.0, 0.001,
		"a held stick should bring the slide all the way round onto it, not part of the way")
	approx((root.get("_slide_direction") as Vector3).length(), 1.0, 0.001,
		"the heading has to stay a unit vector - _apply_slide_velocity() multiplies a speed " +
		"by it, so a short one is a slow slide and a long one a fast one")

# Released stick, straight line. This is also what keeps the run-out from swinging: the last
# frames of the clip are planted feet, and a heading that drifted there would skate.
func test_a_slide_with_no_input_holds_its_line() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_rig(root)
	root.is_sliding = true
	var held := Vector3(sin(0.9), 0.0, cos(0.9))
	root.set("_slide_direction", held)
	_set_stick(root, Vector2.ZERO)
	for i in 60:
		root._steer_slide(1.0 / 60.0)
	approx(absf(angle_difference(_heading_angle(root), 0.9)), 0.0, 0.0001,
		"a centred stick must leave the heading alone - a slide is not steered back to " +
		"anything when the player lets go")

# The whole reason the mesh is written rather than lerped. _apply_slide_velocity() drives the
# body along _slide_direction; if the mesh is anywhere else, that gap is visible skate for as
# long as his feet are planted.
func test_the_mesh_is_welded_to_the_slide_heading() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_rig(root)
	root.is_sliding = true
	root.character.rotation.y = 0.0            # deliberately nowhere near the heading
	root.set("_slide_direction", Vector3(sin(2.4), 0.0, cos(2.4)))
	_set_stick(root, Vector2(1, 0))
	for i in 20:
		root._steer_slide(1.0 / 60.0)
		root._handle_character_rotation(1.0 / 60.0)
		var gap := absf(angle_difference(root.character.rotation.y, _heading_angle(root)))
		if gap > 0.0001:
			fail("frame %d: the mesh is %f rad off the heading the body is travelling on" % [i, gap])
			checks += 1
			return
	checks += 1

# Entering mid-turn, the heading is taken off the mesh rather than off the stick - otherwise
# the weld above snaps his body round on the first frame of the slide.
func test_a_slide_leaves_along_the_line_he_is_visibly_on() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_rig(root)
	root.character.rotation.y = 1.1            # mid-turn: facing here...
	_set_stick(root, Vector2(1, 0))            # ...while the stick asks for +X
	root._start_slide(root.direction)
	approx(absf(angle_difference(_heading_angle(root), 1.1)), 0.0, 0.0001,
		"the slide should start on the facing, not the stick - taking the stick's heading " +
		"pops the mesh round on the entry frame, because the mesh follows the heading")
	check(not root.is_crouching, "starting a slide still has to clear the crouch")
