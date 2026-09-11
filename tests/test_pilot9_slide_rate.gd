extends "res://tests/test_case.gd"

# Covers the slide's playback rate: `slide_time_scale`, the one number the animation's clock
# and the controller's clock are both read off.
#
# The rule this guards is the one every other slide test leans on. `slide_motion` is the
# slide's travel, and the pose the player sees is only the pose that is travelling while the
# AnimationTree plays the clip at exactly the rate _apply_slide_velocity() reads the curve
# at. One side scaled without the other is not an error, a warning or a visible break - it is
# feet that drift against the floor a little further with every frame of a slide.
#
# So the two halves are asserted against each other and against the export, never against a
# constant: a rate of 2 that only the animation knows about, and a rate of 2 that only the
# controller knows about, both have to fail here.
#
# See docs/specs/pilot9-slide-rate.md.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const BUILDER := preload("res://scripts/pilot9_build_scene.gd")

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

# Steps a whole slide with the hold off - the rate's effect on the run-in and the run-out is
# the point, and a hold would stop the clock in the middle of the measurement. Returns the
# distance travelled, the peak speed and the wall time it took.
func _play_whole_clip(root: Node, rate: float) -> Dictionary:
	root.set("slide_time_scale", rate)
	root.set("can_hold_slide", false)
	root.set("is_slide_holding", false)
	# The ceiling out of the way. Doubling the rate doubles every speed the curve produces,
	# and with slide_scale turned up as well the clip runs past slide_max_speed - which would
	# make this a measurement of the clamp. The clamp is a separate rule with its own tests in
	# tests/test_pilot9_slope_momentum.gd; it is what the player meets in game, and the point
	# of lifting it here is to see the rate underneath it.
	root.set("slide_max_speed", 1000.0)
	root.set("_slide_direction", Vector3(0.0, 0.0, 1.0))
	root.set("_slide_time", 0.0)
	root.set("is_sliding", true)
	var duration := float(root.get("slide_duration"))
	var travelled := 0.0
	var peak := 0.0
	var steps := 0
	# Generous: the clip runs `duration / rate` in wall seconds, and the loop stops on the
	# clock rather than on the count anyway.
	var limit := int((duration / rate) / STEP) + 240
	while float(root.get("_slide_time")) < duration and steps < limit:
		root.call("_apply_slide_velocity", STEP)
		var speed := (root.get("velocity") as Vector3).z
		travelled += speed * STEP
		peak = maxf(peak, speed)
		steps += 1
	return {"travelled": travelled, "peak": peak, "wall": float(steps) * STEP}

# --- the dial itself -------------------------------------------------------

func test_the_rate_exists_and_is_positive() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var props: Dictionary = {}
	for p in root.get_property_list():
		props[String(p.name)] = true
	check(props.has("slide_time_scale"),
		"scripts/pilot9.gd has no 'slide_time_scale' - the slide's clip and its distance " +
		"curve have no shared rate to run at")
	if not props.has("slide_time_scale"):
		return
	# A zero or negative rate divides by itself in _apply_slide_velocity's hold split, and a
	# clip that never advances is a slide that never ends.
	check(float(root.get("slide_time_scale")) > 0.0,
		"slide_time_scale is %.2f - at or below zero the clip never advances and the slide " %
			float(root.get("slide_time_scale")) + "never reaches its end")

# Same argument as slide_scale's: the builder rewrites the baked properties on every rig
# sync, and a rate tuned on play must not be one of the things it resets.
func test_the_rate_is_not_a_baked_property() -> void:
	check(not BUILDER.SLIDE_BAKED.has("slide_time_scale"),
		"slide_time_scale is in SLIDE_BAKED, so pilot9_build_scene.gd overwrites it on " +
		"every sync and a re-export silently puts the slide back to the clip's own rate")

# --- the controller's half -------------------------------------------------

# The clock is the whole mechanism: the pose the tree shows is `_slide_time` seconds into the
# clip, and the tree is advancing at `slide_time_scale`, so this is what keeps them the same
# frame. Measured rather than read off the source - a multiply in the wrong place (on the
# distance instead of the clock, say) leaves plausible speeds and the wrong pose.
func test_the_clock_advances_at_the_rate() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var duration := float(root.get("slide_duration"))
	if duration <= 0.0:
		fail("no baked slide to step")
		return
	root.set("slide_time_scale", 2.0)
	root.set("can_hold_slide", false)
	root.set("is_slide_holding", false)
	root.set("_slide_direction", Vector3(0.0, 0.0, 1.0))
	root.set("_slide_time", 0.0)
	root.set("is_sliding", true)
	var steps := 6
	for i in steps:
		root.call("_apply_slide_velocity", STEP)
	approx(float(root.get("_slide_time")), float(steps) * STEP * 2.0, 0.0001,
		"%d frames at a rate of 2 left the clock at %.4fs, not the %.4fs of clip the " %
			[steps, float(root.get("_slide_time")), float(steps) * STEP * 2.0] +
		"AnimationTree has played - the pose and the travel are different frames")

