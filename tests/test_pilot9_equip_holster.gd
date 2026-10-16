extends "res://tests/test_case.gd"

# docs/specs/pilot9-equip-holster.md. The gates, the timeline, the handovers and the turn's
# direction. How it looks is judged in play.

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

func test_turn_goes_counter_clockwise_from_behind() -> void:
	# Counter-clockwise seen from behind is a falling angle: the top end goes down his left side.
	var back := deg_to_rad(-37.0)
	var hand := deg_to_rad(147.0)
	var e0: float = ANIM.end_angle(back, hand, 0)
	check(e0 < back and e0 > back - TAU, "with no extra turns it should arrive inside one turn")
	check(is_equal_approx(fposmod(e0, TAU), fposmod(hand, TAU)), "it should end at the in-hand angle")
	var e1: float = ANIM.end_angle(back, hand, 1)
	check(is_equal_approx(e1, e0 - TAU), "each extra turn adds one full turn")

func test_plane_angle_matches_the_turn_basis() -> void:
	for deg in [0.0, 30.0, -80.0, 150.0]:
		var a := deg_to_rad(deg)
		var got: float = ANIM.plane_angle(Basis(Vector3.BACK, a) * Vector3.UP)
		check(is_equal_approx(wrapf(got - a, -PI, PI) + 1.0, 1.0), "plane_angle should invert the turn at %s deg" % deg)

func test_turn_fraction_runs_zero_to_one() -> void:
	check(is_zero_approx(ANIM.turn_fraction(0.0, 0.32, 0.05, 0.08)), "the turn starts at rest")
	check(is_equal_approx(ANIM.turn_fraction(0.32, 0.32, 0.05, 0.08), 1.0), "the turn ends complete")
	var last := 0.0
	for i in 33:
		var f: float = ANIM.turn_fraction(i * 0.01, 0.32, 0.05, 0.08)
		check(f >= last - 0.000001, "the turn never runs backwards")
		last = f

func test_arm_weight_reaches_turns_then_settles() -> void:
	check(is_zero_approx(ANIM.arm_weight(0.0, 0.15, 0.32, 0.08, 0.4)), "the arm starts free")
	check(is_equal_approx(ANIM.arm_weight(0.15, 0.15, 0.32, 0.08, 0.4), 1.0), "the arm is fully back at the grab")
	check(is_equal_approx(ANIM.arm_weight(0.3, 0.15, 0.32, 0.08, 0.4), 1.0), "the arm holds through the turn")
	check(is_equal_approx(ANIM.arm_weight(0.55, 0.15, 0.32, 0.08, 0.4), 0.4), "the settle ends at the drawn arm's weight")

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

func test_holster_undraws_on_the_press_and_lands_on_the_back() -> void:
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
	check(item.get_parent() == pilot.item_holder.back_socket, "the staff should end in the back socket")
	check(item.transform.is_equal_approx(pilot.item_holder.held_item.back_offset), "at the back placement")

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
	check(pilot.item_holder.item_instance.get_parent() == pilot.item_holder.back_socket, "on his back")
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

func test_the_grab_and_the_settle_do_not_pop() -> void:
	var pilot := _scene()
	if pilot == null:
		fail("could not instance pilot9")
		return
	var anim: Node = pilot.equip_anim
	pilot.press_equip()
	var grab: Transform3D = anim.staff_transform(anim.reach_time + 0.0001)
	check(_near(grab, anim.back_transform(), 0.01), "the staff should leave the back from exactly where it sat")
	var end: Transform3D = anim.staff_transform(anim.total_time())
	check(_near(end, anim.hand_transform(), 0.01), "the staff should end exactly in the hand")

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
