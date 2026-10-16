extends "res://tests/test_case.gd"

# docs/specs/firing-range.md. The stats, the movement rules, waking and sleeping, the hit hook and
# the bolt's two targets. How it looks and feels is judged in play.

const STATS := preload("res://scripts/range/range_stats.gd")
const DUMMY := preload("res://scripts/range/range_dummy.gd")
const BOLT := preload("res://scripts/range/range_bolt.gd")
const FEEDBACK := preload("res://scripts/range/pilot_hit_feedback.gd")
const RANGE := preload("res://scripts/range/firing_range.gd")
const PILOT_TSCN := "res://scenes/pilot9.tscn"


func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root


func _range() -> Node:
	var r: Node = (load("res://scenes/firing_range.tscn") as PackedScene).instantiate()
	_root().add_child(r)
	return r


# --- stats ------------------------------------------------------------------------------------

func test_stats_count_and_reset() -> void:
	var s = STATS.new()
	s.record_dummy_hit(20.0, 1.0)
	s.record_dummy_hit(50.0, 2.0)
	s.record_pilot_hit()
	s.record_reflect(true)
	s.record_reflect(false)
	s.record_reflect(false)
	eq(s.damage_dealt, 70.0, "damage adds up")
	eq(s.hits_on_dummy, 2, "hits on the dummy")
	eq(s.hits_taken, 1, "hits taken")
	eq(s.reflects_perfect, 1, "perfect reflects")
	eq(s.reflects_normal, 2, "normal reflects")
	s.reset()
	eq(s.damage_dealt + s.hits_on_dummy + s.hits_taken + s.reflects_perfect + s.reflects_normal, 0,
		"reset clears every total")


func test_dps_is_a_sliding_window() -> void:
	var s = STATS.new()
	s.record_dummy_hit(30.0, 10.0)
	approx(s.dps(11.0), 10.0, 0.001, "30 damage over the 3 s window is 10 DPS")
	approx(s.dps(14.0), 0.0, 0.001, "the hit has aged out of the window")


# --- movement rules ---------------------------------------------------------------------------

func test_range_velocity_dead_band_and_direction() -> void:
	eq(DUMMY.range_velocity(14.0, 14.0, 1.5, 3.0), 0.0, "on range: still")
	eq(DUMMY.range_velocity(15.4, 14.0, 1.5, 3.0), 0.0, "inside the band: still")
	check(DUMMY.range_velocity(25.0, 14.0, 1.5, 3.0) > 0.0, "too far: closes in")
	check(DUMMY.range_velocity(5.0, 14.0, 1.5, 3.0) < 0.0, "too close: backs off")
	approx(DUMMY.range_velocity(40.0, 14.0, 1.5, 3.0), 3.0, 0.001, "caps at range_speed")


func test_clamp_to_bounds_keeps_the_dummy_on_the_slab() -> void:
	var p: Vector3 = DUMMY.clamp_to_bounds(Vector3(99.0, 2.0, -99.0), Vector3(10.0, 0.0, 20.0), 5.0)
	eq(p, Vector3(15.0, 2.0, 15.0), "pinned to the square, height untouched")
	var inside: Vector3 = DUMMY.clamp_to_bounds(Vector3(11.0, 0.0, 21.0), Vector3(10.0, 0.0, 20.0), 5.0)
	eq(inside, Vector3(11.0, 0.0, 21.0), "inside stays put")


# --- waking and sleeping ----------------------------------------------------------------------

func test_dummy_starts_dormant_and_ignores_hits() -> void:
	var r := _range()
	eq(r.dummy.state, DUMMY.State.DORMANT, "dormant until pilot arrives")
	var got := []
	r.dummy.hit.connect(func(a, k, p): got.append(a))
	r.dummy.take_hit(20.0, &"reflect", Vector3.ZERO)
	check(got.is_empty(), "a dormant dummy reports no hits")
	r.free()


