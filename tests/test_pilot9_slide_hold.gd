extends "res://tests/test_case.gd"

# Covers the held slide: the clip parks on its frame-30 pose, he carries on at a constant
# speed for as long as the player wants, and `crouch` plays out the run-out while `jump`
# cuts straight to the leap.
#
# The failures worth catching here are all quiet ones. The hold is three numbers agreeing
# with each other - the baked `slide_hold_time`, the controller's `_slide_time`, and the
# AnimationTree's own clip clock - and every way they can disagree looks like a working
# slide that feels wrong: a hold on the run-out pose, a body that stops dead while the
# animation keeps going, a clip that plays itself out under a frozen controller.
#
# See docs/specs/pilot9-slide-hold.md.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const BUILDER := preload("res://scripts/pilot9_build_scene.gd")
const ANIM_SCRIPT := preload("res://scripts/pilot9_animation.gd")

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

# A slide already running, at the top of its clip, heading down +Z. Nothing here enters the
# tree, so this is the state _start_slide() would have left behind minus the input reads.
func _begin_slide(root: Node) -> void:
	root.set("_slide_direction", Vector3(0.0, 0.0, 1.0))
	root.set("_slide_time", 0.0)
	root.set("is_sliding", true)
	root.set("is_slide_holding", false)

# Steps _apply_slide_velocity() `count` times and returns the forward speeds seen.
func _run_slide(root: Node, count: int) -> PackedFloat32Array:
	var speeds: PackedFloat32Array = []
	for i in count:
		root.call("_apply_slide_velocity", STEP)
		speeds.append((root.get("velocity") as Vector3).z)
	return speeds

# --- the hold point was baked ----------------------------------------------

# The frame number is quoted on Blender's 60 fps timeline, exactly like SLIDE_KEEP_FRAMES,
# and both are read off the same action. Asserted as the conversion rather than as 0.5 s so
# a re-authored clip moves the expectation with it.
func test_the_hold_time_is_the_hold_frame_in_seconds() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var expected := float(BUILDER.SLIDE_HOLD_FRAME) / BUILDER.SLIDE_SOURCE_FPS
	approx(float(root.get("slide_hold_time")), expected, 0.001,
		"slide_hold_time is not frame %d at %.0f fps - the bake did not run, or an old " %
			[BUILDER.SLIDE_HOLD_FRAME, BUILDER.SLIDE_SOURCE_FPS] +
		"pilot9.tscn is on disk. Zero here is not an error the controller reports: it just " +
		"quietly plays the slide straight through")

# A hold frame outside the trimmed clip is a hold on a pose that is not there. The builder
# refuses that outright rather than clamping, so the two constants have to agree - and this
# is the assertion that says so before a re-export finds out in game.
func test_the_hold_lands_inside_the_trimmed_clip() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var hold := float(root.get("slide_hold_time"))
	var duration := float(root.get("slide_duration"))
	check(hold > 0.0 and hold < duration,
		"the hold at %.3fs is not inside the %.3fs clip" % [hold, duration])
	check(BUILDER.SLIDE_HOLD_FRAME < BUILDER.SLIDE_KEEP_FRAMES,
		"SLIDE_HOLD_FRAME (%d) is at or past SLIDE_KEEP_FRAMES (%d) - the trim would cut " %
			[BUILDER.SLIDE_HOLD_FRAME, BUILDER.SLIDE_KEEP_FRAMES] + "the pose the hold sits on")

# The builder owns this one, like the other three. Tuned in the inspector it would be lost
# on the next sync anyway, and worse, it would disagree with the clip it indexes into.
func test_the_hold_time_is_a_baked_property() -> void:
	check(BUILDER.SLIDE_BAKED.has("slide_hold_time"),
		"slide_hold_time is not in SLIDE_BAKED, so a re-export re-measures the clip and " +
		"leaves the hold pointing at a frame from the old one")

# --- entering the hold -----------------------------------------------------

