extends "res://tests/test_case.gd"

# Covers pilot9's rail grind and the Rail node. See docs/specs/pilot9-rail-grind.md.
#
# The feel cannot be checked headlessly - the snap, the camera swing, the clip blend and both
# gears need a running frame. What IS reachable is the spec's own "Tests" list: the grid, the
# three gates, the direction, the bend, the refill, local space, the loop and the ability gate -
# plus the seams a rename would break silently (the tab row, the tree state, the ruler).

const CONTROLLER := preload("res://scripts/pilot9.gd")
const RAIL_SCRIPT := preload("res://scripts/rail.gd")
const TAB_ABILITIES := preload("res://scripts/ui/tabs/tab_abilities.gd")
const ANIMATION_SCRIPT := preload("res://scripts/pilot9_animation.gd")
const PILOT_TSCN := "res://scenes/pilot9.tscn"
const GRID_TSCN := "res://scenes/jump_grid.tscn"

const TOL := 0.001
## Far from anything else a test run leaves in the tree - the jump grid platform's own rails
## stay parented to root after its test file runs, and the catch tests must only see ours.
const FAR := Vector3(500.0, 50.0, 500.0)

# One shared in-tree pilot9 and one shared set of rails, for tests/test_pilot9_dash.gd's reason:
# a fresh in-tree pilot per test leaks server RIDs a --script run never cleans up.
var _pilot: Node = null
var _rails: Array[Node] = []
var _grid: Node3D = null


func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		(Engine.get_main_loop() as SceneTree).root.add_child(_pilot)
	_pilot._end_rail_grind(CONTROLLER.RailExit.LOST)
	_pilot._end_rail_switch()
	_pilot._rail_last = null
	_pilot._rail_lockout_left = 0.0
	_pilot._rail_sweep_valid = false
	_pilot.can_rail_grind = true
	_pilot.frozen = false
	_pilot.is_dashing = false
	_pilot.is_climbing = false
	_pilot.velocity = Vector3.ZERO
	return _pilot


# A straight rail `length` long along -Z from `origin`, in the tree under its own parent so the
# local-space test can move the parent.
func _rail(origin: Vector3, length: float = 10.0, closed: bool = false) -> Node:
	var parent := Node3D.new()
	parent.position = origin
	(Engine.get_main_loop() as SceneTree).root.add_child(parent)
	var rail = RAIL_SCRIPT.new()
	var c := Curve3D.new()
	if closed:
		# A square-ish loop, 4 m across.
		c.add_point(Vector3(0, 0, 0))
		c.add_point(Vector3(4, 0, 0))
		c.add_point(Vector3(4, 0, -4))
		c.add_point(Vector3(0, 0, -4))
		c.closed = true
	else:
		c.add_point(Vector3.ZERO)
		c.add_point(Vector3(0, 0, -length))
	rail.curve = c
	parent.add_child(rail)
	_rails.append(parent)
	return rail


func end() -> void:
	for n in _rails:
		if is_instance_valid(n):
			if n.get_parent():
				n.get_parent().remove_child(n)
			n.free()
	_rails.clear()
	super()


# --- the ability-tab seam --------------------------------------------------------

func test_base_kit_row_names_a_real_property() -> void:
	var property := ""
	for entry: Array in TAB_ABILITIES.BASE_KIT:
		if entry[0] == "RAIL GRIND":
			property = entry[1]
	check(property != "", "tab_abilities.gd's BASE_KIT has no 'RAIL GRIND' row")
	var body: CharacterBody3D = CONTROLLER.new()
	check(property in body, "scripts/pilot9.gd has no '%s' property - the row reads nothing" % property)
	body.free()


func test_tech_no_longer_lists_rail_grind() -> void:
	for entry: Array in TAB_ABILITIES.TECH:
		check(entry[0] != "RAIL GRIND",
			"RAIL GRIND is built - TECH must not still render it LOCKED under BASE_KIT's row")


# --- the numbers -----------------------------------------------------------------

func test_exported_knobs_have_the_spec_defaults() -> void:
	var b: CharacterBody3D = CONTROLLER.new()
	check(b.can_rail_grind, "can_rail_grind defaults on")
	approx(b.rail_grind_speed, 15.0, TOL, "rail_grind_speed")
	approx(b.rail_sprint_speed, 20.0, TOL, "rail_sprint_speed")
	approx(b.rail_speed_ease_time, 0.25, TOL, "rail_speed_ease_time")
	approx(b.rail_catch_radius, 1.0, TOL, "rail_catch_radius")
	approx(b.rail_snap_time, 0.08, TOL, "rail_snap_time")
	approx(b.rail_relatch_lockout, 0.3, TOL, "rail_relatch_lockout")
	approx(b.rail_jump_max_bend, 45.0, TOL, "rail_jump_max_bend")
	approx(b.rail_coyote_time, 0.15, TOL, "rail_coyote_time")
	approx(b.rail_camera_idle_delay, 0.3, TOL, "rail_camera_idle_delay")
	approx(b.rail_camera_swing_rate, 90.0, TOL, "rail_camera_swing_rate")
	b.free()


