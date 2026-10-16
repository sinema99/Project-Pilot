extends "res://tests/test_case.gd"

# docs/specs/pilot9-reflect.md. The gates, the timing curves, the reflect directions and the
# zone. How the spin looks and feels is judged in play.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const SPIN := preload("res://scripts/items/reflect_spin.gd")
const PROJECTILE := preload("res://scripts/reflect/reflect_projectile.gd")

var _pilot: Node = null

# One shared in-tree instance with the staff drawn and nothing spinning.
func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	_pilot.reflect_spin.cancel()
	_pilot.frozen = false
	if not _pilot.is_item_drawn():
		_pilot.toggle_drawn()
	return _pilot

func _clear_flags(p: Node) -> void:
	p.is_climbing = false
	p.is_vaulting = false
	p.is_wall_running = false
	p.is_rail_grinding = false
	p.is_rail_switching = false

func _step(spin: Node, seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in int(seconds / dt):
		spin._physics_process(dt)

# --- input ------------------------------------------------------------------------------------

func test_reflect_is_on_left_mouse_and_right_shoulder() -> void:
	check(InputMap.has_action(&"reflect"), "project.godot has no `reflect` action")
	if not InputMap.has_action(&"reflect"):
		return
	var evs := InputMap.action_get_events(&"reflect")
	check(evs.any(func(e): return e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT),
		"`reflect` should be on the left mouse button")
	check(evs.any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_RIGHT_SHOULDER),
		"`reflect` should be on the gamepad right shoulder")

# --- pure helpers -----------------------------------------------------------------------------

func test_can_start_needs_every_gate() -> void:
	check(SPIN.can_start(true, true, true, false, false), "all gates open should start")
	check(not SPIN.can_start(false, true, true, false, false), "not while a spin or recovery runs")
	check(not SPIN.can_start(true, false, true, false, false), "not with no item")
	check(not SPIN.can_start(true, true, false, false, false), "not with the staff holstered")
	check(not SPIN.can_start(true, true, true, true, false), "not while frozen")
	check(not SPIN.can_start(true, true, true, false, true), "not in a blocked move")

func test_perfect_window_edges() -> void:
	check(SPIN.is_perfect(0.0, 0.15), "the first instant is perfect")
	check(SPIN.is_perfect(0.15, 0.15), "the window's end is still perfect")
	check(not SPIN.is_perfect(0.16, 0.15), "just after the window is a normal reflect")

func test_spin_angle_starts_and_ends_exactly() -> void:
	approx(SPIN.spin_angle(0.0, 0.6, 2.0, 0.08, 0.1), 0.0, 0.0001, "starts at 0")
	approx(SPIN.spin_angle(0.6, 0.6, 2.0, 0.08, 0.1), 2.0 * TAU, 0.001, "ends at exactly the turns")
	approx(SPIN.spin_angle(9.0, 0.6, 2.0, 0.08, 0.1), 2.0 * TAU, 0.001, "clamped past the end")

func test_spin_angle_only_ever_advances() -> void:
	var last := -1.0
	var ok := true
	for i in 61:
		var a := SPIN.spin_angle(i * 0.01, 0.6, 2.0, 0.08, 0.1)
		if a < last - 0.00001:
			ok = false
		last = a
	check(ok, "the angle should never go backwards")

func test_spin_is_four_turns_in_the_same_beat() -> void:
	var spin = SPIN.new()
	eq(spin.spin_turns, 4.0, "the staff turns 4 times (2x the original 2)")
	approx(spin.spin_duration, 0.6, 0.0001, "across the unchanged 0.6 s")
	spin.free()

