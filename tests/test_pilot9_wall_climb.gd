extends "res://tests/test_case.gd"

# Covers pilot9's wall climb. See docs/specs/pilot9-wall-climb.md.
#
# The pure half - the gates, the angle split against the wall-run's two attaches, the speed that
# makes the height, the stall, the cooldown - is asserted directly. The live half uses real
# collider walls and steps the climb's own calls the way tests/test_pilot9_wall_run.gd steps a
# run: velocity integrated by hand, no move_and_slide(), so the pull has to hold him on the face.
# The full-physics climbs (ground entry, chimney, real capsule) are tests/_probe_wall_climb.gd.

const CONTROLLER := preload("res://scripts/pilot9.gd")
const TAB_ABILITIES := preload("res://scripts/ui/tabs/tab_abilities.gd")
const ITEM_HOLDER := preload("res://scripts/items/item_holder.gd")
const ANIM := preload("res://scripts/pilot9_animation.gd")
const PILOT_TSCN := "res://scenes/pilot9.tscn"

const FAR := Vector3(700.0, 80.0, -700.0)
const DT := 1.0 / 60.0

var _pilot: Node = null
var _walls: Array[Node] = []

func end() -> void:
	for w in _walls:
		if is_instance_valid(w):
			w.free()
	_walls.clear()
	super()

# One shared in-tree pilot, for the wall-run tests' reason (a fresh one per test leaks RIDs).
func _live_pilot() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		_pilot = ps.instantiate()
		(Engine.get_main_loop() as SceneTree).root.add_child(_pilot)
	_pilot._end_wall_climb()
	_pilot._end_wall_run()
	_pilot.frozen = false
	_pilot.is_dashing = false
	_pilot.is_climbing = false
	_pilot.can_wall_climb = true
	_pilot.can_wall_run = true
	_pilot.can_climb = true
	_pilot._wall_climb_lock_left = 0.0
	_pilot._wall_climb_lock_normal = Vector3.ZERO
	_pilot._wall_climb_coyote_left = 0.0
	_pilot._wall_climb_jump_buffered = false
	_pilot._wall_lockout_normal = Vector3.ZERO
	_pilot._wall_lockout_left = 0.0
	_pilot.velocity = Vector3.ZERO
	return _pilot

# A box wall, `size` metres, centred at `centre` in FAR's frame.
func _wall(size: Vector3, centre: Vector3, basis: Basis = Basis()) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.transform = Transform3D(basis, centre + FAR)
	(Engine.get_main_loop() as SceneTree).root.add_child(body)
	_walls.append(body)

# The climb's own calls a physics frame makes, in _physics_process()'s order, then his velocity.
func _step(p: Node) -> void:
	p._handle_mantle_trigger()
	p._handle_wall_climb(DT)
	p._handle_wall_run(DT)
	if p.is_wall_climbing:
		p._apply_wall_climb_velocity(DT)
	elif p.is_wall_running:
		p._apply_wall_run_velocity(DT)
	p.global_position += p.velocity * DT

# A tall face at z = -2 in FAR's frame, normal +Z. He stands 0.6 m in front of it - inside the
# 0.8 m probe from his centre.
func _tall_wall() -> void:
	_wall(Vector3(8, 20, 1), Vector3(0, 10, -2.5))

# --- the seams --------------------------------------------------------------------

func test_base_kit_row_names_a_real_property() -> void:
	var property := ""
	for entry: Array in TAB_ABILITIES.BASE_KIT:
		if entry[0] == "WALL-CLIMB":
			property = entry[1]
	check(property == "can_wall_climb", "tab_abilities.gd's BASE_KIT has no WALL-CLIMB row")
	var body: CharacterBody3D = CONTROLLER.new()
	check("can_wall_climb" in body, "scripts/pilot9.gd has no can_wall_climb")
	body.free()

func test_exported_knobs_have_the_spec_defaults() -> void:
	var b: CharacterBody3D = CONTROLLER.new()
	approx(b.wall_climb_angle, 15.0, 0.0001, "wall_climb_angle")
	approx(b.wall_climb_height, 4.0, 0.0001, "wall_climb_height")
	approx(b.wall_climb_rise_time, 0.8, 0.0001, "wall_climb_rise_time")
	approx(b.wall_climb_stall_time, 0.25, 0.0001, "wall_climb_stall_time")
	approx(b.wall_climb_peel_speed, 1.0, 0.0001, "wall_climb_peel_speed")
	approx(b.wall_climb_same_wall_cooldown, 1.0, 0.0001, "wall_climb_same_wall_cooldown")
	approx(b.wall_climb_anim_speed, 2.5, 0.0001, "wall_climb_anim_speed")
	check(b.can_wall_climb, "can_wall_climb defaults off")
	b.free()