# --- what the rate does, and what it must not do ---------------------------

# Distance is `slide_scale`'s job and only `slide_scale`'s. A rate that moved it would mean
# tuning the feel of the slide also moved where it puts him, which is the one thing the
# builder's bake exists to keep honest.
func test_the_rate_does_not_change_the_distance() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var distance := float(root.get("slide_distance"))
	if float(root.get("slide_duration")) <= 0.0:
		fail("no baked slide to integrate")
		return
	approx(_play_whole_clip(root, 1.0)["travelled"], distance, 0.05,
		"the slide does not travel slide_distance at a rate of 1")
	approx(_play_whole_clip(root, 2.0)["travelled"], distance, 0.05,
		"doubling the rate moved the distance - the rate is how fast the clip plays, not " +
		"how far it goes. That dial is slide_scale")

# The point of the feature, stated as the two things the player actually feels: the same
# slide, in half the time, at twice the speed.
func test_the_rate_scales_the_speed_and_the_length() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	if float(root.get("slide_duration")) <= 0.0:
		fail("no baked slide to integrate")
		return
	var single := _play_whole_clip(root, 1.0)
	var double := _play_whole_clip(root, 2.0)
	approx(double["peak"], single["peak"] * 2.0, 0.2,
		"the slide peaks at %.2f m/s at a rate of 2 against %.2f at a rate of 1 - the clip " %
			[double["peak"], single["peak"]] +
		"is playing faster but the body is not, which is skate")
	approx(double["wall"], single["wall"] * 0.5, 2.0 * STEP,
		"the clip took %.3fs at a rate of 2 against %.3fs at a rate of 1 - doubling the " %
			[double["wall"], single["wall"]] + "rate has to halve the length")

# The held part rides on the same rate. `_slide_hold_speed` is measured off the curve in clip
# seconds, so the conversion into real seconds has to be in there too - without it a fast
# slide drops into a hold going at the old speed, which is a lurch on the frame it parks.
func test_the_rate_reaches_the_hold_speed() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var hold := float(root.get("slide_hold_time"))
	if hold <= 0.0:
		fail("no baked hold to test")
		return
	var speeds: Array[float] = []
	for rate in [1.0, 2.0]:
		root.set("slide_time_scale", rate)
		root.set("can_hold_slide", true)
		root.set("is_slide_holding", false)
		root.set("_slide_direction", Vector3(0.0, 0.0, 1.0))
		root.set("_slide_time", 0.0)
		root.set("is_sliding", true)
		# Wall frames to the hold at this rate, plus two clear of the split frame.
		for i in int((hold / rate) / STEP) + 4:
			root.call("_apply_slide_velocity", STEP)
		if not bool(root.get("is_slide_holding")):
			fail("did not reach the hold at a rate of %.1f" % rate)
			return
		speeds.append(float(root.get("_slide_hold_speed")))
	approx(speeds[1], speeds[0] * 2.0, 0.05,
		"the hold runs at %.2f m/s at a rate of 2 against %.2f at a rate of 1 - the rate " %
			[speeds[1], speeds[0]] + "did not reach _slide_hold_speed, so a faster slide " +
		"parks into a slower hold")

# The rate and the distance dial are independent, and both reach the same slide. Composed
# rather than either-or: rate 2 with a 1.5 scale is 1.5x the ground in half the time.
func test_the_rate_composes_with_slide_scale() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var distance := float(root.get("slide_distance"))
	if float(root.get("slide_duration")) <= 0.0:
		fail("no baked slide to integrate")
		return
	root.set("slide_scale", 1.5)
	var result := _play_whole_clip(root, 2.0)
	approx(result["travelled"], distance * 1.5, 0.08,
		"rate 2 with slide_scale 1.5 travelled %.3f m, not the %.3f m the scale asks for - " %
			[result["travelled"], distance * 1.5] + "the two dials are not independent")