func test_spin_speed_fraction_ramps_holds_and_dies() -> void:
	approx(SPIN.spin_speed_fraction(0.0, 0.6, 0.08, 0.1), 0.0, 0.0001, "at rest at the start")
	approx(SPIN.spin_speed_fraction(0.04, 0.6, 0.08, 0.1), 0.5, 0.0001, "half way up the ease-in")
	approx(SPIN.spin_speed_fraction(0.3, 0.6, 0.08, 0.1), 1.0, 0.0001, "full through the middle")
	approx(SPIN.spin_speed_fraction(0.55, 0.6, 0.08, 0.1), 0.5, 0.0001, "half way down the ease-out")
	approx(SPIN.spin_speed_fraction(0.6, 0.6, 0.08, 0.1), 0.0, 0.0001, "at rest at the end")
	approx(SPIN.spin_speed_fraction(0.7, 0.6, 0.08, 0.1), 0.0, 0.0001, "nothing after the spin")
	# It is spin_angle's actual slope, as a fraction of peak.
	var dt := 0.0001
	var peak := (SPIN.spin_angle(0.3 + dt, 0.6, 4.0, 0.08, 0.1) - SPIN.spin_angle(0.3, 0.6, 4.0, 0.08, 0.1)) / dt
	var slope := (SPIN.spin_angle(0.05 + dt, 0.6, 4.0, 0.08, 0.1) - SPIN.spin_angle(0.05, 0.6, 4.0, 0.08, 0.1)) / dt
	approx(slope / peak, SPIN.spin_speed_fraction(0.05, 0.6, 0.08, 0.1), 0.01, "matches the angle curve")

func test_random_cone_stays_inside_the_cone() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var axis := Vector3(0.3, 0.2, -1.0).normalized()
	var worst := 0.0
	for i in 400:
		var d := SPIN.random_cone_direction(axis, 60.0, rng)
		worst = maxf(worst, rad_to_deg(axis.angle_to(d)))
		approx(d.length(), 1.0, 0.001, "a unit vector")
	check(worst <= 60.001, "every throw should stay within 60 degrees (worst %.2f)" % worst)
	check(worst > 40.0, "the throws should actually spread across the cone (worst %.2f)" % worst)

func test_zero_cone_is_the_axis() -> void:
	var rng := RandomNumberGenerator.new()
	var axis := Vector3.FORWARD
	var d := SPIN.random_cone_direction(axis, 0.0, rng)
	check(d.distance_to(axis) < 0.001, "a 0-degree cone is the axis itself")

# --- the rig ----------------------------------------------------------------------------------

func test_solved_pose_covers_both_arms_and_reaches_forward() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var skel := pilot.get_node("character/Armature/GeneralSkeleton") as Skeleton3D
	var solved: Dictionary = SPIN.solve_reach(skel, 0.25)
	check(solved["ok"], "the rig should have every arm bone the spin needs")
	for n in ["RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm"]:
		check(solved["pose"].has(skel.find_bone(n)), "%s should be posed" % n)
	# Point the solved upper arm at the centre: rotate the rest direction by the pose and it should
	# aim at centre_in_chest (in chest rest space, back in skeleton space).
	var chest := skel.find_bone(&"UpperChest")
	var centre: Vector3 = skel.get_bone_global_rest(chest) * solved["centre_in_chest"]
	var mid := (skel.get_bone_global_rest(skel.find_bone(&"RightUpperArm")).origin
		+ skel.get_bone_global_rest(skel.find_bone(&"LeftUpperArm")).origin) * 0.5
	var front := skel.get_bone_global_rest(chest).basis.z
	check((centre - mid).dot(front) > 0.3, "the hands should meet in front of the chest")
	check(centre.y < mid.y, "the hands should sit below shoulder height")
	# Apply it to the rig and the fists really meet at that point.
	var before: Dictionary = {}
	for bone in solved["pose"]:
		before[bone] = skel.get_bone_pose_rotation(bone)
		skel.set_bone_pose_rotation(bone, solved["pose"][bone])
	var r_hand := skel.get_bone_global_pose(skel.find_bone(&"RightHand")).origin
	var l_hand := skel.get_bone_global_pose(skel.find_bone(&"LeftHand")).origin
	for bone in before:
		skel.set_bone_pose_rotation(bone, before[bone])
	check(r_hand.distance_to(centre) < 0.12, "the right fist should be at the meeting point (%.3f m off)" % r_hand.distance_to(centre))
	check(l_hand.distance_to(centre) < 0.12, "the left fist should be at the meeting point (%.3f m off)" % l_hand.distance_to(centre))

