extends "res://tests/test_case.gd"

# Covers player.gd::_slope_pitch - the trig that tips Setsuna's model along the grade she is
# standing on. Pure and static, so it is called straight off the loaded script with no scene.
#
# The sign convention is the whole reason this is worth a test: rotation.x is nose-down for a
# positive angle, downhill has to come out positive, and a flip looks exactly like a model that
# rears back going down a ramp.

const PLAYER_PATH := "res://scripts/player.gd"

# Runtime load, not preload: a preload of a script that fails to parse is a parse-time error,
# which makes --script fall back to main.tscn and hang. Matches test_apply_stylized.gd.
func _player() -> GDScript:
	return load(PLAYER_PATH) as GDScript

# The upward normal of a plane whose downhill direction is +Z, tilted `deg` off level. Walking
# +Z on this plane loses height; the normal leans toward +Z with it.
func _slope_normal(deg: float) -> Vector3:
	var t := deg_to_rad(deg)
	return Vector3(0.0, cos(t), sin(t))

func test_flat_ground_has_no_pitch() -> void:
	var p := _player()
	for facing in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		approx(p._slope_pitch(facing, Vector3.UP), 0.0, 0.0001,
			"flat floor, facing %s: expected no tilt" % facing)

func test_walking_downhill_pitches_nose_down() -> void:
	var p := _player()
	# +Z is downhill on this plane, and +Z is her nose, so she is heading down a 30 deg grade.
	var pitch: float = p._slope_pitch(Vector3(0, 0, 1), _slope_normal(30.0))
	approx(pitch, deg_to_rad(30.0), 0.01, "30 deg descent should tilt the model 30 deg")
	check(pitch > 0.0, "downhill must be a positive (nose-down) angle")

func test_walking_uphill_pitches_nose_up() -> void:
	var p := _player()
	# Same plane, facing -Z: now she is climbing the 30 deg grade.
	var pitch: float = p._slope_pitch(Vector3(0, 0, -1), _slope_normal(30.0))
	approx(pitch, deg_to_rad(-30.0), 0.01, "30 deg climb should tilt the model -30 deg")
	check(pitch < 0.0, "uphill must be a negative (nose-up) angle")

func test_facing_across_the_slope_has_no_pitch() -> void:
	var p := _player()
	# Steep plane, but her nose runs along the contour - no up or down to it.
	approx(p._slope_pitch(Vector3(1, 0, 0), _slope_normal(35.0)), 0.0, 0.01,
		"facing along the contour of a slope should not tilt her")

func test_grade_inside_the_deadzone_reads_as_flat() -> void:
	var p := _player()
	# 2 deg is under MODEL_SLOPE_PITCH_DEADZONE (3 deg) - collision-mesh noise, not a ramp.
	approx(p._slope_pitch(Vector3(0, 0, 1), _slope_normal(2.0)), 0.0, 0.0001,
		"a grade shallower than the deadzone should return exactly 0")

func test_grade_just_past_the_deadzone_tilts() -> void:
	var p := _player()
	var pitch: float = p._slope_pitch(Vector3(0, 0, 1), _slope_normal(5.0))
	approx(pitch, deg_to_rad(5.0), 0.01, "a 5 deg grade clears the deadzone and tilts")

func test_facing_parallel_to_the_normal_is_safe() -> void:
	var p := _player()
	# Degenerate input (nose straight up the normal): nothing left in the slope plane to measure.
	approx(p._slope_pitch(Vector3(0, 1, 0), Vector3.UP), 0.0, 0.0001,
		"a facing with no component in the slope plane returns 0, not NAN")

func test_pitch_is_clamped_on_a_wall_steep_grade() -> void:
	var p := _player()
	# asin's argument is clamped, so even a near-vertical normal cannot throw.
	var pitch: float = p._slope_pitch(Vector3(0, 0, 1), _slope_normal(80.0))
	check(pitch <= deg_to_rad(90.0) + 0.001 and pitch > 0.0,
		"an 80 deg grade stays a finite positive angle")