func test_rail_defaults() -> void:
	var r = RAIL_SCRIPT.new()
	approx(r.rail_radius, 0.08, TOL, "rail_radius")
	eq(r.rail_sides, 8, "rail_sides")
	r.free()


# --- the grid --------------------------------------------------------------------

# The two gears are measured against the jump grid: 18 m and 24 m, both rail-only rungs (the
# gears were doubled 2026-09-24). Move a gear or the airtime and these fail, which is the point.
func test_the_grid() -> void:
	var b: CharacterBody3D = CONTROLLER.new()
	approx(b.rail_jump_distance(b.rail_grind_speed), 18.0, TOL, "the grind gear clears 18 m")
	approx(b.rail_jump_distance(b.rail_sprint_speed), 24.0, TOL, "rail sprint clears 24 m")
	approx(b.rail_jump_distance(b.rail_grind_speed), 2.0 * b.jump_distance(b.sprint_speed), TOL,
		"the grind gear's jump is twice the sprint rung")
	b.free()


# --- the gates -------------------------------------------------------------------

func test_in_range_and_above_catches() -> void:
	check(CONTROLLER._rail_catch_gates(Vector3(0, 0.3, 0), Vector3.ZERO, Vector3.UP, 0.3, 0.5,
		false), "0.3 m above the centreline, in range, catches")


func test_below_the_centreline_refuses() -> void:
	check(not CONTROLLER._rail_catch_gates(Vector3(0, -0.3, 0), Vector3.ZERO, Vector3.UP, 0.3,
		0.5, false), "rising up through a rail from underneath does not catch")


func test_out_of_range_refuses() -> void:
	check(not CONTROLLER._rail_catch_gates(Vector3(0, 0.6, 0), Vector3.ZERO, Vector3.UP, 0.6,
		0.5, false), "0.6 m off a 0.5 m radius does not catch")


func test_locked_out_refuses() -> void:
	check(not CONTROLLER._rail_catch_gates(Vector3(0, 0.3, 0), Vector3.ZERO, Vector3.UP, 0.3,
		0.5, true), "the rail just left refuses inside the lockout")


func test_above_is_along_the_rails_up() -> void:
	# A rail tipped onto its side: "above" is its up, not the world's.
	check(CONTROLLER._rail_catch_gates(Vector3(0.3, 0, 0), Vector3.ZERO, Vector3.RIGHT, 0.3,
		0.5, false), "above along the rail's own up catches")
	check(not CONTROLLER._rail_catch_gates(Vector3(-0.3, 0.1, 0), Vector3.ZERO, Vector3.RIGHT,
		0.32, 0.5, false), "under along its own up refuses, though world-up calls it above")


# Side-on, feet level with the centreline or under it but more off to the side than below: a
# catch. Before 2026-09-24 these missed and he went through the tube.
func test_a_side_approach_below_the_centreline_catches() -> void:
	check(CONTROLLER._rail_catch_gates(Vector3(0.3, 0, 0), Vector3.ZERO, Vector3.UP, 0.3, 0.5,
		false), "level with the centreline, off to the side")
	check(CONTROLLER._rail_catch_gates(Vector3(0.3, -0.2, 0), Vector3.ZERO, Vector3.UP, 0.36, 0.5,
		false), "under it, but more to the side than below")
	check(not CONTROLLER._rail_catch_gates(Vector3(0.2, -0.3, 0), Vector3.ZERO, Vector3.UP, 0.36,
		0.5, false), "more below than to the side is from underneath")


# End to end: a flat side-on pass at centreline height catches.
func test_crossing_a_rail_side_on_at_its_height_catches() -> void:
	var p := _scene()
	_rail(FAR)
	p.velocity = Vector3(7.5, 0, 0)
	p.global_position = FAR + Vector3(-1.1, -0.1, -5)
	p._handle_rail_grind(1.0 / 60.0)
	check(not p.is_rail_grinding, "out of reach: no catch yet")
	p.global_position = FAR + Vector3(0.9, -0.1, -5)
	p._handle_rail_grind(1.0 / 60.0)
	check(p.is_rail_grinding, "the frame that crossed it side-on caught it")


# The lockout end to end: the same rail refuses, a different one catches at once.
func test_lockout_refuses_the_same_rail_and_not_another() -> void:
	var p := _scene()
	var a := _rail(FAR)
	var b := _rail(FAR + Vector3(20, 0, 0))
	p.global_position = FAR + Vector3(0, 0.3, -5)
	p.velocity = Vector3(0, -2, -3)
	check(p._try_catch_rail(), "falling onto rail A catches")
	check(p._rail == a, "and it is rail A")
	p._end_rail_grind(CONTROLLER.RailExit.CROUCH)
	p.global_position = FAR + Vector3(0, 0.3, -5)
	check(not p._try_catch_rail(), "rail A refuses a re-catch inside the lockout")
	p.global_position = FAR + Vector3(20, 0.3, -5)
	check(p._try_catch_rail(), "rail B catches at once")
	check(p._rail == b, "and it is rail B")


