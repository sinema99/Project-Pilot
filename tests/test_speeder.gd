extends "res://tests/test_case.gd"

# Speeder1, asserted against docs/specs/speeder1.md. Physics is not stepped: the drive is checked
# through its pure steps (step_speed, yaw_rate, bank_target), the hold through step_exit_hold(),
# and the rider through pilot9's begin_ride() / end_ride(). The live drive in trial (hover height,
# top speed, a ledge, the kill plane) is tests/_probe_speeder_drive.gd.

const SpeederScene := preload("res://scenes/speeder.tscn")
const PilotScene := preload("res://scenes/pilot9.tscn")
const PROMPT_SCRIPT := preload("res://scripts/ui/interaction_prompt.gd")
const SCREEN_TSCN := "res://scenes/ui/inventory_screen.tscn"
const BATTERY := preload("res://resources/items/battery.tres")

var _live: Array[Node] = []
var _keys := 0


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _inventory() -> Node:
	return _tree().root.get_node(^"Inventory")


func _in_tree(n: Node) -> Node:
	_tree().root.add_child(n)
	_live.append(n)
	return n


## A speeder with a stash of its own for this test only.
func _speeder() -> Node3D:
	var s: Node3D = SpeederScene.instantiate()
	_keys += 1
	s.stash_key = StringName("test_speeder_%d" % _keys)
	return _in_tree(s)


func end() -> void:
	for n in _live:
		if is_instance_valid(n):
			if n.get_parent():
				n.get_parent().remove_child(n)
			n.free()
	_live.clear()
	for k in _inventory().vehicle_stashes.keys():
		if String(k).begins_with("test_speeder_"):
			_inventory().vehicle_stashes.erase(k)
	super.end()


class _StubRider extends Node3D:
	var ended := false
	var riding: Node3D = null
	func begin_ride(v: Node3D) -> void:
		riding = v
	func end_ride(_pos: Vector3, _yaw: float) -> void:
		ended = true
		riding = null


# --- stash and boxes ----------------------------------------------------------------------

func test_the_stash_is_8_by_6_with_a_battery_and_a_ration() -> void:
	var s := _speeder()
	eq([s.stash.width, s.stash.height], [8, 6], "8 x 6")
	var kinds: Array = []
	for it in s.stash.items:
		kinds.append(String(it.def.id))
	kinds.sort()
	eq(kinds, ["battery", "ration"], "the test seed")
	check(s.stash != _inventory().stash, "its own grid, not EXIA's")


func test_the_stash_lives_on_the_autoload_for_the_session() -> void:
	var s := _speeder()
	var key: StringName = s.stash_key
	var grid: ItemGrid = s.stash
	_live.erase(s)
	s.get_parent().remove_child(s)
	s.free()
	var again: Node3D = SpeederScene.instantiate()
	again.stash_key = key
	_in_tree(again)
	check(again.stash == grid, "a reloaded speeder with the same key gets the same stash")


func test_the_boxes_are_the_cargo_mesh() -> void:
	var s := _speeder()
	check(s.boxes != null, "found")
	var named := false
	for i in s.boxes.mesh.get_surface_count():
		var m: Material = s.boxes.mesh.surface_get_material(i)
		if m != null and m.resource_name.to_lower() == "boxes":
			named = true
	check(named, "the mesh wearing the boxes material")


func test_the_boxes_show_exactly_while_there_is_loot() -> void:
	var s := _speeder()
	check(s.boxes.visible, "seeded: shown")
	for it in s.stash.items.duplicate():
		s.stash.remove(it)
	check(not s.boxes.visible, "emptied: hidden")
	s.stash.add(BATTERY, 1)
	check(s.boxes.visible, "one item back: shown")


