extends "res://tests/test_case.gd"

# Covers the burst: a slide out of a sprint opens FASTER than the sprint and eases back down
# to it, instead of dropping to the clip's own ~5.2 m/s and staying there.
#
# The floor is deliberately a floor and nothing else, so most of what is worth catching here
# is what it must NOT do: overwrite a curve that is already faster, survive the slide that
# set it, compound off a fast entry, hand free speed to the automatic slide off steep ground,
# or block the uphill stall by holding him above SLIDE_STALL_SPEED forever.
#
# See docs/specs/pilot9-slide-boost.md.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const PILOT := preload("res://scripts/pilot9.gd")

# Physics steps, at the project's 60 Hz.
const STEP := 1.0 / 60.0

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

# A slide already running, heading down +Z, entered at `entry` m/s. Nothing here enters the
# tree, so this is the state _start_slide() would have left behind minus the input reads.
func _begin_slide(root: Node, entry: float) -> void:
	root.set("_slide_direction", Vector3(0.0, 0.0, 1.0))
	root.set("_slide_time", 0.0)
	root.set("_slide_elapsed", 0.0)
	root.set("_slide_reference_speed", minf(entry, float(root.get("sprint_speed"))))
	root.set("is_sliding", true)
	root.set("is_slide_holding", false)

# Steps _apply_slide_velocity() `count` times and returns the forward speeds seen.
func _run_slide(root: Node, count: int) -> PackedFloat32Array:
	var speeds: PackedFloat32Array = []
	for i in count:
		root.call("_apply_slide_velocity", STEP)
		speeds.append((root.get("velocity") as Vector3).z)
	return speeds
# The slide-boost pass's own values, applied to an instance so the tests below measure the
# MECHANISM rather than whatever the exports currently happen to be.
#
# Same story as tests/test_pilot9_jump_feel.gd::_tuned(): the 2026-09-10 movement reset
# parked `slide_entry_boost` at 1.0 and `slide_boost_time` at 0.0, and the two tests that
# read them off the scene started failing while the burst itself was untouched. The parked
# values are guarded by tests/test_pilot9_movement_reset.gd. Here we switch the burst on and
# check it still behaves, so it stays covered while it is off.
#
# See docs/specs/pilot9-slide-boost.md.
func _boosted(p: Node) -> Node:
	p.slide_entry_boost = 1.35
	p.slide_boost_time = 2.0
	return p


# --- the shape of the floor -------------------------------------------------

# The two ends of the ramp, which are the whole promise: faster than the reference at the
# start, exactly the reference at `boost_time`.
func test_the_floor_opens_boosted_and_lands_on_the_reference() -> void:
	approx(PILOT._slide_speed_floor_at(8.0, 1.35, 2.0, 0.0), 10.8, 0.0001,
		"the floor does not open at reference * boost")
	approx(PILOT._slide_speed_floor_at(8.0, 1.35, 2.0, 1.0), 9.4, 0.0001,
		"the floor is not linear across the boost - half way in is not half way down")
	approx(PILOT._slide_speed_floor_at(8.0, 1.35, 2.0, 2.0), 8.0, 0.0001,
		"the floor did not reach the reference at boost_time")

# Past the end it is flat, not decaying and not negative. A player who never lets go of
# `crouch` is entitled to a sprint's worth of slide for as long as he wants - that is the
# hold's own promise (docs/specs/pilot9-slide-hold.md) and this must not walk it back.
func test_the_floor_holds_at_the_reference_afterwards() -> void:
	approx(PILOT._slide_speed_floor_at(8.0, 1.35, 2.0, 30.0), 8.0, 0.0001,
		"the floor kept decaying past boost_time")

# Both off switches, since the spec offers both to a player who hates the foot slip.
func test_the_burst_can_be_turned_off() -> void:
	approx(PILOT._slide_speed_floor_at(8.0, 1.0, 2.0, 0.0), 8.0, 0.0001,
		"a boost of 1.0 still boosted")
	approx(PILOT._slide_speed_floor_at(8.0, 1.35, 0.0, 0.0), 8.0, 0.0001,
		"a boost_time of 0.0 still boosted - and it must not divide by zero either")

# No reference, no floor. This is the automatic slide off steep ground: it starts from a
# standstill and gravity is the only thing allowed to speed it up.
func test_a_standing_entry_gets_no_floor() -> void:
	approx(PILOT._slide_speed_floor_at(0.0, 1.35, 2.0, 0.0), 0.0, 0.0001,
		"a slide entered at a standstill was given speed it did not earn")

# --- the reference is clamped ------------------------------------------------