func test_rising_through_a_rail_does_not_catch() -> void:
	var p := _scene()
	_rail(FAR)
	p.global_position = FAR + Vector3(0, -0.3, -5)
	p.velocity = Vector3(0, 5, 0)
	check(not p._try_catch_rail(), "feet under the centreline refuse")


# The tunnelling bug: a fall faster than the catch zone is deep stepped from above it to below
# the centreline between two frames, and neither frame's feet were inside it. 0.3 m to the side
# the zone is 0.95 m deep; this frame goes 1.0 m above to 0.05 m below - 63 m/s at 60 Hz.
func test_a_fall_that_steps_over_the_zone_still_catches() -> void:
	var p := _scene()
	_rail(FAR)
	var above := FAR + Vector3(0.3, 1.0, -5)
	var below := FAR + Vector3(0.3, -0.05, -5)
	p.velocity = Vector3(0, -63, 0)
	p.global_position = above
	p._handle_rail_grind(1.0 / 60.0)
	check(not p.is_rail_grinding, "the frame above the zone does not catch")
	p.global_position = below
	p._handle_rail_grind(1.0 / 60.0)
	check(p.is_rail_grinding, "the frame below the centreline catches the rail it fell past")
	check(p.global_position.y > FAR.y, "and his feet go back to where the path met the zone")


func test_the_same_step_with_no_last_frame_does_not_catch() -> void:
	var p := _scene()
	_rail(FAR)
	p.velocity = Vector3(0, -30, 0)
	p.global_position = FAR + Vector3(0.3, 0.45, -5)
	p._rail_sweep_from = p.global_position
	p._rail_sweep_valid = false
	# More under the rail than beside it - a point the gates refuse on its own.
	p.global_position = FAR + Vector3(0.3, -0.35, -5)
	check(not p._try_catch_rail(), "no sweep to run: only where he is now is tested")


func test_sweep_points() -> void:
	var a := Vector3(0, 1, 0)
	var b := Vector3(0, 0, 0)
	var pts: PackedVector3Array = CONTROLLER._rail_sweep_points(a, b, true)
	check(pts.size() >= 1.0 / CONTROLLER.RAIL_SWEEP_STEP - 0.5, "a metre is stepped finely")
	check(pts[pts.size() - 1].is_equal_approx(b), "the last point is where he is now")
	check(not pts[0].is_equal_approx(a), "last frame's point is not tested twice")
	for i in range(1, pts.size()):
		check(pts[i].distance_to(pts[i - 1]) <= CONTROLLER.RAIL_SWEEP_STEP + TOL,
			"no step longer than RAIL_SWEEP_STEP")
	check(CONTROLLER._rail_sweep_points(a, b, false).size() == 1, "invalid: just now")
	var far := Vector3(0, CONTROLLER.RAIL_SWEEP_MAX + 1.0, 0)
	check(CONTROLLER._rail_sweep_points(far, b, true).size() == 1, "a teleport: just now")


func test_landing_breaks_the_sweep() -> void:
	var p := _scene()
	p.global_position = FAR
	p._rail_sweep_valid = true
	p.is_dashing = true
	p._handle_rail_grind(1.0 / 60.0)
	check(not p._rail_sweep_valid, "a frame the catch does not run breaks the sweep")
	p.is_dashing = false


func test_can_rail_grind_false_refuses_every_catch() -> void:
	var p := _scene()
	_rail(FAR)
	p.can_rail_grind = false
	p.global_position = FAR + Vector3(0, 0.3, -5)
	p.velocity = Vector3(0, -2, 0)
	p._handle_rail_grind(1.0 / 60.0)
	check(not p.is_rail_grinding, "can_rail_grind off: no catch")
	p.can_rail_grind = true
	p._handle_rail_grind(1.0 / 60.0)
	check(p.is_rail_grinding, "and on again, the same frame catches")


func test_the_tip_it_would_ride_off_is_refused() -> void:
	var p := _scene()
	_rail(FAR, 10.0)
	# At the -Z end, travelling -Z: the ride would leave on its first frame.
	p.global_position = FAR + Vector3(0, 0.3, -9.98)
	p.velocity = Vector3(0, -2, -5)
	check(not p._try_catch_rail(), "a catch that would ride straight off the end is refused")
	p.velocity = Vector3(0, -2, 5)
	check(p._try_catch_rail(), "the same tip ridden back along the rail catches")


# --- the direction ---------------------------------------------------------------

func test_direction_follows_velocity() -> void:
	var t := Vector3(0, 0, -1)
	eq(CONTROLLER._rail_ride_dir(t, Vector3(0, 0, -5), Vector3(0, 0, 1)), 1,
		"velocity along +tangent rides +1")
	eq(CONTROLLER._rail_ride_dir(t, Vector3(0, 0, 5), Vector3(0, 0, -1)), -1,
		"velocity along -tangent rides -1, whatever the facing")