func test_the_stash_screen_shows_the_speeders_grid_and_name() -> void:
	var s := _speeder()
	eq(_inventory().stash_of(s), s.stash, "stash_of: its own grid")
	var screen: Control = (load(SCREEN_TSCN) as PackedScene).instantiate()
	_in_tree(screen)
	_inventory().stash_mech = s
	screen.present()
	check(screen.is_stash_mode(), "STASH mode")
	eq(screen.stash_grid(), s.stash, "the right-hand box is the speeder's")
	eq(screen.stash_title(), "SPEEDER1", "portrait titled with its name")
	check(screen.stash_cell_at(screen.stash_cell_origin(Vector2i(7, 5)) + Vector2i(3, 3)) == Vector2i(7, 5),
		"the last cell is there")
	check(screen.stash_cell_at(screen.stash_cell_origin(Vector2i(8, 0)) + Vector2i(3, 3)) == Vector2i(-1, -1),
		"and nothing past 8 wide")
	screen.dismiss()


func test_exia_still_gets_the_shared_stash() -> void:
	eq(_inventory().stash_of(Node3D.new()), _inventory().stash, "no `stash` of its own: EXIA's")


# --- drive ---------------------------------------------------------------------------------

func test_top_speed_in_two_and_a_half_seconds() -> void:
	var s := _speeder()
	var v := 0.0
	var t := 0.0
	while v < s.max_speed and t < 10.0:
		v = s.step_speed(v, 1.0, 1.0 / 60.0)
		t += 1.0 / 60.0
	approx(v, 50.0, 0.001, "50 m/s (25 x the 2.0 size)")
	approx(t, 2.5, 0.05, "in 2.5 s")
	approx(s.step_speed(50.0, 1.0, 0.1), 50.0, 0.001, "held there")


func test_s_brakes_then_reverses_to_twelve() -> void:
	var s := _speeder()
	approx(s.step_speed(25.0, -1.0, 0.1), 19.0, 0.001, "brake 60 m/s^2")
	approx(s.step_speed(1.0, -1.0, 0.1), 0.0, 0.001, "braking stops at 0, no flip into reverse")
	var v := 0.0
	for i in 200:
		v = s.step_speed(v, -1.0, 1.0 / 60.0)
	approx(v, -12.0, 0.001, "reverse capped at 12")
	check(s.step_speed(10.0, 0.0, 0.1) < 10.0, "coasting slows it")


func test_d_turns_right_and_reverse_flips_it() -> void:
	var s := _speeder()
	# The nose is +Z and the rider's right is -X: turning right is a negative yaw rate.
	check(s.yaw_rate(1.0, 20.0) < 0.0, "D at speed: right")
	check(s.yaw_rate(-1.0, 20.0) > 0.0, "A at speed: left")
	check(s.yaw_rate(1.0, -4.0) > 0.0, "reversing flips the steer")
	check(absf(s.yaw_rate(1.0, 0.0)) > absf(s.yaw_rate(1.0, 50.0)), "tighter slow than fast")


func test_bank_follows_the_slip_and_the_stick_up_to_55_degrees() -> void:
	var s := _speeder()
	approx(rad_to_deg(s.bank_target(1.0, 50.0, 40.0)), 55.0, 0.01, "full steer and a full slip: 55")
	check(rad_to_deg(s.bank_target(1.0, 50.0)) < 55.0 and s.bank_target(1.0, 50.0) > 0.0, "the stick alone leans less than the cap")
	check(s.bank_target(0.0, 50.0, 20.0) > 0.0, "sliding left with the stick released: still leant")
	check(s.bank_target(0.0, 50.0, -20.0) < 0.0, "sliding right: leant the other way")
	check(s.bank_target(1.0, 20.0) > 0.0, "D: the top goes right (+ about +Z)")
	approx(s.bank_target(1.0, 0.0), 0.0, 0.0001, "standing: no bank")
	check(s.bank_target(1.0, 5.0) < s.bank_target(1.0, 15.0), "scaled by speed")


func test_hover_numbers() -> void:
	var s := _speeder()
	approx(s.hover_height, 0.45, 0.0001, "origin 0.45 over the ground, hull ~0.5")
	approx(s.max_speed, 50.0, 0.0001, "50 m/s")
	approx(s.reverse_speed, 12.0, 0.0001, "reverse 12")


# --- on and off ----------------------------------------------------------------------------