func test_the_tree_has_the_state_the_driver_writes() -> void:
	var p: Node = (load(PILOT_TSCN) as PackedScene).instantiate()
	var at := p.get_node("AnimationTree") as AnimationTree
	var sm := at.tree_root as AnimationNodeStateMachine
	check(sm.has_node(&"wall_climb"), "pilot9.tscn has no wall_climb state - rerun the builder")
	if sm.has_node(&"wall_climb"):
		var bt := sm.get_node(&"wall_climb") as AnimationNodeBlendTree
		check(bt != null and bt.has_node(&"WallClimbScale"),
			"the wall_climb state has no WallClimbScale for pilot9_animation.gd to drive")
		check(ANIM.WALL_CLIMB_SCALE == "parameters/wall_climb/WallClimbScale/scale",
			"pilot9_animation.gd writes a path the builder does not build")
		for to in [&"jump", &"fall"]:
			check(sm.has_transition(&"wall_climb", to), "no wall_climb -> %s exit" % to)
		for from in [&"Locomotion", &"jump", &"fall", &"wall_run"]:
			check(sm.has_transition(from, &"wall_climb"), "no %s -> wall_climb entry" % from)
	check(not (p.wall_climb_grab_phases as PackedFloat32Array).is_empty(),
		"no grab phases baked - rerun the builder")
	check(p.wall_climb_duration > 0.0, "no clip length baked")
	p.free()

func test_hands_are_blocked_on_the_wall() -> void:
	check(not ITEM_HOLDER.arm_override_for(&"wall_climb"), "the staff hold pose runs on a climb")
	for path in ["res://scripts/items/equip_anim.gd", "res://scripts/items/reflect_spin.gd"]:
		var src := FileAccess.get_file_as_string(path)
		var at := src.find("func _blocked_by_state()")
		check(at != -1 and src.find("is_wall_climbing", at) != -1 \
			and src.find("is_wall_climbing", at) < src.find("\nfunc ", at + 1),
			"%s does not block on a wall climb" % path.get_file())

# --- the numbers ------------------------------------------------------------------

func test_rise_and_stall_come_to_exactly_the_height() -> void:
	var v := CONTROLLER.wall_climb_speed_for(4.0, 0.8, 0.25)
	approx(v, 4.0 / 0.925, 0.0001, "climb speed")
	var h := 0.0
	var steps := 10000
	var dt := 1.05 / float(steps)
	for i in steps:
		h += v * CONTROLLER.wall_climb_speed_fraction_at((float(i) + 0.5) * dt, 0.8, 0.25) * dt
	approx(h, 4.0, 0.001, "rise + stall height")

func test_the_stall_eases_to_a_stop() -> void:
	approx(CONTROLLER.wall_climb_speed_fraction_at(0.5, 0.8, 0.25), 1.0, 0.0001, "mid-rise")
	approx(CONTROLLER.wall_climb_speed_fraction_at(0.925, 0.8, 0.25), 0.5, 0.0001, "mid-stall")
	approx(CONTROLLER.wall_climb_speed_fraction_at(1.05, 0.8, 0.25), 0.0, 0.0001, "end of stall")

# --- the gates --------------------------------------------------------------------

const N := Vector3(0, 0, 1)   # the face's normal; dead-on travel is -Z

func _travel(deg_off_dead_on: float) -> Vector3:
	return Basis(Vector3.UP, deg_to_rad(deg_off_dead_on)) * Vector3(0, 0, -1)

func test_gates_take_dead_on_and_the_cone() -> void:
	for deg in [0.0, 10.0, 15.0, -15.0]:
		check(CONTROLLER._wall_climb_gates(7.5, N, _travel(deg), false, 4.0, 15.0, 15.0),
			"%.0f degrees off dead-on did not climb" % deg)

func test_gates_refuse_outside_the_cone() -> void:
	for deg in [16.0, 30.0, 60.0, -20.0]:
		check(not CONTROLLER._wall_climb_gates(7.5, N, _travel(deg), false, 4.0, 15.0, 15.0),
			"%.0f degrees off dead-on climbed" % deg)

func test_gates_refuse_a_drift_a_dash_and_a_slope() -> void:
	check(not CONTROLLER._wall_climb_gates(3.9, N, _travel(0), false, 4.0, 15.0, 15.0), "a drift climbed")
	check(not CONTROLLER._wall_climb_gates(7.5, N, _travel(0), true, 4.0, 15.0, 15.0), "a dash climbed")
	var ramp := Vector3(0, 0.5, 1).normalized()   # ~27 degrees off vertical
	check(not CONTROLLER._wall_climb_gates(7.5, ramp, _travel(0), false, 4.0, 15.0, 15.0),
		"a ramp climbed")

