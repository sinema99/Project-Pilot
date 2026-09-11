extends "res://tests/test_case.gd"

# Covers slopes as momentum: gravity accelerating a slide down a grade, friction bleeding that
# gain back off, steep ground sliding him whether he asked or not, and the speed surviving the
# end of the slide instead of being assigned over.
#
# Almost everything here is a static function called straight off the loaded script, and that
# shape is deliberate rather than convenient. is_on_floor() cannot be made TRUE without a
# physics world, so no headless test can reach the slope code through _physics_process at all;
# pure functions taking a floor normal are the only version of this arithmetic that can be
# tested before it is in the player's hands. The same fact is what keeps every OTHER slide
# test honest - with no floor under him the bonus is exactly zero and they measure the clip
# alone, exactly as they did before this existed.
#
# The sign convention is the thing worth catching. The horizontal part of a floor normal
# points DOWNHILL, and a flip there is a controller that accelerates you up hills.
#
# See docs/specs/pilot9-slope-momentum.md.

const PILOT_PATH := "res://scripts/pilot9.gd"
const PILOT_TSCN := "res://scenes/pilot9.tscn"

# Physics steps, at the project's 60 Hz.
const STEP := 1.0 / 60.0
# Godot's default, and the one this controller runs at - project.godot overrides nothing.
const GRAVITY := 9.8

var _instances: Array[Node] = []

# Runtime load, not preload: a preload of a script that fails to parse is a parse-time error,
# which makes --script fall back to main.tscn and hang. Matches test_player_slope.gd.
func _pilot() -> GDScript:
	return load(PILOT_PATH) as GDScript

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

# The upward normal of a plane whose downhill direction is +Z, tilted `deg` off level. The
# same helper, and the same convention, as tests/test_player_slope.gd.
func _slope_normal(deg: float) -> Vector3:
	var t := deg_to_rad(deg)
	return Vector3(0.0, cos(t), sin(t))

# The horizontal acceleration a body sliding straight down a `deg` grade should feel:
# gravity along the surface (g sin) projected back onto the horizontal (x cos).
func _expected_accel(deg: float) -> float:
	var t := deg_to_rad(deg)
	return GRAVITY * sin(t) * cos(t)

# Points the stick, the way _handle_movement_input() would have. `dir` is the world-space
# travel direction; Vector3.ZERO is a released stick, which is a different case from every
# other value here rather than a small one - see air_momentum_brake.
func _stick(root: Node, dir: Vector3) -> void:
	root.set("direction", dir)
	root.set("input_dir", Vector2(dir.x, dir.z))
	root.set("input_strength", minf(Vector2(dir.x, dir.z).length(), 1.0))

func _horizontal(root: Node) -> float:
	var v := root.get("velocity") as Vector3
	return Vector2(v.x, v.z).length()

# --- which way is downhill -------------------------------------------------

func test_level_ground_has_no_downhill() -> void:
	var p := _pilot()
	eq(p._downhill(Vector3.UP), Vector3.ZERO,
		"a level floor was given a downhill direction - every slope term keys off this one")

# The whole sign convention in one assertion. A normal that leans +Z belongs to a plane that
# DESCENDS toward +Z, so the flattened normal is the fall line itself.
func test_the_downhill_is_where_the_normal_leans() -> void:
	var p := _pilot()
	var down: Vector3 = p._downhill(_slope_normal(30.0))
	approx(down.z, 1.0, 0.0001, "downhill on a +Z-descending plane should be +Z")
	approx(down.x, 0.0, 0.0001, "downhill picked up an X component on a plane with none")
	approx(down.length(), 1.0, 0.0001, "downhill is not unit length")

# --- gravity along the grade -----------------------------------------------

func test_flat_ground_gives_no_acceleration() -> void:
	var p := _pilot()
	for heading in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, -1).normalized()]:
		var a: float = p._slope_accel(heading, Vector3.UP, GRAVITY, 1.0)
		approx(a, 0.0, 0.0001, "flat floor, heading %s: expected no acceleration" % heading)

