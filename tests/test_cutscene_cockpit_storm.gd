extends "res://tests/test_case.gd"

# docs/specs/cutscene-cockpit-storm.md. Timing, the locked-off camera, the storm's ramp, the
# lightning, the route panel and his taps on it, the strip presses, the buzz growing. How it looks is
# judged by eye (tests/_probe_cockpit_storm_shot.gd).

const SCENE := "res://scenes/cockpit_storm.tscn"


func _shot() -> Node3D:
	var s: Node3D = (load(SCENE) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	return s


func _driver(s: Node3D) -> CockpitStormDriver:
	return s.get_node("Storm")


func test_root_is_named_cockpit_storm() -> void:
	var s := _shot()
	eq(s.name, "CockpitStorm", "root node")
	s.free()


func test_shot_is_ten_seconds_and_autoplays() -> void:
	var s := _shot()
	var ap: AnimationPlayer = s.get_node("AnimationPlayer")
	approx(ap.get_animation(&"shot").length, 10.0, 0.001, "10 s shot")
	eq(ap.current_animation, "shot", "plays on load")
	check(not ap.get_animation(&"shot").loop_mode, "plays once")
	s.free()


func test_finished_fires_at_the_end() -> void:
	var s := _shot()
	var fired := [false]
	s.connect(&"finished", func() -> void: fired[0] = true)
	var ap: AnimationPlayer = s.get_node("AnimationPlayer")
	ap.seek(9.99, true)
	ap.advance(0.05)
	check(fired[0], "finished emitted")
	s.free()


func test_camera_is_locked_off() -> void:
	var s := _shot()
	var cam: Camera3D = s.get_node("Camera3D")
	var rest := cam.global_transform
	for t in [0.0, 1.9, 4.15, 7.5, 9.9]:
		_driver(s).apply(t)
		check(cam.global_transform.is_equal_approx(rest), "camera still at %.2f s" % t)
	s.free()


func test_storm_eases_in_from_three_to_seven() -> void:
	var b := StormBeats.new()
	approx(b.storm(0.0), 0.0, 1e-6, "soft at the start")
	approx(b.storm(3.0), 0.0, 1e-6, "still soft at 3 s")
	approx(b.storm(5.0), 0.5, 1e-6, "halfway at 5 s")
	approx(b.storm(7.0), 1.0, 1e-6, "full at 7 s")
	approx(b.storm(10.0), 1.0, 1e-6, "held to the end")


# The ship never speeds up: the snow streams at one cruise speed all shot, and it streams from one
# fixed way, so the vanishing point stays put behind his head.
func test_snow_streams_at_one_speed_from_one_way() -> void:
	var b := StormBeats.new()
	var calm := b.travel(2.0) - b.travel(1.0)
	var full := b.travel(9.0) - b.travel(8.0)
	check(calm > 0.0, "streams forward")
	approx(full, calm, 1e-5, "same speed in the storm as in the calm")
	check(b.source_dir(0.0).is_equal_approx(b.source_dir(9.0)), "vanishing point never moves")


func test_lightning_pops_twice_in_the_blizzard() -> void:
	var b := StormBeats.new()
	approx(b.flash(7.5), 1.0, 1e-6, "first strike")
	approx(b.flash(9.0), 1.0, 1e-6, "second strike")
	approx(b.flash(5.0), 0.0, 1e-6, "none before")
	check(b.flash(8.3) < 0.01, "gone between")


func test_route_panel_pops_takes_two_taps_and_folds() -> void:
	var s := _shot()
	var d := _driver(s)
	var route: HoloPanel = s.get_node("Holo").route
	check(route != null, "route panel built")
	d.apply(0.9)
	check(not route.visible, "hidden before 1 s")
	d.apply(1.5)
	check(route.visible, "up at 1.5 s")
	eq(route.display.route_taps, 0, "no taps yet")
	d.apply(2.0)
	eq(route.display.route_taps, 1, "first tap")
	d.apply(2.45)
	eq(route.display.route_taps, 2, "second tap")
	check(route.display.route_confirm > 0.5, "confirm flash")
	d.apply(3.0)
	check(not route.visible, "folded away")
	s.free()


func test_fire_shot_has_no_route_panel() -> void:
	var s: Node3D = (load("res://scenes/cockpit.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	check(s.get_node("Holo").route == null, "no route panel in the fire shot")
	s.free()


# On each tap the right wrist is pressed into its button; off the beats it is on the stick.
func test_right_hand_taps_the_two_buttons() -> void:
	var s := _shot()
	var b := _driver(s).beats
	var seat: CockpitSeat = s.get_node("Seat")
	for i in b.taps.size():
		var hover := b.buttons[i] + b.tap_offset
		var w := b.right_wrist(b.taps[i])
		approx(w.distance_to(hover), b.press_depth, 1e-4, "tap %d presses in" % i)
	check(b.right_wrist(1.0).is_equal_approx(seat.right_wrist_target), "on the stick before")
	check(b.right_wrist(3.3).is_equal_approx(seat.right_wrist_target), "back on the stick after")
	s.free()


func test_left_hand_presses_three_slots_and_they_stay_lit() -> void:
	var s := _shot()
	var d := _driver(s)
	var b := d.beats
	var seat: CockpitSeat = s.get_node("Seat")
	eq(b.slots.size(), 3, "three slots")
	for i in b.presses.size():
		var w := b.left_wrist(b.presses[i])
		approx(w.y, b.slots[i].y + b.press_offset.y - b.press_depth, 1e-4, "press %d goes down" % i)
		check(not b.slot_lit(b.presses[i] - 0.01, i), "slot %d dark before" % i)
	check(b.left_wrist(3.4).is_equal_approx(seat.left_wrist_target), "on the stick before")
	check(b.left_wrist(5.1).is_equal_approx(seat.left_wrist_target), "back on the stick after")
	d.apply(9.0)
	var lamp := (seat.get_node("ButtonSlots%d" % d.pressed_slots[0]) as MeshInstance3D).material_override
	check((lamp as StandardMaterial3D).albedo_color.is_equal_approx(CockpitStormDriver.SLOT_LIT), "still lit at 9 s")
	s.free()


func test_seat_buzz_grows_with_the_storm() -> void:
	var d := CockpitStormDriver.new()
	var s := _shot()
	var shake := _driver(s).shake
	var soft := 0.0
	var full := 0.0
	for k in 50:
		soft = maxf(soft, shake.seat_motion(1.0 + k * 0.013).move.length())
		full = maxf(full, shake.seat_motion(8.0 + k * 0.013).move.length())
	check(full > soft * 2.5, "buzz at least 2.5x bigger in the storm")
	check(full < soft * 4.5, "but not the old 5x")
	check(full < 0.01, "still under a centimetre")
	d.free()
	s.free()


# He reacts to the route panel like a relaxed pilot, not a snap: still eyes front a beat after it
# pops, looking at it by the first tap.
func test_he_looks_at_the_panel_a_beat_after_it_pops() -> void:
	var b := StormBeats.new()
	approx(b.glance(b.route_pop + 0.2), 0.0, 1e-6, "not turned yet just after the pop")
	check(b.glance(b.taps[0]) > 0.99, "looking at it by the first tap")


# A small glance down and to his left over the strip presses, gone after.
func test_he_glances_down_left_at_the_strip() -> void:
	var b := StormBeats.new()
	var look := b.head_look(b.presses[1])
	check(look.x > deg_to_rad(8.0) and look.x < deg_to_rad(20.0), "a little down, not all the way")
	check(look.y > deg_to_rad(5.0), "a little to his left")
	approx(b.strip_glance(3.0), 0.0, 1e-6, "eyes front before the hand leaves")
	approx(b.strip_glance(5.5), 0.0, 1e-6, "eyes front after the presses")