# The drawing: climb in the middle, the wall-run on both sides, and every angle is exactly one.
func test_the_angle_split_with_the_wall_run() -> void:
	for deg in range(0, 90):
		var t := _travel(float(deg))
		var climb := CONTROLLER._wall_climb_gates(7.5, N, t, false, 4.0, 15.0, 15.0)
		var head_on := CONTROLLER._wall_run_head_on_gates(false, 7.5, N, t, false, 4.0, 15.0, 30.0)
		var side := CONTROLLER._wall_run_gates(false, 7.5, N, t, false, 4.0, 15.0, 60.0)
		if deg <= 15:
			check(climb, "%d degrees is not a climb" % deg)
		else:
			check(not climb and (head_on or side), "%d degrees is neither run nor climb" % deg)

func test_the_climb_is_decided_after_the_mantle_and_before_the_run() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/pilot9.gd")
	var body := src.substr(src.find("func _physics_process(delta: float) -> void:"))
	var mantle := body.find("_handle_mantle_trigger()")
	var climb := body.find("_handle_wall_climb(delta)")
	var run := body.find("_handle_wall_run(delta)")
	check(mantle != -1 and mantle < climb and climb < run,
		"the climb must run after the mantle and before the wall-run")

func test_the_cooldown_is_one_face_for_one_second() -> void:
	var p := Vector3(0, 1, 0)
	check(CONTROLLER._wall_climb_locked(N, p, 0.5, N, p + Vector3(3, 2, 0)), "same face not locked")
	check(not CONTROLLER._wall_climb_locked(N, p, 0.5, -N, p + Vector3(0, 0, 6)),
		"the facing wall was locked")
	check(not CONTROLLER._wall_climb_locked(N, p, 0.0, N, p), "the lock outlived its second")

# --- live climbs ------------------------------------------------------------------

func test_a_climb_gains_the_height_then_peels() -> void:
	var p := _live_pilot()
	_tall_wall()
	p.global_position = FAR + Vector3(0, 1.0, -1.4)
	p.velocity = Vector3(0, 0, -7.5)
	_step(p)
	check(p.is_wall_climbing, "running dead-on into a tall wall did not climb it")
	var start_y: float = p.global_position.y
	var peak := start_y
	var frames := 0
	while p.is_wall_climbing and frames < 200:
		_step(p)
		peak = maxf(peak, p.global_position.y)
		frames += 1
	approx(peak - start_y, 4.0, 0.15, "climb height")
	approx(p.global_position.z - (FAR.z - 2.0), p._wall_run_hold_distance(), 0.06,
		"not held at the hold distance off the face")
	approx(p.velocity.z, 1.0, 0.001, "the peel is not 1 m/s off the face")
	check(p._wall_climb_coyote_left > 0.0, "no climb coyote after the peel")
	check(p._wall_climb_lock_left > 0.0, "the peel did not start the same-wall cooldown")

func test_jump_kicks_straight_off_with_a_full_jump() -> void:
	var p := _live_pilot()
	_tall_wall()
	p.global_position = FAR + Vector3(0, 1.0, -1.4)
	p.velocity = Vector3(0, 0, -7.5)
	_step(p)
	for i in 10:
		_step(p)
	# The press itself is not simulated: Input.action_press() inside the suite's one frame leaves
	# `jump` just-pressed for every test after this one. The press path is checked in source.
	var handle := FileAccess.get_file_as_string("res://scripts/pilot9.gd")
	handle = handle.substr(handle.find("func _handle_wall_climb(delta: float) -> void:"))
	var press := handle.find('Input.is_action_just_pressed("jump")')
	check(press != -1 and handle.find("_wall_climb_jump_buffered = true", press) != -1,
		"jump on a climb is not buffered into the climb jump")
	p._wall_climb_jump_normal = p._wall_climb_normal
	p._end_wall_climb()
	p._wall_jumps_taken = 3   # deep in a wall-run chain - the climb jump must not read it
	p._take_wall_climb_jump()
	approx(p.velocity.z, p.wall_jump_kick, 0.0001, "the kick is not wall_jump_kick off the face")
	approx(p.velocity.y, p.jump_velocity, 0.0001, "the climb jump decayed")
	check(p._wall_jumps_taken == 3, "the climb jump advanced the wall-run chain")
	check(p._wall_jump_push_time > 0.0, "no push protection after the climb jump")
	var facing := Vector3(sin(p.character.rotation.y), 0, cos(p.character.rotation.y))
	check(facing.dot(N) > 0.99, "he did not turn to face away from the wall")

