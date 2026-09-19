extends "res://tests/test_case.gd"

# Covers pilot9's dash. See docs/specs/pilot9-dash.md.
#
# The feel cannot be checked headlessly - the vanish, the streak's appearance, and the
# blocked-dash cut all need real collision and a running frame, the same wall
# tests/test_pilot9_double_jump.gd and tests/test_pilot9_jump_slide.gd hit for the press
# itself. What IS reachable: the input action, the numbers, the ability-tab seam, the
# availability rule and the air charge as pure functions, the hide/restore round-trip, and
# the streak's own geometry.

const CONTROLLER := preload("res://scripts/pilot9.gd")
const TAB_ABILITIES := preload("res://scripts/ui/tabs/tab_abilities.gd")
const APPLY_STYLIZED := preload("res://scripts/rendering/apply_stylized.gd")
const PILOT_TSCN := "res://scenes/pilot9.tscn"

# One shared, in-tree instance for the hide/restore test only - see
# tests/test_pilot9_climb.gd's note on why: a fresh in-tree pilot9 per test leaks
# physics/render-server RIDs that a --script run never cleans up, and this file needs the
# tree for exactly one thing (the `character` subtree onready populates from).
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
	_pilot._dash_shadow_cache.clear()
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

# --- the hide/restore round-trip ---------------------------------------------------

func test_hide_reaches_invisible_and_restore_undoes_it_exactly() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var meshes: Array[MeshInstance3D] = []
	APPLY_STYLIZED.collect_meshes(root.character, meshes)
	check(meshes.size() > 0, "pilot9.tscn's character subtree has no mesh to hide")
	if meshes.is_empty():
		return

	# One mesh deliberately left off-default, so restore is checked against what it actually
	# had - not a blanket ON, which is the exact failure mode the spec calls out by name.
	meshes[0].visible = false
	var expected: Array[bool] = []
	for mi in meshes:
		expected.append(mi.visible)

	root._hide_for_dash()
	for mi in meshes:
		eq(mi.visible, false, "%s did not go invisible" % mi.name)

	root._restore_from_dash()
	for i in meshes.size():
		eq(meshes[i].visible, expected[i],
			"%s was not restored to its own original visibility" % meshes[i].name)

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

# _travel_direction() always zeroes y, so _dash_direction should never carry a vertical
# component in practice - but _apply_dash_velocity()'s hardcoded velocity.y = 0.0 is the one
# line this entire retune was not allowed to touch, so it gets its own seam rather than trusting
# an upstream guarantee silently.
func test_dash_velocity_never_gains_a_vertical_component() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("_dash_direction", Vector3(0.0, 1.0, 0.0))
	root.velocity = Vector3(0.0, -5.0, 0.0)
	root._apply_dash_velocity()
	eq(root.velocity.y, 0.0,
		"the dash must never change vertical velocity, however _dash_direction got steered")

# --- the ink streak's geometry -----------------------------------------------------
#
# The bundle of manga speed lines that replaced the single tapering ribbon on 2026-09-19 -
# see docs/specs/pilot9-dash.md, "The ink streak". _streak_bundle() is static and pure for
# exactly this: no tree, no camera, no renderer, same arguments in means same bundle out.

const STREAK_CFG := {
	"count": 7,
	"spread_side": 0.30,
	"spread_vert": 0.70,
	"anchor_height": 1.1,
	"converge": 0.25,
	"weight_min_px": 1.0,
	"weight_max_px": 3.0,
	"max_width": 0.12,
	"swell_bias": 0.65,
	"length_min": 0.4,
	"fade_stagger": 0.5,
	"boil_amount": 0.0,
}

# A straight run down +Z, long enough that even the shortest line (length_min 0.4) keeps
# several samples of its own.
func _streak_path(count: int = 20) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in range(count):
		points.append(Vector3(0, 0, float(i) * 0.5))
	return points

func _bundle(points: PackedVector3Array, cfg: Dictionary = STREAK_CFG,
		seed_value: int = 12345, boil_frame: int = 0) -> Array:
	return CONTROLLER._streak_bundle(points, Vector3(6, 2, -4), 75.0, 1080.0, cfg,
		seed_value, boil_frame)

func test_streak_bundle_does_not_crash_on_zero_or_one_point() -> void:
	check(_bundle(PackedVector3Array()).is_empty(),
		"zero sampled points must build nothing rather than error")
	var one := PackedVector3Array([Vector3.ZERO])
	check(_bundle(one).is_empty(),
		"one sampled point - a dash blocked on its first frame - must build nothing " +
		"rather than error")