func test_enter_wakes_and_leave_sleeps_and_clears_bolts() -> void:
	var r := _range()
	var ps := load(PILOT_TSCN) as PackedScene
	var pilot := ps.instantiate()
	_root().add_child(pilot)
	r.enter(pilot)
	check(r.dummy.is_awake(), "stepping on wakes the dummy")
	check(r.pilot_on_slab, "the range knows he is on")
	var bolt := BOLT.new()
	_root().add_child(bolt)
	r.leave()
	eq(r.dummy.state, DUMMY.State.DORMANT, "leaving sends it dormant")
	check(not r.pilot_on_slab, "the range knows he left")
	check(bolt.is_queued_for_deletion(), "bolts in flight are cleared")
	pilot.free()
	r.free()


func test_waking_delays_the_first_shot() -> void:
	var r := _range()
	var d = r.dummy
	var pilot := (load(PILOT_TSCN) as PackedScene).instantiate()
	_root().add_child(pilot)
	pilot.global_position = r.global_position + Vector3(0, 0, 14)
	r.enter(pilot)
	check(d.state == DUMMY.State.WAKING, "waking, not yet active")
	for i in 30:
		d._physics_process(1.0 / 60.0)
	check(d.state == DUMMY.State.WAKING, "still powering on half a second in")
	for i in 40:
		d._physics_process(1.0 / 60.0)
	eq(d.state, DUMMY.State.ACTIVE, "active after the wake delay")
	pilot.free()
	r.free()


func test_frozen_dummy_does_not_move() -> void:
	var r := _range()
	var d = r.dummy
	var pilot := (load(PILOT_TSCN) as PackedScene).instantiate()
	_root().add_child(pilot)
	pilot.global_position = r.global_position + Vector3(0, 0, 14)
	r.enter(pilot)
	d.state = DUMMY.State.ACTIVE
	d.frozen = true
	var before: Vector3 = d.global_position
	for i in 30:
		d._physics_process(1.0 / 60.0)
	eq(d.global_position, before, "frozen holds still")
	d.frozen = false
	for i in 30:
		d._physics_process(1.0 / 60.0)
	check(d.global_position.distance_to(before) > 0.5, "unfrozen it strafes")
	pilot.free()
	r.free()


func test_dummy_faces_pilot_and_stays_in_bounds() -> void:
	var r := _range()
	var d = r.dummy
	var pilot := (load(PILOT_TSCN) as PackedScene).instantiate()
	_root().add_child(pilot)
	pilot.global_position = r.global_position + Vector3(0, 0, 14)
	r.enter(pilot)
	d.state = DUMMY.State.ACTIVE
	var inside := true
	for i in 600:
		d._physics_process(1.0 / 60.0)
		var local: Vector3 = d.global_position - r.global_position
		if absf(local.x) > 25.0 or absf(local.z) > 25.0:
			inside = false
	check(inside, "ten seconds of strafing never leaves the slab")
	var to: Vector3 = pilot.global_position - d.global_position
	to.y = 0.0
	var facing: Vector3 = d.global_transform.basis.z
	check(facing.dot(to.normalized()) > 0.99, "it faces pilot")
	pilot.free()
	r.free()


# --- hits -------------------------------------------------------------------------------------

func test_awake_dummy_reports_a_hit_and_never_dies() -> void:
	var r := _range()
	r.dummy.state = DUMMY.State.ACTIVE
	var got := []
	r.dummy.hit.connect(func(a, k, p): got.append([a, k]))
	for i in 1000:
		r.dummy.take_hit(50.0, &"reflect_perfect", Vector3.ZERO)
	eq(got.size(), 1000, "every hit is reported")
	check(is_instance_valid(r.dummy) and r.dummy.is_awake(), "a thousand hits and it is still there")
	r.free()


func test_range_counts_a_dummy_hit() -> void:
	var r := _range()
	r.dummy.state = DUMMY.State.ACTIVE
	r.dummy.take_hit(50.0, &"reflect_perfect", Vector3.ZERO)
	eq(r.stats.damage_dealt, 50.0, "the HUD total follows the dummy's hits")
	eq(r.stats.hits_on_dummy, 1, "one hit counted")
	r.free()


