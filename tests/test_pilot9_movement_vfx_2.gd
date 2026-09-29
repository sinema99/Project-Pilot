extends "res://tests/test_case.gd"

# Covers pass 2 of pilot9's movement effects - WHEN each one fires, never what it looks like.
# See "Pass 2" in docs/specs/pilot9-movement-vfx.md.
#
# Same rules as tests/test_pilot9_movement_vfx.gd: the dummy renderer runs no particles, and
# is_on_floor() cannot be made true headlessly, so the floor-only sprint kicks are fenced
# through their pure halves.

const PILOT := preload("res://scripts/pilot9.gd")
const PILOT_TSCN := "res://scenes/pilot9.tscn"
const FAR := Vector3(-520.0, 50.0, 520.0)
const DT := 1.0 / 60.0

var _pilot: Node = null

func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		(Engine.get_main_loop() as SceneTree).root.add_child(_pilot)
	_pilot._end_rail_grind(PILOT.RailExit.LOST)
	_pilot._end_wall_run()
	_pilot.is_sliding = false
	_pilot.is_dashing = false
	_pilot.is_jumping = false
	_pilot.frozen = false
	_pilot.velocity = Vector3.ZERO
	_pilot._laser_on = false
	_pilot._laser_ease = 0.0
	_pilot._wall_kick_point = Vector3.ZERO
	_pilot.global_position = FAR
	Settings.set_value(&"movement_effects", "on")
	_pilot._update_movement_vfx(DT)
	_clear_bursts(_pilot)
	_vfx(_pilot)._bolts.clear()
	return _pilot

func end() -> void:
	Settings.set_value(&"movement_effects", "on")
	super()

func _vfx(p: Node) -> Node:
	return p.get_node_or_null("MovementVfx")

func _clear_bursts(p: Node) -> void:
	var v := _vfx(p)
	if v == null:
		return
	for c in v.get_children():
		if c.has_meta(&"persistent"):
			continue
		v.remove_child(c)
		c.free()

func _bursts(p: Node, prefix: String) -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	var v := _vfx(p)
	if v == null:
		return out
	for c in v.get_children():
		if c is GPUParticles3D and c.name.begins_with(prefix):
			out.append(c)
	return out

func _at_speed(p: Node, speed: float) -> void:
	p.velocity = Vector3(0.0, 0.0, -speed)
	p._update_movement_vfx(DT)

# --- the node --------------------------------------------------------------------

func test_the_pilot_builds_the_new_streams() -> void:
	var p := _scene()
	var v := _vfx(p)
	for n in ["SpeedLasers", "SlideSparks", "SlideLight", "WallDust"]:
		var node := v.get_node_or_null(n)
		check(node != null, "%s is missing" % n)
		if node:
			check(node.has_meta(&"persistent"), "%s should be marked persistent" % n)

# --- the lasers ------------------------------------------------------------------

func test_the_laser_latch_has_a_gap() -> void:
	check(not PILOT._laser_latch(false, 8.5, 8.5, 8.0), "exactly the on-speed is not over it")
	check(PILOT._laser_latch(false, 8.6, 8.5, 8.0), "over the on-speed turns it on")
	check(PILOT._laser_latch(true, 8.2, 8.5, 8.0), "once on, it holds inside the gap")
	check(not PILOT._laser_latch(false, 8.2, 8.5, 8.0), "off, the gap does not turn it on")
	check(not PILOT._laser_latch(true, 7.9, 8.5, 8.0), "under the off-speed turns it off")

func test_the_speed_ramp() -> void:
	approx(PILOT._speed_ramp(8.5, 8.5, 20.0), 0.0, 1e-6, "barely there at the on-speed")
	approx(PILOT._speed_ramp(20.0, 8.5, 20.0), 1.0, 1e-6, "heavy at full speed")
	approx(PILOT._speed_ramp(40.0, 8.5, 20.0), 1.0, 1e-6, "clamped past full")
	check(PILOT._speed_ramp(20.0, 8.5, 20.0) > PILOT._speed_ramp(15.0, 8.5, 20.0),
		"a rail sprint should fire harder than a grind")

func test_sprint_speed_is_calm() -> void:
	var p := _scene()
	_at_speed(p, p.sprint_speed)
	check(not _vfx(p).is_firing(), "a plain sprint should not fire")