func test_running_down_the_fall_line_accelerates() -> void:
	var p := _pilot()
	var a: float = p._slope_accel(Vector3(0, 0, 1), _slope_normal(30.0), GRAVITY, 1.0)
	check(a > 0.0, "sliding downhill must gain speed, not lose it - a sign flip here is a " +
		"controller that accelerates you up hills")
	approx(a, _expected_accel(30.0), 0.001,
		"a 30 degree descent should be g*sin*cos horizontally")

func test_running_up_the_fall_line_costs_the_same() -> void:
	var p := _pilot()
	var a: float = p._slope_accel(Vector3(0, 0, -1), _slope_normal(30.0), GRAVITY, 1.0)
	approx(a, -_expected_accel(30.0), 0.001,
		"climbing a grade should cost exactly what descending it pays")

# The dot product's whole job. Steering across a slope has to be worth less than pointing
# straight down it, or the fall line means nothing and every slope is the same slope.
func test_crossing_the_slope_pays_nothing() -> void:
	var p := _pilot()
	var a: float = p._slope_accel(Vector3(1, 0, 0), _slope_normal(35.0), GRAVITY, 1.0)
	approx(a, 0.0, 0.0001, "a heading along the contour is neither up nor down")

func test_a_diagonal_pays_its_share() -> void:
	var p := _pilot()
	var heading := Vector3(1, 0, 1).normalized()      # 45 degrees off the fall line
	var a: float = p._slope_accel(heading, _slope_normal(30.0), GRAVITY, 1.0)
	approx(a, _expected_accel(30.0) * cos(deg_to_rad(45.0)), 0.001,
		"a heading 45 degrees off the fall line should take cos(45) of the gain")

func test_steeper_is_faster_up_to_the_45_degree_peak() -> void:
	var p := _pilot()
	var last := -1.0
	for deg in [5.0, 15.0, 25.0, 35.0, 45.0]:
		var a: float = p._slope_accel(Vector3(0, 0, 1), _slope_normal(deg), GRAVITY, 1.0)
		check(a > last, "a %.0f degree grade did not out-accelerate the one below it" % deg)
		last = a

# The off switch named in the spec, and the dial next to it.
func test_the_scale_multiplies_the_whole_term() -> void:
	var p := _pilot()
	var n := _slope_normal(30.0)
	var once: float = p._slope_accel(Vector3(0, 0, 1), n, GRAVITY, 1.0)
	var twice: float = p._slope_accel(Vector3(0, 0, 1), n, GRAVITY, 2.0)
	var never: float = p._slope_accel(Vector3(0, 0, 1), n, GRAVITY, 0.0)
	approx(twice, once * 2.0, 0.0001, "slide_slope_accel does not scale the gain")
	approx(never, 0.0, 0.0001,
		"slide_slope_accel 0.0 is meant to be the old flat slide exactly")

# get_floor_normal() answers ZERO when he is not on a floor, and a zero heading is a slide
# that has not been given a direction yet. Neither may divide by its own length.
func test_degenerate_inputs_are_safe() -> void:
	var p := _pilot()
	var n := _slope_normal(30.0)
	approx(p._slope_accel(Vector3.ZERO, n, GRAVITY, 1.0), 0.0, 0.0001,
		"a zero heading should be zero acceleration, not a NaN")
	approx(p._slope_accel(Vector3(0, 0, 1), Vector3.ZERO, GRAVITY, 1.0), 0.0, 0.0001,
		"a zero floor normal - what get_floor_normal() returns off the floor - should be zero")

# --- the bonus, frame by frame ---------------------------------------------

func test_gravity_adds_to_the_bonus() -> void:
	var p := _pilot()
	var next: float = p._stepped_bonus(0.0, 4.0, 0.0, 0.5)
	approx(next, 2.0, 0.0001, "4 m/s^2 for half a second is 2 m/s")