func test_the_ground_offer_is_ride_over_stash() -> void:
	var s := _speeder()
	var p: Node = PROMPT_SCRIPT.acquire(s)
	if p != null and not _live.has(p):
		_live.append(p)
	var body := _in_tree(Node3D.new()) as Node3D
	# A pilot on his feet is physics-processing; one in a vehicle is not and gets no offer.
	body.set_physics_process(true)
	s.player_in_range = body
	s._bid_prompt()
	p.commit()
	eq(p.shown_options(), PackedStringArray(["RIDE", "STASH"]), "RIDE over STASH")
	s.player_in_range = null


func test_the_exit_hold_only_fills_at_a_crawl() -> void:
	var s := _speeder()
	var rider := _in_tree(_StubRider.new()) as Node3D
	s.mount(rider)
	s.mount_left = 0.0
	s.grounded = true
	s.speed = 10.0
	s.exit_hold = 0.0
	for i in 60:
		s.step_exit_hold(true, 1.0 / 60.0)
	approx(s.exit_progress(), 0.0, 0.0001, "at 10 m/s the bar does not move")
	eq(s.pilot, rider, "still on")
	s.speed = 1.0
	s.step_exit_hold(true, 0.3)
	approx(s.exit_progress(), 0.5, 0.01, "slow: half a hold, half a bar")
	s.step_exit_hold(false, 0.016)
	check(s.exit_hold < 0.0, "let go: gone")
	s.exit_hold = 0.0
	var off := false
	for i in 40:
		off = s.step_exit_hold(true, 1.0 / 60.0) or off
	check(off, "a full 0.6 s hold at a crawl starts him getting off")
	check(s.pilot == rider and not rider.ended, "still on for the swing")
	s.step_boarding(1.0)
	check(s.pilot == null and rider.ended, "end_ride was called when the swing was done")


func test_stash_rules_aboard() -> void:
	var s := _speeder()
	check(not s.can_open_stash(), "nobody on")
	var rider := _in_tree(_StubRider.new()) as Node3D
	s.mount(rider)
	check(not s.can_open_stash(), "not during the mount")
	s.mount_left = 0.0
	check(s.can_open_stash(), "settled on: Tab opens it")
	s.dismount_left = 0.2
	check(not s.can_open_stash(), "not on the way off")
	s.dismount_left = 0.0
	s.exit_hold = 0.0
	check(not s.can_open_stash(), "not while F is held")
	s.exit_hold = -1.0
	s.set_stash_hold(true)
	check(s.stash_hold, "held while the screen is up")
	s.set_stash_hold(false)
	check(_inventory().piloted_mech() == s, "Tab aboard finds the ridden speeder")


func test_pilot9_rides_visible_frozen_and_holstered() -> void:
	var s := _speeder()
	var pilot: Node3D = _in_tree(PilotScene.instantiate())
	if pilot.item_holder != null:
		pilot.item_holder.set_drawn(true)
	s.mount(pilot)
	eq(pilot.riding, s, "riding it")
	check(pilot.visible, "still on screen (EXIA hides him; a bike does not)")
	check(pilot.frozen, "reads no input")
	check(not pilot.is_physics_processing(), "his own physics off")
	check(pilot.collision_shape.disabled, "his shape off")
	check(pilot.ride_pose != null and pilot.ride_pose.active, "the tuck layer is on")
	eq(pilot.ride_pose.get_index(), pilot.ride_pose.get_parent().get_child_count() - 1,
		"and last on the skeleton")
	check(pilot.item_holder == null or not pilot.item_holder.is_drawn, "the staff put away")
	check(not pilot.can_open_inventory(), "Tab is the stash aboard, not his own screen")
	pilot.set_inventory_hold(true)
	pilot.set_inventory_hold(false)
	check(pilot.frozen, "closing the stash screen does not unfreeze him on the bike")
	s.mount_left = 0.0
	s.dismount()
	s.step_boarding(1.0)
	eq(pilot.riding, null, "off")
	check(not pilot.frozen and pilot.is_physics_processing(), "his body is his again")
	check(not pilot.ride_pose.active, "the tuck layer is off")
	eq(pilot.coat.extra_planes if pilot.coat != null else [], [], "the coat's seat plane is gone")