func test_spin_node_is_built_on_the_pilot() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	check(pilot.reflect_spin != null, "the pilot should build a ReflectSpin")
	check(pilot.reflect_spin.ready_to_spin(), "the rig should be solved and the spin modifier added")
	check(pilot.reflect_spin.zone != null, "the reflect zone should exist")
	check(not pilot.reflect_spin.zone.monitoring, "the zone is off until a spin")
	check(pilot.is_in_group(&"reflect_target"), "the pilot is what the test emitter aims at")

func test_disc_replaces_the_trail() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var spin: Node = pilot.reflect_spin
	check(spin.get_node_or_null(^"SpinTrail") == null, "the old trail is gone")
	var disc := spin.get_node_or_null(^"SpinDisc") as MeshInstance3D
	check(disc != null, "the spin disc is built")
	if disc == null:
		return
	check(not disc.visible, "hidden while idle")
	_clear_flags(pilot)
	check(spin.try_start(), "spin starts")
	_step(spin, 0.3)
	spin._process(0.0)
	check(disc.visible == Settings.movement_effects, "shown at full speed when effects are on")
	if disc.visible:
		var staff: Node3D = pilot.item_holder.item_instance
		approx(disc.global_position.distance_to(staff.global_position), 0.0, 0.001, "centred on the staff")
		approx(disc.global_basis.y.normalized().dot(staff.global_basis.y.normalized()), 1.0, 0.001,
			"lined up with the staff")
		approx(disc.global_basis.y.length(), spin.tip_distance, 0.001, "as big as the staff")
	spin.cancel()
	spin._process(0.0)
	check(not disc.visible, "hidden once the spin is over")

# --- the gates on a real pilot -----------------------------------------------------------------

func test_holstered_press_does_nothing() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	pilot.toggle_drawn()
	_clear_flags(pilot)
	check(not pilot.reflect_spin.try_start(), "a press with the staff holstered should not spin")
	eq(pilot.reflect_spin.phase, SPIN.Phase.IDLE, "and it stays idle")

func test_blocked_moves_refuse_and_free_moves_start() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	for flag in ["is_climbing", "is_vaulting", "is_wall_running", "is_rail_grinding", "is_rail_switching"]:
		_clear_flags(pilot)
		pilot.set(flag, true)
		check(not pilot.reflect_spin.try_start(), "%s should block the spin" % flag)
	_clear_flags(pilot)
	check(pilot.reflect_spin.try_start(), "with no blocking move the spin should start")
	pilot.reflect_spin.cancel()

func test_frozen_refuses() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	_clear_flags(pilot)
	pilot.frozen = true
	check(not pilot.reflect_spin.try_start(), "a frozen pilot cannot spin")
	pilot.frozen = false

func test_phases_run_spin_recovery_idle_and_block_a_second_press() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	_clear_flags(pilot)
	var spin: Node = pilot.reflect_spin
	check(spin.try_start(), "first press starts")
	eq(spin.phase, SPIN.Phase.SPIN, "spinning")
	check(not spin.try_start(), "a press mid-spin does nothing")
	_step(spin, spin.spin_duration + 0.05)
	eq(spin.phase, SPIN.Phase.RECOVERY, "the spin hands over to recovery")
	check(not spin.zone.monitoring, "the zone is off in recovery")
	check(not spin.try_start(), "a press in recovery does nothing")
	_step(spin, spin.recovery_duration + 0.05)
	eq(spin.phase, SPIN.Phase.IDLE, "recovery ends")
	check(spin.try_start(), "after recovery a new spin starts")
	spin.cancel()