func test_friction_takes_it_back_off() -> void:
	var p := _pilot()
	var next: float = p._stepped_bonus(5.0, 0.0, 2.0, 0.5)
	approx(next, 4.0, 0.0001, "2 m/s^2 of friction for half a second is 1 m/s")

# The clamp that keeps the flat-ground hold exactly the constant one it was. Friction that
# ran through zero would drag a slide with no slope backwards.
func test_friction_stops_at_zero_rather_than_reversing() -> void:
	var p := _pilot()
	var next: float = p._stepped_bonus(0.01, 0.0, 2.0, STEP)
	eq(next, 0.0, "friction pulled the bonus through zero - on the flat that is a slide " +
		"being dragged backwards by its own friction term")

func test_an_uphill_bonus_is_bled_back_toward_zero_too() -> void:
	var p := _pilot()
	var next: float = p._stepped_bonus(-5.0, 0.0, 2.0, 0.5)
	approx(next, -4.0, 0.0001, "friction on a negative bonus must also pull toward zero")
	eq(p._stepped_bonus(-0.01, 0.0, 2.0, STEP), 0.0,
		"friction pulled a negative bonus through zero")

func test_gravity_and_friction_compose() -> void:
	var p := _pilot()
	var next: float = p._stepped_bonus(0.0, 4.0, 2.0, 1.0)
	approx(next, 2.0, 0.0001,
		"a second of 4 m/s^2 against 2 m/s^2 of friction should net 2 m/s")

# A grade whose gain does not clear the friction is not a hill worth sliding down, and it has
# to net out NEGATIVE rather than being floored at the gain.
func test_a_shallow_grade_loses_to_friction() -> void:
	var p := _pilot()
	var gentle: float = p._slope_accel(Vector3(0, 0, 1), _slope_normal(5.0), GRAVITY, 1.0)
	check(gentle < 2.0, "the test's premise is gone: a 5 degree grade now out-pulls the " +
		"2.0 m/s^2 shipping friction")
	var next: float = p._stepped_bonus(3.0, gentle, 2.0, 1.0)
	check(next < 3.0, "a grade shallower than the friction should still be losing speed")

# --- the ceiling and the floor ---------------------------------------------

func test_the_bonus_is_added_to_the_clip() -> void:
	var p := _pilot()
	approx(p._capped_slide_speed(6.0, 3.0, 20.0), 9.0, 0.0001,
		"the total is the clip's speed plus the terrain's")

func test_the_total_is_capped() -> void:
	var p := _pilot()
	approx(p._capped_slide_speed(6.0, 100.0, 20.0), 20.0, 0.0001,
		"slide_max_speed is not capping the total")

# Clamped rather than allowed through zero: a slide that has run out of speed going uphill
# stalls out, it does not start travelling backwards while facing forwards.
func test_an_uphill_slide_stops_rather_than_reversing() -> void:
	var p := _pilot()
	approx(p._capped_slide_speed(6.0, -20.0, 20.0), 0.0, 0.0001,
		"a big negative bonus reversed him instead of stopping him")

# --- momentum --------------------------------------------------------------

func test_over_speed_decays_at_the_rate() -> void:
	var p := _pilot()
	approx(p._decayed_speed(20.0, 8.0, 12.0, 0.5), 14.0, 0.0001,
		"12 m/s^2 for half a second is 6 m/s off")

func test_the_decay_stops_on_the_target() -> void:
	var p := _pilot()
	approx(p._decayed_speed(9.0, 8.0, 12.0, 1.0), 8.0, 0.0001,
		"the decay undershot the target - momentum must not push him below a sprint")

