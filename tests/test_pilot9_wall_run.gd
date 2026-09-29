extends "res://tests/test_case.gd"

# Covers pilot9's wall-run. See docs/specs/pilot9-wall-run.md.
#
# The feel cannot be checked headlessly - the entry snap, the rise, the push protection, the
# wall coyote and the free launch off the end of a wall all need real collision and a running
# frame. What IS reachable, the same as tests/test_pilot9_dash.gd's split: the ability-tab
# seam, the exported numbers, the grid, the six gates, the corridor, the chain and the speed
# floor as pure functions - which is also exactly the list the spec's own "Tests" section asks
# for.

const CONTROLLER := preload("res://scripts/pilot9.gd")
const TAB_ABILITIES := preload("res://scripts/ui/tabs/tab_abilities.gd")
const PILOT_TSCN := "res://scenes/pilot9.tscn"

# _camera_wall_run_tangent() reads camera_pivot, an @onready reference CONTROLLER.new() never
# populates - nothing enters the tree, so _ready never runs. Rigged by hand, the same way
# tests/test_pilot9_turn_to_face.gd and tests/test_pilot9_slide.gd already do for the same var.
var _instances: Array[Node] = []

func _scene() -> Node:
	var ps := load(PILOT_TSCN) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate()
	_instances.append(n)
	n.camera_pivot = n.get_node("CameraPivot")
	return n

func end() -> void:
	for n in _instances:
		if is_instance_valid(n):
			n.free()
	_instances.clear()
	for w in _walls:
		if is_instance_valid(w):
			w.free()
	_walls.clear()
	for a in ["forward", "backward", "left", "right"]:
		Input.action_release(a)
	super()

# --- the ability-tab seam --------------------------------------------------------

func test_base_kit_row_names_a_real_property() -> void:
	var property := ""
	for entry: Array in TAB_ABILITIES.BASE_KIT:
		if entry[0] == "WALL-RUN":
			property = entry[1]
	check(property != "", "tab_abilities.gd's BASE_KIT has no 'WALL-RUN' row")
	if property == "":
		return
	var body: CharacterBody3D = CONTROLLER.new()
	var found := false
	for p in body.get_property_list():
		if String(p.name) == property:
			found = true
			break
	check(found, ("scripts/pilot9.gd has no '%s' property - the WALL-RUN row reads nothing " +
		"and renders LOCKED forever") % property)
	body.free()

func test_tech_no_longer_lists_wall_run_or_air_dash() -> void:
	for entry: Array in TAB_ABILITIES.TECH:
		check(entry[0] != "WALL-RUN",
			"WALL-RUN is built now - TECH must not still render it LOCKED under BASE_KIT's " +
			"own UNLOCKED row")
		check(entry[0] != "AIR DASH",
			"AIR DASH is built - the same lie WALL-RUN's removal was fixing, one feature " +
			"earlier")

# --- the numbers -----------------------------------------------------------------

func test_exported_knobs_have_the_spec_defaults() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	check(body.can_wall_run, "can_wall_run defaults to off")
	approx(body.wall_run_speed, 7.5, 0.0001, "wall_run_speed drifted off sprint")
	approx(body.wall_run_speed_ramp, 0.25, 0.0001, "wall_run_speed_ramp drifted")
	approx(body.wall_run_flat_time, 2.0, 0.0001, "wall_run_flat_time drifted off the grid")
	approx(body.wall_run_droop_time, 0.8, 0.0001, "wall_run_droop_time drifted off the tail")
	approx(body.wall_run_droop_gravity, 0.35, 0.0001, "wall_run_droop_gravity drifted")
	approx(body.wall_run_min_speed, 4.0, 0.0001, "wall_run_min_speed drifted")
	approx(body.wall_run_wall_angle, 15.0, 0.0001, "wall_run_wall_angle drifted")
	approx(body.wall_run_attach_angle, 60.0, 0.0001, "wall_run_attach_angle drifted")
	approx(body.wall_run_detach_angle, 45.0, 0.0001, "wall_run_detach_angle drifted")
	approx(body.wall_jump_kick, 8.5, 0.0001, "wall_jump_kick drifted off the 6 m corridor")
	approx(body.wall_jump_chain_decay, 0.5, 0.0001, "wall_jump_chain_decay drifted")
	approx(body.wall_jump_steer_back_ramp, 0.4, 0.0001, "wall_jump_steer_back_ramp drifted")
	approx(body.wall_jump_coyote_time, 0.15, 0.0001, "wall_jump_coyote_time drifted")
	approx(body.wall_run_pull_time, 0.1, 0.0001, "wall_run_pull_time drifted")
	approx(body.wall_run_follow_angle, 20.0, 0.0001, "wall_run_follow_angle drifted")
	body.free()

func test_the_per_flight_count_is_gone() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	for p in body.get_property_list():
		check(String(p.name) != "wall_runs_per_flight",
			"wall_runs_per_flight is deleted - the bound is on height now, not on walls. See " +
			"'The bound' in the spec")
	body.free()

# --- the grid ----------------------------------------------------------------------

