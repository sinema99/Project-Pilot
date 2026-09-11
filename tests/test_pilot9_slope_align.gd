extends "res://tests/test_case.gd"

# Covers slope alignment: the MESH lies along the grade he is standing on while the collision
# capsule stays bolt upright. See docs/specs/pilot9-slope-align.md.
#
# Almost everything here is the static _slope_align_angles() called straight off the loaded
# script, for the reason test_pilot9_slope_momentum.gd gives at length: is_on_floor() cannot be
# made true without a physics world, so a pure function taking a floor normal is the only form
# of this arithmetic a headless test can reach.
#
# Two things here are worth more than the rest.
#
# The first is the ROUND TRIP. The spec's claim is "parallel with the slope", not "leans about
# right", and the only honest way to assert that is to rebuild the basis from the two angles
# this returns and check that it carries local +Y onto the floor normal. Every other assertion
# below is a sign or a dial; that one is the feature.
#
# The second is the sign convention, in both axes. A floor's normal leans DOWNHILL, positive
# rotation.x is nose-down, and `character`'s local +X points to pilot9's LEFT (the 180 degree
# basis on the node). Any of those flipped braces him against the hill instead of lying along
# it, which on play reads as a broken clip rather than as a wrong sign.

const PILOT_PATH := "res://scripts/pilot9.gd"
const PILOT_TSCN := "res://scenes/pilot9.tscn"

const ANGLE_TOL := 0.0001
const BLEND_TOL := 0.001
# 300 steps at the shipping slope_align_speed of 10.0 puts the lerp far past any tolerance
# here; the settle is about convergence, not about the rate.
const SETTLE_STEPS := 300
const SETTLE_DELTA := 0.016

var _instances: Array[Node] = []

# Runtime load, not preload: a preload of a script that fails to parse is a parse-time error,
# which makes --script fall back to main.tscn and hang. Matches test_pilot9_slope_momentum.gd.
func _pilot() -> GDScript:
	return load(PILOT_PATH) as GDScript

func _scene() -> Node:
	var ps := load(PILOT_TSCN) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate()
	_instances.append(n)
	n.character = n.get_node("character")
	return n

func _anim(n: Node) -> Node:
	var a := n.get_node("Animation")
	a.player = n
	a.animation_tree = n.get_node("AnimationTree")
	return a

func end() -> void:
	for n in _instances:
		if is_instance_valid(n):
			n.free()
	_instances.clear()
	super()

# The upward normal of a plane tilted `deg` off level whose downhill direction is the heading
# `downhill_yaw` (0 = +Z, the same yaw convention character.rotation.y uses). The untilted
# case is the same helper and the same convention as test_pilot9_slope_momentum.gd.
func _slope_normal(deg: float, downhill_yaw: float = 0.0) -> Vector3:
	var t := deg_to_rad(deg)
	return Vector3(0.0, cos(t), sin(t)).rotated(Vector3.UP, downhill_yaw)

func _angle_eq(actual: float, expected: float, msg: String) -> void:
	checks += 1
	var d := absf(angle_difference(actual, expected))
	if d > ANGLE_TOL:
		fail("%s\n      expected: %f\n      actual:   %f  (off by %f rad)" % [msg, expected, actual, d])

# --- nothing underfoot, nothing to lie along -------------------------------

func test_level_ground_is_untilted() -> void:
	var p := _pilot()
	eq(p._slope_align_angles(0.0, Vector3.UP, 1.0, 1.0), Vector2.ZERO,
		"flat floor tilted the mesh - he would stand crooked on every level surface")

func test_zero_normal_is_untilted() -> void:
	var p := _pilot()
	# What get_floor_normal() hands back with nothing under him. Guarded rather than left to
	# normalized() returning zero, because atan2(0, 0) is 0 and would have looked fine.
	eq(p._slope_align_angles(1.3, Vector3.ZERO, 1.0, 1.0), Vector2.ZERO,
		"a zero floor normal produced a tilt - airborne frames would pose him off a stale grade")

# --- the signs -------------------------------------------------------------

func test_facing_downhill_pitches_nose_down() -> void:
	var p := _pilot()
	var a: Vector2 = p._slope_align_angles(0.0, _slope_normal(30.0), 1.0, 1.0)
	_angle_eq(a.x, deg_to_rad(30.0),
		"heading down a 30 degree grade did not pitch him 30 degrees nose-down")
	_angle_eq(a.y, 0.0, "a straight descent rolled him - there is no sideways grade to lean on")