func test_a_vertical_drop_takes_the_facing() -> void:
	var t := Vector3(0, 0, -1)
	eq(CONTROLLER._rail_ride_dir(t, Vector3.ZERO, Vector3(0, 0, -1)), 1, "facing +tangent: +1")
	eq(CONTROLLER._rail_ride_dir(t, Vector3.ZERO, Vector3(0, 0, 1)), -1, "facing -tangent: -1")
	eq(CONTROLLER._rail_ride_dir(t, Vector3(0.1, 0, 0.2), Vector3(0, 0, -1)), 1,
		"a drift under RAIL_DIR_MIN_SPEED still counts as a drop")


# Side-on: fast, but the momentum ALONG the rail is what counts.
func test_a_side_approach_rides_the_way_its_momentum_leans() -> void:
	var t := Vector3(0, 0, -1)
	eq(CONTROLLER._rail_ride_dir(t, Vector3(7.5, 0, 1.0), Vector3(1, 0, 0)), -1,
		"mostly across, leaning +Z: rides -1")
	eq(CONTROLLER._rail_ride_dir(t, Vector3(7.5, 0, -1.0), Vector3(1, 0, 0)), 1,
		"mostly across, leaning -Z: rides +1")


func test_dead_square_across_falls_to_facing_then_camera() -> void:
	var t := Vector3(0, 0, -1)
	eq(CONTROLLER._rail_ride_dir(t, Vector3(7.5, 0, 0.1), Vector3(0.7, 0, 0.7)), -1,
		"momentum square across: the facing's lean decides")
	eq(CONTROLLER._rail_ride_dir(t, Vector3(7.5, 0, 0.1), Vector3(1, 0, 0), Vector3(0.5, 0, -0.8)),
		1, "facing square too: the camera decides")


func test_a_side_approach_at_a_tip_rides_back_along_the_rail() -> void:
	var p := _scene()
	_rail(FAR, 10.0)
	# Square across the -Z tip, the tiebreak pointing off it: it rides back instead of refusing.
	p.global_position = FAR + Vector3(0.1, 0.2, -9.98)
	p.velocity = Vector3(-7.5, -2, -0.2)
	check(p._try_catch_rail(), "a side-on catch at the tip is not refused")
	eq(p._rail_dir, -1, "and it rides back along the rail")


# --- the curve lean ----------------------------------------------------------------

func test_a_straight_rail_leans_nothing() -> void:
	var t := Vector3(0, 0, -1)
	approx(CONTROLLER._rail_lean_roll(t, t, 1.5, 10.0, 6.0), 0.0, TOL, "upright on a straight")


func test_a_right_bend_leans_right_and_a_left_bend_left() -> void:
	var t := Vector3(0, 0, -1)
	var right := t.rotated(Vector3.UP, deg_to_rad(-20.0))
	var left := t.rotated(Vector3.UP, deg_to_rad(20.0))
	approx(CONTROLLER._rail_lean_roll(t, right, 1.5, 10.0, 6.0), deg_to_rad(10.0), TOL,
		"a tight right bend: full lean, positive rotation.z tips his head right")
	approx(CONTROLLER._rail_lean_roll(t, left, 1.5, 10.0, 6.0), deg_to_rad(-10.0), TOL,
		"a tight left bend: full lean the other way")


func test_a_gentle_bend_leans_in_proportion() -> void:
	var t := Vector3(0, 0, -1)
	var right := t.rotated(Vector3.UP, deg_to_rad(-4.5))  # 3 deg/m over 1.5 m: half of 6
	approx(CONTROLLER._rail_lean_roll(t, right, 1.5, 10.0, 6.0), deg_to_rad(5.0), TOL,
		"half the full turn rate, half the lean")


func test_a_rail_climbing_straight_does_not_lean() -> void:
	var a := Vector3(0, 0.2, -1).normalized()
	var b := Vector3(0, 0.6, -1).normalized()
	approx(CONTROLLER._rail_lean_roll(a, b, 1.5, 10.0, 6.0), 0.0, TOL,
		"a change in slope is not a bend")


# --- the bend --------------------------------------------------------------------

func test_neutral_stick_is_the_tangent() -> void:
	var h: Vector3 = CONTROLLER._rail_jump_heading(Vector3(0, 0, -1), Vector3.ZERO, 45.0)
	check(h.is_equal_approx(Vector3(0, 0, -1)), "neutral stick launches along the tangent: %s" % h)


func test_a_stick_ninety_off_is_capped_at_forty_five() -> void:
	var t := Vector3(0, 0, -1)
	var h: Vector3 = CONTROLLER._rail_jump_heading(t, Vector3(1, 0, 0), 45.0)
	approx(rad_to_deg(t.angle_to(h)), 45.0, 0.01, "bent the full 45 degrees and no further")
	check(h.x > 0.0, "toward the stick")
	approx(h.length(), 1.0, TOL, "unit length - speed and grid distance unchanged")


