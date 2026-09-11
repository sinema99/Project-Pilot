extends "res://tests/test_case.gd"

# Covers the 2026-09-10 movement reset. See docs/specs/pilot9-movement-reset.md.
#
# Every feel layer pilot9 accumulated over four passes is parked at a neutral value so the
# baseline can be felt before any of them comes back. Nothing was deleted - the code paths
# are live, and their own test files still cover the mechanisms by passing values in.
#
# This file guards the OTHER half: that the parked values are still parked. The failure it
# exists to catch is silent by construction - a later tuning pass nudges one export back up,
# the suite stays green because every mechanism still works, and the baseline everyone is
# comparing against has quietly moved. A play session cannot tell you that happened. A diff
# on this file can.
#
# It also pins the two traps found while building the reset, because both are cases where
# the obvious "off" value is the wrong one and a future reader will reach for it again:
#
#   1. `momentum_brake` / `air_momentum_brake` at 0.0 do NOT disable momentum. The branch is
#      still entered and _decayed_speed() then subtracts nothing, so he coasts forever. The
#      neutral value is the TOP of the range.
#   2. `slide_boost_time: 0.0` kills the burst but NOT the floor - the slide is still held at
#      its entry speed. That is deliberate and documented; this file asserts it so that if
#      someone later removes the floor, they do it knowingly.
#
# Nothing here enters the tree. The statics are fully parameterised and the exports are read
# off a fresh instance.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const DT := 1.0 / 60.0

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

func _script() -> GDScript:
	return load("res://scripts/pilot9.gd") as GDScript

# --- the jump is parked ----------------------------------------------------

func test_jump_assists_are_all_off() -> void:
	var p := _scene()
	check(p != null, "pilot9.tscn did not instantiate")
	if p == null:
		return
	approx(p.jump_cut, 1.0, 0.0001,
		"jump_cut is not 1.0 - a tap is being clipped again, which is the single dial the " +
		"2026-09-10 session named")
	approx(p.jump_fall_multiplier, 1.0, 0.0001,
		"jump_fall_multiplier is not 1.0 - gravity is asymmetric again")
	approx(p.jump_apex_speed, 0.0, 0.0001, "the apex hang is back on (band)")
	approx(p.jump_apex_scale, 1.0, 0.0001, "the apex hang is back on (scale)")
	approx(p.coyote_time, 0.0, 0.0001, "coyote time is back on")
	approx(p.jump_buffer_time, 0.0, 0.0001, "the jump buffer is back on")

# The arc itself, not the assists. These two ARE the jump's parameterisation and are meant to
# be tuned - but they are reset to the pre-2026-09-10 arc, and that arc is what every mantle
# band and every lip in the map was placed against. Moving them is a level-design decision.
func test_the_arc_is_the_one_the_map_was_built_against() -> void:
	var p := _scene()
	if p == null:
		return
	approx(p.jump_height, 1.84, 0.001,
		"jump_height moved - climb_band_min/max and every lip in the map are tuned to 1.84 m")
	approx(p.jump_time_to_apex, 0.61, 0.001, "jump_time_to_apex moved")
	# The derived pair, which is the whole point of the parameterisation. 2h/t and 2h/t^2.
	approx(p.jump_velocity, 6.032, 0.01,
		"the derived launch speed is no longer the 6.0 m/s he was played with")
	approx(p.jump_gravity, 9.89, 0.01,
		"the derived rise gravity is no longer within a whisker of Godot's default 9.8")

# max_fall_speed is NOT part of the reset - it is a bound, not an assist. Asserted so that a
# future reader does not "finish the job" by zeroing it, which would let a long drop
# integrate without limit.
func test_terminal_velocity_survived_the_reset() -> void:
	var p := _scene()
	if p == null:
		return
	approx(p.max_fall_speed, 28.0, 0.01, "max_fall_speed was reset - it is a bound, not a feel layer")
	# Under the restored symmetric gravity it is ~39 m into a drop, which nothing in the map
	# reaches. If that stops being true the number needs revisiting, not deleting.
	var reach: float = (p.max_fall_speed * p.max_fall_speed) / (2.0 * p.jump_gravity)
	check(reach > 30.0,
		"terminal velocity is now reached inside %.1f m - short hops will meet it" % reach)

