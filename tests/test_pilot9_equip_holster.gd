extends "res://tests/test_case.gd"

# docs/specs/pilot9-staff-materialize.md. The gates, the timeline, the handovers and the sweep.
# How it looks is judged in play.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const STAFF := "res://resources/items/staff.tres"
const ANIM := preload("res://scripts/items/equip_anim.gd")

var _pilot: Node = null

# One shared in-tree instance, staff holstered, nothing playing, every flag clear.
func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		var loop := Engine.get_main_loop() as SceneTree
		if loop:
			loop.root.add_child(_pilot)
	_pilot.is_climbing = false
	_pilot.is_vaulting = false
	_pilot.is_wall_running = false
	_pilot.frozen = false
	_pilot.equip_anim.finish_now()
	_pilot.reflect_spin.cancel()
	if _pilot.item_holder.held_item == null:
		_pilot.set_item(load(STAFF))
	if _pilot.is_item_drawn():
		_pilot.toggle_drawn()
	return _pilot

func _step(anim: Node, seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in int(ceil(seconds / dt)):
		anim._process(dt)

func _near(a: Transform3D, b: Transform3D, eps: float) -> bool:
	return a.origin.distance_to(b.origin) < eps and (a.basis.y.normalized() - b.basis.y.normalized()).length() < eps

# --- pure helpers -----------------------------------------------------------------------------

func test_can_start_needs_every_gate() -> void:
	check(ANIM.can_start(true, true, false), "all gates open should start")
	check(not ANIM.can_start(false, true, false), "not while one is playing")
	check(not ANIM.can_start(true, false, false), "not with no item")
	check(not ANIM.can_start(true, true, true), "not in a mantle, vault or wall-run")

func test_sweep_grows_only_during_the_sweep() -> void:
	check(is_zero_approx(ANIM.sweep_fraction(0.1, 0.15, 0.2)), "nothing in his hand while the arm goes out")
	check(is_equal_approx(ANIM.sweep_fraction(0.35, 0.15, 0.2), 1.0), "full length when the sweep ends")
	var last := 0.0
	for i in 51:
		var f: float = ANIM.sweep_fraction(i * 0.01, 0.15, 0.2)
		check(f >= last - 0.000001, "the staff never shrinks on a draw")
		last = f

func test_arm_weight_goes_out_holds_then_settles() -> void:
	check(is_zero_approx(ANIM.arm_weight(0.0, 0.15, 0.2, 0.15, 0.4)), "the arm starts free")
	check(is_equal_approx(ANIM.arm_weight(0.15, 0.15, 0.2, 0.15, 0.4), 1.0), "fully out when the sweep starts")
	check(is_equal_approx(ANIM.arm_weight(0.3, 0.15, 0.2, 0.15, 0.4), 1.0), "held out through the sweep")
	check(is_equal_approx(ANIM.arm_weight(0.5, 0.15, 0.2, 0.15, 0.4), 0.4), "ends at the drawn arm's weight")

func test_shape_ends_on_the_hold_whatever_the_weight() -> void:
	for w in [0.0, 0.3, 1.0]:
		check(is_zero_approx(ANIM.shape_fraction(0.0, w)), "arm-out at the start of the arm back")
		check(is_equal_approx(ANIM.shape_fraction(1.0, w), 1.0), "the hold at the end, weight %s" % w)

func test_flick_is_a_bump_at_the_sweep_start() -> void:
	check(is_zero_approx(ANIM.flick_amount(0.1, 0.15, 0.12)), "no flick before the sweep")
	check(ANIM.flick_amount(0.21, 0.15, 0.12) > 0.9, "peaks mid-flick")
	check(is_zero_approx(ANIM.flick_amount(0.3, 0.15, 0.12)), "over before the sweep ends")

func test_arm_out_points_down_right_and_forward() -> void:
	# Skeleton space: facing +Z, his right -X.
	var d: Vector3 = ANIM.upper_arm_dir(35.0, 20.0)
	check(d.y < -0.5 and d.x < -0.3 and d.z > 0.1, "upper arm down, out to his right and a bit forward: %s" % d)
	var f: Vector3 = ANIM.forearm_dir(d, 25.0)
	check(f.z > d.z and is_equal_approx(rad_to_deg(d.angle_to(f)), 25.0), "the forearm bends further forward")

# --- in the scene -------------------------------------------------------------------------------

func test_equip_draws_only_when_it_ends() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var anim: Node = pilot.equip_anim
	check(anim.ready_to_play(), "the equip animation should be built on the rig")
	check(pilot.press_equip(), "R should start the draw")
	check(anim.is_playing(), "the draw should be playing")
	_step(anim, anim.total_time() * 0.6)
	check(not pilot.is_item_drawn(), "the staff should not count as drawn mid-draw")
	_step(anim, anim.total_time())
	check(not anim.is_playing(), "the draw should end")
	check(pilot.is_item_drawn(), "the staff should be drawn when the draw ends")
	check(pilot.item_holder.item_instance.get_parent() == pilot.item_holder.hand_socket,
		"the staff should end in the hand socket")
	check(is_zero_approx(anim.arm_modifier.influence), "the animation's arm should be off after")

func test_holster_undraws_on_the_press_and_ends_hidden() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	pilot.toggle_drawn()
	var anim: Node = pilot.equip_anim
	check(pilot.press_equip(), "R should start the holster")
	check(not pilot.is_item_drawn(), "the staff should stop counting as drawn on the press")
	_step(anim, anim.total_time() + 0.05)
	check(not anim.is_playing(), "the holster should end")
	check(not pilot.is_item_drawn(), "still holstered after")
	var item: Node3D = pilot.item_holder.item_instance
	check(not item.visible, "the staff should be gone")
	check(item.transform.is_equal_approx(pilot.item_holder.held_item.hand_offset), "reset to full length in the hand")
	check(not pilot.equip_anim._edges[0].visible, "the edges should be off")

func test_r_mid_animation_is_ignored() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var anim: Node = pilot.equip_anim
	pilot.press_equip()
	_step(anim, 0.1)
	var t: float = anim.t
	check(not pilot.press_equip(), "a second R mid-draw should be ignored")
	check(anim.direction == 1 and is_equal_approx(anim.t, t), "the draw should carry on untouched")

func test_blocked_moves_ignore_the_press() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	for flag in [&"is_climbing", &"is_vaulting", &"is_wall_running"]:
		pilot.set(flag, true)
		check(not pilot.press_equip(), "R should be ignored while %s" % flag)
		check(not pilot.equip_anim.is_playing() and not pilot.is_item_drawn(), "nothing should change while %s" % flag)
		pilot.set(flag, false)

func test_a_blocked_move_mid_draw_finishes_it_drawn() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var anim: Node = pilot.equip_anim
	pilot.press_equip()
	_step(anim, 0.2)
	pilot.is_wall_running = true
	_step(anim, 1.0 / 60.0)
	check(not anim.is_playing(), "a wall-run should end the draw at once")
	check(pilot.is_item_drawn(), "an interrupted draw lands drawn")
	pilot.is_wall_running = false

func test_a_blocked_move_mid_holster_finishes_it_holstered() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	pilot.toggle_drawn()
	var anim: Node = pilot.equip_anim
	pilot.press_equip()
	_step(anim, 0.2)
	pilot.is_vaulting = true
	_step(anim, 1.0 / 60.0)
	check(not anim.is_playing(), "a vault should end the holster at once")
	check(not pilot.is_item_drawn(), "an interrupted holster lands holstered")
	check(not pilot.item_holder.item_instance.visible, "gone")
	pilot.is_vaulting = false

func test_reflect_is_ignored_during_the_animation() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	pilot.press_equip()
	_step(pilot.equip_anim, 0.3)
	check(not pilot.reflect_spin.try_start(), "no reflect mid-draw")
	pilot.equip_anim.finish_now()
	pilot.press_equip()
	_step(pilot.equip_anim, 0.1)
	check(not pilot.reflect_spin.try_start(), "no reflect mid-holster")

func test_the_staff_forms_from_nothing_to_full_length() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var anim: Node = pilot.equip_anim
	var item: Node3D = pilot.item_holder.item_instance
	pilot.press_equip()
	check(not item.visible, "nothing in his hand at the press")
	_step(anim, anim.out_time * 0.5)
	check(not item.visible, "still nothing while the arm goes out")
	check(anim.arm_modifier.influence > 0.0, "the arm is going out")
	_step(anim, anim.out_time * 0.5 + anim.sweep_time * 0.4)
	check(item.visible, "forming mid-sweep")
	var len_y: float = item.transform.basis.get_scale().y
	check(len_y > 0.05 and len_y < 0.99, "part grown mid-sweep: %s" % len_y)
	check(anim._edges[0].visible and anim._edges[1].visible, "both cyan edges ride the ends")
	_step(anim, anim.total_time())
	check(item.visible and item.transform.is_equal_approx(pilot.item_holder.held_item.hand_offset),
		"full length in the hand at the end")
	check(not anim._edges[0].visible, "edges gone at the end")

func test_toggle_drawn_still_snaps() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	pilot.toggle_drawn()
	check(pilot.is_item_drawn() and not pilot.equip_anim.is_playing(), "toggle_drawn() stays an instant draw")

func test_a_snap_mid_animation_finishes_it_first() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	pilot.press_equip()
	_step(pilot.equip_anim, 0.1)
	pilot.set_item(load(STAFF))
	check(not pilot.equip_anim.is_playing(), "an item swap should end the draw")
	check(pilot.is_item_drawn(), "and keep it drawn, as the draw would have")