func test_the_lasers_come_on_hold_and_go() -> void:
	var p := _scene()
	var v := _vfx(p)
	_at_speed(p, 9.0)
	check(v.is_firing(), "over 8.5 m/s they should fire")
	_at_speed(p, 8.2)
	check(v.is_firing(), "inside the gap they should hold")
	_at_speed(p, 7.9)
	check(not v.is_firing(), "under 8.0 they should stop")

func test_the_lasers_ease_in() -> void:
	var p := _scene()
	_at_speed(p, 12.0)
	check(p._laser_ease > 0.0 and p._laser_ease < 1.0, "one frame in, they are still easing (%s)"
		% p._laser_ease)
	for i in 20:
		_at_speed(p, 12.0)
	approx(p._laser_ease, 1.0, 1e-6, "after the fade-in they are full")

func test_bolts_shoot_back_and_flare_out() -> void:
	var p := _scene()
	var v := _vfx(p)
	for i in 30:
		_at_speed(p, 20.0)
	v._process(0.05)
	var spans: Array[PackedVector3Array] = v.bolt_spans()
	check(spans.size() > 0, "half a second at 20 m/s should have fired bolts")
	var chest: Vector3 = p.global_position + Vector3.UP * p.vfx_laser_chest_height
	var back := Vector3.BACK
	for s in spans:
		var dir := (s[1] - s[0]).normalized()
		var deg := rad_to_deg(dir.angle_to(back))
		# 20 degrees at full speed, less round the squashed top and bottom of the cone.
		check(deg > 10.0 and deg < 21.0, "a bolt should flare 10-21 deg off straight back (%.1f)"
			% deg)
		check((s[0] - chest).dot(back) > 0.0, "a bolt should start behind his chest")
		var off := (s[1] - chest) - back * (s[1] - chest).dot(back)
		check(off.length() > p.vfx_laser_ring_radius * 0.5,
			"no bolt should run down his centreline (%.2f m off)" % off.length())

func test_more_speed_fires_more() -> void:
	var p := _scene()
	var v := _vfx(p)
	for i in 60:
		_at_speed(p, 9.0)
	var slow: int = v.bolt_spans().size()
	v._bolts.clear()
	for i in 60:
		_at_speed(p, 20.0)
	var fast: int = v.bolt_spans().size()
	check(fast > slow * 2, "a second at 20 m/s should fire far more than at 9 (%d vs %d)"
		% [fast, slow])

func test_no_bolt_comes_near_the_lens() -> void:
	var p := _scene()
	var v := _vfx(p)
	var chest: Vector3 = FAR + Vector3.UP * p.vfx_laser_chest_height
	# The worst case: the camera straight down the line the bolts fire along.
	var eye := chest + Vector3.BACK * 3.5
	v.lasers(true, chest, Vector3.BACK, 1.0, 1.0, Vector3.ZERO, eye, 2.0)
	check(v.bolt_spans().size() > 10, "most angles should still be clear (%d fired)"
		% v.bolt_spans().size())
	var closest := INF
	for step in 30:
		for s in v.bolt_spans():
			var near := Geometry3D.get_closest_point_to_segment(eye, s[0], s[1])
			closest = minf(closest, near.distance_to(eye))
		v._process(0.01)
	check(closest >= p.vfx_laser_camera_clear * 0.95,
		"no bolt should come within the clear zone (closest %.2f m)" % closest)

func test_bolts_run_out() -> void:
	var p := _scene()
	var v := _vfx(p)
	for i in 30:
		_at_speed(p, 20.0)
	check(v.bolt_spans().size() > 0, "bolts should be live")
	v._process(p.vfx_laser_lifetime * 1.2)
	eq(v.bolt_spans().size(), 0, "after their life every bolt should be gone")

func test_a_fall_is_not_speed() -> void:
	var p := _scene()
	p.velocity = Vector3(0.0, -25.0, 0.0)
	p._update_movement_vfx(DT)
	check(not _vfx(p).is_firing(), "straight down is the landing dip's, not the lasers'")