func test_exit_spot_is_the_left_side_facing_the_nose() -> void:
	var s := _speeder()
	var spot: Dictionary = s.exit_spot()
	var local: Vector3 = s.global_transform.affine_inverse() * (spot.position as Vector3)
	check(local.x > 0.5, "his left (+X)")
	approx(spot.yaw, s.rotation.y, 0.0001, "facing along the nose")


func test_the_ride_pose_reaches_the_grips_and_pegs() -> void:
	# The pose layer in a live skeleton is only checkable in a drawn frame (the skeleton puts the
	# un-modified pose back after each update); this pins that the points are reachable at all:
	# hip to grip and hip to peg within his arm / leg length.
	var s := _speeder()
	var seat: Vector3 = s.seat_point
	# Sitting upright (hip 10 + spine 20 = 30 degrees forward) is the long reach.
	var shoulder := seat + Vector3(0.0, 0.46 * cos(deg_to_rad(30.0)), 0.46 * sin(deg_to_rad(30.0)))
	for p: Vector3 in [s.grip_left, s.grip_right]:
		var sh := shoulder + Vector3(0.2 * signf(p.x), 0.0, 0.0)
		check((p - sh).length() < 0.72, "grip in reach of the upright shoulder")
	for p in [s.peg_left, s.peg_right]:
		check(((p as Vector3) - seat).length() < 0.97, "peg in reach of the hip")
	check(s.grip_left.x > 0.0 and s.grip_right.x < 0.0, "left grip on +X (his left)")


# --- pass 2: size, boarding, tuck, fire ------------------------------------------------------

func test_the_bike_is_twice_the_size() -> void:
	var s := _speeder()
	approx(s.size_scale, 2.0, 0.0001, "2.0x")
	approx(s.model.scale.x, 2.0, 0.0001, "the model")
	approx((s.body_shape.shape as BoxShape3D).size.z, 6.0, 0.0001, "the hull's box: 3 m x 2")
	approx((s.area_shape.shape as SphereShape3D).radius, 5.2, 0.0001, "the interaction sphere")
	var s2 := _speeder()
	approx((s2.body_shape.shape as BoxShape3D).size.z, 6.0, 0.0001, "a second instance is not scaled twice")


func test_the_bike_does_not_move_while_he_gets_on_or_off() -> void:
	var s := _speeder()
	s.speed = 1.5
	var at: Vector3 = s.global_position
	var rider := _in_tree(_StubRider.new()) as Node3D
	s.mount(rider)
	approx(s.speed, 0.0, 0.0001, "mounting stops it")
	for i in 60:
		s.step_boarding(1.0 / 60.0)
		check(s.global_position.is_equal_approx(at), "still through the mount")
	check(s.mount_left <= 0.0, "the mount is done")
	s.speed = 1.2
	s.dismount()
	approx(s.speed, 0.0, 0.0001, "getting off stops it too")
	check(s.transition_active(), "the swing is running")
	check(s.global_position.is_equal_approx(at), "and the bike has not moved")


func test_the_spot_is_fixed_and_a_pilot_on_it_does_not_walk() -> void:
	var s := _speeder()
	var spot: Dictionary = s.exit_spot()
	var local: Vector3 = s.global_transform.affine_inverse() * (spot.position as Vector3)
	check(local.is_equal_approx(s.mount_spot), "the exit is the mount spot, every time")
	var rider := _in_tree(_StubRider.new()) as Node3D
	rider.global_position = spot.position
	s.mount(rider)
	approx(s._mount_walk, 0.0, 0.0001, "standing on the spot: no walk")
	approx(s.mount_left, s.mount_swing_time, 0.0001, "just the swing")
	s.step_boarding(10.0)
	s.dismount()
	var back: Vector3 = s._exit_world
	check(back.is_equal_approx(spot.position), "he is put down where he got on")