func test_a_small_bend_is_taken_whole() -> void:
	var t := Vector3(0, 0, -1)
	var stick := t.rotated(Vector3.UP, deg_to_rad(20.0))
	var h: Vector3 = CONTROLLER._rail_jump_heading(t, stick, 45.0)
	approx(rad_to_deg(t.angle_to(h)), 20.0, 0.01, "inside the cap, the stick's heading exactly")


func test_a_sloped_tangent_launches_flat() -> void:
	var h: Vector3 = CONTROLLER._rail_jump_heading(Vector3(0, 0.5, -1).normalized(), Vector3.ZERO,
		45.0)
	approx(h.y, 0.0, TOL, "the heading is horizontal - jump_velocity owns the vertical")
	approx(h.length(), 1.0, TOL, "and unit length, so a downhill rail's jump still clears 9 m")


# --- the gears -------------------------------------------------------------------

func test_speed_eases_to_the_gear_both_ways() -> void:
	approx(CONTROLLER._rail_speed_at(0.0, 7.5, 0.25, 0.0), 0.0, TOL, "starts at entry speed")
	approx(CONTROLLER._rail_speed_at(0.0, 7.5, 0.25, 0.125), 3.75, TOL, "linear through the ease")
	approx(CONTROLLER._rail_speed_at(0.0, 7.5, 0.25, 1.0), 7.5, TOL, "and held at the gear")
	approx(CONTROLLER._rail_speed_at(14.0, 7.5, 0.25, 0.25), 7.5, TOL,
		"a faster entry is brought DOWN to the gear, not held")


# --- the refill ------------------------------------------------------------------

func test_starting_a_grind_refills_like_a_landing() -> void:
	var p := _scene()
	var r := _rail(FAR)
	p.global_position = FAR + Vector3(0, 0.3, -5)
	p._air_jumps_left = 0
	p._dash_air_charge = false
	p._wall_jumps_taken = 3
	p._start_rail_grind(r, 5.0, 1)
	check(p.is_rail_grinding, "grinding")
	eq(p._air_jumps_left, p.air_jumps, "the double jump is back")
	check(p._dash_air_charge, "the dash's air charge is back")
	eq(p._wall_jumps_taken, 0, "the wall-jump chain is reset")


# The rail's gear is the ground sprint toggle: caught sprinting he rail-sprints, otherwise he
# grinds, and a gear change mid-ride follows the toggle - not a held button.
func test_the_gear_is_the_sprint_toggle() -> void:
	var p := _scene()
	var r := _rail(FAR)
	p.global_position = FAR + Vector3(0, 0.3, -5)
	p.sprint_toggled = true
	p._start_rail_grind(r, 5.0, 1)
	check(p.is_rail_sprinting, "caught sprinting, he rail-sprints")
	eq(p._rail_speed_to, p.rail_sprint_speed, "at the sprint gear")
	p._end_rail_grind(CONTROLLER.RailExit.JUMP)
	p._rail_lockout_left = 0.0
	p.sprint_toggled = false
	p._start_rail_grind(r, 5.0, 1)
	check(not p.is_rail_sprinting, "caught not sprinting, he grinds")
	eq(p._rail_speed_to, p.rail_grind_speed, "at the grind gear")
	p.sprint_toggled = true
	p._handle_rail_grind(1.0 / 60.0)
	check(p.is_rail_sprinting, "toggling sprint on the rail shifts to the sprint gear")


func test_leaving_starts_the_lockout_and_only_the_end_opens_coyote() -> void:
	var p := _scene()
	var r := _rail(FAR)
	p.global_position = FAR + Vector3(0, 0.3, -5)
	p._start_rail_grind(r, 5.0, 1)
	p._end_rail_grind(CONTROLLER.RailExit.JUMP)
	check(not p.is_rail_grinding, "a jump ends the grind")
	check(p._rail_last == r and p._rail_lockout_left > 0.0, "and starts the same-rail lockout")
	approx(p._rail_coyote_left, 0.0, TOL, "a jump opens no rail coyote")
	p._start_rail_grind(r, 5.0, 1)
	p._end_rail_grind(CONTROLLER.RailExit.END)
	approx(p._rail_coyote_left, p.rail_coyote_time, TOL, "running off the end opens it")


# Riding off an open end hands him the end tangent at ride speed and the coyote; a closed
# curve never ends.
func test_running_off_the_end_launches_along_it() -> void:
	var p := _scene()
	var r := _rail(FAR, 10.0)
	p.global_position = FAR + Vector3(0, 0.08, -9.9)
	p._start_rail_grind(r, 9.9, 1)
	p._rail_speed = 7.5
	p._rail_speed_from = 7.5
	p._rail_speed_to = 7.5
	p._handle_rail_grind(1.0 / 30.0)
	check(not p.is_rail_grinding, "0.25 m of travel off 0.1 m of rail ends the ride")
	check(p.velocity.is_equal_approx(Vector3(0, 0, -7.5)),
		"he carries on along the end tangent at ride speed: %s" % p.velocity)
	check(p._rail_coyote_left > 0.0, "with the rail coyote open")
	check(p._rail_launch_carry, "and the stick keeps the ride speed until he lands")
	approx(p._rail_launch_speed, 7.5, TOL, "at the ride speed")
	p._rail_launch_carry = false