# At or under the target this returns the input untouched, which is what leaves the stock
# Real Controller assignment - dead stop included - owning every ordinary frame.
func test_at_or_under_the_target_nothing_happens() -> void:
	var p := _pilot()
	approx(p._decayed_speed(5.0, 8.0, 12.0, 1.0), 5.0, 0.0001,
		"the momentum branch touched a speed below its target")
	approx(p._decayed_speed(8.0, 8.0, 12.0, 1.0), 8.0, 0.0001,
		"the momentum branch touched a speed exactly at its target")

# --- the brake -------------------------------------------------------------
#
# Momentum that cannot be given up is not momentum, it is ice. These are the assertions that
# say so: the rate he pays depends on whether he is still asking for the speed.

func test_driving_into_his_own_momentum_pays_the_drive_rate() -> void:
	var p := _pilot()
	approx(p._momentum_rate(1.0, 12.0, 60.0), 12.0, 0.0001,
		"stick straight into his own travel should cost the drive rate and nothing more")

func test_letting_go_pays_the_brake() -> void:
	var p := _pilot()
	approx(p._momentum_rate(-1.0, 12.0, 60.0), 60.0, 0.0001,
		"a released stick - passed as -1 - must brake, not coast")

func test_pushing_across_his_travel_brakes_too() -> void:
	var p := _pilot()
	approx(p._momentum_rate(0.0, 12.0, 60.0), 60.0, 0.0001,
		"a stick across his own travel is a request to stop going that way")
	approx(p._momentum_rate(-0.5, 12.0, 60.0), 60.0, 0.0001,
		"pushing back against his travel must not be gentler than pushing across it")

func test_a_half_agreeing_stick_pays_something_in_between() -> void:
	var p := _pilot()
	var rate: float = p._momentum_rate(0.5, 12.0, 60.0)
	check(rate > 12.0 and rate < 60.0,
		"a stick half-way between his travel and across it should cost something between " +
		"the two rates, not one of them")

func test_a_zero_decay_keeps_the_speed_forever() -> void:
	var p := _pilot()
	approx(p._decayed_speed(20.0, 8.0, 0.0, 10.0), 20.0, 0.0001,
		"air_momentum_decay 0.0 is the shipping value and has to mean no air friction at all")

# --- steep ground ----------------------------------------------------------

func test_a_gentle_grade_is_not_an_auto_slide() -> void:
	var p := _pilot()
	check(not p._is_auto_slide_slope(_slope_normal(30.0), 35.0),
		"a 30 degree ramp took his feet out from under him at a 35 degree threshold")
	check(not p._is_auto_slide_slope(Vector3.UP, 35.0),
		"level ground started an automatic slide")

func test_a_steep_grade_is() -> void:
	var p := _pilot()
	check(p._is_auto_slide_slope(_slope_normal(40.0), 35.0),
		"a 40 degree face did not start an automatic slide at a 35 degree threshold")

func test_the_threshold_is_the_dial() -> void:
	var p := _pilot()
	var n := _slope_normal(40.0)
	check(not p._is_auto_slide_slope(n, 45.0),
		"raising slide_auto_angle past the grade did not switch the automatic slide off")
	check(p._is_auto_slide_slope(n, 20.0),
		"lowering slide_auto_angle below the grade did not switch it on")

# Off the floor there is no floor normal, and a zero vector must not read as a vertical wall.
func test_no_floor_is_not_a_steep_floor() -> void:
	var p := _pilot()
	check(not p._is_auto_slide_slope(Vector3.ZERO, 35.0),
		"a zero normal - what get_floor_normal() returns in the air - read as steep ground")

# --- wiring ----------------------------------------------------------------

# A slide already running, at the top of its clip, heading down +Z. The same fixture the rest
# of the slide tests use - nothing enters the tree, so is_on_floor() is false throughout and
# the bonus is only ever what the test puts there.
func _begin_slide(root: Node) -> void:
	root.set("_slide_direction", Vector3(0.0, 0.0, 1.0))
	root.set("_slide_time", 0.0)
	root.set("is_sliding", true)
	root.set("is_slide_holding", false)
	root.set("_slide_bonus", 0.0)

