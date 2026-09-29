extends "res://tests/test_case.gd"

# Covers pilot9's dash. See docs/specs/pilot9-dash.md.
#
# The feel cannot be checked headlessly - how the afterimages look, and the blocked-dash cut,
# which needs real collision and a running frame, the same wall
# tests/test_pilot9_double_jump.gd and tests/test_pilot9_jump_slide.gd hit for the press
# itself. What IS reachable: the input action, the numbers, the ability-tab seam, the
# availability rule and the air charge as pure functions, the afterimages' spacing / colour /
# clear as pure functions, the `dash` state's wiring, and one real launch in the real scene.

const CONTROLLER := preload("res://scripts/pilot9.gd")
const TAB_ABILITIES := preload("res://scripts/ui/tabs/tab_abilities.gd")
const APPLY_STYLIZED := preload("res://scripts/rendering/apply_stylized.gd")
const PILOT_TSCN := "res://scenes/pilot9.tscn"
const AFTERIMAGE := preload("res://scripts/pilot9_afterimage.gd")
const ANIMATION := preload("res://scripts/pilot9_animation.gd")

# One shared, in-tree instance for the real-launch tests only - see
# tests/test_pilot9_climb.gd's note on why: a fresh in-tree pilot9 per test leaks
# physics/render-server RIDs that a --script run never cleans up, and this file needs the
# tree for the `character` subtree and the AnimationTree onready populates from.
var _pilot: Node = null

func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	_pilot.is_dashing = false
	_pilot.frozen = false
	if _pilot._afterimage != null:
		_pilot._afterimage.clear()
	return _pilot

# --- the input action ----------------------------------------------------------

func test_dash_action_exists() -> void:
	check(InputMap.has_action("dash"), "project.godot has no 'dash' action")

# --- the ability-tab seam --------------------------------------------------------

# tab_abilities.gd's _reads_true() looks the property up by STRING; a rename on either side
# renders the row permanently LOCKED with nothing in the log - the same class of failure
# CROUCH_SCALE and SLIDE_SCALE are pinned against elsewhere.
func test_base_kit_row_names_a_real_property() -> void:
	var property := ""
	for entry: Array in TAB_ABILITIES.BASE_KIT:
		if entry[0] == "DASH":
			property = entry[1]
	check(property != "", "tab_abilities.gd's BASE_KIT has no 'DASH' row")
	if property == "":
		return
	var body: CharacterBody3D = CONTROLLER.new()
	var found := false
	for p in body.get_property_list():
		if String(p.name) == property:
			found = true
			break
	check(found, ("scripts/pilot9.gd has no '%s' property - the DASH row reads nothing " +
		"and renders LOCKED forever") % property)
	body.free()

# --- the numbers -----------------------------------------------------------------

func test_exported_knobs_have_the_spec_defaults() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	check(body.can_dash, "can_dash defaults to off")
	approx(body.dash_speed, 40.0, 0.0001, "dash_speed drifted from the 2026-09-18 doubling")
	approx(body.dash_time, 0.25, 0.0001, "dash_time drifted from the user's 2026-09-18 halving")
	approx(body.dash_cooldown, 1.5, 0.0001,
		"dash_cooldown drifted from the number chosen against his 1.2 s airtime")
	approx(body.camera_dash_lag_delay, 0.05, 0.0001,
		"camera_dash_lag_delay drifted from the 2026-09-19 'wait longer' retune")
	approx(body.camera_dash_lag_time, 0.3, 0.0001,
		"camera_dash_lag_time drifted from the 2026-09-19 'catch up slower' retune")
	body.free()

func test_dash_distance_is_ten_metres() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	approx(body.dash_distance(), 10.0, 0.0001,
		"the dash drifted off its post-play-session 10 m - see the spec's note on the " +
		"sprint jump's 9 m lip before treating a drift here as safe to fix quietly")
	body.free()

# --- availability: both limiters, and the blocked states -------------------------