func test_a_pilot_from_far_away_walks_to_the_spot_first() -> void:
	var s := _speeder()
	var rider := _in_tree(_StubRider.new()) as Node3D
	rider.global_position = s.global_position + Vector3(-3.0, 0.0, 2.0)
	s.mount(rider)
	approx(s._mount_walk, s.mount_walk_time, 0.0001, "a walk")
	var p0: Vector2 = s.boarding_progress()
	approx(p0.y, 0.0, 0.0001, "no swing yet")
	s.mount_left = s.mount_swing_time * 0.5
	var p1: Vector2 = s.boarding_progress()
	approx(p1.x, 1.0, 0.0001, "arrived")
	approx(p1.y, 0.5, 0.01, "half way over the saddle")
	s.mount_left = 0.0
	eq(s.boarding_progress(), Vector2.ONE, "seated")


func test_the_swing_runs_backwards_getting_off() -> void:
	var s := _speeder()
	var rider := _in_tree(_StubRider.new()) as Node3D
	s.mount(rider)
	s.step_boarding(10.0)
	s.dismount()
	approx(s.boarding_progress().y, 1.0, 0.0001, "starts seated")
	s.dismount_left = s.dismount_swing_time * 0.25
	approx(s.boarding_progress().y, 0.25, 0.01, "coming off")


func test_the_tuck_is_speed_dependent() -> void:
	var s := _speeder()
	approx(smoothstep(s.tuck_from_share, s.tuck_full_share, 0.0), 0.0, 0.0001, "upright parked")
	approx(smoothstep(s.tuck_from_share, s.tuck_full_share, 0.9), 1.0, 0.0001, "tucked at speed")
	var pose := preload("res://scripts/speeder_ride_pose.gd").new()
	check(pose.hip_upright_degrees < pose.hip_pitch_degrees and pose.spine_upright_degrees < pose.spine_pitch_degrees,
		"the tucked pose is lower than the upright one")
	pose.free()


func test_thruster_levels() -> void:
	var F := preload("res://scripts/speeder_fire.gd")
	eq(F.levels(false, 1.0, 20.0, 0.5, 0.0), Vector2.ZERO, "nobody on: dark")
	var idle: Vector2 = F.levels(true, 0.0, 0.0, 0.0, 0.0)
	check(idle.x > 0.0 and idle.x < 0.3, "rider on, parked: a small flicker")
	var full: Vector2 = F.levels(true, 1.0, 37.5, 1.0, 0.0)
	check(full.x > 0.95, "full throttle: full")
	var coast: Vector2 = F.levels(true, 0.0, 20.0, 0.55, 0.0)
	check(coast.x > idle.x and coast.x < full.x, "coasting in between")
	var brake: Vector2 = F.levels(true, -1.0, 20.0, 0.55, 0.0)
	check(brake.x < 0.1, "braking: almost out")
	var right: Vector2 = F.levels(true, 1.0, 30.0, 0.8, 1.0)
	check(right.x > right.y, "a right turn (D): the left nozzle flares, the right dims")
	var left: Vector2 = F.levels(true, 1.0, 30.0, 0.8, -1.0)
	check(left.y > left.x, "a left turn (A): the right nozzle flares")


func test_the_thruster_fire_draws_two_flames_and_obeys_the_setting() -> void:
	var s := _speeder()
	check(s.fire != null, "built")
	eq(s.fire._roots.size(), 2, "two nozzles")
	s.fire.drive(1.0, 0.5, true)
	for i in 30:
		s.fire._process(1.0 / 30.0)
	check(s.fire.flame_length(0) > s.fire.flame_length(1) and s.fire.flame_length(1) > 0.0,
		"both lit, the left longer")
	check(s.fire.sparks_emitting(0) and s.fire.sparks_emitting(1), "cube sparks on")
	check(s.fire.flame_length(0) > 1.0, "a metre-plus flame at full burn")
	s.fire.drive(1.0, 1.0, false)
	for i in 120:
		s.fire._process(1.0 / 30.0)
	approx(s.fire.flame_length(0), 0.0, 0.0001, "MOVEMENT EFFECTS off: out")
	check(not s.fire.sparks_emitting(0), "and no sparks")