func test_the_dash_stops_new_bolts_only() -> void:
	var p := _scene()
	var v := _vfx(p)
	for i in 30:
		_at_speed(p, 20.0)
	var live: int = v.bolt_spans().size()
	p.is_dashing = true
	for i in 10:
		_at_speed(p, 40.0)
	check(not v.is_firing(), "the afterimages own the dash")
	eq(v.bolt_spans().size(), live, "bolts already fired should fly on, none added")
	p.is_dashing = false
	_at_speed(p, 12.0)
	check(v.is_firing(), "still fast after the dash, they should pick back up")

# --- the slide -------------------------------------------------------------------

func test_a_fast_slide_sparks_and_lights() -> void:
	var p := _scene()
	var v := _vfx(p)
	p.is_sliding = true
	_at_speed(p, 8.0)
	check(v.is_slide_sparking(), "a slide at speed should spark")
	check(v.slide_light().visible, "and light his foot")
	p.is_sliding = false
	_at_speed(p, 8.0)
	check(not v.is_slide_sparking(), "out of the slide the stream stops")
	check(not v.slide_light().visible, "and the light goes out")

func test_a_slow_slide_tail_is_quiet() -> void:
	var p := _scene()
	p.is_sliding = true
	_at_speed(p, 2.5)
	check(not _vfx(p).is_slide_sparking(), "under 3 m/s the tail should not sputter")

func test_a_run_does_not_spark() -> void:
	var p := _scene()
	_at_speed(p, 8.0)
	check(not _vfx(p).is_slide_sparking(), "only a slide sparks")

func test_a_slide_start_throws_the_entry_burst() -> void:
	var p := _scene()
	p.velocity = Vector3(0.0, 0.0, -7.5)
	p._start_slide(Vector3(0.0, 0.0, -1.0), true)
	eq(_bursts(p, "SlideSparkBurst").size(), 1, "one shower as the slide starts")

func test_a_slide_from_nothing_does_not_burst() -> void:
	var p := _scene()
	p.velocity = Vector3(0.0, 0.0, -1.0)
	p._start_slide(Vector3(0.0, 0.0, -1.0), true)
	eq(_bursts(p, "SlideSparkBurst").size(), 0, "under the cutoff, no entry burst either")

# --- the wall --------------------------------------------------------------------

func test_the_wall_dust_fades_through_the_droop() -> void:
	approx(PILOT._wall_dust_fade(0.5, 2.0, 0.8), 1.0, 1e-6, "full through the flat run")
	approx(PILOT._wall_dust_fade(2.4, 2.0, 0.8), 0.5, 1e-6, "half way down the droop")
	approx(PILOT._wall_dust_fade(2.8, 2.0, 0.8), 0.0, 1e-6, "gone at the end")
	approx(PILOT._wall_dust_fade(3.0, 2.0, 0.0), 0.0, 1e-6, "no droop, no divide by zero")

func test_a_wall_run_scuffs_and_attaches() -> void:
	var p := _scene()
	var v := _vfx(p)
	p.velocity = Vector3(0.0, 0.0, -7.5)
	p._start_wall_run(Vector3.RIGHT, Vector3.FORWARD, FAR + Vector3(-0.4, 1.0, 0.0))
	eq(_bursts(p, "WallAttachDust").size(), 1, "a puff where he lands on the wall")
	p._update_movement_vfx(DT)
	check(v.is_scuffing(), "the trail should run with him")
	approx(p._wall_kick_point.x, FAR.x - 0.4, 1e-4, "the contact should be on the face")
	p._end_wall_run()
	p._update_movement_vfx(DT)
	check(not v.is_scuffing(), "off the wall the trail stops")

func test_a_coyote_wall_jump_kicks_off_the_wall_not_the_air() -> void:
	var p := _scene()
	var wall := FAR + Vector3(-0.4, 0.0, 0.0)
	p._wall_kick_point = wall
	p._wall_jump_normal = Vector3.RIGHT
	p.global_position = FAR + Vector3(1.5, 0.0, -1.0)     # already well clear of it
	p._take_wall_jump()
	var kicks := _bursts(p, "WallKickDust")
	eq(kicks.size(), 2, "the ring on the face and the push-out puff")
	for k in kicks:
		check(k.global_position.distance_to(wall) < 0.1,
			"the kick belongs on the wall at %s, not at %s" % [wall, k.global_position])

