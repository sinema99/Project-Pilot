extends "res://tests/test_case.gd"

# Covers the body lean: roll into turns, pitch with changes of speed, ground walk/run/sprint
# only. See docs/specs/pilot9-body-lean.md.
#
# is_on_floor() cannot be made true without a physics world, so the tests drive
# _body_lean_target(delta, on_floor) directly with on_floor passed in, and _tick() below
# replays the one thing _align_model_to_slope() adds on top - the slope_align_speed ease onto
# character.rotation - against level ground. That ease is what the caps are measured through.

const PILOT_TSCN := "res://scenes/pilot9.tscn"
const PILOT_PATH := "res://scripts/pilot9.gd"
const DT := 1.0 / 60.0

var _instances: Array[Node] = []

func _pilot() -> GDScript:
	return load(PILOT_PATH) as GDScript

func _scene() -> Node:
	var ps := load(PILOT_TSCN) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate()
	_instances.append(n)
	n.character = n.get_node("character")
	n.character.rotation = Vector3.ZERO
	n.velocity = Vector3.ZERO
	n._reseed_body_lean()
	return n

func end() -> void:
	for n in _instances:
		if is_instance_valid(n):
			n.free()
	_instances.clear()
	super()

# One frame of _align_model_to_slope() on level ground: lean target, then the shared ease.
func _tick(n: Node, on_floor: bool = true) -> Vector2:
	var lean: Vector2 = n._body_lean_target(DT, on_floor)
	var target := lean if on_floor else Vector2.ZERO
	var step: float = n.slope_align_speed * DT
	n.character.rotation.x = lerp_angle(n.character.rotation.x, target.x, step)
	n.character.rotation.z = lerp_angle(n.character.rotation.z, target.y, step)
	return lean

# Moving at `speed` along his facing, turning at `yaw_rate` rad/s, for `frames`. Returns the
# extreme roll seen and leaves the mesh where it ended.
func _carve(n: Node, speed: float, yaw_rate: float, frames: int) -> float:
	var extreme := 0.0
	for i in frames:
		n.character.rotation.y += yaw_rate * DT
		var yaw: float = n.character.rotation.y
		n.velocity = Vector3(sin(yaw), 0.0, cos(yaw)) * speed
		_tick(n)
		if absf(n.character.rotation.z) > absf(extreme):
			extreme = n.character.rotation.z
	return extreme

# Holds `speed` for `frames`, returning the largest |pitch| the mesh reaches (signed).
func _hold_speed(n: Node, speed: float, frames: int) -> float:
	var extreme := 0.0
	n.velocity = Vector3(0.0, 0.0, speed)
	for i in frames:
		_tick(n)
		if absf(n.character.rotation.x) > absf(extreme):
			extreme = n.character.rotation.x
	return extreme

# --- peak fraction -----------------------------------------------------------

func test_peak_fraction_at_shipping_lags() -> void:
	approx(_pilot()._body_lean_peak_fraction(0.25, 0.1), 0.5427, 0.005,
		"two-lag peak fraction off - the pitch caps would not be the visible peaks")

func test_peak_fraction_equal_lags_is_one_over_e() -> void:
	approx(_pilot()._body_lean_peak_fraction(0.2, 0.2), exp(-1.0), 0.0001,
		"equal time constants should peak at 1/e")
	approx(_pilot()._body_lean_peak_fraction(0.2, 0.2 + 0.00001), exp(-1.0), 0.001,
		"near-equal time constants should approach 1/e without blowing up")

func test_full_speed_up_peaks_at_forward_cap() -> void:
	var n := _scene()
	var peak := _hold_speed(n, n.body_lean_pitch_full_gap, 120)
	var cap := deg_to_rad(n.body_lean_pitch_forward_max)
	check(peak > 0.0, "speeding up tipped him BACK - pitch sign flipped")
	approx(peak, cap, cap * 0.1, "standing -> sprint peak is not the forward cap")

func test_full_stop_peaks_at_back_cap() -> void:
	var n := _scene()
	n.velocity = Vector3(0.0, 0.0, n.body_lean_pitch_full_gap)
	n._reseed_body_lean()
	var peak := _hold_speed(n, 0.0, 120)
	var cap := deg_to_rad(n.body_lean_pitch_back_max)
	check(peak < 0.0, "stopping tipped him FORWARD - pitch sign flipped")
	approx(-peak, cap, cap * 0.1, "sprint -> stop peak is not the back cap")

# --- roll ---------------------------------------------------------------------

func test_left_turn_leans_left_right_turn_leans_right() -> void:
	var n := _scene()
	var left := _carve(n, 7.5, PI, 30)
	check(left < 0.0, "a left turn rolled him OUT of it (rotation.z should go negative)")
	var m := _scene()
	var right := _carve(m, 7.5, -PI, 30)
	check(right > 0.0, "a right turn rolled him OUT of it (rotation.z should go positive)")

func test_turn_on_the_spot_does_not_roll() -> void:
	var n := _scene()
	approx(_carve(n, 0.0, PI, 60), 0.0, 0.0001, "a standing turn leaned him")

