extends "res://tests/test_case.gd"

# Covers pilot9's movement effects - WHEN each one fires, never what it looks like. See
# docs/specs/pilot9-movement-vfx.md.
#
# The dummy renderer runs no particles, so the look is the play session's. What these fence is
# the gating that fails silently: the switch that leaves a stream spraying, a coyote jump that
# kicks up dust in mid-air, a bounce pad that dusts, a rail landing that dusts, a switch
# landing that throws the catch's shower, and the dust curve that is meant to be the dip's.

const PILOT := preload("res://scripts/pilot9.gd")
const RAIL_SCRIPT := preload("res://scripts/rail.gd")
const PILOT_TSCN := "res://scenes/pilot9.tscn"
## Far from anything else a test run leaves in the tree, for the rail tests' reason.
const FAR := Vector3(-500.0, 50.0, 500.0)

# One shared in-tree pilot9, for tests/test_pilot9_dash.gd's reason: a fresh in-tree pilot per
# test leaks server RIDs a --script run never cleans up.
var _pilot: Node = null
var _rails: Array[Node] = []

func _scene() -> Node:
	if _pilot == null or not is_instance_valid(_pilot):
		var ps := load(PILOT_TSCN) as PackedScene
		if ps == null:
			return null
		_pilot = ps.instantiate()
		(Engine.get_main_loop() as SceneTree).root.add_child(_pilot)
	_pilot._end_rail_grind(PILOT.RailExit.LOST)
	_pilot._end_rail_switch()
	_pilot.is_sliding = false
	_pilot.is_jumping = false
	_pilot.frozen = false
	_pilot.velocity = Vector3.ZERO
	_pilot._dip_pending_speed = 0.0
	_pilot._land_dust_pending = 0.0
	_pilot.global_position = FAR
	_clear_bursts(_pilot)
	Settings.set_value(&"movement_effects", "on")
	return _pilot

func end() -> void:
	for n in _rails:
		if is_instance_valid(n):
			if n.get_parent():
				n.get_parent().remove_child(n)
			n.free()
	_rails.clear()
	Settings.set_value(&"movement_effects", "on")
	super()

func _vfx(p: Node) -> Node:
	return p.get_node_or_null("MovementVfx")

# The bursts are freed by a timer, and a test never lets one run out.
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

func _rail(origin: Vector3) -> Node:
	var parent := Node3D.new()
	parent.position = origin
	(Engine.get_main_loop() as SceneTree).root.add_child(parent)
	var rail = RAIL_SCRIPT.new()
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO)
	c.add_point(Vector3(0, 0, -10))
	rail.curve = c
	parent.add_child(rail)
	_rails.append(parent)
	return rail

# A landing at `fall` m/s, run through both halves of the hand-off the way a frame does.
func _land(p: Node, fall: float) -> void:
	p._dip_pending_speed = fall
	p._resolve_landing_dip()
	p._emit_landing_dust()

# --- the curves ------------------------------------------------------------------

func test_dust_strength_hits_the_dips_three_anchors() -> void:
	approx(PILOT._landing_dust_strength(5.0, 5.0, 10.0, 28.0), 0.0, 1e-6,
		"at the dip's minimum speed there should be no dust")
	approx(PILOT._landing_dust_strength(3.0, 5.0, 10.0, 28.0), 0.0, 1e-6,
		"a step-down should get no dust")
	approx(PILOT._landing_dust_strength(10.0, 5.0, 10.0, 28.0), 0.5, 1e-6,
		"a full jump's landing should be the halfway mark - side puffs, no ring")
	approx(PILOT._landing_dust_strength(28.0, 5.0, 10.0, 28.0), 1.0, 1e-6,
		"terminal velocity should be full strength")
	approx(PILOT._landing_dust_strength(60.0, 5.0, 10.0, 28.0), 1.0, 1e-6,
		"faster than terminal should clamp, not grow")