func test_with_the_assists_off_gravity_is_one_everywhere() -> void:
	var s := _script()
	var p := _scene()
	if p == null:
		return
	for vy in [8.0, 1.0, 0.5, 0.0, -0.5, -1.0, -8.0]:
		approx(s._gravity_scale(vy, p.jump_fall_multiplier, p.jump_apex_speed,
			p.jump_apex_scale), 1.0, 0.0001,
			"gravity is scaled at vy = %.1f - with every assist off the arc must be plain" % vy)

func test_with_the_cut_off_a_released_jump_is_the_full_arc() -> void:
	var s := _script()
	var p := _scene()
	if p == null:
		return
	var cut: float = p.jump_velocity * p.jump_cut
	# Released, at every point of the rise. jump_cut: 1.0 puts the clamp AT the launch speed,
	# so nothing on the way up is ever above it.
	for vy in [p.jump_velocity, 4.0, 2.0, 0.1]:
		approx(s._cut_rise(vy, false, cut), vy, 0.0001,
			"a released jump was cut at vy = %.2f - the tap-is-a-hop layer is back on" % vy)

# --- the momentum trap -----------------------------------------------------

# The reason the brakes sit at 200.0 and not 0.0, pinned as executable text. If someone
# "neutralises" them to zero this fails, and the message says what it costs.
func test_a_zero_brake_never_stops_him() -> void:
	var s := _script()
	# Carrying a sprint, asking for nothing, braking at "off".
	var kept: float = s._decayed_speed(8.0, 0.0, 0.0, DT)
	approx(kept, 8.0, 0.0001,
		"the premise of the reset's brake value changed: a 0.0 brake used to shed nothing")
	# ...and it never will, however long you wait.
	var v := 8.0
	for _i in range(600):
		v = s._decayed_speed(v, 0.0, 0.0, DT)
	approx(v, 8.0, 0.0001,
		"a 0.0 brake now decays - if that is a real fix, this test and the spec both need " +
		"rewriting, because 0.0 becomes the correct neutral")

func test_the_brakes_are_parked_at_instant_not_at_zero() -> void:
	var s := _script()
	var p := _scene()
	if p == null:
		return
	check(p.momentum_brake >= 200.0,
		"momentum_brake is %.1f - below the instant stop he coasts on a released stick; " % p.momentum_brake +
		"0.0 is a TRAP here, not an off switch. See docs/specs/pilot9-movement-reset.md")
	check(p.air_momentum_brake >= 200.0,
		"air_momentum_brake is %.1f - the 2026-09-09 'fall down long pipes in a straight " % p.air_momentum_brake +
		"line' report is re-opened below the instant stop")
	# What "instant" has to mean: a sprint gone inside a handful of frames.
	var v: float = p.sprint_speed
	var frames := 0
	while v > 0.0 and frames < 60:
		v = s._decayed_speed(v, 0.0, p.momentum_brake, DT)
		frames += 1
	check(frames <= 4,
		"a released sprint takes %d frames to stop - that is drift, not the stock dead stop" % frames)

func test_the_drive_rates_are_off() -> void:
	var p := _scene()
	if p == null:
		return
	approx(p.momentum_decay, 0.0, 0.0001, "grounded momentum drive is back on")
	approx(p.air_momentum_decay, 0.0, 0.0001, "airborne momentum drive is back on")

# --- the slide is parked ---------------------------------------------------

func test_slide_boost_and_slope_gain_are_off() -> void:
	var p := _scene()
	if p == null:
		return
	approx(p.slide_entry_boost, 1.0, 0.0001, "the slide's entry burst is back on")
	approx(p.slide_boost_time, 0.0, 0.0001, "the slide's burst ease is back on")
	approx(p.slide_slope_accel, 0.0, 0.0001,
		"slope acceleration is back on - a slide is gaining speed off a grade again")
	check(not p.can_auto_slide,
		"auto-slide is back on - steep ground is taking the verb away from the player, " +
		"which is the clearest case of what the 2026-09-10 session asked to stop")