# Entry speed is capped at a sprint before it becomes a floor. Uncapped, a slide entered at
# 20 m/s off a ramp would set a 27 m/s floor that never decays below 20, and a chain of
# slides would be a speed exploit rather than a route.
func test_the_reference_cannot_exceed_a_sprint() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sprint := float(root.get("sprint_speed"))
	root.set("velocity", Vector3(0.0, 0.0, 20.0))
	root.call("_start_slide", Vector3(0.0, 0.0, 1.0), true)
	approx(float(root.get("_slide_reference_speed")), sprint, 0.0001,
		"a 20 m/s entry set a reference above sprint_speed")

# And is the entry speed when that is the smaller of the two - a slide out of a crouch does
# not get a sprint's floor for free.
func test_a_slow_entry_keeps_its_own_reference() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("velocity", Vector3(0.0, 0.0, 2.0))
	root.call("_start_slide", Vector3(0.0, 0.0, 1.0), true)
	approx(float(root.get("_slide_reference_speed")), 2.0, 0.0001,
		"a 2 m/s entry was rounded up to a sprint")

# The burst does not outlive the slide that set it. A stale reference would boost the next
# slide off the last one's entry - including an automatic slide off steep ground, which is
# supposed to have no floor at all.
func test_the_reference_is_cleared_when_the_slide_ends() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	root.set("velocity", Vector3(0.0, 0.0, 8.0))
	root.call("_start_slide", Vector3(0.0, 0.0, 1.0), true)
	root.call("_end_slide")
	approx(float(root.get("_slide_reference_speed")), 0.0, 0.0001,
		"the reference survived the slide it belonged to")
	approx(float(root.get("_slide_elapsed")), 0.0, 0.0001,
		"the burst clock survived the slide it belonged to")

# --- what the slide actually runs at -----------------------------------------

# The complaint, as an assertion: pressing `crouch` at a sprint used to cost about a third
# of his speed on every frame of the clip.
func test_a_slide_out_of_a_sprint_is_never_slower_than_the_sprint() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sprint := float(root.get("sprint_speed"))
	_begin_slide(root, sprint)
	# Four seconds: the whole clip, well past the hold, and past the end of the burst.
	var speeds := _run_slide(root, int(4.0 / STEP))
	var slowest := speeds[0]
	for v in speeds:
		slowest = minf(slowest, v)
	check(slowest >= sprint - 0.01,
		"the slide dropped to %.2f m/s out of a %.2f m/s sprint" % [slowest, sprint])

# And it opens above one. Read on the first frame, where the floor is at its boost.
func test_the_slide_opens_faster_than_a_sprint() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_boosted(root)
	var sprint := float(root.get("sprint_speed"))
	var boost := float(root.get("slide_entry_boost"))
	if boost <= 1.0:
		fail("slide_entry_boost is off in the scene, so there is no burst to measure")
		return
	_begin_slide(root, sprint)
	var speeds := _run_slide(root, 1)
	approx(speeds[0], sprint * boost, 0.05,
		"the first frame of the slide is not the boosted sprint")

# The burst is spent on wall clock, not on clip time - and the hold freezes clip time. A
# player parked on the hold pose has to come off the boost like anyone else.
func test_the_burst_decays_through_a_hold() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	if float(root.get("slide_hold_time")) <= 0.0:
		fail("no baked hold to test")
		return
	var bare := _scene()
	if bare == null:
		fail("scenes/pilot9.tscn did not load")
		return
	_boosted(root)
	var sprint := float(root.get("sprint_speed"))
	var boost_time := float(root.get("slide_boost_time"))
	var frames := int((boost_time + 1.0) / STEP)
	# Against an unboosted twin rather than against a number. What "the burst decayed" means
	# is that the slide is doing what it would have done without one, and since
	# docs/specs/pilot9-slide-rate.md that is no longer the same thing as "running at a
	# sprint": at slide_time_scale 2.0 the clip's own hold speed is about 12 m/s, well above
	# the 7.5 the floor would hold him at, so the floor is simply irrelevant by then. The
	# twin says so at whatever rate the slide is tuned to.
	_begin_slide(root, sprint)
	_begin_slide(bare, sprint)
	var early := _run_slide(root, 2)
	var bare_early := _run_slide(bare, 2)
	var late := _run_slide(root, frames)
	var bare_late := _run_slide(bare, frames)
	check(bool(root.get("is_slide_holding")),
		"the slide left the hold on its own - this test is no longer measuring one")
	check(early[0] > bare_early[0] + 0.5,
		"the burst is not visible at the start: %.2f m/s against the plain slide's %.2f" %
			[early[0], bare_early[0]])
	approx(late[late.size() - 1], bare_late[bare_late.size() - 1], 0.1,
		"the burst was still running %.1fs in: %.2f m/s against an unboosted slide's %.2f" %
			[boost_time + 1.0, late[late.size() - 1], bare_late[bare_late.size() - 1]])