func test_gear_weight_ramps_between_the_gears() -> void:
	approx(PILOT._rail_gear_weight(15.0, 15.0, 20.0), 0.0, 1e-6, "the grind gear is 0")
	approx(PILOT._rail_gear_weight(20.0, 15.0, 20.0), 1.0, 1e-6, "the sprint gear is 1")
	approx(PILOT._rail_gear_weight(17.5, 15.0, 20.0), 0.5, 1e-6, "the ease is a ramp")
	approx(PILOT._rail_gear_weight(5.0, 15.0, 20.0), 0.0, 1e-6,
		"a slow entry still easing up should clamp at 0")
	approx(PILOT._rail_gear_weight(15.0, 20.0, 20.0), 1.0, 1e-6,
		"equal gears should not divide by zero")

# --- the node --------------------------------------------------------------------

func test_the_pilot_builds_its_effects() -> void:
	var p := _scene()
	var v := _vfx(p)
	check(v != null, "pilot9 should build a MovementVfx child in _ready()")
	if v == null:
		return
	check(v.get_node_or_null("GrindSparks") is GPUParticles3D, "the grind stream is missing")
	check(v.get_node_or_null("GrindLight") is OmniLight3D, "the grind light is missing")
	check(not v.is_grinding(), "nothing should spray before a rail")

func test_the_switch_is_a_settings_row() -> void:
	var found := false
	for row: Array in Settings.DEFS:
		if row[0] == &"movement_effects":
			found = true
			eq(row[1], "MOVEMENT EFFECTS", "the row's label")
			eq(row[3][row[4]], "on", "it should default ON")
	check(found, "settings.gd has no movement_effects row")

# --- the jumps -------------------------------------------------------------------

# is_on_floor() cannot be made true headlessly, which is exactly the coyote case: a floor jump
# taken with no floor under him.
func test_a_coyote_jump_kicks_up_no_dust() -> void:
	var p := _scene()
	p._take_floor_jump()
	eq(_bursts(p, "GroundJumpDust").size(), 0, "dust in mid-air off a coyote jump")

func test_the_double_jump_is_air_not_dust() -> void:
	var p := _scene()
	_vfx(p).double_jump(p.global_position)
	eq(_bursts(p, "DoubleJumpRing").size(), 1, "the ring")
	eq(_bursts(p, "DoubleJumpWind").size(), 1, "the wind streaks")
	eq(_bursts(p, "GroundJumpDust").size() + _bursts(p, "LandingDust").size(), 0,
		"no dust mid-air")

func test_the_double_jump_branch_calls_the_effect() -> void:
	var f := FileAccess.open("res://scripts/pilot9.gd", FileAccess.READ)
	var src := f.get_as_text()
	var at := src.find("air_jumped.emit()")
	check(at >= 0, "the double jump's signal is gone")
	var tail := src.substr(at, 200)
	check(tail.contains("_vfx.double_jump("),
		"the double-jump branch should fire the air burst right after air_jumped")

# --- the landing -----------------------------------------------------------------

func test_a_step_down_lands_clean() -> void:
	var p := _scene()
	_land(p, 4.0)
	eq(_bursts(p, "LandingDust").size(), 0, "a step-down should raise no dust")

func test_a_full_jump_lands_on_two_side_puffs() -> void:
	var p := _scene()
	_land(p, p.jump_velocity * sqrt(p.jump_fall_multiplier))
	eq(_bursts(p, "LandingDust").size(), 2, "left and right, and no ring yet")

func test_a_big_drop_adds_the_ring() -> void:
	var p := _scene()
	_land(p, p.max_fall_speed)
	eq(_bursts(p, "LandingDust").size(), 3, "the side puffs plus the ring")

func test_a_bounce_pad_cancels_the_dust() -> void:
	var p := _scene()
	p.is_jumping = true      # what the pad's launch leaves behind by the next frame
	_land(p, p.max_fall_speed)
	eq(_bursts(p, "LandingDust").size(), 0, "a pad launch on touchdown should not dust")

func test_the_dust_ignores_camera_motion() -> void:
	var p := _scene()
	Settings.set_value(&"camera_motion", "off")
	_land(p, p.max_fall_speed)
	Settings.set_value(&"camera_motion", "on")
	eq(_bursts(p, "LandingDust").size(), 3, "CAMERA MOTION off should not take the dust with it")

func test_a_slide_landing_trails_backward() -> void:
	var p := _scene()
	p.is_sliding = true
	p.velocity = Vector3(0, 0, -8)
	_land(p, p.max_fall_speed)
	var dust := _bursts(p, "LandingDust")
	check(dust.size() > 0, "a slide landing should still dust")
	for d in dust:
		var pull: Vector3 = (d.process_material as ParticleProcessMaterial).gravity
		check(pull.z > 0.0, "the dust should trail back (+Z) behind a slide heading -Z, got %s"
			% [pull])