# The clock stops on the hold, and stops ON it rather than wherever the frame that crossed
# happened to land. A hold that drifts a few milliseconds past its frame every time is a
# hold on a slightly different pose at every frame rate.
func test_the_slide_parks_on_the_hold_frame() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var hold := float(root.get("slide_hold_time"))
	if hold <= 0.0:
		fail("no baked hold to test")
		return
	_begin_slide(root)
	# Half a second past the hold: long enough that a clock which failed to stop would be
	# well into the run-out by now.
	_run_slide(root, int((hold + 0.5) / STEP))
	check(bool(root.get("is_slide_holding")),
		"the slide did not enter the hold - _apply_slide_velocity ran %.3fs past it" % 0.5)
	eq(float(root.get("_slide_time")), hold,
		"_slide_time did not stop exactly on the hold frame")

# The whole point of the feature, stated as the thing it replaced: the old slide was over
# by `slide_duration` and this one is not.
func test_the_hold_outlives_the_clip() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	if float(root.get("slide_hold_time")) <= 0.0:
		fail("no baked hold to test")
		return
	_begin_slide(root)
	# Ten seconds - eight times the clip's own length.
	var speeds := _run_slide(root, int(10.0 / STEP))
	check(bool(root.get("is_slide_holding")),
		"the slide ended itself after 10 s - the hold is supposed to wait for the player")
	check(speeds[speeds.size() - 1] > 0.1,
		"he is doing %.3f m/s ten seconds in - the hold stopped moving him" %
			speeds[speeds.size() - 1])

# Constant, by the user's call: no friction and no gravity term along the floor. A slope
# carries him further only because move_and_slide() projects this constant horizontal
# velocity down it. A decay creeping in here would be a tuning decision nobody made.
func test_the_hold_speed_does_not_change() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var hold := float(root.get("slide_hold_time"))
	if hold <= 0.0:
		fail("no baked hold to test")
		return
	_begin_slide(root)
	# One clear frame past the crossing: that frame is split between the curve and the hold
	# (see _apply_slide_velocity), so it is the last frame that is not purely held.
	_run_slide(root, int(hold / STEP) + 2)
	var first := (root.get("velocity") as Vector3).z
	_run_slide(root, int(5.0 / STEP))
	var last := (root.get("velocity") as Vector3).z
	approx(last, first, 0.0001,
		"the hold speed drifted over 5 s - it is meant to be flat")

# Measured off the curve rather than declared, so the entry into the hold is continuous.
# The number this catches is a dropped factor: a hold that starts at a plausible-looking
# fraction of the clip's speed reads as a lurch on the frame it parks.
func test_the_hold_carries_the_speed_the_clip_reached() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var hold := float(root.get("slide_hold_time"))
	if hold <= 0.0:
		fail("no baked hold to test")
		return
	_begin_slide(root)
	var steps := int(hold / STEP)
	var approaching := _run_slide(root, steps)
	var before := approaching[approaching.size() - 1]
	_run_slide(root, 3)   # over the boundary and into the hold
	var held := (root.get("velocity") as Vector3).z
	check(bool(root.get("is_slide_holding")), "did not reach the hold")
	# Loose: `before` is one frame's difference off the curve and `held` is a 50 ms average,
	# so they are two honest measurements of a decelerating curve and cannot be equal. What
	# is being denied is a factor of `slide_distance` or `slide_scale` going missing, which
	# would be off by metres rather than by tenths.
	approx(held, before, 1.0,
		"the hold runs at %.2f m/s where the clip had just been doing %.2f - that is not a " %
			[held, before] + "measurement of the same curve")

# The dial still works on the held part. slide_scale multiplies the curve, and the hold
# speed is read off the curve, so it has to carry through - otherwise turning it up makes
# a faster entry that drops into a slower hold.
func test_slide_scale_reaches_the_hold_speed() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var hold := float(root.get("slide_hold_time"))
	if hold <= 0.0:
		fail("no baked hold to test")
		return
	var steps := int(hold / STEP) + 2
	_begin_slide(root)
	_run_slide(root, steps)
	var base := (root.get("velocity") as Vector3).z
	root.set("slide_scale", 2.0)
	_begin_slide(root)
	_run_slide(root, steps)
	var doubled := (root.get("velocity") as Vector3).z
	approx(doubled, base * 2.0, 0.01,
		"slide_scale does not reach the hold speed - the entry would speed up and the hold " +
		"would not")