func test_facing_uphill_pitches_nose_up() -> void:
	var p := _pilot()
	# Same slope, turned to walk up it: downhill is now behind him.
	var a: Vector2 = p._slope_align_angles(PI, _slope_normal(30.0), 1.0, 1.0)
	_angle_eq(a.x, deg_to_rad(-30.0),
		"heading up a 30 degree grade did not pitch him 30 degrees nose-up - the sign is flipped")
	_angle_eq(a.y, 0.0, "a straight climb rolled him")

func test_slope_falling_to_his_right_rolls_right() -> void:
	var p := _pilot()
	# Facing +X with the fall line at +Z: downhill is off his right shoulder.
	var a: Vector2 = p._slope_align_angles(PI / 2.0, _slope_normal(30.0), 1.0, 1.0)
	_angle_eq(a.x, 0.0, "crossing the grade pitched him - the fall line is square to his heading")
	_angle_eq(a.y, deg_to_rad(30.0),
		"ground falling away to his right did not roll him into it - he is braced, not lying along it")

func test_slope_falling_to_his_left_rolls_left() -> void:
	var p := _pilot()
	var a: Vector2 = p._slope_align_angles(-PI / 2.0, _slope_normal(30.0), 1.0, 1.0)
	_angle_eq(a.x, 0.0, "crossing the grade pitched him")
	_angle_eq(a.y, deg_to_rad(-30.0),
		"ground falling away to his left did not roll him into it - the roll sign is pinned from both sides")

func test_yaw_frame_is_applied() -> void:
	var p := _pilot()
	# One fixed slope, walked round at four headings. Pitch and roll trade places; if the
	# function were quietly world-space, all four would return the same pair.
	var n := _slope_normal(20.0)
	var t := deg_to_rad(20.0)
	var expected := [Vector2(t, 0.0), Vector2(0.0, t), Vector2(-t, 0.0), Vector2(0.0, -t)]
	for i in 4:
		var a: Vector2 = p._slope_align_angles(i * PI / 2.0, n, 1.0, 1.0)
		_angle_eq(a.x, expected[i].x, "pitch at heading %d of 4 on one fixed slope" % (i + 1))
		_angle_eq(a.y, expected[i].y, "roll at heading %d of 4 on one fixed slope" % (i + 1))

# --- the claim: parallel, not approximately parallel -----------------------

func test_round_trip_puts_his_up_axis_on_the_floor_normal() -> void:
	var p := _pilot()
	# The feature, asserted as the thing it says it is. Rebuild the mesh's basis from the two
	# angles plus the heading it was given, in the Euler order Node3D uses, and its local +Y
	# has to come out as the floor normal. Grades and headings scattered, including the
	# awkward diagonals where a pitch-only or a world-space version would both pass everything
	# above and fail here.
	#
	# Deadzone off, which is what the parameter exists for: it is deliberately not exact -
	# a heading within 3 degrees of square to the fall line gives up its sliver of pitch on
	# purpose - and this test is about the alignment, not about the noise guard.
	for deg in [10.0, 25.0, 44.0]:
		for downhill_yaw in [0.0, 0.7, 2.4, -1.9]:
			for yaw in [0.0, 0.4, 1.6, 3.0, -2.2]:
				var n := _slope_normal(deg, downhill_yaw)
				var a: Vector2 = p._slope_align_angles(yaw, n, 1.0, 1.0, 0.0)
				var up := Basis.from_euler(Vector3(a.x, yaw, a.y), EULER_ORDER_YXZ) * Vector3.UP
				checks += 1
				if up.distance_to(n) > 0.001:
					fail(("mesh up axis missed the floor normal at %.0f deg, fall line %.1f rad, heading %.1f rad" \
						+ "\n      expected: %s\n      actual:   %s") % [deg, downhill_yaw, yaw, str(n), str(up)])
					return

func test_character_node_uses_the_euler_order_this_rests_on() -> void:
	var n := _scene()
	# The whole scheme - writing yaw, pitch and roll as three independent components and
	# keeping the heading exactly what _handle_character_rotation() set - holds because the
	# yaw is applied outermost. A scene re-saved with any other order breaks it silently.
	eq(n.character.rotation_order, EULER_ORDER_YXZ,
		"the character node's rotation order is not YXZ - the slope tilt would drag his heading with it")