func test_availability_needs_both_limiters() -> void:
	# On the ground the air charge is irrelevant - the cooldown alone gates it.
	check(CONTROLLER._dash_availability(true, 0.0, false, true, false, false),
		"a grounded dash off cooldown must be available with no air charge at all")
	check(not CONTROLLER._dash_availability(true, 0.4, true, true, false, false),
		"the cooldown must gate a grounded dash even with the air charge available")
	# Airborne, off cooldown: the charge is the only thing standing between him and a second
	# air dash - the rule a cooldown alone cannot be trusted to keep once it gets tuned down.
	check(CONTROLLER._dash_availability(true, 0.0, true, false, false, false),
		"an airborne dash with a charge and no cooldown must be available")
	check(not CONTROLLER._dash_availability(true, 0.0, false, false, false, false),
		"an airborne dash with the charge already spent must stay refused however low the " +
		"cooldown gets")

func test_availability_blocked_states() -> void:
	check(CONTROLLER._dash_availability(true, 0.0, true, true, false, false),
		"the control case - nothing blocking it - must be available; the negative checks " +
		"below are only meaningful against this")
	check(not CONTROLLER._dash_availability(false, 0.0, true, true, false, false),
		"can_dash off must refuse the dash outright")
	check(not CONTROLLER._dash_availability(true, 0.0, true, true, true, false),
		"mid-mantle must refuse the dash outright")
	check(not CONTROLLER._dash_availability(true, 0.0, true, true, false, true),
		"frozen must refuse the dash outright")

# --- the air charge, as pure functions --------------------------------------------

func test_air_charge_is_refreshed_only_by_touching_a_floor() -> void:
	check(CONTROLLER._dash_air_charge_refreshed(false, true),
		"touching a floor must refresh a spent charge")
	check(CONTROLLER._dash_air_charge_refreshed(true, false),
		"an airborne frame must not touch an already-available charge")
	check(not CONTROLLER._dash_air_charge_refreshed(false, false),
		"an airborne frame must not invent a charge that was not there")

func test_air_charge_is_spent_only_by_an_airborne_launch() -> void:
	check(CONTROLLER._dash_air_charge_after_launch(true, true),
		"a dash launched from the floor must leave the charge intact, even one that then " +
		"carries him off a ledge")
	check(not CONTROLLER._dash_air_charge_after_launch(true, false),
		"a dash launched in the air must spend the charge")
	check(not CONTROLLER._dash_air_charge_after_launch(false, true),
		"a ground dash must not hand back a charge that was already spent")

# --- the afterimages: a real launch ------------------------------------------------
#
# Replaced the hide/restore round-trip on 2026-09-28, when the vanish was retired - see
# docs/specs/pilot9-dash.md, "The afterimages".

func test_dash_state_parameters_exist_in_the_scene() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	check(root.anim_tree.get(CONTROLLER.DASH_SCALE_PARAM) != null,
		"no %s - rebuild pilot9.tscn with scripts/pilot9_build_scene.gd" % CONTROLLER.DASH_SCALE_PARAM)
	check(root.anim_tree.get(CONTROLLER.DASH_SEEK_PARAM) != null,
		"no %s - the launch would start the cycle wherever it was" % CONTROLLER.DASH_SEEK_PARAM)
	eq(ANIMATION.DASH_SCALE, CONTROLLER.DASH_SCALE_PARAM,
		"pilot9_animation.gd and pilot9.gd disagree on the dash TimeScale's path")

func test_launch_keeps_him_visible_cuts_to_dash_and_drops_the_first_ghost() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var meshes: Array[MeshInstance3D] = []
	APPLY_STYLIZED.collect_meshes(root.character, meshes)
	var before: Array[bool] = []
	for mi in meshes:
		before.append(mi.visible)

	root._start_dash(Vector3.FORWARD)
	for i in meshes.size():
		eq(meshes[i].visible, before[i], "%s changed visibility on a dash" % meshes[i].name)
	var playback: AnimationNodeStateMachinePlayback = root.anim_tree.get("parameters/playback")
	eq(playback.get_current_node(), CONTROLLER.DASH_STATE, "the launch did not hard-cut to `dash`")
	# The launch ghost is owed until his skeleton re-emits after the hard cut - see
	# Pilot9Afterimage.begin().
	root._afterimage.advance(root.character, root.global_position, root.global_position)
	eq(root._afterimage.ghost_count(), 0, "the launch ghost must wait for a fresh snapshot")
	root._afterimage._on_skeleton_updated()   # stand in for the skeleton update a --script run skips
	root._afterimage.advance(root.character, root.global_position, root.global_position)
	eq(root._afterimage.ghost_count(), 1, "the first tick after a snapshot drops the launch ghost")

	var ghost: Node3D = root._afterimage.get_child(0)
	check(ghost.visible, "the launch ghost was not shown")
	var shown := 0
	for copy in ghost.get_children():
		var mi := copy as MeshInstance3D
		if not mi.visible:
			continue
		shown += 1
		check(mi.mesh != null, "a shown ghost mesh is empty")
		eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ghosts cast no shadow")
		var mat := mi.material_override as ShaderMaterial
		check(mat != null and mat.shader == AFTERIMAGE.FILL_SHADER,
			"a ghost is not drawn in the afterimage fill")
		check(mi.material_overlay == null, "the rim light must not ride onto a ghost")
	check(shown > 0, "the launch ghost showed no meshes")
	root._end_dash()
	root._afterimage.clear()