func test_wall_run_distance_is_the_grid() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	approx(body.wall_run_distance(), 15.0, 0.0001,
		"every wall-run must cross exactly 15 m - wall_run_speed times wall_run_flat_time, " +
		"whatever he caught the wall at. See the spec's 'The grid'")
	body.free()

# --- the six gates, as one pure function --------------------------------------------

const ON: bool = true
const OFF: bool = false
const VERTICAL_WALL := Vector3(1.0, 0.0, 0.0)
const ALONG_WALL := Vector3(0.0, 0.0, 1.0)   # tangent to VERTICAL_WALL - a real wall-run
const INTO_WALL := Vector3(-1.0, 0.0, 0.0)   # head-on - must always be refused
const MIN_SPEED := 4.0
const WALL_ANGLE := 15.0
const ATTACH_ANGLE := 60.0

# Straight off a wall-jump from VERTICAL_WALL: 7.5 m/s along it, 8.5 m/s kicked away along
# its normal - ~41 degrees off that normal. Not constant expressions, so not consts.
var _off_a_wall_jump: Vector3 = Vector3(8.5, 0.0, 7.5).normalized()
# The 180: the same speeds, turned back toward the wall he left.
var _back_to_the_wall: Vector3 = Vector3(-8.5, 0.0, 7.5).normalized()

func test_gates_control_case_is_available() -> void:
	check(CONTROLLER._wall_run_gates(OFF, 5.0, VERTICAL_WALL, ALONG_WALL, OFF,
		MIN_SPEED, WALL_ANGLE, ATTACH_ANGLE),
		"the control case - airborne, a run, a vertical wall, travel along it, not moving " +
		"away, not dashing - must be available; the six refusals below are only meaningful " +
		"against this")

func test_gate_one_refuses_on_the_floor() -> void:
	check(not CONTROLLER._wall_run_gates(ON, 5.0, VERTICAL_WALL, ALONG_WALL, OFF,
		MIN_SPEED, WALL_ANGLE, ATTACH_ANGLE),
		"on the floor must refuse the wall-run outright - never off the floor")

func test_gate_two_refuses_a_drift() -> void:
	check(not CONTROLLER._wall_run_gates(OFF, 1.0, VERTICAL_WALL, ALONG_WALL, OFF,
		MIN_SPEED, WALL_ANGLE, ATTACH_ANGLE),
		"under wall_run_min_speed must refuse it - a wall-run is a run, not a drift")

func test_gate_three_refuses_a_shallow_face() -> void:
	# A face tipped 45 degrees off vertical - well past the 15 degree wall_run_wall_angle.
	var shallow := Vector3(0.7, 0.7, 0.0).normalized()
	check(not CONTROLLER._wall_run_gates(OFF, 5.0, shallow, ALONG_WALL, OFF,
		MIN_SPEED, WALL_ANGLE, ATTACH_ANGLE),
		"a face this far off vertical must refuse the wall-run")

func test_gate_four_refuses_hitting_the_wall_head_on() -> void:
	check(not CONTROLLER._wall_run_gates(OFF, 5.0, VERTICAL_WALL, INTO_WALL, OFF,
		MIN_SPEED, WALL_ANGLE, ATTACH_ANGLE),
		"hitting a wall head-on is a wall-hit, not a wall-run, and must be refused - the case " +
		"the spec calls out by name")

func test_gate_five_refuses_the_wall_just_jumped_off() -> void:
	# The regression that ate the wall-jump. Gate 4 on its own - the only angle test the first
	# build had - accepts this travel, so it would have welded him straight back on.
	var theta := rad_to_deg(acos(_off_a_wall_jump.dot(VERTICAL_WALL)))
	check(absf(theta - 90.0) <= ATTACH_ANGLE,
		"precondition: gate 4 alone must accept travel ~41 degrees off the normal, or this " +
		"test is not guarding the regression it is named for (theta %.1f)" % theta)
	check(not CONTROLLER._wall_run_gates(OFF, 11.3, VERTICAL_WALL, _off_a_wall_jump, OFF,
		MIN_SPEED, WALL_ANGLE, ATTACH_ANGLE),
		"travel moving away from the face he just wall-jumped off must be refused - otherwise " +
		"he re-grabs it the next frame and the wall-jump never happens")

func test_gate_five_is_not_a_lockout_the_180_still_attaches() -> void:
	check(CONTROLLER._wall_run_gates(OFF, 11.3, VERTICAL_WALL, _back_to_the_wall, OFF,
		MIN_SPEED, WALL_ANGLE, ATTACH_ANGLE),
		"turning back toward the wall he just left is moving toward it and must attach - the " +
		"deliberate 180")

func test_gate_six_refuses_mid_dash() -> void:
	check(not CONTROLLER._wall_run_gates(OFF, 5.0, VERTICAL_WALL, ALONG_WALL, ON,
		MIN_SPEED, WALL_ANGLE, ATTACH_ANGLE),
		"mid-dash must refuse the wall-run outright")

# --- the head-on path: gates 1, 2, 3 and 6, the angle test looks for dead-on instead -----

const HEAD_ON_ANGLE := 30.0
# Inside wall_run_attach_angle already - not a constant expression, so not a const like the
# others above.
var _near_along: Vector3 = Vector3(0.3, 0.0, 1.0).normalized()