# --- local space -----------------------------------------------------------------

# The moving-rail guarantee: the ride is an offset, so moving the rail's parent moves where
# that offset is in the world by exactly as much. Sampled through global_transform, no physics.
func test_a_moving_rail_carries_the_rider() -> void:
	var r := _rail(FAR)
	var before: Vector3 = r.top_at(4.0)
	var shift := Vector3(5.0, 1.0, -3.0)
	(r.get_parent() as Node3D).position += shift
	var after: Vector3 = r.top_at(4.0)
	check((after - before).is_equal_approx(shift),
		"the same offset moved with the parent: %s vs %s" % [after - before, shift])


func test_a_turned_rail_turns_its_tangent() -> void:
	var r := _rail(FAR)
	var before: Vector3 = r.tangent_at(4.0)
	(r.get_parent() as Node3D).rotation.y = PI * 0.5
	var after: Vector3 = r.tangent_at(4.0)
	check(before.is_equal_approx(Vector3(0, 0, -1)), "along -Z before: %s" % before)
	check(after.is_equal_approx(Vector3(-1, 0, 0)), "and along -X after a quarter turn: %s" % after)


func test_the_rider_rides_on_top_of_the_tube() -> void:
	var r := _rail(FAR)
	var top: Vector3 = r.top_at(3.0)
	var centre: Vector3 = r.point_at(3.0)
	approx(top.y - centre.y, r.rail_radius, TOL, "feet at centreline + rail_radius")


# --- the loop --------------------------------------------------------------------

func test_offset_past_the_end_wraps_on_a_closed_curve() -> void:
	approx(CONTROLLER._rail_offset_advanced(15.5, 1.0, 16.0, true), 0.5, TOL, "wraps forward")
	approx(CONTROLLER._rail_offset_advanced(0.25, -0.5, 16.0, true), 15.75, TOL, "and backward")
	check(not CONTROLLER._rail_offset_ended(0.5, 16.0, true), "a loop never ends")


func test_offset_past_the_end_ends_an_open_curve() -> void:
	var next: float = CONTROLLER._rail_offset_advanced(15.5, 1.0, 16.0, false)
	check(CONTROLLER._rail_offset_ended(next, 16.0, false), "past the far end ends")
	check(CONTROLLER._rail_offset_ended(-0.1, 16.0, false), "so does past the near end")
	check(not CONTROLLER._rail_offset_ended(8.0, 16.0, false), "in the middle does not")


func test_a_closed_rail_reports_a_loop() -> void:
	var r := _rail(FAR, 0.0, true)
	check(r.is_loop(), "closed curve reads as a loop")
	approx(r.ride_length(), 16.0, 0.05, "and its length includes the closing side")


# --- the rail node ---------------------------------------------------------------

func test_a_rail_joins_the_group() -> void:
	var r := _rail(FAR)
	check(r.is_in_group(CONTROLLER.RAIL_GROUP), "pilot9 finds rails through the group")


func test_the_tube_is_generated_and_has_no_collision() -> void:
	var r := _rail(FAR)
	var tube := r.get_node_or_null(RAIL_SCRIPT.TUBE_NAME) as MeshInstance3D
	check(tube != null and tube.mesh != null, "the tube is generated from the curve")
	check(r.find_children("*", "CollisionObject3D", true, false).is_empty(),
		"and nothing on a rail collides")


func test_tube_rings_sit_at_the_radius() -> void:
	var pts := PackedVector3Array([Vector3.ZERO, Vector3(0, 0, -4)])
	var mesh: ArrayMesh = RAIL_SCRIPT.tube_mesh(pts, 0.1, 8, false)
	check(mesh != null, "a straight line sweeps")
	if mesh == null:
		return
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var off_axis := 0
	for v in verts:
		var r := Vector2(v.x, v.y).length()
		if r > TOL and absf(r - 0.1) > TOL:
			off_axis += 1
	eq(off_axis, 0, "every ring vertex is exactly rail_radius off the centreline")


# --- the animation seam ----------------------------------------------------------

func test_the_tree_has_the_rail_state_and_its_gear_blend() -> void:
	var ps := load(PILOT_TSCN) as PackedScene
	var n := ps.instantiate()
	var ap := n.get_node("AnimationPlayer") as AnimationPlayer
	check(ap.has_animation(&"rail_grind"), "rail_grind is in the library")
	check(ap.has_animation(&"rail_sprint"), "rail_sprint is in the library")
	var sm := (n.get_node("AnimationTree") as AnimationTree).tree_root as AnimationNodeStateMachine
	check(sm.has_node(&"rail"), "the tree has a `rail` state")
	var bt := sm.get_node(&"rail") as AnimationNodeBlendTree
	check(bt != null and bt.has_node(&"RailGear"), "with the RailGear blend")
	# pilot9_animation.gd writes this path; a rename on either side fails silently in game.
	check(ANIMATION_SCRIPT.RAIL_GEAR == "parameters/rail/RailGear/blend_amount",
		"the driver's path names the state and node the builder makes")
	check(sm.has_transition(&"fall", &"rail") and sm.has_transition(&"jump", &"rail"),
		"both airborne states enter it")
	n.free()