# The off switch. `can_hold_slide` false has to be the old slide exactly, because it is what
# the user falls back to if the hold turns out to feel wrong in play.
func test_can_hold_slide_off_plays_the_clip_straight_through() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var duration := float(root.get("slide_duration"))
	if duration <= 0.0:
		fail("no baked slide")
		return
	root.set("can_hold_slide", false)
	_begin_slide(root)
	_run_slide(root, int(duration / STEP) + 2)
	check(not bool(root.get("is_slide_holding")),
		"the slide held with can_hold_slide off")
	check(float(root.get("_slide_time")) >= duration,
		"_slide_time stopped at %.3fs of %.3fs with the hold switched off" %
			[float(root.get("_slide_time")), duration])

# Same for a scene built before the hold existed, or a build whose bake was refused: zero
# means no hold, and no hold means the slide it always was rather than a slide that parks
# on frame 0 forever.
func test_a_zero_hold_time_plays_the_clip_straight_through() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var duration := float(root.get("slide_duration"))
	if duration <= 0.0:
		fail("no baked slide")
		return
	root.set("slide_hold_time", 0.0)
	_begin_slide(root)
	_run_slide(root, int(duration / STEP) + 2)
	check(not bool(root.get("is_slide_holding")),
		"a zero slide_hold_time still put him into a hold")

# --- leaving the hold ------------------------------------------------------

# Leaving is a resume, not a restart. `crouch` clears the flag and the clock picks up from
# the hold frame, so what plays is frames 30-75 - the run-out. Restarting the clip instead
# would replay the drop into the slide he is already in.
func test_leaving_the_hold_resumes_the_run_out() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var hold := float(root.get("slide_hold_time"))
	var duration := float(root.get("slide_duration"))
	if hold <= 0.0:
		fail("no baked hold to test")
		return
	_begin_slide(root)
	_run_slide(root, int((hold + 1.0) / STEP))
	if not bool(root.get("is_slide_holding")):
		fail("did not reach the hold")
		return
	# What the `crouch` branch of _handle_crouch_and_slide() does, without the input read -
	# Input cannot be driven headlessly.
	root.set("is_slide_holding", false)
	_run_slide(root, 1)
	var resumed := float(root.get("_slide_time"))
	check(resumed > hold and resumed < duration,
		"leaving the hold put the clock at %.3fs, which is neither the hold (%.3fs) it " %
			[resumed, hold] + "resumed from nor inside the %.3fs clip" % duration)
	# And it does not fall straight back in.
	_run_slide(root, int((duration - hold) / STEP))
	check(not bool(root.get("is_slide_holding")),
		"the run-out re-entered the hold - the crossing test is not one-way")
	check(float(root.get("_slide_time")) >= duration,
		"the run-out did not reach the end of the clip")

# The distance stays honest across a hold: the run-in plus the run-out still add up to
# exactly what the clip was authored to travel, with the held metres on top and not one
# frame's worth double-counted at the seam.
#
# Stated as an identity rather than as a number, because it is one. Every frame's travel is
# either read off the curve - advancing _slide_time by that much - or spent at the hold
# speed, and the frame that crosses into the hold is split between the two. So over any run:
#
#     travelled == curve travel up to _slide_time + hold_speed * (elapsed - _slide_time)
#
# Run to the end of the clip, _slide_time is `slide_duration` and the first term is the whole
# `slide_distance`. A seam that rounds the crossing frame either way breaks this by about a
# frame of travel - a tenth of a metre, invisible in play and exactly the kind of drift that
# accumulates once a slope is a dozen slides long.
func test_a_held_slide_still_travels_the_clip_plus_the_hold() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var hold := float(root.get("slide_hold_time"))
	var duration := float(root.get("slide_duration"))
	var distance := float(root.get("slide_distance"))
	if hold <= 0.0 or duration <= 0.0:
		fail("no baked hold to test")
		return
	_begin_slide(root)
	var travelled := 0.0
	var steps := 0
	# Run-in, then a two-second hold, then the run-out to the end of the clip.
	for s in _run_slide(root, int((hold + 2.0) / STEP)):
		travelled += s * STEP
		steps += 1
	if not bool(root.get("is_slide_holding")):
		fail("did not reach the hold")
		return
	var held_speed := float(root.get("_slide_hold_speed"))
	root.set("is_slide_holding", false)
	while float(root.get("_slide_time")) < duration and steps < 10000:
		root.call("_apply_slide_velocity", STEP)
		travelled += (root.get("velocity") as Vector3).z * STEP
		steps += 1
	var elapsed := float(steps) * STEP
	var expected := distance + held_speed * (elapsed - duration)
	approx(travelled, expected, 0.02,
		"a held slide travelled %.3f m where the clip's %.3f m plus %.3f s of hold at " %
			[travelled, distance, elapsed - duration] +
		"%.3f m/s is %.3f m - the seam is losing or duplicating travel" % [held_speed, expected])