func test_head_on_control_case_is_available() -> void:
	check(CONTROLLER._wall_run_head_on_gates(OFF, 5.0, VERTICAL_WALL, INTO_WALL, OFF,
		MIN_SPEED, WALL_ANGLE, HEAD_ON_ANGLE),
		"dead-on travel into a vertical wall, a run, not dashing, must be available through " +
		"the head-on path - this is the case the six gates refuse and the camera redirect " +
		"exists to catch")

func test_head_on_refuses_travel_the_ordinary_path_already_accepts() -> void:
	check(not CONTROLLER._wall_run_head_on_gates(OFF, 5.0, VERTICAL_WALL, _near_along, OFF,
		MIN_SPEED, WALL_ANGLE, HEAD_ON_ANGLE),
		"travel already inside wall_run_attach_angle must not also qualify through the " +
		"head-on path - the two gates are meant to cover disjoint bands of the same 90 degrees")

func test_head_on_refuses_on_the_floor() -> void:
	check(not CONTROLLER._wall_run_head_on_gates(ON, 5.0, VERTICAL_WALL, INTO_WALL, OFF,
		MIN_SPEED, WALL_ANGLE, HEAD_ON_ANGLE),
		"on the floor must refuse the head-on path too - never off the floor")

func test_head_on_refuses_a_drift() -> void:
	check(not CONTROLLER._wall_run_head_on_gates(OFF, 1.0, VERTICAL_WALL, INTO_WALL, OFF,
		MIN_SPEED, WALL_ANGLE, HEAD_ON_ANGLE),
		"under wall_run_min_speed must refuse the head-on path - a wall-run is a run")

func test_head_on_refuses_mid_dash() -> void:
	check(not CONTROLLER._wall_run_head_on_gates(OFF, 5.0, VERTICAL_WALL, INTO_WALL, ON,
		MIN_SPEED, WALL_ANGLE, HEAD_ON_ANGLE),
		"mid-dash must refuse the head-on path outright")

func test_head_on_refuses_a_shallow_face() -> void:
	var shallow := Vector3(0.7, 0.7, 0.0).normalized()
	check(not CONTROLLER._wall_run_head_on_gates(OFF, 5.0, shallow, INTO_WALL, OFF,
		MIN_SPEED, WALL_ANGLE, HEAD_ON_ANGLE),
		"a face this far off vertical must refuse the head-on path too")

# --- the camera-supplied tangent, standing in for a travel tangent that doesn't exist ----

func test_camera_tangent_lies_in_the_wall_plane() -> void:
	var body := _scene()
	# VERTICAL_WALL's normal is +X. At yaw 0 the camera pivot looks down -Z, already parallel
	# to the face, so the projection is exact: (0, 0, -1) with nothing pushed into or out of it.
	body.camera_pivot.rotation.y = 0.0
	var tangent: Vector3 = body._camera_wall_run_tangent(VERTICAL_WALL)
	check(tangent.length() > 0.0001, "a camera looking along the wall must give a non-zero " +
		"tangent")
	check(absf(tangent.x) < 0.0001, "the tangent must lie in the wall plane, not push into " +
		"or out of the face")

func test_camera_tangent_flips_with_the_camera() -> void:
	var body := _scene()
	body.camera_pivot.rotation.y = 0.0
	var one_way: Vector3 = body._camera_wall_run_tangent(VERTICAL_WALL)
	body.camera_pivot.rotation.y = PI
	var other_way: Vector3 = body._camera_wall_run_tangent(VERTICAL_WALL)
	check(one_way.dot(other_way) < 0.0, "looking the other way along the wall must send him " +
		"the other way - that is the whole point of letting the camera choose")

func test_camera_tangent_is_zero_looking_dead_into_the_wall() -> void:
	var body := _scene()
	# Yaw 90 degrees: the camera's forward formula gives (-1, 0, 0), exactly anti-parallel to
	# VERTICAL_WALL's +X normal - the one case with no redirect to give.
	body.camera_pivot.rotation.y = deg_to_rad(90.0)
	var tangent: Vector3 = body._camera_wall_run_tangent(VERTICAL_WALL)
	check(tangent.length() <= 0.0001, "a camera looking dead into the wall must give no " +
		"tangent - there is nothing to redirect")

# --- the corridor: one wall-jump crosses 6 m by the apex ----------------------------

# His capsule and the 0.8 m probe take ~1 m off the gap - see "Why 8.5" in the spec.
const CORRIDOR := 6.0
const CAPSULE_AND_PROBE := 1.0

func test_a_wall_jump_crosses_the_corridor_by_the_apex() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	var crossed: float = body.wall_jump_kick * body.jump_time_to_apex
	check(crossed >= CORRIDOR - CAPSULE_AND_PROBE - 0.0001,
		("a wall-jump must cover the %.0f m corridor (less %.0f m of capsule and probe) by the " +
		"apex, so the far wall is caught rising - it covers %.2f m") %
		[CORRIDOR, CAPSULE_AND_PROBE, crossed])
	body.free()

