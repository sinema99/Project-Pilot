extends "res://tests/test_case.gd"

# Covers the camera's answer to walls: it zooms in toward pilot9 rather than clipping through
# them or snapping around them. See docs/specs/pilot9-camera-collision.md.
#
# Two things here are the feature and the rest are guards. The first is the ASYMMETRY - fast
# in, slow out - because that single inequality is what stops a grazing edge from oscillating
# the shot at 60 Hz, and a symmetric pair of speeds would look perfectly reasonable in the
# file while shipping the bug back. The second is that the probe is FATTER than the arm's own
# backstop: equal radii would only ever agree with the engine's instant clamp, always too late
# to damp, and the retraction would be a snap again with all the new machinery still in place.
#
# The cast itself is not asserted. The runner works on the first idle frame with no walls in
# the world and no physics step behind it, so the probe is nulled wherever a test drives the
# real per-frame function - these are about the arithmetic and the wiring, and the wall is the
# player's to walk into.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const PILOT := preload("res://scripts/pilot9.gd")

# Physics steps, at the project's 60 Hz.
const STEP := 1.0 / 60.0

var _instances: Array[Node] = []

# These need _ready() to have run - the arm's shape and the probe are built there, and
# spring_arm is an @onready. So the rig goes into the real tree and comes back out in end(),
# the way tests/test_pilot9_sprint_fov.gd does it.
func _scene() -> Node:
	var ps := load(PILOT_TSCN) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		n.free()
		return null
	tree.root.add_child(n)
	_instances.append(n)
	return n

func end() -> void:
	for n in _instances:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_instances.clear()
	super()

func _arm(root: Node) -> SpringArm3D:
	return root.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D

# --- the damping curve ------------------------------------------------------

# Toward a wall the retract rate is used, and only it.
func test_a_shorter_target_travels_at_the_retract_speed() -> void:
	var stepped := PILOT._camera_length_step(3.5, 1.0, STEP, 16.0, 3.0)
	approx(stepped, lerpf(3.5, 1.0, 16.0 * STEP), 0.0001,
		"pulling in does not use camera_retract_speed")

# Away from one, the return rate, and only it.
func test_a_longer_target_travels_at_the_return_speed() -> void:
	var stepped := PILOT._camera_length_step(1.0, 3.5, STEP, 16.0, 3.0)
	approx(stepped, lerpf(1.0, 3.5, 3.0 * STEP), 0.0001,
		"easing back out does not use camera_return_speed")

# The whole feature in one assertion: the same gap closes faster inward than outward. Ship
# these equal and the flicker comes back with every other line of this change still in place.
func test_pulling_in_is_faster_than_easing_out() -> void:
	var gap := 2.5
	var inward := 3.5 - PILOT._camera_length_step(3.5, 3.5 - gap, STEP, 16.0, 3.0)
	var outward := PILOT._camera_length_step(1.0, 1.0 + gap, STEP, 16.0, 3.0) - 1.0
	check(inward > outward * 2.0,
		"the camera does not pull in appreciably faster than it eases out (in %f, out %f)" % [inward, outward])

# A long frame - a hitch, a load, a breakpoint - must arrive at the target, not shoot past it.
func test_a_long_frame_does_not_overshoot() -> void:
	approx(PILOT._camera_length_step(3.5, 1.0, 1.0, 16.0, 3.0), 1.0, 0.0001,
		"a long frame overshoots the desired length instead of landing on it")
	approx(PILOT._camera_length_step(1.0, 3.5, 1.0, 16.0, 3.0), 3.5, 0.0001,
		"a long frame overshoots on the way back out")

func test_nothing_moves_when_the_target_is_already_met() -> void:
	approx(PILOT._camera_length_step(2.0, 2.0, STEP, 16.0, 3.0), 2.0, 0.0001,
		"the length drifts when there is nothing to travel to")

# The anti-flicker property, driven rather than argued: a hit that comes and goes on
# alternating frames settles IN, near the obstructed length, instead of oscillating across
# the whole gap. Half these frames ask for 3.5 and it still must not get near it.
func test_an_alternating_hit_settles_in_not_across_the_gap() -> void:
	var length := 3.5
	for i in 60:
		var desired := 1.0 if i % 2 == 0 else 3.5
		length = PILOT._camera_length_step(length, desired, STEP, 16.0, 3.0)
	check(length < 1.6,
		"a flickering hit leaves the camera swinging rather than settled in (%f)" % length)