# A floor RAISES. It never takes anything away, on any frame, which is the one property
# that lets this be layered on top of two shipped specs without re-tuning either of them.
func test_the_floor_only_ever_raises_the_clip() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var bare := _scene()
	if bare == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var frames := int(3.0 / STEP)
	_begin_slide(root, float(root.get("sprint_speed")))
	var boosted := _run_slide(root, frames)
	_begin_slide(bare, 0.0)
	var plain := _run_slide(bare, frames)
	for i in frames:
		check(boosted[i] >= plain[i] - 0.001,
			"frame %d: the boosted slide runs at %.3f where the clip alone does %.3f" %
				[i, boosted[i], plain[i]])

# And where the curve is above the floor, the clip drives untouched. Out of a full sprint
# that is nowhere - the floor opens at 10.8 m/s and the curve peaks at 8.39 - so the case
# is exercised where it actually occurs: a slow entry, which is a slide out of a crouch
# (docs/specs/pilot9-slide-crouch.md). Nothing about those slides may have changed.
func test_a_slow_entry_leaves_the_clip_untouched() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var bare := _scene()
	if bare == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var reference := 1.6                  # a slow entry, the old crouch_speed
	var ceiling := reference * float(root.get("slide_entry_boost"))
	var frames := int(1.0 / STEP)
	_begin_slide(root, reference)
	var floored := _run_slide(root, frames)
	_begin_slide(bare, 0.0)
	var plain := _run_slide(bare, frames)
	var compared := 0
	for i in frames:
		if plain[i] > ceiling + 0.001:
			compared += 1
			approx(floored[i], plain[i], 0.001,
				"frame %d: the floor overwrote a curve that was already faster" % i)
	check(compared > 0,
		"the clip never out-runs a %.2f m/s floor in its first second, so nothing was " %
			ceiling + "compared - the curve is not the one this test was written against")

# A slide with no floor reproduces the old speeds. This is the regression guard for the two
# specs the burst is layered on top of: nothing about the curve, the hold or the split frame
# moved to make room for it.
func test_no_reference_leaves_the_clip_alone() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var duration := float(root.get("slide_duration"))
	var distance := float(root.get("slide_distance"))
	var hold := float(root.get("slide_hold_time"))
	_begin_slide(root, 0.0)
	# Up to the hold, which is the one stretch driven purely by the curve. In WALL frames:
	# the hold is quoted in clip seconds and the clip runs at `slide_time_scale`, so stepping
	# `hold / STEP` frames would carry a fast slide well into the run-out and measure the
	# whole clip. See docs/specs/pilot9-slide-rate.md.
	var steps := int((hold / float(root.get("slide_time_scale"))) / STEP)
	var travelled := 0.0
	for v in _run_slide(root, steps):
		travelled += v * STEP
	var expected := float(root.call("_slide_speed_at", hold))
	check(travelled > 0.0, "a slide with no floor did not move him at all")
	check(travelled < distance,
		"a slide with no floor covered %.2f m before the hold, out of the clip's %.2f" %
			[travelled, distance])
	check(expected > 0.0 and expected < distance / duration * 3.0,
		"the clip's speed at the hold (%.2f m/s) is not a measurement of this curve" % expected)

# --- the floor does not block the exits --------------------------------------

# A negative bonus eats through the floor rather than being clamped out by it. Without this
# a slide steered up a face would sit at a sprint forever and SLIDE_STALL_SPEED - the exit
# that stands him up when he runs out of hill - would be unreachable.
func test_an_uphill_bonus_still_reaches_the_stall() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var sprint := float(root.get("sprint_speed"))
	if float(root.get("slide_hold_time")) <= 0.0:
		fail("no baked hold to test")
		return
	_begin_slide(root, sprint)
	_run_slide(root, int(1.0 / STEP))     # into the hold, on the flat
	# What a second or two up a steep face leaves in the bonus. _advance_slide_bonus() is
	# not reachable headlessly (it needs a floor under him), so it is set directly - the
	# point being tested is that _apply_slide_velocity() does not clamp it away.
	root.set("_slide_bonus", -sprint * 1.5)
	var speeds := _run_slide(root, 1)
	check(speeds[0] < PILOT.SLIDE_STALL_SPEED,
		"a bonus of -%.1f left him at %.2f m/s - the floor is holding him above the stall" %
			[sprint * 1.5, speeds[0]])
