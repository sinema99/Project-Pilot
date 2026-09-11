extends "res://tests/test_case.gd"

# Covers the 2026-09-11 jump grid. See docs/specs/pilot9-jump-grid.md.
#
# The jump is specified in whole numbers so a gap in the map can be built to a measurement:
# 2.0 m high, 1.2 s in the air, and ground speeds of 2.5 / 5.0 / 7.5 that clear gaps of
# exactly 3 / 6 / 9 m. None of those are numbers the physics volunteered - they are chosen,
# and every one of them is one export away from being 6.0999 again.
#
# So this file asserts the ROUND NUMBERS THEMSELVES, not the arithmetic that produces them.
# A test that recomputed `speed * jump_air_time` and compared it to `jump_distance()` would
# pass forever while the grid rotted. The point of failing here is to make someone open the
# spec and re-measure the map, or decide not to.
#
# It also pins the three dials the grid silently depends on - the fall multiplier, the jump
# cut and the apex hang. All three are parked off by the 2026-09-10 reset, and all three
# would make the measurements above wrong without touching a single number in them.
#
# Nothing here enters the tree; the exports are read off a fresh instance.

const PILOT_TSCN := "res://scenes/pilot9.tscn"

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

# --- the grid --------------------------------------------------------------

# 1.2 s, and it has to be exact: it is the multiplier a level designer applies by hand.
func test_air_time_is_one_point_two_seconds() -> void:
	var p := _scene()
	check(p != null, "pilot9.tscn did not instantiate")
	if p == null:
		return
	approx(p.jump_air_time, 1.2, 0.0001,
		"airtime is off 1.2 s - every gap in the map is now the wrong width")

# The three numbers the map is built to. Whole metres or the grid is not a grid.
func test_the_three_gaps_are_whole_metres() -> void:
	var p := _scene()
	if p == null:
		return
	approx(p.jump_distance(p.walk_speed), 3.0, 0.0001, "a walking jump no longer clears 3 m")
	approx(p.jump_distance(p.speed), 6.0, 0.0001, "a running jump no longer clears 6 m")
	approx(p.jump_distance(p.sprint_speed), 9.0, 0.0001, "a sprint jump no longer clears 9 m")

# The default argument is the run, because that is the jump a gap is usually asked about.
func test_jump_distance_defaults_to_a_run() -> void:
	var p := _scene()
	if p == null:
		return
	approx(p.jump_distance(), p.jump_distance(p.speed), 0.0001,
		"jump_distance() no longer defaults to `speed`")

# Vertical is the other half of the grid: 3 m of single jump, 6 m of double.
func test_the_heights_are_whole_metres() -> void:
	var p := _scene()
	if p == null:
		return
	approx(p.jump_height, 3.0, 0.0001, "a single jump no longer peaks at 3 m")
	eq(p.air_jumps, 1, "the 6 m double-jump ceiling assumes exactly one air jump")
	approx(p.jump_height * 2.0, 6.0, 0.0001, "a double jump no longer peaks at 6 m")

# Height is the one dial that moves WITHOUT moving a gap, which is the whole reason it could
# be raised on its own. If this ever fails, airtime has picked up a height term and the
# vertical and horizontal halves of the grid are no longer independent.
func test_height_does_not_touch_the_gaps() -> void:
	var p := _scene()
	if p == null:
		return
	p.jump_height = 3.0 * 7.0
	approx(p.jump_air_time, 1.2, 0.0001, "airtime moved with jump_height")
	approx(p.jump_distance(p.speed), 6.0, 0.0001, "the 6 m run gap moved with jump_height")

# --- what the grid rests on ------------------------------------------------

# The fall multiplier is the one that would move every gap without moving a number anyone
# was looking at: at 1.9 the 6 m run gap quietly becomes 5.1 m and the map stops fitting.
func test_a_heavier_fall_shortens_every_gap() -> void:
	var p := _scene()
	if p == null:
		return
	approx(p.jump_fall_multiplier, 1.0, 0.0001,
		"gravity is asymmetric again - the whole grid is short and the map needs re-measuring")
	p.jump_fall_multiplier = 4.0
	# Rise 0.6 s, fall 0.6 / sqrt(4) = 0.3 s.
	approx(p.jump_air_time, 0.9, 0.0001,
		"jump_air_time does not track the fall multiplier - it is lying about the gap width")
	approx(p.jump_distance(p.speed), 4.5, 0.0001, "jump_distance did not follow the airtime")

# The other two the measurement cannot model. Both off, both documented in the spec as the
# point at which the grid becomes a bound rather than a number.
func test_the_dials_the_measurement_cannot_model_are_off() -> void:
	var p := _scene()
	if p == null:
		return
	approx(p.jump_cut, 1.0, 0.0001,
		"the jump cut is on - the grid is now what a HELD jump clears, not what a jump clears")
	approx(p.jump_apex_speed, 0.0, 0.0001,
		"the apex hang is on - it lengthens the arc and jump_air_time does not model it")
	approx(p.jump_apex_scale, 1.0, 0.0001, "the apex hang is on by the other switch")

# --- the derivation --------------------------------------------------------

# The arc under the grid, in case someone re-derives the properties and lands a frame off.
func test_the_derived_pair_follows_the_grid() -> void:
	var p := _scene()
	if p == null:
		return
	approx(p.jump_velocity, 10.0, 0.001, "2h/t is not the launch speed the grid asks for")
	approx(p.jump_gravity, 16.6667, 0.001, "2h/t^2 is not the rise gravity the grid asks for")
	# Round-trips: the apex the launch speed actually reaches is the height that produced it.
	approx(p.jump_velocity * p.jump_velocity / (2.0 * p.jump_gravity), p.jump_height, 0.0001,
		"v^2/2g does not come back to jump_height - the derivation is wrong")

# What the mantle actually reaches, which is `peak + climb_band_max` and not the apex: the
# probe fires every airborne frame, so he passes through every height on the way up and down.
# Pinned because raising jump_height moves it a metre at a time and the map is built to it -
# 4.9 m is what makes TrainingV's 4.2 m block a single-jump mantle rather than a double.
func test_what_a_mantle_reaches() -> void:
	var p := _scene()
	if p == null:
		return
	approx(p.jump_height + p.climb_band_max, 4.9, 0.0001,
		"a single jump no longer mantles a 4.9 m lip - the map's block heights need re-checking")
	approx(p.jump_height * 2.0 + p.climb_band_max, 7.9, 0.0001,
		"a double jump no longer mantles a 7.9 m lip")
	check(p.climb_band_max < p.jump_height,
		"the top of the mantle band is above a single jump - lips in it need a double jump")
	check(p.climb_band_min < p.climb_band_max, "the mantle band is inverted")