# --- pass 4: Sparrow driving (docs/specs/speeder1-pass4-driving.md) --------------------------------

func test_a_boost_runs_to_eighty_and_lets_go_over_two_seconds() -> void:
	var s := _speeder()
	var v := 50.0
	for i in 120:
		v = s.step_speed(v, 1.0, 1.0 / 60.0, true)
	approx(v, 80.0, 0.001, "boost tops out at 80 m/s")
	var t := 0.0
	while v > 50.001 and t < 10.0:
		v = s.step_speed(v, 1.0, 1.0 / 60.0, false)
		t += 1.0 / 60.0
	approx(t, 2.0, 0.05, "back to cruise in about 2 s once it is let go")
	approx(s.step_speed(80.0, 0.0, 0.1, false), 78.5, 0.001, "coasting off a boost bleeds at the same rate")
	check(s.step_speed(-3.0, 1.0, 0.1, true) > -3.0 and s.step_speed(-3.0, 1.0, 0.1, true) <= 0.0,
		"a boost never flips a reversing bike straight forward")


func test_the_boost_meter_drains_in_three_seconds_and_refills_in_six() -> void:
	var s := _speeder()
	var st := {meter = 1.0, empty = false, idle = 0.0}
	var t := 0.0
	var burning := true
	while t < 3.2:
		st = s.boost_step(st.meter, st.empty, st.idle, true, 1.0 / 60.0)
		burning = st.boosting
		t += 1.0 / 60.0
	approx(st.meter, 0.0, 0.0001, "empty after 3 s")
	check(not burning and st.empty, "and the boost cuts out, locked")
	# Holding it while locked does nothing; letting go refills after the idle.
	st = s.boost_step(st.meter, st.empty, st.idle, true, 0.1)
	check(not st.boosting, "locked out while held")
	t = 0.0
	while t < 6.4:
		st = s.boost_step(st.meter, st.empty, st.idle, false, 1.0 / 60.0)
		t += 1.0 / 60.0
	approx(st.meter, 1.0, 0.001, "refilled over 6 s (after a 0.4 s idle)")
	st = s.boost_step(0.2, true, 1.0, true, 0.016)
	check(not st.boosting, "an emptied meter will not restart below 25%")
	st = s.boost_step(0.3, true, 1.0, true, 0.016)
	check(st.boosting, "and restarts above it")


func test_a_slide_needs_speed_and_a_hard_turn() -> void:
	var s := _speeder()
	approx(s.slide_target(1.0, 10.0), 0.0, 0.0001, "slow: no slide")
	approx(s.slide_target(0.0, 50.0), 0.0, 0.0001, "no steer: no slide")
	approx(s.slide_target(1.0, 20.0), 0.0, 0.0001, "40% of cruise is where it starts")
	check(s.slide_target(1.0, 50.0) > 0.99, "full lock at cruise: a full slide")
	check(s.slide_target(0.5, 50.0) < s.slide_target(1.0, 50.0), "scaled by the steer")
	approx(s.slide_target(1.0, -20.0), 0.0, 0.0001, "reversing never slides")
	check(s.grip_rate(0.0) > s.grip_rate(1.0), "less grip while sliding")
	check(s.grip_rate(1.0, 1.0) < s.grip_rate(1.0), "a power slide has the least grip")
	# The slip angle at full lock and speed: yaw rate over grip, about 35-40 degrees; the power slide deeper.
	var slip := rad_to_deg(atan(absf(s.yaw_rate(1.0, 50.0)) / s.grip_rate(1.0)))
	check(slip > 33.0 and slip < 42.0, "full float: slip %.1f deg" % slip)
	var pslip := rad_to_deg(atan(absf(s.yaw_rate(1.0, 50.0)) * s.drift_yaw_mult / s.grip_rate(1.0, 1.0)))
	check(pslip > slip + 12.0, "power slide deeper: %.1f deg" % pslip)