# --- the wiring -------------------------------------------------------------

# The arm gets a shape at all. Bare, it casts a hairline ray, which is the corner poke.
func test_the_arm_sweeps_a_sphere_of_the_clearance_radius() -> void:
	var root := _scene()
	check(root != null, "pilot9.tscn did not instantiate")
	if root == null:
		return
	var sphere := _arm(root).shape as SphereShape3D
	check(sphere != null, "the SpringArm3D still has no shape - it is casting a bare ray")
	if sphere == null:
		return
	approx(sphere.radius, float(root.get("camera_clearance")), 0.0001,
		"the arm's backstop sphere is not camera_clearance wide")

# The load-bearing relationship between the two spheres. Equal radii is the failure that
# leaves everything else here passing and the pop still on screen.
func test_the_probe_is_fatter_than_the_backstop() -> void:
	var root := _scene()
	check(root != null, "pilot9.tscn did not instantiate")
	if root == null:
		return
	var probe := root.get("_camera_probe") as PhysicsShapeQueryParameters3D
	check(probe != null, "no probe query was built at _ready()")
	if probe == null:
		return
	var probe_sphere := probe.shape as SphereShape3D
	check(probe_sphere != null, "the probe does not cast a sphere")
	if probe_sphere == null:
		return
	approx(probe_sphere.radius,
		float(root.get("camera_clearance")) + float(root.get("camera_probe_lead")), 0.0001,
		"the probe is not camera_probe_lead fatter than the backstop")
	check(probe_sphere.radius > (_arm(root).shape as SphereShape3D).radius,
		"the probe is not fatter than the arm's own shape, so it can never trip first")

# He must be out of both casts. CameraPivot sits inside his own capsule, so a sphere that
# does not exclude him hits at zero travel on frame one and every frame after.
func test_pilot9_is_excluded_from_both_casts() -> void:
	var root := _scene()
	check(root != null, "pilot9.tscn did not instantiate")
	if root == null:
		return
	var body := root as CollisionObject3D
	var probe := root.get("_camera_probe") as PhysicsShapeQueryParameters3D
	check(probe != null and probe.exclude.has(body.get_rid()),
		"the probe would cast against pilot9's own capsule")
	# SpringArm3D exposes no reader for its exclusions; remove_excluded_object() answers
	# whether the RID was there, and this rig is thrown away in end() anyway.
	check(_arm(root).remove_excluded_object(body.get_rid()),
		"the SpringArm3D would collide with pilot9's own capsule")

# --- what walls must not do -------------------------------------------------

# The mesh reads the mode length, not the wall-aware one. Keying it off spring_length would
# blink his body out whenever a wall squeezed the camera under 30% of camera_distance.
func test_a_wall_does_not_make_pilot9_disappear() -> void:
	var root := _scene()
	check(root != null, "pilot9.tscn did not instantiate")
	if root == null:
		return
	var character := root.get("character") as Node3D
	check(character != null, "the rig has no character mesh")
	if character == null:
		return
	# Nulled so the step never reaches the physics server: this is about the two lengths, not
	# about the cast. _camera_obstruction_length() hands its argument straight back without it.
	root.set("_camera_probe", null)
	# Jammed against a wall: the mode still wants the full 3.5, the arm is down at 0.4.
	_arm(root).spring_length = 0.4
	root.call("_handle_camera_transition", STEP)
	check(character.visible, "a wall squeezing the camera in hid pilot9's body")

# First person is still first person - a zero-length arm has nothing to collide with, and the
# probe is skipped outright rather than asked about a zero-length motion.
func test_first_person_skips_the_probe() -> void:
	var root := _scene()
	check(root != null, "pilot9.tscn did not instantiate")
	if root == null:
		return
	approx(float(root.call("_camera_obstruction_length", 0.0)), 0.0, 0.0001,
		"a zero-length arm was still put through the probe")