func test_walk_leans_less_than_sprint() -> void:
	var w := _scene()
	var walk := absf(_carve(w, 2.0, PI * 0.5, 60))
	var s := _scene()
	var sprint := absf(_carve(s, 7.5, PI * 0.5, 60))
	check(walk > 0.0 and walk < sprint, "same yaw rate should lean less at a walk (%f vs %f)" % [walk, sprint])

func test_sustained_sprint_carve_settles_at_cap() -> void:
	var n := _scene()
	_carve(n, 7.5, PI, 120)
	approx(absf(n.character.rotation.z), deg_to_rad(n.body_lean_roll_max), deg_to_rad(0.5),
		"a held 180 deg/s sprint carve should sit at the roll cap")

# --- pitch --------------------------------------------------------------------

func test_speed_up_returns_to_level() -> void:
	var n := _scene()
	_hold_speed(n, 7.5, 90)
	approx(n.character.rotation.x, 0.0, deg_to_rad(0.5),
		"pitch still held a second and a half into a sprint - it should be a lean into a change")

func test_constant_sprint_holds_no_pitch() -> void:
	var n := _scene()
	n.velocity = Vector3(0.0, 0.0, 7.5)
	n._reseed_body_lean()
	approx(_hold_speed(n, 7.5, 60), 0.0, 0.0001, "a steady sprint pitched him")

# --- gate ---------------------------------------------------------------------

func _gated_lean(flag: String) -> Vector2:
	var n := _scene()
	n.set(flag, true)
	n.velocity = Vector3(0.0, 0.0, 7.5)
	n.character.rotation.y = 0.5
	return n._body_lean_target(DT, true)

func test_gated_states_give_no_lean() -> void:
	for flag in ["is_crouching", "is_sliding", "is_dashing", "is_climbing", "is_vaulting",
			"is_wall_running", "is_rail_grinding", "is_rail_switching", "frozen"]:
		eq(_gated_lean(flag), Vector2.ZERO, "%s should give no lean" % flag)

func test_air_gives_no_lean() -> void:
	var n := _scene()
	n.velocity = Vector3(0.0, 0.0, 7.5)
	n.character.rotation.y = 0.5
	eq(n._body_lean_target(DT, false), Vector2.ZERO, "airborne should give no lean")

func test_ungated_gives_lean() -> void:
	# The control for the gate tests: same setup, nothing set, and it leans.
	var n := _scene()
	n.velocity = Vector3(0.0, 0.0, 7.5)
	n.character.rotation.y = 0.5
	var lean: Vector2 = n._body_lean_target(DT, true)
	check(lean.x != 0.0 and lean.y != 0.0, "the ungated case gave no lean - the gate tests prove nothing")

func test_felt_speed_tracks_in_the_air() -> void:
	var n := _scene()
	n.velocity = Vector3(0.0, 0.0, 7.5)
	n._reseed_body_lean()
	n.velocity = Vector3.ZERO
	for i in 30:
		n._body_lean_target(DT, false)
	# His air speed changes and settles before he lands; the felt speed follows it in the air,
	# so landing at that speed kicks nothing.
	n.velocity = Vector3(0.0, 0.0, 7.5)
	for i in 120:
		n._body_lean_target(DT, false)
	approx(n._body_lean_target(DT, true).x, 0.0, deg_to_rad(0.1),
		"landing at the speed he held in the air kicked the pitch")

# --- off switches -------------------------------------------------------------

func test_roll_off_switch() -> void:
	var n := _scene()
	n.body_lean_roll_max = 0.0
	n.velocity = Vector3(0.0, 0.0, 7.5)
	n.character.rotation.y = 0.5
	var lean: Vector2 = n._body_lean_target(DT, true)
	eq(lean.y, 0.0, "roll_max 0 still rolled")
	check(lean.x != 0.0, "roll_max 0 also killed the pitch")

func test_pitch_off_switches() -> void:
	var n := _scene()
	n.body_lean_pitch_forward_max = 0.0
	n.velocity = Vector3(0.0, 0.0, 7.5)
	n.character.rotation.y = 0.5
	var lean: Vector2 = n._body_lean_target(DT, true)
	eq(lean.x, 0.0, "forward_max 0 still pitched forward")
	check(lean.y != 0.0, "forward_max 0 also killed the roll")
	var m := _scene()
	m.body_lean_pitch_back_max = 0.0
	m.velocity = Vector3(0.0, 0.0, 7.5)
	m._reseed_body_lean()
	m.velocity = Vector3.ZERO
	eq(m._body_lean_target(DT, true).x, 0.0, "back_max 0 still pitched back")

# --- reseed -------------------------------------------------------------------

func test_reseed_absorbs_a_yaw_snap() -> void:
	var n := _scene()
	n.velocity = Vector3(0.0, 0.0, 7.5)
	n._reseed_body_lean()
	n.character.rotation.y = 2.0
	n._reseed_body_lean()
	approx(n._body_lean_target(DT, true).y, 0.0, 0.0001, "a reseeded yaw snap still rolled him")