# The floor the burst leaves behind. Documented, deliberate, and asserted here so that
# removing it is a decision rather than an accident.
func test_the_speed_floor_outlives_the_burst() -> void:
	var s := _script()
	var p := _scene()
	if p == null:
		return
	var floor_now: float = s._slide_speed_floor_at(p.sprint_speed, p.slide_entry_boost,
		p.slide_boost_time, 0.0)
	approx(floor_now, p.sprint_speed, 0.0001,
		"with the burst off the slide no longer holds its entry speed - if that was " +
		"intended, docs/specs/pilot9-movement-reset.md needs updating, because it says " +
		"the floor is left standing on purpose")
	# Still there much later - a zero boost_time means flat forever, not a fading floor.
	approx(s._slide_speed_floor_at(p.sprint_speed, p.slide_entry_boost, p.slide_boost_time,
		30.0), p.sprint_speed, 0.0001, "the floor decayed away over time")
	# And it still refuses to invent speed from a standstill.
	approx(s._slide_speed_floor_at(0.0, p.slide_entry_boost, p.slide_boost_time, 0.0), 0.0,
		0.0001, "a slide from a standstill is being given speed it never had")

# The player-driven halves of the slide are NOT part of the reset: both spend a press the
# player actually made, which is the line this session drew.
func test_the_player_driven_slide_options_survived() -> void:
	var p := _scene()
	if p == null:
		return
	check(p.can_hold_slide, "the held slide was reset - it is a player choice, not an assist")
	check(p.can_buffer_slide, "the buffered slide was reset - same argument")
	check(p.can_slide, "the slide itself was switched off")

# --- what the reset deliberately did NOT touch -----------------------------

# The audit that shaped this pass: these have sat at their authored values since the port and
# no tuning pass ever moved them. If one drifts, the reset's central claim - that speed,
# crouch and the climb probes were never the problem - stops being true.
func test_the_untouched_dials_are_still_untouched() -> void:
	var p := _scene()
	if p == null:
		return
	approx(p.speed, 5.0, 0.0001, "speed drifted from stock Real Controller")
	approx(p.walk_speed, 2.5, 0.0001, "walk_speed drifted from stock Real Controller")
	approx(p.sprint_speed, 8.0, 0.0001, "sprint_speed drifted from stock Real Controller")
	approx(p.crouch_speed, 1.6, 0.0001, "crouch_speed drifted from its authored value")
	approx(p.rotation_speed, 10.0, 0.0001, "rotation_speed drifted from stock Real Controller")
	approx(p.slide_scale, 1.0, 0.0001, "slide_scale drifted - the clip is no longer the slide")
	approx(p.slide_cooldown, 0.4, 0.0001, "slide_cooldown drifted")
	eq(p.air_jumps, 1, "air_jumps changed - the double jump is a move, not an assist")

# The climb probes are the subject of the NEXT pass, and this pins what that pass starts
# from. The relationship in the message is load-bearing: the forward ray has to pass UNDER
# the shallowest lip the band accepts or it sails over every wall in range.
func test_the_climb_probe_is_untouched_and_still_coherent() -> void:
	var p := _scene()
	if p == null:
		return
	approx(p.climb_probe_height, 0.85, 0.0001, "climb_probe_height drifted")
	approx(p.climb_probe_reach, 0.6, 0.0001, "climb_probe_reach drifted")
	approx(p.climb_band_min, 0.9, 0.0001, "climb_band_min drifted")
	approx(p.climb_band_max, 1.9, 0.0001, "climb_band_max drifted")
	check(p.climb_probe_height < p.climb_band_min,
		"the forward ray (%.2f m) is at or above the shallowest lip the band accepts " % p.climb_probe_height +
		"(%.2f m) - it will sail over the top of every wall in range" % p.climb_band_min)