# --- the afterimages: frozen skeletons ---------------------------------------------
#
# Since 2026-09-28 a ghost is a Skeleton3D posed like him, not a baked mesh - the bake cost
# ~27 ms a ghost. See docs/specs/pilot9-dash.md, "Frozen skeletons, not baked meshes".

func test_a_ghost_carries_his_pose_on_his_own_mesh_and_skin() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root._start_dash(Vector3.FORWARD)
	var ai: Pilot9Afterimage = root._afterimage
	var skel: Skeleton3D = ai._skeleton
	if skel == null:
		fail("the afterimages found no skeleton under character")
		return
	# A pose nothing else would give him, so a ghost left at rest cannot pass by accident.
	var bone := skel.get_bone_count() - 1
	skel.set_bone_pose_rotation(bone, Quaternion(Vector3.UP, 1.1))
	ai._on_skeleton_updated()
	ai.advance(root.character, root.global_position, root.global_position)
	eq(ai.ghost_count(), 1, "no launch ghost to check")
	var ghost: Skeleton3D = ai._ghosts[0]
	eq(ghost.get_bone_count(), skel.get_bone_count(), "the ghost's skeleton has different bones")
	var worst := 0.0
	for b in skel.get_bone_count():
		worst = maxf(worst, ghost.get_bone_global_pose(b).origin.distance_to(
			skel.get_bone_global_pose(b).origin))
	approx(worst, 0.0, 0.0001, "the ghost's bones are not where his are")
	check(ghost.get_bone_global_pose(bone).basis.is_equal_approx(skel.get_bone_global_pose(bone).basis),
		"the ghost did not take his pose - a ghost at rest would look like a T-pose")
	var skinned := 0
	for k in ai._sources.size():
		var src: MeshInstance3D = ai._sources[k]
		var copy: MeshInstance3D = ai._copies[0][k]
		if ai._skinned(src):
			skinned += 1
			check(copy.mesh == src.mesh, "%s was copied, not shared - that is the bake back" % src.name)
			check(copy.skin == src.skin, "%s does not share his skin" % src.name)
			check(copy.get_node_or_null(copy.skeleton) == ghost,
				"%s is not skinned off the ghost's own skeleton" % src.name)
	check(skinned > 0, "no skinned mesh was found to freeze")
	root._end_dash()
	ai.clear()

func test_a_clear_hands_the_ghosts_back_to_the_pool() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var ai: Pilot9Afterimage = root._afterimage
	root._start_dash(Vector3.FORWARD)
	eq(ai._pool.size(), root.afterimage_max_count, "the pool is not afterimage_max_count ghosts")
	var first: Node = ai._pool[0]
	var children := ai.get_child_count()
	ai._on_skeleton_updated()
	ai.advance(root.character, root.global_position, root.global_position)
	root._end_dash()
	ai.clear()
	eq(ai.ghost_count(), 0, "a clear left live ghosts")
	check(not first.visible, "a cleared ghost is still showing")
	root._start_dash(Vector3.FORWARD)
	check(ai._pool[0] == first, "a second dash rebuilt the pool instead of reusing it")
	eq(ai.get_child_count(), children, "a dash created or freed ghost nodes")
	root._end_dash()
	ai.clear()