func _run_slide(root: Node, count: int) -> void:
	for i in count:
		root.call("_apply_slide_velocity", STEP)

# The bonus has to reach the velocity in BOTH halves of the slide, or a slope only pays out
# once he has settled into the hold and the run-in down a ramp is dead time.
func test_the_bonus_reaches_the_run_in_speed() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	# The ceiling lifted for this one: the run-in opens near 17 m/s at slide_time_scale 2.0
	# and 4 m/s on top of it lands past slide_max_speed, so both readings would come back
	# clamped to 20 and the sum would be untestable. The cap is asserted on its own below.
	root.set("slide_max_speed", 1000.0)
	_begin_slide(root)
	_run_slide(root, 3)
	var plain := (root.get("velocity") as Vector3).z
	_begin_slide(root)
	root.set("_slide_bonus", 4.0)
	_run_slide(root, 3)
	var boosted := (root.get("velocity") as Vector3).z
	approx(boosted, plain + 4.0, 0.0001,
		"4 m/s of slope did not reach the run-in - the clip is driving it alone")

func test_the_bonus_reaches_the_hold_speed() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var hold := float(root.get("slide_hold_time"))
	if hold <= 0.0:
		fail("no baked hold to test")
		return
	_begin_slide(root)
	_run_slide(root, int(hold / STEP) + 4)
	if not bool(root.get("is_slide_holding")):
		fail("did not reach the hold")
		return
	var plain := (root.get("velocity") as Vector3).z
	root.set("_slide_bonus", 4.0)
	_run_slide(root, 1)
	approx((root.get("velocity") as Vector3).z, plain + 4.0, 0.0001,
		"4 m/s of slope did not reach the held speed - the hold is the half of the slide a " +
		"long descent is spent in")

func test_the_cap_reaches_the_velocity() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_begin_slide(root)
	root.set("_slide_bonus", 500.0)
	_run_slide(root, 1)
	approx((root.get("velocity") as Vector3).z, float(root.get("slide_max_speed")), 0.0001,
		"slide_max_speed did not cap the velocity actually written")

# The regression the whole feature is balanced against: with no slope under him the slide is
# the slide that was built. Its own file asserts the flatness; this asserts the REASON is
# still true - that nothing was quietly folded into the clip's own numbers.
func test_a_slide_with_no_floor_gains_nothing() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_begin_slide(root)
	_run_slide(root, int(3.0 / STEP))
	eq(float(root.get("_slide_bonus")), 0.0,
		"the bonus moved with no floor under him - airborne frames must add nothing")

func test_starting_a_slide_clears_the_bonus() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("_slide_bonus", 9.0)
	root.call("_start_slide", Vector3(0, 0, 1), true)
	eq(float(root.get("_slide_bonus")), 0.0,
		"a slide opened carrying the last one's slope speed")

func test_ending_a_slide_clears_the_bonus_but_not_the_speed() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_begin_slide(root)
	root.set("_slide_bonus", 6.0)
	root.set("velocity", Vector3(0.0, 0.0, 15.0))
	root.call("_end_slide")
	eq(float(root.get("_slide_bonus")), 0.0, "_end_slide left the bonus behind")
	approx((root.get("velocity") as Vector3).z, 15.0, 0.0001,
		"_end_slide zeroed the speed the slope gave him - the carry-out is the point of " +
		"gaining it")

# The automatic slide points him down the fall line, and that is the one entry that may not
# be overridden by where he happened to be facing when the ground gave way.
func test_a_forced_slide_takes_the_heading_it_is_given() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var fall_line := Vector3(1, 0, 0)
	root.call("_start_slide", fall_line, true)
	var dir := root.get("_slide_direction") as Vector3
	approx(dir.x, 1.0, 0.0001, "a forced slide did not take the fall line it was handed")
	approx(dir.z, 0.0, 0.0001, "a forced slide kept part of his old facing")