func test_grip_takes_the_slide_back_smoothly_and_never_adds_speed() -> void:
	var s := _speeder()
	var fl := Vector2(50.0, 20.0)
	var mag := fl.length()
	var t := 0.0
	while absf(fl.y) > 0.05 * 20.0 and t < 3.0:
		fl = s.apply_grip(fl.x, fl.y, 0.0, 1.0 / 60.0)
		t += 1.0 / 60.0
		check(fl.length() <= mag + 0.0001, "grip never adds speed")
	check(t > 0.5 and t < 1.0, "95%% of the slide gone in under a second, no snap (%.2f)" % t)
	var sliding: Vector2 = s.apply_grip(50.0, 20.0, 1.0, 0.1)
	var gripped: Vector2 = s.apply_grip(50.0, 20.0, 0.0, 0.1)
	check(absf(sliding.y) > absf(gripped.y), "a full slide holds on to the sideways speed longer")
	check(s.apply_grip(-5.0, 2.0, 0.0, 0.1).x < 0.0, "reversing stays reversing")


func test_the_hop_is_a_metre_and_a_half() -> void:
	var s := _speeder()
	var g: float = s.gravity * s.gravity_scale
	var v := sqrt(2.0 * g * s.jump_height)
	approx(v * v / (2.0 * g), 1.5, 0.0001, "the launch speed reaches 1.5 m")
	approx(s.jump_height, 1.5, 0.0001, "1.5 m")


func test_the_boost_flares_the_thrusters_and_lights_the_streaks() -> void:
	var F := preload("res://scripts/speeder_fire.gd")
	var plain: Vector2 = F.levels(true, 0.0, 20.0, 0.4, 0.0, 0.0)
	var boosted: Vector2 = F.levels(true, 0.0, 20.0, 0.4, 0.0, 1.0)
	check(boosted.x > 1.2 and boosted.x > plain.x * 2.0, "a boost goes long and hot even coasting")
	eq(F.levels(false, 1.0, 20.0, 0.5, 0.0, 1.0), Vector2.ZERO, "nobody on: still dark")
	var s := _speeder()
	check(s.fire._streaks != null, "the speed lines are built")
	s.fire.drive(1.0, 1.0, true, 1.0)
	check(s.fire.streaks_emitting(), "boosting: streaming")
	s.fire.drive(1.0, 1.0, false, 1.0)
	check(not s.fire.streaks_emitting(), "MOVEMENT EFFECTS off: none")
	s.fire.drive(1.0, 1.0, true, 0.0)
	check(not s.fire.streaks_emitting(), "no boost: none")


func test_there_is_no_boost_bar() -> void:
	var s := _speeder()
	check(s.get_node_or_null(^"Hud") == null, "no boost bar on the bike")


func test_the_camera_is_led_by_the_nose() -> void:
	var s := _speeder()
	s.rotation.y = 0.0
	s.speed = 40.0
	s.velocity = Vector3(20.0, 0.0, 40.0)
	var heading: float = s.view_heading()
	check(heading > 0.05 and heading < atan2(20.0, 40.0) * 0.3, "a drift to the left: the nose, with a quarter of the way to the travel line")
	s.velocity = Vector3(1.0, 0.0, 2.0)
	approx(s.view_heading(), 0.0, 0.0001, "at a crawl: the nose")
	s.speed = -10.0
	s.velocity = Vector3(0.0, 0.0, -10.0)
	approx(s.view_heading(), 0.0, 0.0001, "reversing: the nose")


func test_the_course_is_built_with_its_own_bike() -> void:
	var c: Node3D = preload("res://scripts/speeder_course.gd").new()
	_in_tree(c)
	check(c.speeder != null and c.speeder.name == &"Speeder2", "Speeder2 at the start")
	eq(c.speeder.stash_key, &"speeder_course", "its own stash")
	var boxes := 0
	for ch in c.get_children():
		if ch is StaticBody3D:
			boxes += 1
	check(boxes >= 10, "slab, ramps and walls (%d)" % boxes)
	_inventory().vehicle_stashes.erase(&"speeder_course")