func test_pilot_take_hit_emits_and_does_not_hurt() -> void:
	var pilot := (load(PILOT_TSCN) as PackedScene).instantiate()
	_root().add_child(pilot)
	var got := []
	pilot.hit_taken.connect(func(a, k, p): got.append(k))
	var hp_before: Vector3 = pilot.velocity
	pilot.take_hit(0.0, &"range_bolt", Vector3.ZERO)
	eq(got, [&"range_bolt"], "hit_taken fires")
	eq(pilot.velocity, hp_before, "a hit does not push him")
	pilot.free()


func test_bolt_meets_the_reflect_contract() -> void:
	var b := BOLT.new()
	check(b.is_in_group(&"reflectable"), "in the reflectable group")
	eq(b.collision_layer, 128, "on the reflectable layer")
	check(b.has_method(&"reflect"), "answers reflect()")
	b.velocity = Vector3(0, 0, 28)
	b.reflect(Vector3(1, 0, 0), true)
	check(b.reflected and b.was_perfect, "reflect records the turn")
	approx(b.velocity.length(), 28.0, 0.001, "speed is kept")
	approx(b.velocity.x, 28.0, 0.001, "now flying the new way")
	b.free()


func test_bolt_hurts_the_pilot_only_before_reflect() -> void:
	var pilot := (load(PILOT_TSCN) as PackedScene).instantiate()
	_root().add_child(pilot)
	var got := []
	pilot.hit_taken.connect(func(a, k, p): got.append(k))
	var hurtbox: Area3D = pilot.get_node("Hurtbox")
	var b := BOLT.new()
	_root().add_child(b)
	b._on_area_entered(hurtbox)
	eq(got.size(), 1, "an unreflected bolt hurts him")
	var b2 := BOLT.new()
	_root().add_child(b2)
	b2.reflected = true
	b2._on_area_entered(hurtbox)
	eq(got.size(), 1, "a reflected bolt no longer hurts him")
	pilot.free()


func test_reflected_bolt_hurts_the_dummy_with_perfect_damage() -> void:
	var r := _range()
	r.dummy.state = DUMMY.State.ACTIVE
	var b := BOLT.new()
	_root().add_child(b)
	b.reflected = true
	b.was_perfect = true
	b._on_area_entered(r.dummy.get_node("Hitbox"))
	eq(r.stats.damage_dealt, 50.0, "a perfect reflect deals the perfect damage")
	var b2 := BOLT.new()
	_root().add_child(b2)
	b2._on_area_entered(r.dummy.get_node("Hitbox"))
	eq(r.stats.hits_on_dummy, 1, "an unreflected bolt does not hurt its own shooter")
	r.free()


func test_flash_and_vignette_curves() -> void:
	check(FEEDBACK.flash_color(0.0).r > 0.9 and FEEDBACK.flash_color(0.0).g > 0.9, "starts white")
	check(FEEDBACK.flash_color(0.1).g < 0.3, "then red")
	approx(FEEDBACK.flash_color(1.0).a, 0.0, 0.001, "gone by the end")
	check(FEEDBACK.vignette_strength(0.0) > FEEDBACK.vignette_strength(0.2), "the vignette fades")
	eq(FEEDBACK.vignette_strength(5.0), 0.0, "and ends")


func test_hud_text_lists_every_stat() -> void:
	var s = STATS.new()
	s.record_dummy_hit(50.0, 0.0)
	s.record_pilot_hit()
	s.record_reflect(true)
	var t: String = RANGE.hud_text(s, 0.0, true)
	check("50" in t and "FROZEN" in t and "1 perfect" in t, "damage, frozen flag and reflects shown")


func test_perfect_reflect_steers_onto_a_moving_shooter() -> void:
	var v: Vector3 = BOLT.steer_toward(Vector3(0, 0, -28), Vector3.ZERO, Vector3(10, 0, -10), 0.5)
	check(v.x > 0.0, "it turns toward a target off to the side")
	approx(v.length(), 28.0, 0.001, "speed is kept")
	eq(BOLT.steer_toward(Vector3(0, 0, -28), Vector3.ZERO, Vector3(0, 0, -10), 0.5), Vector3(0, 0, -28),
		"already on target: unchanged")