# --- the ruler -------------------------------------------------------------------

func _platform() -> Node3D:
	if _grid == null or not is_instance_valid(_grid):
		var ps := load(GRID_TSCN) as PackedScene
		_grid = ps.instantiate() as Node3D
		(Engine.get_main_loop() as SceneTree).root.add_child(_grid)
	return _grid


# The landing pad sits exactly the gear's jump past the rail's end, top level with his feet.
func test_the_ruler_rail_gaps_measure_what_they_claim() -> void:
	var grid := _platform()
	var rails := grid.get_node_or_null("Rails")
	check(rails != null, "the jump grid builds a Rails row")
	if rails == null:
		return
	var b: CharacterBody3D = CONTROLLER.new()
	var expected := {
		"Rail_18m": b.rail_jump_distance(b.rail_grind_speed),
		"Rail_24m": b.rail_jump_distance(b.rail_sprint_speed),
	}
	b.free()
	for station_name in expected:
		var station := rails.get_node_or_null(station_name)
		check(station != null, "the ruler has %s" % station_name)
		if station == null:
			continue
		var rail = station.get_node("Rail")
		var landing := station.get_node("Landing") as StaticBody3D
		var shape := landing.get_node("Shape") as CollisionShape3D
		var size := (shape.shape as BoxShape3D).size
		var end: Vector3 = rail.top_at(rail.ride_length())
		var near_face := shape.global_position.z + size.z * 0.5
		approx(end.z - near_face, float(expected[station_name]), 0.01,
			"%s: rail end to landing pad" % station_name)
		approx(shape.global_position.y + size.y * 0.5, end.y, 0.01,
			"%s: the pad's top is level with his feet on the rail" % station_name)
	var hop := rails.get_node_or_null("Rail_Hop")
	check(hop != null and hop.get_node_or_null("Rail1") != null
		and hop.get_node_or_null("Rail2") != null, "the parallel pair is built")


# -- rail to rail: the switch and the held cap ("Rail to rail" in the spec) ---------------

func test_switch_side_needs_the_stick_thirty_off() -> void:
	var t := Vector3(0, 0, -1)                        # riding -Z; right of the ride is +X
	eq(CONTROLLER._rail_switch_side(t, Vector3.ZERO, 30.0), 0, "neutral is not a switch")
	eq(CONTROLLER._rail_switch_side(t, t.rotated(Vector3.UP, deg_to_rad(-20.0)), 30.0), 0,
		"20 degrees off is the ordinary jump")
	eq(CONTROLLER._rail_switch_side(t, Vector3(1, 0, 0), 30.0), 1, "full right aims right")
	eq(CONTROLLER._rail_switch_side(t, Vector3(-1, 0, -1), 30.0), -1, "diagonal left aims left")


func test_switch_target_gates() -> void:
	var t := Vector3(0, 0, -1)
	var feet := Vector3.ZERO
	var ahead := Vector3(0, 0, -3)
	var ok := func(target: Vector3, side: int) -> bool:
		return CONTROLLER._rail_switch_target_ok(feet, ahead, target, t, side, 6.0, 2.0, 4.0)
	check(ok.call(Vector3(3, 0, -3), 1), "a parallel rail 3 m right qualifies")
	check(not ok.call(Vector3(3, 0, -3), -1), "but not when the stick aims left")
	check(not ok.call(Vector3(0.2, 0, -3), 1), "a rail on his own line is never a switch")
	check(not ok.call(Vector3(7, 0, -3), 1), "out of reach")
	check(not ok.call(Vector3(3, 2.5, -3), 1), "too high")
	check(not ok.call(Vector3(3, -4.5, -3), 1), "too far down")
	check(ok.call(Vector3(3, -3.5, -3), 1), "a drop inside the limit")


func test_switch_arc_ends_and_peaks() -> void:
	var a := Vector3(0, 5, 0)
	var b := Vector3(3, 3, -3)
	check(CONTROLLER._rail_switch_arc(a, b, 0.0, 1.0).is_equal_approx(a), "starts at his feet")
	check(CONTROLLER._rail_switch_arc(a, b, 1.0, 1.0).is_equal_approx(b), "ends on the rail")
	approx(CONTROLLER._rail_switch_arc(a, b, 0.5, 1.0).y, 4.0 + 1.0 + 1.0, TOL,
		"mid-flight: the straight line's 4 m plus the bump plus half the 2 m drop")