func test_the_far_wall_is_caught_on_arrival() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	# Arriving at the opposite wall of the corridor, whose normal faces back at him.
	var arrival := Vector3(body.wall_jump_kick, 0.0, body.wall_run_speed)
	check(CONTROLLER._wall_run_gates(OFF, arrival.length(), -VERTICAL_WALL,
		arrival.normalized(), OFF, body.wall_run_min_speed, body.wall_run_wall_angle,
		body.wall_run_attach_angle),
		"the wall-jump's own arrival angle (~49 degrees off the far face) must pass the gates, " +
		"or the corridor is a promise the attach breaks")
	body.free()

# --- the chain: height halves per link, and the whole series is the +6 m ceiling ----

func test_chain_heights_halve() -> void:
	approx(CONTROLLER.wall_jump_height_for(0, 3.0, 0.5), 3.0, 0.0001, "first wall-jump is 3 m")
	approx(CONTROLLER.wall_jump_height_for(1, 3.0, 0.5), 1.5, 0.0001, "second is 1.5 m")
	approx(CONTROLLER.wall_jump_height_for(2, 3.0, 0.5), 0.75, 0.0001, "third is 0.75 m")

func test_chain_launch_speed_matches_the_height() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	for n in 4:
		var v: float = CONTROLLER.wall_jump_velocity_for(n, body.jump_velocity,
			body.wall_jump_chain_decay)
		var height: float = v * v / (2.0 * body.jump_gravity)
		approx(height, CONTROLLER.wall_jump_height_for(n, body.jump_height,
			body.wall_jump_chain_decay), 0.001,
			"wall-jump %d's launch speed does not reach the height the chain promises" % n)
	body.free()

func test_the_chain_ceiling_protects_the_maps() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	var ceiling: float = CONTROLLER.wall_jump_chain_ceiling(body.jump_height,
		body.wall_jump_chain_decay)
	approx(ceiling, 6.0, 0.0001,
		"wall-run must contribute at most +6 m of vertical per flight - the number maps get " +
		"authored against. A wall_jump_chain_decay of 1.0 makes every corridor an elevator")
	var total := 0.0
	for n in 20:
		total += CONTROLLER.wall_jump_height_for(n, body.jump_height, body.wall_jump_chain_decay)
	check(total <= ceiling + 0.0001,
		"twenty chained wall-jumps climbed %.3f m, over the %.1f m ceiling" % [total, ceiling])
	body.free()

# --- the speed floor ------------------------------------------------------------------

func test_a_slow_entry_ramps_to_wall_run_speed() -> void:
	approx(CONTROLLER._wall_run_speed_at(4.5, 7.5, 0.25, 0.0), 4.5, 0.0001,
		"the ramp must start from the entry speed, not snap")
	approx(CONTROLLER._wall_run_speed_at(4.5, 7.5, 0.25, 0.125), 6.0, 0.0001,
		"halfway through the ramp must be halfway to wall_run_speed")
	approx(CONTROLLER._wall_run_speed_at(4.5, 7.5, 0.25, 1.0), 7.5, 0.0001,
		"past the ramp a slow catch must run at wall_run_speed - the grid is one number")

func test_a_fast_entry_is_held_not_added_to() -> void:
	approx(CONTROLLER._wall_run_speed_at(9.0, 7.5, 0.25, 1.0), 9.0, 0.0001,
		"an entry over wall_run_speed is held - the floor lifts, it never slows or adds")

func test_the_into_wall_part_of_an_arrival_is_dropped() -> void:
	# Off a wall-jump: 7.5 m/s along the corridor, 8.5 m/s into the new face.
	var arrival := Vector3(-8.5, 0.0, 7.5)
	approx(CONTROLLER._along_wall_speed(arrival, ALONG_WALL), 7.5, 0.0001,
		"only the along-wall part of an arrival may carry into the run - 11.3 m/s would make " +
		"every chain snowball")

# --- air control after a wall-jump --------------------------------------------------

func test_the_push_survives_until_pulled_against() -> void:
	approx(CONTROLLER._wall_jump_steer_authority(0.0, 0.4), 0.0, 0.0001,
		"not pulling back, the stick must own none of the kick")
	approx(CONTROLLER._wall_jump_steer_authority(0.2, 0.4), 0.5, 0.0001,
		"halfway through the steer-back ramp the stick owns half of it")
	approx(CONTROLLER._wall_jump_steer_authority(1.0, 0.4), 1.0, 0.0001,
		"past the ramp the stick owns all of it - the deliberate 180")

# --- the let-go lockout -----------------------------------------------------------------

func test_same_wall_matches_the_plane_not_the_hit_point() -> void:
	var p := Vector3(2.0, 1.0, 0.0)
	check(CONTROLLER._same_wall(VERTICAL_WALL, p, VERTICAL_WALL, p + Vector3(0, 0.5, 9.0)),
		"a hit further along the same face must read as the same wall")
	check(not CONTROLLER._same_wall(VERTICAL_WALL, p, -VERTICAL_WALL, p + Vector3(-6, 0, 0)),
		"the opposite wall of a corridor must not read as the same wall")
	check(not CONTROLLER._same_wall(VERTICAL_WALL, p, VERTICAL_WALL, p + Vector3(3, 0, 0)),
		"a parallel face 3 m out must not read as the same wall")
	check(not CONTROLLER._same_wall(Vector3.ZERO, p, VERTICAL_WALL, p),
		"no lockout stored must lock nothing")

