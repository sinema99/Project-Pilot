extends "res://tests/test_case.gd"

# Covers pilot9's ledge mantle: the bake that takes climb_up's root motion apart, the two
# contact points the snaps are measured between, the `climb` state, and the detection
# predicate. See docs/specs/pilot9-climb.md.
#
# The mantle is unusual among his moves in that nothing about it is a physics simulation -
# the body is written onto a path with its collision shape off - so almost everything worth
# asserting is that a number landed where the runtime expects to read it. A curve that
# failed to bake leaves a mantle that plays the animation and travels nowhere; a contact
# offset that failed to bake leaves him grabbing at air a metre from the wall.
#
# The raycasts themselves are not exercised here. _evaluate_ledge() is deliberately split
# out of _probe_ledge() so the whole decision - band, slope, headroom - can be tested with
# mock hit dictionaries and no physics world, which is what the tests below feed it.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const BUILDER := preload("res://scripts/pilot9_build_scene.gd")

# From the 2026-09-06 17:58 PILOT9.glb export. The Blender action "P.climbing" runs 1.150 s
# and its Hips walk +1.890 m up / +0.514 m forward once motion_scale is applied. What the
# controller is actually driven by is measured between the clip's own contact poses instead
# (see _ensure_climb_motion): 1.324 m up, 1.104 m forward. Asserted loosely - the user
# re-authors these clips, and a changed distance is correct rather than broken.
const CLIMB_CLIP_LENGTH := 1.150
const CLIMB_RISE := 1.324
const CLIMB_REACH := 1.104
const CLIMB_INSET := 0.514

var _pilot: Node = null

# Unlike the other pilot9 suites, this one puts the scene IN the tree. The mantle is written
# in global_position and gated on is_on_floor(), and both of those are errors on a
# CharacterBody3D that has no tree above it. Nothing pumps the tree in a --script run, so
# the node gets its _ready and no frames - which is all these tests want.
#
# ONE instance, reused and reset per test. An in-tree pilot9 scene registers physics and
# render-server RIDs that a --script run never cleans up; standing up a fresh one for each
# of the ~20 tests here piles enough of them to segfault the engine on exit (all checks
# still pass, but run_tests.gd returns 139). Sharing one keeps the leak to a single scene.
func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	# Back to a known state - one shared instance means whatever the last test left set
	# (is_climbing, can_climb, a buffered press) would otherwise bleed into the next.
	_pilot.is_climbing = false
	_pilot.can_climb = true
	_pilot.frozen = false
	_pilot.is_sliding = false
	_pilot._slide_buffered = false
	_pilot._climb_jump_buffered = false
	_pilot._climb_time = 0.0
	_pilot._air_jumps_left = 0
	_pilot.velocity = Vector3.ZERO
	_pilot.input_dir = Vector2.ZERO
	_pilot.direction = Vector3.ZERO
	_pilot.global_position = Vector3.ZERO
	if _pilot.has_node("character"):
		_pilot.get_node("character").rotation = Vector3.ZERO
	return _pilot

# `character` resolves through @onready now that the scene enters the tree, so this only
# exists to keep the intent of each test visible at its call site.
func _rig(root: Node) -> void:
	root.character = root.get_node("character")

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