# --- the dials -------------------------------------------------------------

func test_weights_scale_their_own_axis() -> void:
	var p := _pilot()
	var n := _slope_normal(30.0, 0.9)          # a fall line off both axes, so neither is zero
	var full: Vector2 = p._slope_align_angles(0.0, n, 1.0, 1.0)
	var half: Vector2 = p._slope_align_angles(0.0, n, 0.5, 1.0)
	_angle_eq(half.x, full.x * 0.5, "slope_align_pitch did not scale the pitch")
	_angle_eq(half.y, full.y, "slope_align_pitch leaked into the roll")

func test_zero_weight_is_an_off_switch() -> void:
	var p := _pilot()
	var n := _slope_normal(30.0, 0.9)
	var pitch_only: Vector2 = p._slope_align_angles(0.0, n, 1.0, 0.0)
	_angle_eq(pitch_only.y, 0.0,
		"slope_align_roll at 0.0 still rolled him - this is the dial that reproduces Setsuna")
	check(absf(pitch_only.x) > 0.01, "slope_align_roll at 0.0 also killed the pitch")
	eq(p._slope_align_angles(0.0, n, 0.0, 0.0), Vector2.ZERO,
		"both weights at 0.0 did not restore the pre-2026-09-11 upright mesh")

func test_deadzone_reads_a_shallow_grade_as_flat() -> void:
	var p := _pilot()
	eq(p._slope_align_angles(0.0, _slope_normal(2.0, 0.9), 1.0, 1.0), Vector2.ZERO,
		"a 2 degree grade tilted him - collision mesh noise would twitch him standing still")
	var live: Vector2 = p._slope_align_angles(0.0, _slope_normal(4.0), 1.0, 1.0)
	check(absf(live.x) > 0.0,
		"a 4 degree grade read as flat - the deadzone is eating real slopes")
	# Those two bracket the default between 2 and 4 degrees, which is the guard the game
	# actually runs with - worth pinning, because the round trip above turns it off and would
	# not notice the default going with it.
	var off: Vector2 = p._slope_align_angles(0.0, _slope_normal(2.0), 1.0, 1.0, 0.0)
	check(absf(off.x) > 0.0,
		"the deadzone parameter at 0.0 still swallowed a 2 degree grade - it is not the guard")

# --- applied to the node ---------------------------------------------------

func test_airborne_levels_the_mesh() -> void:
	var n := _scene()
	# Nothing has ever called move_and_slide() on this instance, so is_on_floor() is false -
	# the airborne case, and the mantle's case too.
	n.character.rotation.x = 0.5
	n.character.rotation.z = -0.4
	for i in SETTLE_STEPS:
		n._align_model_to_slope(SETTLE_DELTA)
	_angle_eq(n.character.rotation.x, 0.0, "airborne pitch did not ease back to level")
	_angle_eq(n.character.rotation.z, 0.0, "airborne roll did not ease back to level")

func test_slope_tilt_leaves_the_heading_alone() -> void:
	var n := _scene()
	n.character.rotation.y = 1.234
	n.character.rotation.x = 0.5
	n.character.rotation.z = -0.4
	for i in SETTLE_STEPS:
		n._align_model_to_slope(SETTLE_DELTA)
	_angle_eq(n.character.rotation.y, 1.234,
		"the tilt moved his heading - the turn-to-face rule and the slide's welded facing both rest on it not doing that")

# --- the blend feed the tilt could have broken -----------------------------

func test_blend_feed_ignores_the_slope_tilt() -> void:
	var n := _scene()
	var a := _anim(n)
	# Running straight ahead, on a grade. The body-space blend reads the mesh's basis, and if
	# it read the TILTED basis the forward term would come back as cos(pitch) - a run that
	# quietly drifts toward a walk on every hill.
	n.character.rotation.y = 0.9
	n.character.rotation.x = deg_to_rad(35.0)
	n.character.rotation.z = deg_to_rad(15.0)
	n.input_dir = Vector2(0.0, -1.0)
	n.input_strength = 1.0
	n.direction = Vector3(sin(0.9), 0.0, cos(0.9))
	var blend: Vector2 = a._travel_blend()
	checks += 1
	if blend.distance_to(Vector2(0.0, 1.0)) > BLEND_TOL:
		fail("travel straight ahead on a slope did not ask for pure run_forward\n      actual: %s" % str(blend))