# --- can_wall_run = false --------------------------------------------------------------
#
# Not one of the six gates itself - _wall_run_gates() has no can_wall_run parameter, the same
# way _dash_availability() takes can_dash but the mantle's six gates take no can_climb. It is
# checked at the call site, in _handle_wall_run(), ahead of ever probing for a wall.

func test_can_wall_run_false_is_checked_before_any_probe() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	body.can_wall_run = false
	# frozen or is_climbing or is_dashing or is_on_floor() or not can_wall_run - can_wall_run
	# is the one of those five refusals reachable with no physics world at all.
	check(not body.can_wall_run, "can_wall_run did not read back false")
	body.free()

# --- the sprint cycle on the wall, leaned off it (2026-09-26) --------------------------

func test_wall_side_reads_from_travel_not_facing() -> void:
	# Travelling +Z, his left is +X. A wall at +X has its normal pointing -X, and vice versa.
	check(not CONTROLLER._wall_on_right_of(Vector3(-1, 0, 0), Vector3(0, 0, 1)),
		"a wall on his left (at +X, travelling +Z) read as a right wall")
	check(CONTROLLER._wall_on_right_of(Vector3(1, 0, 0), Vector3(0, 0, 1)),
		"a wall on his right (at -X, travelling +Z) read as a left wall")
	check(not CONTROLLER._wall_on_right_of(Vector3(1, 0, 0), Vector3(0, 0, -1)),
		"reversing along the same wall must swap its side")

func test_neither_wall_mirrors_the_rig() -> void:
	var n := _scene()
	if n == null:
		fail("could not load " + PILOT_TSCN)
		return
	var armature: Node3D = n.get_node("character/Armature")
	n._start_wall_run(Vector3(-1, 0, 0), Vector3(0, 0, 1))
	check(not n.wall_run_on_right(), "a left wall latched as right")
	approx(armature.scale.x, 1.0, 0.0001, "a left-wall run mirrored the rig - the sprint cycle has no side")
	n._end_wall_run()
	n._start_wall_run(Vector3(1, 0, 0), Vector3(0, 0, 1))
	approx(armature.scale.x, 1.0, 0.0001, "a right-wall run mirrored the rig")

func test_wall_run_state_plays_the_sprint_cycle() -> void:
	var n := _scene()
	if n == null:
		fail("could not load " + PILOT_TSCN)
		return
	var at := n.get_node_or_null("AnimationTree") as AnimationTree
	var sm := at.tree_root as AnimationNodeStateMachine if at else null
	if sm == null or not sm.has_node(&"wall_run"):
		fail("no `wall_run` state in the AnimationTree")
		return
	var clip := sm.get_node(&"wall_run") as AnimationNodeAnimation
	check(clip != null and clip.animation == &"sprint_forward",
		"the `wall_run` state plays '%s', not the ground sprint cycle" % (clip.animation if clip else &"?"))

func test_wall_run_lean_default() -> void:
	var body: CharacterBody3D = CONTROLLER.new()
	approx(body.wall_run_lean, 30.0, 0.0001, "wall_run_lean drifted")
	body.free()

func test_lean_puts_his_head_away_from_the_wall_on_both_sides() -> void:
	# Built the way the mesh is: yaw welded along the run, roll on rotation.z, Euler YXZ. The
	# roll axis is the travel axis, so the mesh's own 180 degree basis cannot flip this.
	for travel: Vector3 in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0)]:
		for side: float in [1.0, -1.0]:
			var normal: Vector3 = travel.cross(Vector3.UP).normalized() * side
			var yaw := atan2(travel.x, travel.z)
			var roll := CONTROLLER._wall_run_roll_angles(yaw, normal, 30.0).y
			var up := Basis.from_euler(Vector3(0.0, yaw, roll)) * Vector3.UP
			approx(rad_to_deg(up.angle_to(Vector3.UP)), 30.0, 0.01,
				"lean is not 30 degrees (travel %s, normal %s)" % [travel, normal])
			check(up.dot(normal) > 0.0,
				"head leans INTO the wall (travel %s, normal %s)" % [travel, normal])

# --- mantle vs wall-run (see "Mantle vs wall-run" in the spec) ----------------------

const _SRC_PATH := "res://scripts/pilot9.gd"