# --- the animation seam ----------------------------------------------------

# The two halves of the TimeScale, asserted against each other. AnimationTree.set() stores
# an unknown parameter path silently, so a rename on either side leaves the clip running
# past the hold pose under a controller that has already frozen - with nothing in the log.
func test_the_animation_script_writes_the_scale_the_builder_built() -> void:
	var expected := "parameters/%s/%s/scale" % [BUILDER.SLIDE_STATE, BUILDER.SLIDE_SCALE_NODE]
	eq(ANIM_SCRIPT.SLIDE_SCALE, expected,
		"pilot9_animation.gd writes a TimeScale path the builder does not build")

func test_the_tree_exposes_the_slide_scale_parameter() -> void:
	var root := _scene()
	if root == null:
		fail("scenes/pilot9.tscn did not load")
		return
	var at := root.get_node_or_null("AnimationTree") as AnimationTree
	if at == null:
		fail("no AnimationTree on pilot9.tscn")
		return
	var found := false
	for p in at.get_property_list():
		if String(p.name) == ANIM_SCRIPT.SLIDE_SCALE:
			found = true
			break
	check(found, "the AnimationTree exposes no '%s' - nothing can freeze the slide clip" %
		ANIM_SCRIPT.SLIDE_SCALE)

# The one rule that keeps a TimeScale legal in this state. Both clocks may stop and start
# together; neither may run at a rate the other does not. The crouch's eased scale right
# beside it is exactly what must not be copied here, so the shape of the write is asserted
# rather than left to the comment above it.
func test_the_slide_scale_is_only_ever_frozen_or_running() -> void:
	var src := FileAccess.open("res://scripts/pilot9_animation.gd", FileAccess.READ)
	if src == null:
		fail("could not read scripts/pilot9_animation.gd")
		return
	var text := src.get_as_text()
	var at := text.find("func _drive_slide")
	check(at != -1, "pilot9_animation.gd has no _drive_slide() - nothing drives the hold")
	if at == -1:
		return
	var body := text.substr(at)
	# Hard 0/1 - a third value or a rate between them advances the clip against a distance
	# curve that knows nothing about it, and the animation never gets that drift back. The
	# freeze condition also carries is_slide_holding: the hold pose is what has to stay put.
	# (2026-09-07: it now ALSO freezes on `not is_sliding`, so the held pose - not a slice of
	# run-out - is what cross-fades into the crouch. See docs/specs/pilot9-slide-crouch.md.)
	check(body.contains("0.0 if hold_pose else 1.0"),
		"_drive_slide() no longer writes a hard 0/1 - a rate between them drifts the clip " +
		"against the distance curve and the animation never gets it back")
	check(body.contains("is_slide_holding"),
		"_drive_slide() no longer freezes on is_slide_holding - the hold pose would advance")
	check(not body.contains("lerp"),
		"_drive_slide() eases the scale like the crouch's does. The crouch may: its clip " +
		"drives nothing. This one is tied to _slide_time and would drift by the integral " +
		"of the ease on every hold")