# Every key on climb_up's Hips position track, one axis at a time. The bake reads this
# track, then locks two of its three axes, so this is where both halves are visible.
func _hips_axis(root: Node, axis: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = []
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(BUILDER.CLIMB_CLIP):
		return out
	var a := ap.get_animation(BUILDER.CLIMB_CLIP)
	var track := a.find_track(NodePath(BUILDER.SLIDE_MOTION_TRACK), Animation.TYPE_POSITION_3D)
	if track == -1:
		return out
	for k in a.track_get_key_count(track):
		out.append((a.track_get_key_value(track, k) as Vector3)[axis])
	return out

func _span(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var lo := values[0]
	var hi := values[0]
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo

# A mock raycast result in the shape intersect_ray() returns.
func _hit(position: Vector3, normal: Vector3) -> Dictionary:
	return {"position": position, "normal": normal}

# --- the clip --------------------------------------------------------------

func test_the_climb_clip_is_a_one_shot_of_a_plausible_length() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(BUILDER.CLIMB_CLIP):
		fail("no 'climb_up' in the library - the Blender action P.climbing did not come across")
		return
	var a := ap.get_animation(BUILDER.CLIMB_CLIP)
	approx(a.length, CLIMB_CLIP_LENGTH, 0.5, "climb_up's duration moved a long way")
	eq(a.loop_mode, Animation.LOOP_NONE, "climb_up is a one-shot mantle, not a cycle")

func test_climb_tracks_all_bind_to_real_bones() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var skel := root.get_node_or_null("%GeneralSkeleton") as Skeleton3D
	if ap == null or skel == null or not ap.has_animation(BUILDER.CLIMB_CLIP):
		fail("climb_up or the skeleton is missing")
		return
	var a := ap.get_animation(BUILDER.CLIMB_CLIP)
	check(a.get_track_count() > 0, "climb_up has no tracks at all")
	var broken: PackedStringArray = []
	for t in a.get_track_count():
		# A GLB clip only plays unedited because the retargeter rewrote its paths onto the
		# unique-named skeleton RC's own clips address.
		var path := str(a.track_get_path(t))
		if not path.begins_with("%GeneralSkeleton:"):
			broken.append("path '%s' lost its unique-name prefix" % path)
			continue
		var bone := path.get_slice(":", 1)
		if bone != "" and skel.find_bone(bone) == -1:
			broken.append(bone)
	check(broken.is_empty(),
		"climb_up tracks that do not land on the retargeted rig: %s" % str(broken))

# The inverse of the old test_the_climb_clip_keeps_its_root_motion in the slide suite. The
# clip's travel is the mantle, but it cannot stay in the clip: a root-motion track cannot be
# cross-faded, so a Hips left at +1.89 m would drag the mesh down through the exit fade. Two
# axes locked, not the slide's one.
func test_the_climb_pose_is_locked_in_place_on_both_axes() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var y := _hips_axis(root, Vector3.AXIS_Y)
	var z := _hips_axis(root, Vector3.AXIS_Z)
	check(not y.is_empty(),
		"climb_up has no %s position track - _ensure_climb_motion() could not have run"
		% BUILDER.SLIDE_MOTION_TRACK)
	if y.is_empty():
		return
	check(_span(y) < 0.01,
		("climb_up's hips still rise %.3f m. _ensure_climb_motion() did not lock the clip, " +
		"so the body would be driven by the curve AND the mesh by the clip - double the " +
		"rise, and a mesh that snaps back over the exit cross-fade.") % _span(y))
	check(_span(z) < 0.01,
		"climb_up's hips still travel %.3f m forward - the Z half of the lock did not happen"
		% _span(z))

# The other half of the lock, from the other side: X carries the lateral sway on the pull-up
# and locking it too would flatten the clip into a lift on rails.
func test_the_climb_keeps_its_lateral_sway() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var x := _hips_axis(root, Vector3.AXIS_X)
	if x.is_empty():
		fail("climb_up has no hips position track")
		return
	check(_span(x) > 0.01,
		"climb_up's hips no longer sway sideways at all - the lock took X with Y and Z, " +
		"and X is the one axis that is meant to survive it")

# --- the bake --------------------------------------------------------------

func test_the_climb_curves_were_baked_onto_the_controller() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var cy := root.get("climb_motion_y") as Curve
	var cz := root.get("climb_motion_z") as Curve
	check(cy != null and cz != null,
		"climb_motion_y/_z are null - the mantle would play its animation and travel " +
		"nowhere. Object.set() drops an unknown property silently, so check the names " +
		"still match pilot9_build_scene.gd::CLIMB_BAKED")
	if cy == null or cz == null:
		return
	check(cy.point_count > 8,
		"climb_motion_y has only %d points - too coarse for a smooth arc" % cy.point_count)
	approx(cy.sample(0.0), 0.0, 0.001, "climb_motion_y must start at zero rise")
	approx(cy.sample(1.0), 1.0, 0.001,
		"climb_motion_y must end at the full rise - it is normalised, and the metres are " +
		"climb_rise")
	approx(cz.sample(0.0), 0.0, 0.001, "climb_motion_z must start at zero reach")
	approx(cz.sample(1.0), 1.0, 0.001, "climb_motion_z must end at the full reach")

# The two excursions past 0..1 that make this an arc rather than a lift, and the exact thing
# Curve's default value range would quietly flatten: the Y curve rises ABOVE its endpoint
# near the top (the pull over the lip, before he settles onto it) and the Z curve dips BELOW
# zero at the start (the swing back before the pull). A clamped bake still passes every
# endpoint assertion above and reads as a lift on rails in game.
func test_the_climb_arc_is_not_clamped_flat() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var cy := root.get("climb_motion_y") as Curve
	var cz := root.get("climb_motion_z") as Curve
	if cy == null or cz == null:
		fail("no baked climb curves to inspect")
		return
	var peak := 0.0
	var dip := 0.0
	for i in 129:
		var u := float(i) / 128.0
		peak = maxf(peak, cy.sample(u))
		dip = minf(dip, cz.sample(u))
	check(peak > 1.005,
		("climb_motion_y peaks at %.3f. It should overshoot 1.0 - that is him pulling over " +
		"the lip before settling. A peak of exactly 1.0 means the curve's value range " +
		"clamped it.") % peak)
	check(dip < -0.005,
		("climb_motion_z never goes negative (lowest %.3f). It should dip below zero at the " +
		"start - the swing back before the pull - and a floor of exactly 0 means the " +
		"curve's value range clamped it.") % dip)

# He is being written to a position every frame, so a curve that ran backwards would be a
# frame of teleport rather than a frame of reverse velocity. The Y curve does settle back a
# little after its peak, which is the landing; anything more than that is a bad bake.
func test_the_rise_curve_only_settles_after_its_peak() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var cy := root.get("climb_motion_y") as Curve
	if cy == null:
		fail("no baked climb_motion_y to inspect")
		return
	var high := cy.sample(0.0)
	var worst := 0.0
	for i in range(1, 129):
		var v := cy.sample(float(i) / 128.0)
		high = maxf(high, v)
		worst = maxf(worst, high - v)
	check(worst < 0.15,
		("climb_motion_y drops %.3f below its running peak. A mantle rises and then settles " +
		"onto the ledge; a bigger fall than that is a bake that read the clip wrong.") % worst)

func test_the_baked_distances_describe_a_mantle() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	approx(float(root.get("climb_rise")), CLIMB_RISE, 0.5,
		"climb_rise moved a long way from the export the mantle was wired against")
	approx(float(root.get("climb_reach")), CLIMB_REACH, 0.5, "climb_reach moved a long way")
	approx(float(root.get("climb_inset")), CLIMB_INSET, 0.3,
		"climb_inset moved a long way - it is the level-design contract, the width of top " +
		"a ledge needs before there is anything to stand on")
	check(float(root.get("climb_rise")) > 0.8,
		("climb_rise is %.3f m - climb_up came back exported In Place and there is no " +
		"travel left to drive the body with") % root.get("climb_rise"))

# The two anchors the whole feature hangs off. The entry snap subtracts the hand offset from
# the detected lip and the exit snap subtracts the foot offset from the landing point, so a
# wrong one is a catch that does not line up with the visible edge - the spec's risk 2.
func test_the_contact_offsets_were_measured_off_the_clip() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var hand: Vector3 = root.get("climb_hand_offset")
	var foot: Vector3 = root.get("climb_foot_offset")
	check(hand.y > 1.2 and hand.y < 2.1,
		("climb_hand_offset sits %.3f m above his feet on frame 1. He is hanging at " +
		"near-full extension there, so anything outside roughly 1.2-2.1 m means the " +
		"forward kinematics in _ensure_climb_motion() read the wrong pose.") % hand.y)
	check(hand.z > 0.2,
		"climb_hand_offset is %.3f m in front of him - his hands have to be reaching out " % hand.z +
		"at the wall, or the entry snap plants him inside it")
	check(absf(foot.y) < 0.6,
		("climb_foot_offset puts his soles %.3f m off his own origin on the last frame. " +
		"That is a rest-pose correction away from zero; a large value means the toe bones " +
		"were read without it.") % foot.y)

# The two clocks. The state machine plays climb_up on its own and _climb_time runs in
# _physics_process; this is the only thing holding them together.
func test_the_baked_duration_matches_the_clip_exactly() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(BUILDER.CLIMB_CLIP):
		fail("no climb_up to compare against")
		return
	approx(float(root.get("climb_duration")), ap.get_animation(BUILDER.CLIMB_CLIP).length, 0.001,
		"climb_duration and the clip disagree. They are separate clocks - the state machine " +
		"plays the clip and _physics_process runs the path - and nothing else keeps them together")

# --- the state machine -----------------------------------------------------

# The inverse of the old test_the_climb_clip_is_imported_but_not_wired in the slide suite.
func test_state_machine_has_a_climb_state_playing_the_climb_clip() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no AnimationNodeStateMachine on the AnimationTree")
		return
	check(sm.has_node(BUILDER.CLIMB_STATE), "the locomotion state machine has no 'climb' state")
	if not sm.has_node(BUILDER.CLIMB_STATE):
		return
	# A plain animation node, not the crouch's blend tree. The clip is sped up by its own
	# custom timeline, not a TimeScale node: a TimeScale would advance the clip at a rate the
	# path knows nothing about and the two clocks would part company with nothing in the log.
	# The custom timeline keeps this a plain AnimationNodeAnimation - see the clocks test below.
	var node := sm.get_node(BUILDER.CLIMB_STATE)
	var clip := node as AnimationNodeAnimation
	check(clip != null,
		"the climb state is a %s, not a plain AnimationNodeAnimation - if that is on " % node.get_class() +
		"purpose, check nothing in it rescales time (docs/specs/pilot9-climb.md risk 1)")
	if clip:
		eq(str(clip.animation), str(BUILDER.CLIMB_CLIP), "the climb state plays the wrong clip")

# The mantle plays climb_speed times faster than authored, and the ONE thing that makes that
# safe is that the same factor drives both clocks: the clip through this custom timeline, the
# path through _apply_climb_motion() advancing _climb_time by delta * climb_speed. A timeline
# that does not match climb_duration / climb_speed is the two clocks drifting apart.
func test_the_clip_and_the_path_are_sped_up_by_the_same_factor() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null or not sm.has_node(BUILDER.CLIMB_STATE):
		fail("no climb state to inspect")
		return
	var clip := sm.get_node(BUILDER.CLIMB_STATE) as AnimationNodeAnimation
	if clip == null:
		fail("the climb state is not a plain AnimationNodeAnimation")
		return
	var speed := float(root.get("climb_speed"))
	check(speed > 1.0, "climb_speed is %.2f - the mantle is meant to play faster than authored" % speed)
	check(clip.use_custom_timeline and clip.stretch_time_scale,
		"the climb clip is not on a stretched custom timeline, so climb_speed does nothing to " +
		"what the player sees while _climb_time still runs fast - the two clocks are split")
	var raw := float(root.get("climb_duration"))
	approx(clip.timeline_length, raw / speed, 0.01,
		("the climb state's timeline is %.3fs but climb_duration / climb_speed is %.3fs. The " +
		"clip and the path would finish at different times.") % [clip.timeline_length, raw / speed])

func test_climb_is_entered_from_both_airborne_states() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	# The trigger is airborne, and depending on where in the arc the press lands the tree is
	# in `jump` (still rising) or `fall` (past apex). Both edges, or a mantle taken early off
	# a rising jump plays as a jump.
	for from in ["fall", "jump"]:
		var into := _transition(sm, from, "climb")
		check(into != null, "no %s -> climb transition" % from)
		if into == null:
			continue
		eq(into.advance_expression, "is_climbing", "%s -> climb fires on the wrong expression" % from)
		eq(into.advance_mode, AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO,
			"%s -> climb must advance automatically; nothing calls travel() for it" % from)
		eq(into.priority, 0, "%s -> climb must outrank its plain-airborne siblings" % from)
		check(into.xfade_time < 0.12,
			("%s -> climb fades over %.2fs. The entry snap has already teleported him to " +
			"the lip, and a long fade blends the old airborne pose across that teleport - " +
			"it reads as a lurch.") % [from, into.xfade_time])

func test_climb_has_exactly_one_exit_and_it_goes_to_locomotion() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sm := _state_machine(root)
	if sm == null:
		fail("no state machine")
		return
	var out := _transition(sm, "climb", "Locomotion")
	check(out != null, "no climb -> Locomotion transition - the mantle would be a one-way trip")
	if out:
		eq(out.advance_expression, "not is_climbing", "climb -> Locomotion fires on the wrong expression")
		check(out.xfade_time > 0.12,
			("climb -> Locomotion fades over %.2fs. The fade is what hands control back a " +
			"beat early by eating the end of the stand-up, so a short one means he watches " +
			"the clip out instead.") % out.xfade_time)
	# The mantle is not cancellable - collision is off and he is on a scripted path over an
	# edge - so there is deliberately nothing else out of it. A buffered jump fires from
	# Locomotion after the state has already been left.
	check(_transition(sm, "climb", "jump") == null,
		"there is a climb -> jump transition. The mantle is not cancellable; a jump pressed " +
		"during one is buffered and spent after the exit snap")
	check(_transition(sm, "climb", "fall") == null,
		"there is a climb -> fall transition. His collision shape is off for the whole " +
		"mantle, so he cannot leave the floor part way through one")

# --- the controller --------------------------------------------------------

# is_climbing is read by the tree through advance_expression, not by code a rename would
# carry along: an expression naming a property that does not exist simply never fires, which
# is how the crouch broke once.
func test_the_controller_exposes_the_climb_properties() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var props := {}
	for p in root.get_property_list():
		props[String(p.name)] = true
	check(props.has("is_climbing"),
		"scripts/pilot9.gd has no 'is_climbing' - every climb advance_expression silently never fires")
	for name in ["can_climb", "climb_probe_height", "climb_probe_reach", "climb_band_min",
			"climb_band_max", "climb_max_lip_slope", "climb_headroom"]:
		check(props.has(name), "scripts/pilot9.gd has no '%s'" % name)
	if props.has("is_climbing"):
		check(root.get("is_climbing") == false, "pilot9 must not start mid-mantle")

# The one constraint between two of those dials, and it is silent when broken: the forward
# ray has to pass UNDER the lip it is looking for. Cast at or above the shallowest ledge the
# band accepts, it sails over the top of every wall in range and no mantle ever triggers.
func test_the_forward_ray_is_cast_below_the_shallowest_ledge() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	check(float(root.get("climb_probe_height")) < float(root.get("climb_band_min")),
		("the forward ray is cast %.2f m up and the band starts at %.2f m. A ray at or " +
		"above the lip misses the wall face entirely and nothing is ever climbable.")
		% [root.get("climb_probe_height"), root.get("climb_band_min")])

func test_the_climb_dials_stay_out_of_the_baked_list() -> void:
	for name in ["can_climb", "climb_band_min", "climb_band_max", "climb_probe_height",
			"climb_probe_reach", "climb_max_lip_slope", "climb_headroom"]:
		check(not BUILDER.CLIMB_BAKED.has(name),
			("%s is in CLIMB_BAKED, so pilot9_build_scene.gd would overwrite it on every " +
			"sync - the probe numbers are meant to be tuned and to survive a rig swap") % name)

# --- detection -------------------------------------------------------------

# The band is the only filter the mantle has: no climbable layer, no tag. Everything it lets
# through becomes a mantle, so both ends of it and the slope cutoff are worth pinning.
func test_the_band_accepts_a_ledge_and_refuses_what_is_outside_it() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var lo: float = root.get("climb_band_min")
	var hi: float = root.get("climb_band_max")
	var mid := (lo + hi) * 0.5
	check(root._qualifies_as_ledge(mid, Vector3.UP),
		"a flat lip at %.2f m, in the middle of the band, is not being accepted" % mid)
	check(not root._qualifies_as_ledge(lo - 0.3, Vector3.UP),
		"a lip %.2f m up is under the band and must not be a mantle - that is a step to " % (lo - 0.3) +
		"walk over, not a ledge to pull up onto")
	check(not root._qualifies_as_ledge(hi + 0.5, Vector3.UP),
		"a lip %.2f m up is over the band and must not be a mantle - his hands cannot " % (hi + 0.5) +
		"reach it from the pose the clip opens in")

func test_a_sloped_top_is_not_a_ledge() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var mid: float = (float(root.get("climb_band_min")) + float(root.get("climb_band_max"))) * 0.5
	var tilted := Vector3(1, 1, 0).normalized()   # 45 degrees
	check(not root._qualifies_as_ledge(mid, tilted),
		"a 45-degree face at mantle height qualifies as a ledge. He arrives standing on it, " +
		"so anything past climb_max_lip_slope is a ramp to slide off, not a top to land on")
	check(not root._qualifies_as_ledge(mid, Vector3.DOWN),
		"a downward-facing surface qualifies as a ledge - the underside of an overhang " +
		"would offer a mantle")

# The whole decision, driven through the same function the raycasts feed. The lip handed
# back is the WALL FACE at the top surface's height: the down ray is cast deliberately
# inside the platform, and his hands belong on the edge rather than 0.4 m in from it.
func test_three_good_hits_produce_a_mantle_at_the_wall_face() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var lip_h: float = (float(root.get("climb_band_min")) + float(root.get("climb_band_max"))) * 0.5
	var forward := _hit(Vector3(0, 0.85, 2.0), Vector3.BACK)
	var down := _hit(Vector3(0, lip_h, 2.4), Vector3.UP)
	var ledge: Dictionary = root._evaluate_ledge(0.0, forward, down, {})
	check(not ledge.is_empty(), "three good hits produced no mantle")
	if ledge.is_empty():
		return
	var lip: Vector3 = ledge["lip"]
	approx(lip.z, 2.0, 0.001,
		"the lip came back at z %.3f, which is the down ray's own hit 0.4 m inside the " % lip.z +
		"platform. It has to be the wall face, or his hands land on top instead of on the edge")
	approx(lip.y, lip_h, 0.001, "the lip took its height from the wrong hit")

func test_no_wall_and_no_top_are_both_refused() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var lip_h: float = (float(root.get("climb_band_min")) + float(root.get("climb_band_max"))) * 0.5
	var forward := _hit(Vector3(0, 0.85, 2.0), Vector3.BACK)
	var down := _hit(Vector3(0, lip_h, 2.4), Vector3.UP)
	check((root._evaluate_ledge(0.0, {}, down, {}) as Dictionary).is_empty(),
		"a mantle was offered with nothing in front of him - the forward ray found no wall")
	check((root._evaluate_ledge(0.0, forward, {}, {}) as Dictionary).is_empty(),
		"a mantle was offered with no top - the down ray found nothing inside the band")

# He arrives standing, so planting him inside a ceiling is an uglier failure than refusing.
# Nothing is above the one climbable block in trial.tscn, so this never fires there; it is
# in for the first real level.
func test_a_blocker_over_the_landing_point_refuses_the_mantle() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var lip_h: float = (float(root.get("climb_band_min")) + float(root.get("climb_band_max"))) * 0.5
	var forward := _hit(Vector3(0, 0.85, 2.0), Vector3.BACK)
	var down := _hit(Vector3(0, lip_h, 2.4), Vector3.UP)
	var ceiling := _hit(Vector3(0, lip_h + 1.0, 2.5), Vector3.DOWN)
	check((root._evaluate_ledge(0.0, forward, down, ceiling) as Dictionary).is_empty(),
		"a mantle was offered with a ceiling a metre over the spot he would stand up in")

# --- the snaps and the path ------------------------------------------------

# The entry snap's one job, asserted as geometry rather than as a number: wherever the lip
# is and whichever way the wall faces, the clip's frame-1 hands land ON it.
func test_the_entry_snap_puts_his_hands_on_the_lip() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_rig(root)
	var lip := Vector3(3.0, 1.84, -7.5)
	var wall_normal := Vector3(-1, 0, 0)          # a wall facing -X, so he must face +X
	root._start_climb(lip, wall_normal)
	check(root.is_climbing, "_start_climb did not set is_climbing")
	var body := Basis(Vector3.UP, root.character.rotation.y)
	var hands: Vector3 = root.global_position + body * (root.get("climb_hand_offset") as Vector3)
	approx(hands.distance_to(lip), 0.0, 0.001,
		"his frame-1 hands land %.3f m from the lip. The snap is the whole grab - there is " % hands.distance_to(lip) +
		"no reach animated before it, so a wrong offset reads as him catching thin air")
	approx(absf(angle_difference(root.character.rotation.y, atan2(1.0, 0.0))), 0.0, 0.001,
		"he is not facing the wall. The heading is the one opposite the forward ray's hit " +
		"normal, flattened to the ground plane")
	approx((root.get("velocity") as Vector3).length(), 0.0, 0.001,
		"incoming velocity survived the entry snap - the snap has already placed him, and " +
		"anything left over fights the path")

# The other end. The exit hard-snaps here rather than trusting the last sampled frame, so
# this is where his soles actually meet the platform.
func test_the_exit_endpoint_puts_his_soles_on_the_platform() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_rig(root)
	var lip := Vector3(0.0, 1.84, 0.0)
	root._start_climb(lip, Vector3.BACK)          # a wall facing +Z, so he must face -Z
	var body := Basis(Vector3.UP, root.character.rotation.y)
	var endpoint: Vector3 = root.get("_climb_end_position")
	var soles: Vector3 = endpoint + body * (root.get("climb_foot_offset") as Vector3)
	approx(soles.y, lip.y, 0.001,
		"his soles finish %.3f m off the platform top. The endpoint is computed from the " % (soles.y - lip.y) +
		"detected lip so a frame of drift cannot leave him half in the floor")
	# Projected onto his heading rather than read off an axis, so the assertion says the
	# same thing whichever way the wall happens to face.
	var inward: float = (root.get("_climb_facing") as Vector3).dot(soles - lip)
	approx(inward, float(root.get("climb_inset")), 0.001,
		"he lands %.3f m in from the lip, not climb_inset. That distance is the " % inward +
		"level-design contract for how wide a climbable top has to be")

# The path itself, integrated off the tree. The curve can be perfect and a factor dropped in
# _apply_climb_motion() still leaves him arriving somewhere else entirely.
func test_the_path_runs_from_the_catch_to_the_endpoint() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_rig(root)
	root._start_climb(Vector3(0.0, 1.84, 0.0), Vector3.BACK)
	var start: Vector3 = root.global_position
	var endpoint: Vector3 = root.get("_climb_end_position")
	var duration: float = root.get("climb_duration")
	var lowest := start.y
	var steps := 120
	# Two frames past the clip: summing duration/steps back up lands a hair short of
	# duration in floating point, and the mantle ends on `>=`.
	for i in steps + 2:
		root._apply_climb_motion(duration / float(steps))
		if not root.is_climbing:
			break
		lowest = minf(lowest, (root.global_position as Vector3).y)
	check(not root.is_climbing,
		"the mantle is still running after its full duration - _apply_climb_motion() never " +
		"reached climb_duration, so is_climbing would stay true and the tree never leaves `climb`")
	approx((root.global_position as Vector3).distance_to(endpoint), 0.0, 0.001,
		"the mantle finished %.3f m from its own endpoint"
		% (root.global_position as Vector3).distance_to(endpoint))
	check(lowest > start.y - 0.05,
		("he dips %.3f m below the catch part way through the pull. The rise curve should " +
		"never take him back down past where he grabbed.") % (start.y - lowest))

# frozen ends the mantle rather than pausing it: nothing advances _climb_time while frozen,
# and he would hang in the air with his collision shape switched off. Landing him on top is
# the safe stop - same reasoning as the slide ending itself.
func test_frozen_ends_the_mantle_on_top_and_drops_the_buffered_jump() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_rig(root)
	root._start_climb(Vector3(0.0, 1.84, 0.0), Vector3.BACK)
	root._apply_climb_motion(0.3)
	root.set("_climb_jump_buffered", true)
	var endpoint: Vector3 = root.get("_climb_end_position")
	root._end_climb(false)
	check(not root.is_climbing, "frozen did not clear is_climbing - the tree would stay in `climb`")
	approx((root.global_position as Vector3).distance_to(endpoint), 0.0, 0.001,
		"frozen left him mid-arc rather than snapping him onto the ledge, with his " +
		"collision shape still disabled")
	check(root.get("_climb_jump_buffered") == false,
		"the buffered jump survived a frozen mantle - it would fire on the frame he unfreezes")

# The exit snap teleports him onto the ledge without a move_and_slide(), so is_on_floor() is
# still false on the frame after. The buffered press has to be spent before the air-jump
# branch or the mantle silently charges him an air jump for it.
func test_a_jump_buffered_through_the_mantle_fires_free_on_the_next_frame() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("_air_jumps_left", 1)
	root.set("_climb_jump_buffered", true)
	root.velocity = Vector3.ZERO
	root._handle_gravity_and_jump(1.0 / 60.0)
	approx(root.velocity.y, float(root.get("jump_velocity")), 0.001,
		"the buffered jump did not fire on the frame after the mantle ended")
	check(root.get("_climb_jump_buffered") == false, "the buffered press was not consumed")
	eq(root.get("_air_jumps_left"), 1,
		"the buffered mantle jump spent an air jump. It is the press the player already " +
		"made during the climb, not a second one")

# Gravity is not integrated during a mantle. Without this the velocity banked over its
# 1.15 s would fire him at the floor on the exit frame.
func test_gravity_is_not_banked_during_the_mantle() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("is_climbing", true)
	root.velocity = Vector3.ZERO
	for i in 60:
		root._handle_gravity_and_jump(1.0 / 60.0)
	approx(root.velocity.y, 0.0, 0.001,
		"a second of mantle banked %.2f m/s of fall - it would all be spent on the frame " % root.velocity.y +
		"the exit snap puts him on the platform")

# The slide's _slide_direction discipline, applied to the mantle: the entry snap placed his
# hands along one heading, so anything that turns him slides the grab off the edge it was
# measured against.
func test_the_mesh_is_welded_to_the_climb_heading() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_rig(root)
	root.camera_pivot = root.get_node("CameraPivot")
	root._start_climb(Vector3(0.0, 1.84, 0.0), Vector3.BACK)
	var heading: float = root.character.rotation.y
	root.input_dir = Vector2(1, 0)                # the player fighting it with the stick
	root.direction = Vector3(1, 0, 0)
	for i in 20:
		root._handle_character_rotation(1.0 / 60.0)
	approx(absf(angle_difference(root.character.rotation.y, heading)), 0.0, 0.0001,
		"the stick turned him %f rad off the heading his hands were placed along"
		% angle_difference(root.character.rotation.y, heading))

# The mantle is airborne-only and it is the first thing the guard chain checks, so a `jump`
# press with the feature switched off falls straight through to the double jump rather than
# reaching a raycast at all.
func test_the_mantle_can_be_switched_off() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("can_climb", false)
	check(not root._try_start_climb(),
		"can_climb is false and _try_start_climb() still tried - it must return before the " +
		"probe, or the press is swallowed by a feature that is turned off")
	check(not root.is_climbing, "a mantle started with can_climb false")