func test_advance_places_a_ghost_at_the_exact_crossing() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root._start_dash(Vector3.FORWARD)
	root._afterimage._launch_owed = false   # this test is about the crossing, not the launch ghost
	var mesh_origin: Vector3 = root.character.global_position
	var here: Vector3 = root.global_position
	# One 2 m tick from the launch: the 1.6 m crossing is 0.4 m back from where the tick ended.
	root._afterimage.advance(root.character, here - Vector3(0, 0, 2.0), here)
	eq(root._afterimage.ghost_count(), 1, "a 2 m tick past a 1.6 m spacing drops one ghost")
	var placed: Node3D = root._afterimage.get_child(0).get_child(0)
	var source := root.character.find_child(placed.name, true, false) as Node3D
	var expected: Vector3 = (source.global_position if source != null else mesh_origin) 		+ Vector3(0, 0, -0.4)
	approx(placed.global_position.distance_to(expected), 0.0, 0.001,
		"the ghost was not pulled back to the exact crossing")
	root._end_dash()
	root._afterimage.clear()

# --- steering ----------------------------------------------------------------------
#
# Retuned 2026-09-18: the dash used to lock its heading at launch with no steering at all - the
# user tried that, changed their mind, and asked for free left/right control instead, with
# altitude (untouched by either design) staying exactly flat. Unlike _steer_slide()'s lerp,
# _steer_dash() is not smoothed: he is invisible for the whole window (see
# test_hide_reaches_invisible_and_restore_undoes_it_exactly, above), so there is nothing on
# screen for a turn rate to hide a snap from.

# The controller state _handle_movement_input() would have produced for this stick, at camera
# yaw 0 so a stick vector and a world direction are the same thing - same helper
# tests/test_pilot9_slide.gd uses for _steer_slide().
func _set_stick(root: Node, stick: Vector2) -> void:
	root.camera_pivot.rotation.y = 0.0
	root.input_dir = stick
	root.input_strength = minf(stick.length(), 1.0)
	root.direction = Vector3(stick.x, 0.0, stick.y).normalized()

func test_steer_dash_snaps_straight_onto_a_held_stick() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("_dash_direction", Vector3(0.0, 0.0, 1.0))
	_set_stick(root, Vector2(1, 0))
	root._steer_dash()
	var got: Vector3 = root.get("_dash_direction")
	approx(got.distance_to(root.direction), 0.0, 0.0001,
		"a held stick must move the dash heading onto it in a single frame - no lerp, unlike " +
		"the slide's _steer_slide()")

func test_steer_dash_holds_its_heading_when_the_stick_is_centred() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var held := Vector3(sin(0.9), 0.0, cos(0.9))
	root.set("_dash_direction", held)
	_set_stick(root, Vector2.ZERO)
	root._steer_dash()
	var got: Vector3 = root.get("_dash_direction")
	approx(got.distance_to(held), 0.0, 0.0001,
		"a centred stick must leave the dash heading alone - the same rule _steer_slide() " +
		"follows for the slide")

# The dash is horizontal only: the camera's pitch never tilts it.
func test_dash_stays_flat_whatever_the_camera_pitch() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_set_stick(root, Vector2(0, -1))
	for deg in [40.0, -40.0]:
		root.camera_pivot.rotation.x = deg_to_rad(deg)
		root._steer_dash()
		root._apply_dash_velocity()
		approx(root.velocity.y, 0.0, 0.0001, "a pitched camera must not tilt the dash")
		approx(root.velocity.length(), root.dash_speed, 0.001, "the flat dash runs at dash_speed")

# --- the afterimages: spacing, colour, clear ------------------------------------------

func test_afterimage_knobs_have_the_spec_defaults() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	approx(body.afterimage_spacing, 1.6, 0.0001, "spacing drifted from the six-ghost 1.6 m")
	eq(body.afterimage_max_count, 6, "max count drifted from the agreed six")
	approx(body.dash_anim_speed, 2.5, 0.0001, "the sprint cycle's dash rate drifted")
	approx(body.afterimage_clear_time, 0.35, 0.0001, "the tail-to-head clear drifted from 0.35 s")
	body.free()