# --- momentum, through _apply_movement -------------------------------------

# The bug this whole branch exists to fix, at its simplest: an airborne pilot9 doing 20 m/s
# out of a slide, with the stock assignment reaching for `speed` (5.0).
func test_the_air_does_not_reassign_his_speed_down() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("velocity", Vector3(0.0, 2.0, 20.0))
	_stick(root, Vector3(0.0, 0.0, 1.0))
	root.call("_apply_movement", STEP)
	var v := root.get("velocity") as Vector3
	approx(v.z, 20.0, 0.0001,
		"the air took %.2f m/s off him in one frame - with air_momentum_decay at 0.0 it " %
			(20.0 - v.z) + "may take nothing")
	approx(v.y, 2.0, 0.0001, "_apply_movement wrote the vertical velocity")

# With no stick there is no heading to steer by, so what is left of the momentum has to carry
# its own. It may bleed along that line; it may never be turned off it, because a fall that
# wanders sideways as it slows is the same drift from a different direction.
func test_speed_with_no_stick_keeps_its_own_heading() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("velocity", Vector3(0.0, 0.0, 18.0))
	_stick(root, Vector3.ZERO)
	root.call("_apply_movement", STEP)
	var v := root.get("velocity") as Vector3
	check(v.z < 18.0, "the released stick kept all 18 m/s - air_momentum_brake is dead")
	check(v.z > 0.0, "one frame of the air brake stopped him dead - it is a rate, not a switch")
	approx(v.x, 0.0, 0.0001, "the momentum lost its heading when the stick was let go")

# The whole point of the air brake, stated the way the player asked for it: let go of the
# stick over a shaft and he goes DOWN it, not across it. Measured as the horizontal distance
# a walk-off costs him, because that is what decides whether he clears the lip and hits a wall.
func test_a_released_stick_falls_straight_down() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var walk := float(root.get("speed"))
	root.set("velocity", Vector3(0.0, 0.0, walk))
	_stick(root, Vector3.ZERO)
	var drift := 0.0
	for i in int(1.0 / STEP):
		root.call("_apply_movement", STEP)
		drift += (root.get("velocity") as Vector3).z * STEP
	approx((root.get("velocity") as Vector3).z, 0.0, 0.0001,
		"a second after the stick was released he is still travelling - he cannot fall down " +
		"a pipe in a straight line while anything is pushing him along it")
	check(drift < 0.5,
		"walking off a lip at %.1f m/s carried him %.2f m sideways before the fall " %
			[walk, drift] + "straightened out - the shaft is not that wide")

# The dial, both ends of it. 0.0 is the old behaviour and has to stay reachable: some maps
# want a flying fall, and a dial nobody can turn off is a hardcode with a label on it.
func test_the_air_brake_dial_still_works() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("air_momentum_brake", 0.0)
	root.set("velocity", Vector3(0.0, 0.0, 18.0))
	_stick(root, Vector3.ZERO)
	root.call("_apply_movement", STEP)
	approx((root.get("velocity") as Vector3).z, 18.0, 0.0001,
		"air_momentum_brake 0.0 did not restore the old carry-forever fall - the dial is dead")

# A stick still beats the brake. This is the line between "he drifts" and "he cannot steer a
# jump", and crossing it would take the whole momentum feature down with it.
func test_driving_into_the_momentum_still_pays_nothing_in_the_air() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("velocity", Vector3(0.0, 0.0, 18.0))
	_stick(root, Vector3(0.0, 0.0, 1.0))
	for i in int(1.0 / STEP):
		root.call("_apply_movement", STEP)
	approx((root.get("velocity") as Vector3).z, 18.0, 0.0001,
		"holding the stick into his own travel cost him speed in the air - " +
		"air_momentum_decay is 0.0 and the brake is for a stick he let GO of")