func test_a_standing_landing_does_not_trail() -> void:
	var p := _scene()
	_land(p, p.max_fall_speed)
	for d in _bursts(p, "LandingDust"):
		var pull: Vector3 = (d.process_material as ParticleProcessMaterial).gravity
		eq(pull, Vector3.ZERO, "no slide, no trail")

# --- the rail --------------------------------------------------------------------

func test_a_rail_catch_throws_the_heavy_shower() -> void:
	var p := _scene()
	var r := _rail(FAR)
	p.global_position = FAR + Vector3(0, 0.3, -5)
	p._start_rail_grind(r, 5.0, 1)
	var bursts := _bursts(p, "RailSparkBurst")
	eq(bursts.size(), 1, "one shower on the catch")
	if bursts.size() == 1:
		eq(bursts[0].amount, p.vfx_spark_catch_count, "the catch's count, not the switch's")

func test_a_switch_landing_throws_the_small_burst() -> void:
	var p := _scene()
	var r := _rail(FAR)
	p.global_position = FAR + Vector3(0, 0.3, -5)
	p._start_rail_grind(r, 5.0, 1, true)
	var bursts := _bursts(p, "RailSparkBurst")
	eq(bursts.size(), 1, "one burst on the switch landing, not two")
	if bursts.size() == 1:
		eq(bursts[0].amount, p.vfx_spark_switch_count, "the switch's count")

func test_the_switch_landing_says_so() -> void:
	var f := FileAccess.open("res://scripts/pilot9.gd", FileAccess.READ)
	check(f.get_as_text().contains("_start_rail_grind(rail, _switch_offset, _switch_dir, true)"),
		"_tick_rail_switch() should land through the switch burst, not the catch shower")

func test_the_stream_and_light_follow_the_ride() -> void:
	var p := _scene()
	var r := _rail(FAR)
	var v := _vfx(p)
	p.global_position = FAR + Vector3(0, 0.3, -5)
	p._start_rail_grind(r, 5.0, 1)
	p._update_grind_vfx()
	check(v.is_grinding(), "grinding should spray")
	check(v.grind_light().visible, "grinding should light his feet")
	p._end_rail_grind(PILOT.RailExit.JUMP)
	p._update_grind_vfx()
	check(not v.is_grinding(), "off the rail the stream should stop")
	check(not v.grind_light().visible, "off the rail the light should go out")

func test_a_rail_landing_raises_no_dust() -> void:
	var p := _scene()
	var r := _rail(FAR)
	p.global_position = FAR + Vector3(0, 0.3, -5)
	p._start_rail_grind(r, 5.0, 1)
	p._land_dust_pending = 1.0
	p._emit_landing_dust()
	eq(_bursts(p, "LandingDust").size(), 0, "a rail gets sparks, not dust")

# --- the switch ------------------------------------------------------------------

func test_off_means_nothing_at_all() -> void:
	var p := _scene()
	var r := _rail(FAR)
	var v := _vfx(p)
	Settings.set_value(&"movement_effects", "off")
	p.global_position = FAR + Vector3(0, 0.3, -5)
	p._start_rail_grind(r, 5.0, 1)
	p._update_grind_vfx()
	check(not v.is_grinding(), "OFF should stop the stream")
	check(not v.grind_light().visible, "OFF should put the light out")
	p._end_rail_grind(PILOT.RailExit.JUMP)
	_land(p, p.max_fall_speed)
	var bursts := 0
	for c in v.get_children():
		if not c.has_meta(&"persistent"):
			bursts += 1
	eq(bursts, 0, "OFF should spawn no bursts - only the streams and lights remain")

func test_boarding_stops_the_stream() -> void:
	var p := _scene()
	var r := _rail(FAR)
	var v := _vfx(p)
	p.global_position = FAR + Vector3(0, 0.3, -5)
	p._start_rail_grind(r, 5.0, 1)
	p._update_grind_vfx()
	p._end_verbs_for_boarding()
	check(not v.is_grinding(), "no physics frames run aboard, so boarding itself must stop it")