func test_streak_bundle_draws_one_line_per_configured_count() -> void:
	var bundle := _bundle(_streak_path())
	eq(bundle.size(), 7, "expected one entry per configured line")
	for line in bundle:
		var verts: PackedVector3Array = line["verts"]
		check(verts.size() % 2 == 0, "a strip must be whole left/right pairs")
		check(verts.size() >= 4, "a line too short to draw must be dropped, not emitted short")

func test_streak_lines_are_spindles_thin_at_both_ends() -> void:
	# The pen profile is what makes a strip read as drawn rather than extruded: a line lands
	# thin, swells, and lifts thin. Both ENDS near zero and something substantial in between.
	for line in _bundle(_streak_path()):
		var verts: PackedVector3Array = line["verts"]
		var n := verts.size()
		approx(verts[0].distance_to(verts[1]), 0.0, 0.0001,
			"a line must taper to nothing at its own tail")
		approx(verts[n - 2].distance_to(verts[n - 1]), 0.0, 0.0001,
			"a line must taper to nothing at the head, where it meets him")
		var widest := 0.0
		for i in range(0, n, 2):
			widest = maxf(widest, verts[i].distance_to(verts[i + 1]))
		check(widest > 0.0, "a line that is zero width along its whole length is not a line")

func test_streak_pen_weight_is_constant_in_pixels_not_metres() -> void:
	# The reason the bundle is sized in pixels at all: every other ink in this game is
	# (outline_width is 4 px, crease.gdshader's line_width_px is 2 px), and a hairline sized
	# in metres goes sub-pixel and shimmers the moment the camera pulls back. Doubling the
	# camera distance must therefore roughly double the drawn width in metres.
	var points := _streak_path()
	var near := CONTROLLER._streak_bundle(points, Vector3(0, 0, -10), 75.0, 1080.0,
		STREAK_CFG, 12345, 0)
	var far := CONTROLLER._streak_bundle(points, Vector3(0, 0, -20), 75.0, 1080.0,
		STREAK_CFG, 12345, 0)
	eq(near.size(), far.size(), "the same seed must build the same number of lines")
	check(_widest(near) > 0.0, "the near bundle must draw something to compare")
	var ratio := _widest(far) / _widest(near)
	check(ratio > 1.5 and ratio < 2.5,
		"twice the distance must be about twice the width in metres - a constant pen " +
		"weight on screen. Got a ratio of %f" % ratio)

func test_streak_pen_weight_is_clamped_in_close() -> void:
	# ...but a pen weight is a fixed ANGULAR size, so without the ceiling a camera sitting on
	# top of the bundle resolves 3 px into a slab and undoes the whole effect.
	var points := _streak_path()
	var close := CONTROLLER._streak_bundle(points, Vector3(0, 0.5, 0.2), 75.0, 1080.0,
		STREAK_CFG, 12345, 0)
	check(_widest(close) <= STREAK_CFG["max_width"] + 0.0001,
		"no line may draw wider than streak_max_width however close the camera gets")

func _widest(bundle: Array) -> float:
	var widest := 0.0
	for line in bundle:
		var verts: PackedVector3Array = line["verts"]
		for i in range(0, verts.size(), 2):
			widest = maxf(widest, verts[i].distance_to(verts[i + 1]))
	return widest

func test_streak_lines_converge_toward_the_head_and_splay_at_the_tail() -> void:
	# "Coming out of him", stated as geometry: the bundle is wide where it is oldest and
	# pinched where it meets his chest. Measured as the spread of the lines' centrelines.
	var bundle := _bundle(_streak_path())
	check(_spread_at(bundle, true) > _spread_at(bundle, false) * 1.5,
		"the bundle must be markedly wider at the tail than where it meets him")
	check(_spread_at(bundle, false) > 0.0,
		"converge is 0.25, not 0 - the lines must stay a short segment apart at the head " +
		"rather than merging to a point")

# Greatest distance between any two lines' centres, at the tail end or the head end.
func _spread_at(bundle: Array, at_tail: bool) -> float:
	var centres: Array[Vector3] = []
	for line in bundle:
		var verts: PackedVector3Array = line["verts"]
		var i := 0 if at_tail else verts.size() - 2
		centres.append((verts[i] + verts[i + 1]) * 0.5)
	var widest := 0.0
	for a in centres:
		for b in centres:
			widest = maxf(widest, a.distance_to(b))
	return widest

func test_streak_bundle_is_centred_on_his_chest_not_his_feet() -> void:
	# _dash_points samples global_position, which is his FEET - the collision capsule sits
	# 0.978 m above it. Without streak_anchor_height the lines converge at his ankles.
	var bundle := _bundle(_streak_path())
	var lowest := INF
	for line in bundle:
		var verts: PackedVector3Array = line["verts"]
		for v in verts:
			lowest = minf(lowest, v.y)
	check(lowest > 0.1,
		"the path runs along y=0, his feet - no part of the bundle should be down there")