func test_the_wall_jump_ring_lies_on_the_face() -> void:
	var p := _scene()
	p._wall_kick_point = FAR
	p._wall_jump_normal = Vector3.RIGHT
	p._take_wall_jump()
	var ring := _bursts(p, "WallKickDust")
	check(ring.size() > 0, "no kick")
	if ring.size() > 0:
		var m := ring[0].process_material as ParticleProcessMaterial
		approx(m.emission_ring_axis.dot(Vector3.RIGHT), 1.0, 1e-4,
			"the ring's axis should be the wall's normal")

# --- the hands -------------------------------------------------------------------

func test_hand_taps_are_two_either_side() -> void:
	var p := _scene()
	p._emit_hand_taps(FAR, Vector3.FORWARD)
	var taps := _bursts(p, "HandTap")
	eq(taps.size(), 2, "one under each hand")
	if taps.size() == 2:
		approx(absf(taps[0].global_position.x - taps[1].global_position.x),
			2.0 * PILOT.HAND_TAP_HALF_SPREAD, 1e-4, "spread across his facing")

func test_the_mantle_and_vault_tap() -> void:
	var src := FileAccess.open("res://scripts/pilot9.gd", FileAccess.READ).get_as_text()
	var climb := src.find("func _start_climb(")
	check(climb >= 0 and src.substr(climb, 5000).contains("_emit_hand_taps(lip"),
		"the mantle's entry snap should tap the lip")
	var vault := src.find("func _apply_vault_motion(")
	check(vault >= 0 and src.substr(vault, 600).contains("_emit_hand_taps(_vault_hand_top"),
		"the vault should tap on its plant frame")

# --- the sprint kicks ------------------------------------------------------------

func test_a_sprint_start_is_an_edge_on_the_floor() -> void:
	check(PILOT._sprint_started(true, true, false), "breaking into a sprint on the floor")
	check(not PILOT._sprint_started(true, true, true), "already sprinting is not a start")
	check(not PILOT._sprint_started(false, true, false), "not in the air")
	check(not PILOT._sprint_started(true, false, false), "not sprinting is not a start")

func test_a_reversal_inside_the_window_is_a_hard_turn() -> void:
	var h := [[0.0, Vector3(0, 0, -1)]]
	eq(PILOT._hard_turn_from(h, Vector3(0, 0, 1), 0.15, 0.2, 100.0), Vector3(0, 0, -1),
		"a reversal inside 0.2 s should skid, thrown the old way")
	eq(PILOT._hard_turn_from(h, Vector3(0, 0, 1), 0.3, 0.2, 100.0), Vector3.ZERO,
		"the same swing spread over 0.3 s is a curve, not a cut")
	eq(PILOT._hard_turn_from(h, Vector3(1, 0, 0), 0.1, 0.2, 100.0), Vector3.ZERO,
		"a 90 degree cut is under the 100 degree line")

# --- the switch ------------------------------------------------------------------

func test_off_means_no_pass_two_either() -> void:
	var p := _scene()
	var v := _vfx(p)
	Settings.set_value(&"movement_effects", "off")
	p.is_sliding = true
	_at_speed(p, 12.0)
	check(not v.is_firing(), "OFF should stop the lasers")
	check(not v.is_slide_sparking(), "OFF should stop the slide sparks")
	check(not v.slide_light().visible, "OFF should put the slide light out")
	p._start_slide(Vector3.FORWARD, true)
	p._emit_hand_taps(FAR, Vector3.FORWARD)
	p._wall_kick_point = FAR
	p._wall_jump_normal = Vector3.RIGHT
	p._take_wall_jump()
	var bursts := 0
	for c in v.get_children():
		if not c.has_meta(&"persistent"):
			bursts += 1
	eq(bursts, 0, "OFF should spawn no bursts")

func test_boarding_stops_every_stream() -> void:
	var p := _scene()
	var v := _vfx(p)
	p.is_sliding = true
	_at_speed(p, 12.0)
	p._end_verbs_for_boarding()
	check(not v.is_firing(), "no physics frames run aboard, so boarding must stop the lasers")
	check(not v.is_slide_sparking(), "and stop the slide sparks")