func _src_body(header: String) -> String:
	var f := FileAccess.open(_SRC_PATH, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	var start := text.find(header)
	if start < 0:
		return ""
	var rest := text.substr(start + header.length())
	var stop := rest.find("\nfunc ")
	return rest if stop < 0 else rest.substr(0, stop)

func test_steering_into_the_wall_is_the_mantle_intent() -> void:
	# Wall at -X (normal +X). Straight into it is -X.
	var n := Vector3(1, 0, 0)
	check(CONTROLLER._steers_into_wall(Vector3(-1, 0, 0), n, 45.0),
		"the stick dead into the wall did not read as steering in")
	check(CONTROLLER._steers_into_wall(Vector3(-1, 0, 0.5).normalized(), n, 45.0),
		"the stick ~27 degrees off dead-in did not read as steering in")

func test_running_along_or_away_is_not_the_mantle_intent() -> void:
	var n := Vector3(1, 0, 0)
	check(not CONTROLLER._steers_into_wall(Vector3(0, 0, 1), n, 45.0),
		"the stick along the wall read as steering in - a run on a low wall would mantle again")
	check(not CONTROLLER._steers_into_wall(Vector3(-0.5, 0, 1).normalized(), n, 45.0),
		"a stick nudged 27 degrees in read as steering in - that is still a run, inside the " +
		"stick-detach cone")
	check(not CONTROLLER._steers_into_wall(Vector3(1, 0, 0), n, 45.0),
		"the stick away from the wall read as steering in")
	check(not CONTROLLER._steers_into_wall(Vector3.ZERO, n, 45.0),
		"a centred stick read as steering in")

func test_the_mantle_is_decided_before_the_wall_run_attach() -> void:
	var body := _src_body("func _physics_process(delta: float) -> void:")
	var mantle := body.find("_handle_mantle_trigger()")
	var wall := body.find("_handle_wall_run(delta)")
	check(mantle >= 0 and wall >= 0 and mantle < wall,
		"_handle_mantle_trigger() does not run ahead of _handle_wall_run() - a reachable ledge " +
		"would be grabbed as a one-frame wall-run first")

func test_a_run_never_mantles_by_proximity_alone() -> void:
	var body := _src_body("func _handle_gravity_and_jump(delta: float) -> void:")
	check(not body.contains("_try_start_climb"),
		"_handle_gravity_and_jump() probes for a mantle again - during a run that is the " +
		"automatic run-top grab the 2026-09-23 fix removed")
	var off_run := _src_body("func _try_mantle_off_wall_run() -> bool:")
	check(off_run.contains("_steers_into_wall("),
		"the run-top mantle no longer asks for the stick into the wall")
	check(off_run.contains("_wall_run_direction"),
		"the ahead probe during a run is no longer aimed along the run")

func test_steering_in_during_the_rise_holds_the_run_for_the_mantle() -> void:
	# Letting go on the rise un-mirrored the rig and swung the mesh for the frames before the
	# airborne mantle caught the same lip - the tilt before the mantle. Since "Committed to the
	# wall" no stick direction lets go at all, so the run must not read the stick.
	var run := _src_body("func _handle_wall_run(delta: float) -> void:")
	check(not run.contains("_wall_run_stick()") and not run.contains("\"crouch\""),
		"the stick or crouch can let go of the wall again")
	var turn := _src_body("func _handle_character_rotation(delta: float) -> void:")
	check(turn.contains("elif is_wall_running:")
			and turn.contains("atan2(_wall_run_direction.x, _wall_run_direction.z)"),
		"the mesh turns into the wall while reaching for the top of a run")

func test_the_mesh_is_welded_parallel_to_the_wall_for_the_whole_run() -> void:
	# The stick is camera-relative, so turning toward it let a camera nudge swing him off the
	# face. The weld has to sit ahead of the no-input early return, or a centred stick would
	# leave him wherever he was facing at attach.
	var turn := _src_body("func _handle_character_rotation(delta: float) -> void:")
	var weld := turn.find("elif is_wall_running:")
	var no_input := turn.find("elif input_dir == Vector2.ZERO:")
	check(weld != -1 and no_input != -1 and weld < no_input,
		"the wall-run weld is missing or sits behind the no-input early return")

func test_only_the_head_on_attach_refuses_where_a_mantle_could_take_the_top() -> void:
	# Head-on at a reachable lip is a mantle, so that attach still asks the mantle's own probe.
	# Alongside a wall he is not facing it, the mantle would not fire, and the refusal was a
	# dead zone - see "Staying on the wall" (1) in the spec.
	var handle := _src_body("func _handle_wall_run(delta: float) -> void:")
	check(handle.count("_wall_top_in_mantle_reach(") == 1,
		"the top-of-wall check must be on exactly one attach path, the head-on one")
	var top := handle.find("_wall_top_in_mantle_reach(")
	var ahead := handle.find("_probe_wall_ahead(travel)")
	check(ahead != -1 and top > ahead,
		"the top-of-wall check is on the sideways attach again - the dead zone on short walls")
	var gate := _src_body("func _wall_top_in_mantle_reach(wall_normal: Vector3) -> bool:")
	check(gate.contains("_probe_ledge(") and gate.contains("wall_run_probe_reach"),
		"the top-of-wall check is not the mantle's own probe at the run-top reach")


# --- staying on the wall (see "Staying on the wall, 2026-09-24" in the spec) -----------

# One shared in-tree pilot, for tests/test_pilot9_rail_grind.gd's reason: a fresh in-tree
# pilot per test leaks server RIDs a --script run never cleans up. Far from everything else a
# run leaves in the tree, and not where the rail tests put theirs.
const WALL_FAR := Vector3(-500.0, 50.0, 500.0)
const DT := 1.0 / 60.0
var _pilot: Node = null
var _walls: Array[Node] = []

func _live_pilot() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		_pilot = ps.instantiate()
		(Engine.get_main_loop() as SceneTree).root.add_child(_pilot)
	_pilot._end_wall_run()
	_pilot.frozen = false
	_pilot.is_dashing = false
	_pilot.is_climbing = false
	_pilot.can_wall_run = true
	_pilot._wall_lockout_normal = Vector3.ZERO
	_pilot._wall_lockout_left = 0.0
	_pilot.velocity = Vector3.ZERO
	return _pilot

# A box wall, `size` metres, its transform in WALL_FAR's frame.
func _wall(size: Vector3, xform: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.transform = Transform3D(xform.basis, xform.origin + WALL_FAR)
	(Engine.get_main_loop() as SceneTree).root.add_child(body)
	_walls.append(body)
	return body

# The run's own two calls a physics frame makes, then moves him by his velocity - no
# collision, which is the point: the pull, not the capsule, has to hold him on the face. Air
# frames (off the wall) keep his velocity and let _handle_wall_run() try to re-attach.
func _step(p: Node) -> void:
	p._handle_wall_run(DT)
	if p.is_wall_running:
		p._apply_wall_run_velocity(DT)
	p.global_position += p.velocity * DT

func test_the_stick_is_read_in_the_runs_frame_not_the_cameras() -> void:
	var p := _live_pilot()
	p._wall_run_direction = Vector3(0, 0, -1)
	Input.action_press("forward")
	for yaw in [0.0, PI / 2.0, PI]:
		p.camera_pivot.rotation.y = yaw
		var stick: Vector3 = p._wall_run_stick()
		check(stick.is_equal_approx(Vector3(0, 0, -1)),
			"forward with the camera at %.0f degrees read %s, not along the run" % [
				rad_to_deg(yaw), stick])
	Input.action_release("forward")
	p.camera_pivot.rotation.y = 0.0

func test_run_frame_stick_steers_in_lets_go_and_holds() -> void:
	# Running -Z, wall on his right (+X), so the face's normal points -X.
	var run := Vector3(0, 0, -1)
	var n := Vector3(-1, 0, 0)
	var into: Vector3 = CONTROLLER._run_frame_stick(Vector2(1, 0), run)
	check(CONTROLLER._steers_into_wall(into, n, 45.0), "strafe toward the wall is not steering in")
	var away: Vector3 = CONTROLLER._run_frame_stick(Vector2(-1, 0), run)
	var theta := rad_to_deg(acos(clampf(away.dot(n), -1.0, 1.0)))
	check(absf(theta - 90.0) > 45.0 and not CONTROLLER._steers_into_wall(away, n, 45.0),
		"strafe toward open space does not land in the let-go cone")
	for raw in [Vector2(0, -1), Vector2(0, 1), Vector2(0.5, -1).normalized()]:
		var s: Vector3 = CONTROLLER._run_frame_stick(raw, run)
		var t := rad_to_deg(acos(clampf(s.dot(n), -1.0, 1.0)))
		check(absf(t - 90.0) <= 45.0, "stick %s would let go - it should hold the run" % raw)
	check(CONTROLLER._run_frame_stick(Vector2.ZERO, run) == Vector3.ZERO, "centred is nothing")

func test_the_pull_closes_the_gap_across_the_run() -> void:
	approx(CONTROLLER._wall_run_pull_speed(0.39, 0.39, 0.1), 0.0, 0.0001, "pulls at the hold")
	check(CONTROLLER._wall_run_pull_speed(0.8, 0.39, 0.1) > 0.0, "does not pull toward the face")
	check(CONTROLLER._wall_run_pull_speed(0.2, 0.39, 0.1) < 0.0, "does not ease off a close face")
	var p := _live_pilot()
	p._start_wall_run(Vector3(-1, 0, 0), Vector3(0, 0, -1))
	p._wall_run_gap = 0.8
	p._wall_run_time = 1.0
	p._apply_wall_run_velocity(DT)
	approx(p.velocity.z, -p.wall_run_speed, 0.001, "the pull leaked into the run's speed")
	check(p.velocity.x > 0.0, "the pull is not toward the wall")
	p._end_wall_run()

func test_the_run_follows_a_seam_not_a_corner() -> void:
	var n := Vector3(-1, 0, 0)
	check(CONTROLLER._wall_follows(n, n.rotated(Vector3.UP, deg_to_rad(10.0)), 20.0),
		"a 10 degree seam is not followed")
	check(not CONTROLLER._wall_follows(n, n.rotated(Vector3.UP, deg_to_rad(30.0)), 20.0),
		"a 30 degree turn is followed - that is a different wall")

func test_lockout_by_cause() -> void:
	check(is_inf(CONTROLLER._wall_lockout_time_for(CONTROLLER.WallLetGo.TIMER)),
		"the timer does not lock until the ground")
	approx(CONTROLLER._wall_lockout_time_for(CONTROLLER.WallLetGo.WALL_ENDED), 0.0,
		0.0001, "a wall that ended locks something")
	var p := _live_pilot()
	p._start_wall_run(Vector3(-1, 0, 0), Vector3(0, 0, -1), WALL_FAR)
	p._let_go_of_wall(CONTROLLER.WallLetGo.TIMER)
	p._tick_wall_lockout(10.0)
	check(p._wall_lockout_normal != Vector3.ZERO, "the timer lockout wore off in the air")
	p._wall_lockout_normal = Vector3.ZERO
	p._start_wall_run(Vector3(-1, 0, 0), Vector3(0, 0, -1), WALL_FAR)
	p._let_go_of_wall(CONTROLLER.WallLetGo.WALL_ENDED)
	check(p._wall_lockout_normal == Vector3.ZERO, "a wall that ended locked itself out")

# "Committed to the wall": the stick pointed straight off the face, and crouch, both hold the run.
func test_only_jump_the_wall_ending_or_the_clock_lets_go() -> void:
	var p := _live_pilot()
	_wall(Vector3(1, 6, 30), Transform3D(Basis(), Vector3(1.5, 3, -14)))
	_start_beside(p, 0.7, -0.5, 1.0)
	check(p.is_wall_running, "never attached to the test wall")
	p._wall_run_leveled = true
	Input.action_press("left")      # away from a wall on his right
	for i in 10:
		_step(p)
	check(p.is_wall_running, "stick away from the wall let go of it")
	Input.action_release("left")
	Input.action_press("crouch")
	_step(p)
	check(p.is_wall_running, "crouch let go of the wall")
	Input.action_release("crouch")
	Input.action_press("jump")
	_step(p)
	check(not p.is_wall_running and p._wall_jump_buffered, "jump did not take him off the wall")
	Input.action_release("jump")
	p._wall_jump_buffered = false

# Faces at x = 1 in WALL_FAR's frame, normal -X; he runs -Z with the wall on his right.
func _start_beside(p: Node, x: float, z: float, feet_y: float) -> void:
	p.global_position = WALL_FAR + Vector3(x, feet_y, z)
	p.velocity = Vector3(0, 0, -7.5)
	p._handle_wall_run(DT)

func test_a_doorway_is_run_past_and_the_far_panel_regrabbed() -> void:
	var p := _live_pilot()
	_wall(Vector3(1, 6, 8), Transform3D(Basis(), Vector3(1.5, 3, -4)))       # z 0 .. -8
	_wall(Vector3(1, 6, 10), Transform3D(Basis(), Vector3(1.5, 3, -14.5)))   # z -9.5 .. -19.5
	_start_beside(p, 0.7, -0.5, 1.0)
	check(p.is_wall_running, "did not attach to the first panel")
	var left_first := false
	for i in 150:
		_step(p)
		if not p.is_wall_running:
			left_first = true
		if p.global_position.z < WALL_FAR.z - 12.0:
			break
	check(left_first, "never left the first panel across the doorway")
	check(p.is_wall_running, "did not re-grab the second panel past the doorway")

func test_a_ten_degree_bend_is_one_run() -> void:
	var p := _live_pilot()
	_wall(Vector3(1, 6, 8), Transform3D(Basis(), Vector3(1.5, 3, -4)))
	# Turning 10 degrees away from him at z = -8, overlapping back 0.3 m so there is no crack.
	var b := Basis(Vector3.UP, deg_to_rad(-10.0))
	var dir := b * Vector3(0, 0, -1)
	var into := b * Vector3(1, 0, 0)
	_wall(Vector3(1, 6, 10), Transform3D(b, Vector3(1, 3, -8) + dir * 4.7 + into * 0.5))
	_start_beside(p, 0.7, -0.5, 1.0)
	check(p.is_wall_running, "did not attach")
	var dropped := false
	for i in 110:
		_step(p)
		if not p.is_wall_running:
			dropped = true
			break
	check(not dropped, "dropped at the bend, %.2f m along" % (WALL_FAR.z - p.global_position.z))
	check(p._wall_normal.angle_to(b * Vector3(-1, 0, 0)) < deg_to_rad(2.0),
		"did not take the bent face's normal")
	var gap: float = p._wall_run_gap
	approx(gap, p._wall_run_hold_distance(), 0.05, "not held at the hold distance after the bend")

func test_a_three_metre_wall_caught_rising_runs_along_its_top() -> void:
	var p := _live_pilot()
	_wall(Vector3(1, 3, 20), Transform3D(Basis(), Vector3(1.5, 1.5, -10)))   # top at 3 m
	p.global_position = WALL_FAR + Vector3(0.7, 1.2, -0.5)
	p.velocity = Vector3(0, 6.0, -7.5)
	p._handle_wall_run(DT)
	check(p.is_wall_running, "a 3 m wall alongside refused the attach - the dead zone")
	var dropped := false
	for i in 60:
		_step(p)
		if not p.is_wall_running:
			dropped = true
			break
	check(not dropped, "rose off the top of the wall and dropped, feet at %.2f" %
		(p.global_position.y - WALL_FAR.y))
	check(p._wall_run_leveled, "never levelled at the top")
	check(p.global_position.y - WALL_FAR.y < 3.0 - CONTROLLER.WALL_RUN_LOW_PROBE_HEIGHT + 0.3,
		"rose past where the low ray still sees the face")