func test_streak_lines_end_ragged_rather_than_all_on_one_line() -> void:
	var lengths := {}
	for line in _bundle(_streak_path()):
		lengths[line["verts"].size()] = true
	check(lengths.size() > 1,
		"lines are handed lengths spread across [length_min, 1.0] - if they all came out " +
		"the same the bundle's tail is square and it reads as a comb")

func test_streak_lines_carry_a_spread_of_pen_weights() -> void:
	var widths: Array[float] = []
	for line in _bundle(_streak_path()):
		var verts: PackedVector3Array = line["verts"]
		var widest := 0.0
		for i in range(0, verts.size(), 2):
			widest = maxf(widest, verts[i].distance_to(verts[i + 1]))
		widths.append(widest)
	widths.sort()
	check(widths[widths.size() - 1] > widths[0] * 1.5,
		"weights are spread across [weight_min_px, weight_max_px] - seven identical " +
		"strokes is the comb this replaced")

func test_streak_fade_floors_run_thinnest_first() -> void:
	# The staggered fade: light strokes give up the most of the fade and wink out first, so
	# the last things on screen are the heaviest lines and the silhouette holds to the end.
	var floors_by_width := {}
	for line in _bundle(_streak_path()):
		var verts: PackedVector3Array = line["verts"]
		var widest := 0.0
		for i in range(0, verts.size(), 2):
			widest = maxf(widest, verts[i].distance_to(verts[i + 1]))
		floors_by_width[widest] = line["fade_floor"]
		check(line["fade_floor"] >= 0.0 and line["fade_floor"] < 1.0,
			"a fade floor at or past 1.0 would make a line invisible from the first frame")
	var widths := floors_by_width.keys()
	widths.sort()
	check(floors_by_width[widths[0]] > floors_by_width[widths[widths.size() - 1]],
		"the thinnest line must give up more of the fade than the heaviest")

func test_streak_bundle_is_stable_for_a_seed_and_differs_between_seeds() -> void:
	# Both halves matter. Stable, or the bundle boils on every physics frame whether the boil
	# is on or not; different, or every dash in a session draws the identical seven strokes.
	var points := _streak_path()
	var a := _bundle(points, STREAK_CFG, 111)
	var b := _bundle(points, STREAK_CFG, 111)
	for i in range(a.size()):
		check(a[i]["verts"] == b[i]["verts"], "the same seed must rebuild the same bundle")
	var c := _bundle(points, STREAK_CFG, 222)
	var differs := false
	for i in range(a.size()):
		if a[i]["verts"] != c[i]["verts"]:
			differs = true
	check(differs, "a different dash must draw a different bundle")

func test_streak_boil_moves_the_lines_only_when_it_is_on() -> void:
	var points := _streak_path()
	var off_0 := _bundle(points, STREAK_CFG, 111, 0)
	var off_3 := _bundle(points, STREAK_CFG, 111, 3)
	for i in range(off_0.size()):
		check(off_0[i]["verts"] == off_3[i]["verts"],
			"with boil_amount 0 the boil frame must have no effect at all")
	var boiling: Dictionary = STREAK_CFG.duplicate()
	boiling["boil_amount"] = 0.08
	var on_0 := _bundle(points, boiling, 111, 0)
	var on_3 := _bundle(points, boiling, 111, 3)
	var differs := false
	for i in range(on_0.size()):
		if on_0[i]["verts"] != on_3[i]["verts"]:
			differs = true
	check(differs, "with the boil on, a new boil frame must move the offsets")

func test_streak_survives_a_dash_that_never_moved() -> void:
	# A dash blocked on frame two: two samples, both at the same place, so every tangent is
	# degenerate. Must build something or nothing, but must not error.
	var stuck := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var bundle := _bundle(stuck)
	check(bundle is Array, "a dash that never moved must not error the geometry")

func test_streak_single_line_bundle_is_legal() -> void:
	# streak_line_count is exported down to 1, which is the old single ribbon back, near
	# enough - it has to build rather than divide by a zero span.
	var one: Dictionary = STREAK_CFG.duplicate()
	one["count"] = 1
	var bundle := _bundle(_streak_path(), one)
	eq(bundle.size(), 1, "a one-line bundle must build exactly one line")

# --- the camera catch-up -----------------------------------------------------------
#
# Covers _camera_dash_lag_position(), the arithmetic behind CameraPivot falling behind during
# a dash and gliding back on by the time `camera_dash_lag_delay + camera_dash_lag_time` is up -
# see docs/specs/pilot9-dash.md, Camera. The flag that turns it on and off
# (_camera_dash_lag_active), the elapsed-time clock, and the weld itself all live in _process(),
# a drawn-frame callback a --script run never ticks - same wall the vanish and the streak's
# appearance hit. This is the one piece of it that is a pure function, so it is the one piece
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