func test_a_switch_lands_on_the_parallel_rail_with_its_speed() -> void:
	var p := _scene()
	var a := _rail(FAR, 14.0)
	var b := _rail(FAR + Vector3(3, 0, 0), 14.0)
	p.global_position = a.top_at(4.0)
	p._start_rail_grind(a, 4.0, 1)
	p._rail_speed = 7.5
	Input.action_press("right")
	var switched: bool = p._try_rail_switch()
	Input.action_release("right")
	check(switched, "the stick aimed at the rail 3 m right starts a switch")
	check(p.is_rail_switching and not p.is_rail_grinding, "in flight, off the first rail")
	check(p._switch_rail == b, "onto the parallel rail")
	var dt := 1.0 / 60.0
	for i in int(ceil(p.rail_switch_time / dt)) + 1:
		p._tick_rail_switch(dt)
	check(p.is_rail_grinding and p._rail == b, "landed on it")
	approx(p._rail_speed, 7.5, TOL, "with the speed he left with")
	eq(p._rail_dir, 1, "riding on the way he was going")


func test_no_rail_that_way_is_the_ordinary_jump() -> void:
	var p := _scene()
	var a := _rail(FAR, 14.0)
	_rail(FAR + Vector3(-3, 0, 0), 14.0)            # left of him; the stick says right
	p.global_position = a.top_at(4.0)
	p._start_rail_grind(a, 4.0, 1)
	p._rail_speed = 7.5
	Input.action_press("right")
	var switched: bool = p._try_rail_switch()
	Input.action_release("right")
	check(not switched, "nothing to the right - no switch")
	check(p.is_rail_grinding, "still on the rail for the ordinary jump to take")


func test_the_rail_jump_keeps_the_ride_speed() -> void:
	var p := _scene()
	p.direction = Vector3.ZERO
	p._take_rail_jump(Vector3(0, 0, -15.0))
	approx(Vector3(p.velocity.x, 0, p.velocity.z).length(), 15.0, TOL, "full gear speed off it")
	approx(p.velocity.z, -15.0, TOL, "along the ride")
	approx(p.velocity.y, p.jump_velocity, TOL, "an ordinary jump up")
	check(p._rail_launch_carry, "carried until he lands")
	p._rail_launch_carry = false


func test_a_pushed_stick_jumps_off_where_it_points() -> void:
	var p := _scene()
	p.direction = Vector3(1, 0, 0)                   # square across the rail
	p._take_rail_jump(Vector3(0, 0, -15.0))
	approx(p.velocity.x, 15.0, TOL, "no 45 degree cap - straight where the stick points")
	approx(p._rail_launch_speed, 15.0, TOL, "at the ride speed")
	p.direction = Vector3.ZERO
	p._rail_launch_carry = false


func test_the_stick_turns_a_carry_freely_at_ride_speed() -> void:
	var p := _scene()
	p._rail_launch_carry = true
	p._rail_launch_speed = 20.0
	p.velocity = Vector3(0, 2.0, -20.0)
	p.direction = Vector3(0, 0, 1)                   # straight back the way he came
	p.input_strength = 1.0
	p._apply_stick_movement(1.0 / 60.0)
	approx(p.velocity.z, 20.0, TOL, "turned all the way round, full ride speed")
	p.direction = Vector3.ZERO
	p._rail_launch_carry = false


func test_a_released_stick_brakes_a_carry_and_pushing_brings_it_back() -> void:
	var p := _scene()
	p._rail_launch_carry = true
	p._rail_launch_speed = 20.0
	p.velocity = Vector3(0, 2.0, -20.0)
	p.direction = Vector3.ZERO
	p._apply_stick_movement(1.0 / 60.0)
	check(Vector3(p.velocity.x, 0, p.velocity.z).length() < 20.0 - TOL,
		"no stick - no momentum kept, the air brake takes it")
	p.direction = Vector3(1, 0, 0)
	p.input_strength = 1.0
	p._apply_stick_movement(1.0 / 60.0)
	approx(p.velocity.x, 20.0, TOL, "push again and the ride speed is straight back")
	p.direction = Vector3.ZERO
	p._rail_launch_carry = false


func test_the_landing_ease_runs_from_landing_speed_to_the_target() -> void:
	approx(CONTROLLER._rail_land_speed_at(20.0, 5.0, 0.5, 0.0), 20.0, TOL, "starts at landing speed")
	approx(CONTROLLER._rail_land_speed_at(20.0, 5.0, 0.5, 0.25), 12.5, TOL, "halfway at half time")
	approx(CONTROLLER._rail_land_speed_at(20.0, 5.0, 0.5, 0.5), 5.0, TOL, "back to normal")
	approx(CONTROLLER._rail_land_speed_at(20.0, 5.0, 0.5, 9.0), 5.0, TOL, "and stays there")
	check(CONTROLLER._rail_land_speed_at(20.0, 5.0, 0.5, 0.05) > 19.5, "eases out, not a cliff")
	approx(CONTROLLER._rail_land_speed_at(20.0, 5.0, 0.0, 0.0), 5.0, TOL, "0 s snaps")