func test_crossings_land_on_every_multiple_of_the_spacing() -> void:
	eq(AFTERIMAGE.crossings(0.0, 0.67, 1.6).size(), 0, "no crossing inside the first 0.67 m")
	var one: PackedFloat32Array = AFTERIMAGE.crossings(1.34, 0.67, 1.6)
	eq(one.size(), 1, "1.34 -> 2.01 m crosses 1.6 once")
	approx(one[0], 0.26, 0.0001, "the crossing is measured from the segment's start")
	var two: PackedFloat32Array = AFTERIMAGE.crossings(0.0, 3.3, 1.6)
	eq(two.size(), 2, "a 3.3 m segment from 0 crosses 1.6 and 3.2")
	approx(two[1], 3.2, 0.0001, "the second crossing")
	eq(AFTERIMAGE.crossings(1.6, 1.0, 1.6).size(), 0,
		"a segment starting ON a crossing must not drop it twice")
	eq(AFTERIMAGE.crossings(0.0, 5.0, 0.0).size(), 0, "zero spacing must not loop forever")
	eq(AFTERIMAGE.crossings(0.0, 0.0, 1.6).size(), 0, "a tick that never moved crosses nothing")

func test_colour_runs_head_at_the_newest_to_tail_at_the_oldest() -> void:
	var head := Color(0.3, 0.9, 1.0)
	var tail := Color(0.35, 1.0, 0.45)
	eq(AFTERIMAGE.rank_color(0, 6, head, tail), head, "the newest ghost is the head colour")
	eq(AFTERIMAGE.rank_color(5, 6, head, tail), tail, "max_count - 1 back is the tail colour")
	eq(AFTERIMAGE.rank_color(9, 6, head, tail), tail, "past the tail clamps to the tail")
	eq(AFTERIMAGE.rank_color(3, 1, head, tail), head, "a one-ghost trail must not divide by zero")

func test_clear_holds_then_goes_tail_to_head() -> void:
	var n := 6
	for i in n:
		approx(AFTERIMAGE.fade_at(i, n, 0.0, 0.35, 0.12), 1.0, 0.0001,
			"every ghost is fully solid the moment the dash ends")
		approx(AFTERIMAGE.fade_at(i, n, 0.35, 0.35, 0.12), 0.0, 0.0001,
			"every ghost is gone at afterimage_clear_time")
	var mid := 0.15
	check(AFTERIMAGE.fade_at(0, n, mid, 0.35, 0.12) < AFTERIMAGE.fade_at(n - 1, n, mid, 0.35, 0.12),
		"the oldest ghost must be further gone than the newest - tail to head")
	check(AFTERIMAGE.fade_at(n - 1, n, 0.34, 0.35, 0.12) > 0.0,
		"the newest must last until the clear time, not vanish early")
	approx(AFTERIMAGE.fade_at(0, 1, 0.12, 0.35, 0.12), 0.0, 0.0001,
		"a lone ghost fades over one fade_time")

# --- the camera catch-up -----------------------------------------------------------
#
# Covers _camera_dash_lag_position(), the arithmetic behind CameraPivot falling behind during
# a dash and gliding back on by the time `camera_dash_lag_delay + camera_dash_lag_time` is up -
# see docs/specs/pilot9-dash.md, Camera. The flag that turns it on and off
# (_camera_dash_lag_active), the elapsed-time clock, and the weld itself all live in _process(),
# a drawn-frame callback a --script run never ticks - same wall the afterimages' look hits. This is the one piece of it that is a pure function, so it is the one piece
# asserted.
#
# The property that actually matters is the one 5d65b07-style feedback loop would silently
# regress: convergence has to be tied to TIME, not to distance or to the target having
# stopped - that regression is exactly what sent this back for a second pass, see the spec.

func test_lag_reproduces_the_launch_position_at_zero_elapsed() -> void:
	var start := Vector3(1, 2, 3)
	var pos: Vector3 = CONTROLLER._camera_dash_lag_position(
		start, Vector3(11, 2, 3), 0.0, 0.0, 0.5)
	approx(pos.distance_to(start), 0.0, 0.0001,
		"elapsed 0.0 must reproduce the launch position exactly, or the dash opens with a pop")