func test_holstering_mid_spin_cancels_it() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	_clear_flags(pilot)
	var spin: Node = pilot.reflect_spin
	spin.try_start()
	pilot.toggle_drawn()
	eq(spin.phase, SPIN.Phase.IDLE, "holstering ends the spin")
	check(not spin.zone.monitoring, "and the zone goes off")

# --- reflecting -------------------------------------------------------------------------------

func _ball(spin: Node, pilot: Node, shooter: Node3D) -> Node:
	var ball := PROJECTILE.new()
	ball.shooter = shooter
	ball.velocity = Vector3(0, 0, -10)
	pilot.get_parent().add_child(ball)
	ball.global_position = spin.spin_centre()
	return ball

func test_a_hit_in_the_window_returns_to_the_shooter() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	_clear_flags(pilot)
	var spin: Node = pilot.reflect_spin
	var shooter := Node3D.new()
	pilot.get_parent().add_child(shooter)
	shooter.global_position = spin.spin_centre() + Vector3(8, 0, 4)
	var ball := _ball(spin, pilot, shooter)
	spin.try_start()
	spin.elapsed = 0.05
	spin.zone.global_position = spin.spin_centre()
	# Physics overlaps do not update headless without a physics frame, so ask the direction rule directly.
	var d: Vector3 = spin.reflect_direction(true, ball.global_position, shooter)
	var want: Vector3 = ((shooter.global_position + Vector3.UP) - ball.global_position).normalized()
	check(d.distance_to(want) < 0.001, "a perfect reflect aims at the shooter")
	ball.reflect(d, true)
	check(ball.reflected and ball.was_perfect, "the ball knows it was turned, perfectly")
	approx(ball.velocity.length(), 10.0, 0.001, "and keeps its speed")
	spin.cancel()
	ball.free()
	shooter.free()

func test_a_late_hit_goes_into_the_cone_around_the_aim() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var spin: Node = pilot.reflect_spin
	var aim: Vector3 = -pilot.camera_3d.global_basis.z
	var worst := 0.0
	for i in 60:
		var d: Vector3 = spin.reflect_direction(false, Vector3.ZERO, null)
		worst = maxf(worst, rad_to_deg(aim.angle_to(d)))
	check(worst <= spin.random_cone_deg + 0.01, "a normal reflect stays in the cone (worst %.1f)" % worst)

func test_a_perfect_with_no_shooter_falls_back_to_the_cone() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var spin: Node = pilot.reflect_spin
	var aim: Vector3 = -pilot.camera_3d.global_basis.z
	var d: Vector3 = spin.reflect_direction(true, Vector3.ZERO, null)
	check(rad_to_deg(aim.angle_to(d)) <= spin.random_cone_deg + 0.01,
		"with nothing to return to, a perfect reflect still goes somewhere sensible")

func test_projectile_contract() -> void:
	var ball := PROJECTILE.new()
	check(ball.is_in_group(&"reflectable"), "a projectile is in the reflectable group")
	eq(ball.collision_layer, 128, "and on the reflectable layer")
	ball.velocity = Vector3(3, 0, 4)
	ball.reflect(Vector3.UP, false)
	check(ball.velocity.distance_to(Vector3.UP * 5.0) < 0.001, "reflect turns it, speed kept")
	ball.free()

func test_zone_watches_the_reflectable_layer_only_while_spinning() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var spin: Node = pilot.reflect_spin
	eq(spin.zone.collision_mask, 128, "the zone sees the reflectable layer")
	eq(spin.zone.collision_layer, 0, "and is on none itself")
	_clear_flags(pilot)
	spin.try_start()
	check(spin.zone.monitoring, "on during a spin")
	spin.cancel()
	check(not spin.zone.monitoring, "off once it ends")