func test_a_chimney_catches_the_far_wall() -> void:
	var p := _live_pilot()
	_tall_wall()                                            # face at z = -2, normal +Z
	_wall(Vector3(8, 20, 1), Vector3(0, 10, 4.5))           # face at z = 4, normal -Z: 6 m across
	p.global_position = FAR + Vector3(0, 1.0, -1.4)
	p.velocity = Vector3(0, 0, -7.5)
	_step(p)
	for i in 20:
		_step(p)
	p._wall_climb_jump_normal = p._wall_climb_normal
	p._end_wall_climb()
	p._take_wall_climb_jump()
	var caught := false
	for i in 120:
		p.velocity.y -= p.jump_gravity * DT
		_step(p)
		if p.is_wall_climbing:
			caught = true
			break
	check(caught, "flew across the chimney and never climbed the far wall")
	check(p._wall_climb_normal.dot(Vector3(0, 0, -1)) > 0.99, "climbed something but not the far wall")

func test_the_same_face_waits_a_second_and_another_does_not() -> void:
	var p := _live_pilot()
	_tall_wall()
	p.global_position = FAR + Vector3(0, 1.0, -1.4)
	p.velocity = Vector3(0, 0, -7.5)
	_step(p)
	p._end_wall_climb()
	p.velocity = Vector3(0, 0, -7.5)
	var hit: Dictionary = p._probe_wall_ahead(Vector3(0, 0, -1))
	check(not p._can_start_wall_climb(hit, Vector3(0, 0, -1)), "re-climbed the same face at once")
	p._handle_wall_climb(p.wall_climb_same_wall_cooldown + 0.01)
	hit = p._probe_wall_ahead(Vector3(0, 0, -1))
	check(p.is_wall_climbing or p._can_start_wall_climb(hit, Vector3(0, 0, -1)),
		"the same face was still locked after the cooldown")

func test_an_inside_corner_hands_the_run_to_a_climb() -> void:
	var p := _live_pilot()
	_wall(Vector3(1, 20, 20), Vector3(1.5, 10, -8))        # A: face x = 1, normal -X, along -Z
	_wall(Vector3(8, 20, 1), Vector3(-2, 10, -6.5))        # B: face z = -6, normal +Z, across the run
	p.global_position = FAR + Vector3(0.6, 1.0, -0.5)
	p.velocity = Vector3(0, 0, -7.5)
	p._handle_wall_run(DT)
	check(p.is_wall_running, "never caught wall A")
	p._wall_run_leveled = true
	var climbed := false
	for i in 120:
		_step(p)
		if p.is_wall_climbing:
			climbed = true
			break
	check(climbed, "ran into the corner and did not climb wall B")
	check(not p.is_wall_running, "the run survived the handoff")
	check(p._wall_climb_normal.dot(Vector3(0, 0, 1)) > 0.99, "climbed the wrong wall")

func test_a_reachable_lip_in_the_air_is_the_mantles() -> void:
	var p := _live_pilot()
	_wall(Vector3(8, 2.5, 3), Vector3(0, 1.25, -3.5))      # face z = -2, top at 2.5 m
	p.global_position = FAR + Vector3(0, 1.0, -1.4)         # lip 1.5 m over his feet - in the band
	p.velocity = Vector3(0, 0, -7.5)
	var hit: Dictionary = p._probe_wall_ahead(Vector3(0, 0, -1))
	check(not hit.is_empty(), "the probe missed the low wall")
	check(not p._can_start_wall_climb(hit, Vector3(0, 0, -1)), "climbed a lip the mantle can take")

func test_the_wall_ending_keeps_the_climb_speed() -> void:
	var p := _live_pilot()
	p.can_climb = false                                     # no mantle to take the top
	_wall(Vector3(8, 4, 1), Vector3(0, 2, -2.5))            # top at 4 m
	p.global_position = FAR + Vector3(0, 0.5, -1.4)
	p.velocity = Vector3(0, 0, -7.5)
	_step(p)
	check(p.is_wall_climbing, "did not climb the 4 m wall")
	for i in 60:
		_step(p)
		if not p.is_wall_climbing:
			break
	check(not p.is_wall_climbing, "climbed on past the top of the wall")
	check(p.velocity.y > 1.0, "the wall's top stopped his rise dead")

func test_can_wall_climb_off_falls_back_to_the_head_on_run() -> void:
	var p := _live_pilot()
	p.can_wall_climb = false
	_tall_wall()
	p.global_position = FAR + Vector3(0, 1.0, -1.4)
	p.velocity = Vector3(0, 0, -7.5)
	var hit: Dictionary = p._probe_wall_ahead(Vector3(0, 0, -1))
	check(not p._can_start_wall_climb(hit, Vector3(0, 0, -1)), "climbed with can_wall_climb off")