func test_lag_lands_exactly_on_target_when_the_window_closes() -> void:
	var target := Vector3(11, 2, 3)
	var pos: Vector3 = CONTROLLER._camera_dash_lag_position(
		Vector3(1, 2, 3), target, 0.5, 0.0, 0.5)
	approx(pos.distance_to(target), 0.0, 0.0001,
		"elapsed == delay + duration must land exactly on the target, or _process()'s " +
		"hand-back to the hard weld snaps")

# The actual bug report this rework fixes: a fixed-rate exponential chase never fully closes
# the gap against a target that keeps moving at constant velocity (its steady-state error is
# proportional to that velocity), which is why the old build only caught up once the player let
# go of the stick. Advancing `target` between the two samples below is standing in for him
# continuing to move after the dash - and the position must still land on the CURRENT target
# once elapsed reaches duration, not lag behind it.
func test_lag_still_lands_on_a_target_that_kept_moving() -> void:
	var start := Vector3.ZERO
	var moving_target := Vector3(12, 0, 0)
	var pos: Vector3 = CONTROLLER._camera_dash_lag_position(start, moving_target, 0.5, 0.0, 0.5)
	approx(pos.distance_to(moving_target), 0.0, 0.0001,
		"a target that moved further between launch and the deadline must still be caught " +
		"exactly, or the camera is left trailing a still-moving pilot9 again")

func test_lag_opens_a_gap_partway_through_and_it_shrinks_toward_the_close() -> void:
	# target advances at a constant rate, standing in for dash_speed.
	var start := Vector3.ZERO
	var mid: Vector3 = CONTROLLER._camera_dash_lag_position(
		start, Vector3(5, 0, 0), 0.25, 0.0, 0.5)
	var late: Vector3 = CONTROLLER._camera_dash_lag_position(
		start, Vector3(9, 0, 0), 0.45, 0.0, 0.5)
	var gap_mid := Vector3(5, 0, 0).distance_to(mid)
	var gap_late := Vector3(9, 0, 0).distance_to(late)
	check(gap_mid > 0.0, "no lag ever opens against a moving target - the 'falls behind' half " +
		"of the effect is gone")
	check(gap_late < gap_mid,
		"the gap does not shrink as the window closes - the 'glides back on' half is gone")

func test_lag_elapsed_past_duration_still_lands_on_target() -> void:
	var target := Vector3(4, 0, -1)
	var pos: Vector3 = CONTROLLER._camera_dash_lag_position(Vector3.ZERO, target, 10.0, 0.0, 0.5)
	approx(pos.distance_to(target), 0.0, 0.0001,
		"elapsed past delay + duration (a hitch that skips a frame past the deadline) must " +
		"clamp to the target, not overshoot past it")

func test_lag_with_zero_duration_is_the_target_immediately() -> void:
	var target := Vector3(7, 0, 2)
	var pos: Vector3 = CONTROLLER._camera_dash_lag_position(Vector3.ZERO, target, 0.0, 0.0, 0.0)
	approx(pos.distance_to(target), 0.0, 0.0001,
		"a duration of 0.0 must not divide by zero or leave the rig stranded at the start")

# The delay is a hold, not a slower glide: before it has elapsed the weight must be pinned at
# 0.0 even though the target has already moved, which is what reads as "the camera waits"
# rather than "the camera glides slower" - test_lag_opens_a_gap_... above already covers the
# glide's own shape once it starts.
func test_lag_holds_at_the_start_position_until_the_delay_elapses() -> void:
	var start := Vector3.ZERO
	var pos: Vector3 = CONTROLLER._camera_dash_lag_position(
		start, Vector3(9, 0, 0), 0.2, 0.3, 0.5)
	approx(pos.distance_to(start), 0.0, 0.0001,
		"elapsed still inside the delay must reproduce the launch position exactly, or the " +
		"camera starts gliding before the wait is up")

func test_lag_delay_still_lands_on_target_once_its_own_window_closes() -> void:
	var target := Vector3(9, 0, 0)
	var pos: Vector3 = CONTROLLER._camera_dash_lag_position(Vector3.ZERO, target, 0.8, 0.3, 0.5)
	approx(pos.distance_to(target), 0.0, 0.0001,
		"elapsed == delay + duration must still land exactly on the target with a delay in " +
		"play, or _process()'s hand-back to the hard weld snaps")