# Pushing across his travel is the brake too, in the air exactly as on the floor: it is a
# request to stop going that way, and half an answer to it is the vagueness that reads as ice.
func test_pushing_across_his_travel_brakes_in_the_air() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("velocity", Vector3(0.0, 0.0, 18.0))
	_stick(root, Vector3(1.0, 0.0, 0.0))
	root.call("_apply_movement", STEP)
	check(_horizontal(root) < 18.0,
		"a stick pushed across an airborne pilot9's travel took nothing off him")

# The feel guard, and the reason `momentum_brake` is five times `momentum_decay`: the skid
# from a full-speed slide exit to a sprint has to be short enough to read as a stop rather
# than as ice. Stated as a distance because that is what the player sees.
func test_the_brake_stops_him_inside_three_metres() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var p := _pilot()
	var brake := float(root.get("momentum_brake"))
	var sprint := float(root.get("sprint_speed"))
	var speed := float(root.get("slide_max_speed"))
	var travelled := 0.0
	var steps := 0
	while speed > sprint + 0.001 and steps < 10000:
		speed = p._decayed_speed(speed, sprint, brake, STEP)
		travelled += speed * STEP
		steps += 1
	check(travelled < 3.0,
		"letting go at the %.0f m/s cap skids %.2f m before he is back to a sprint - that " %
			[float(root.get("slide_max_speed")), travelled] +
		"is the ice-skating this rate exists to answer")

func test_the_air_decay_dial_still_works() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("air_momentum_decay", 12.0)
	root.set("velocity", Vector3(0.0, 0.0, 20.0))
	# With the stick in: this dial is the DRIVE rate, and a released stick would be answered
	# by air_momentum_brake instead.
	_stick(root, Vector3(0.0, 0.0, 1.0))
	root.call("_apply_movement", 0.5)
	approx((root.get("velocity") as Vector3).z, 14.0, 0.0001,
		"air_momentum_decay is not being applied - the dial is dead")

# It may not decay past a sprint. Under one, ordinary locomotion owns the frame again.
func test_momentum_never_decays_below_a_sprint() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sprint := float(root.get("sprint_speed"))
	root.set("momentum_decay", 12.0)
	root.set("air_momentum_decay", 12.0)
	root.set("velocity", Vector3(0.0, 0.0, 20.0))
	_stick(root, Vector3(0.0, 0.0, 1.0))
	for i in int(5.0 / STEP):
		root.call("_apply_movement", STEP)
	approx((root.get("velocity") as Vector3).z, sprint, 0.001,
		"momentum decayed past sprint_speed - below it the stock assignment owns the frame")

# --- sticking to the grade -------------------------------------------------

# The snap length is the difference between riding a ramp and hopping down it. Asserted as
# the constant AND as the write, because a constant nothing assigns is worth nothing.
func test_the_floor_snap_covers_a_fast_frame_on_a_steep_grade() -> void:
	var p := _pilot()
	var snap: float = p.FLOOR_SNAP_LENGTH
	var max_speed := 20.0                      # slide_max_speed's shipping value
	# One frame's drop at the cap on the steepest thing Godot still calls a floor.
	var drop := max_speed * STEP * tan(deg_to_rad(45.0))
	check(snap >= drop,
		"floor_snap_length is %.2f m but one frame at %.0f m/s down a 45 degree face drops " %
			[snap, max_speed] + "%.2f m - he would leave the surface at the crest" % drop)

func test_ready_actually_sets_the_snap_length() -> void:
	var f := FileAccess.open(PILOT_PATH, FileAccess.READ)
	if f == null:
		fail("could not read scripts/pilot9.gd")
		return
	check(f.get_as_text().contains("floor_snap_length = FLOOR_SNAP_LENGTH"),
		"nothing assigns floor_snap_length - the constant is documentation and the body is " +
		"still on Godot's 0.1 m default")
