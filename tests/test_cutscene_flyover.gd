extends "res://tests/test_case.gd"

# docs/specs/cutscene-flyover.md. The shot's length, the building crawling left and down while
# staying in frame, the bank (late, leftward, still speeding up at the cut, the camera never
# rolling with it), the float, the height, and the trails streaming from the first frame. How it
# looks is judged by eye (tests/_probe_flyover_shot.gd).

const SCENE := "res://scenes/cutscene_flyover.tscn"
# Ichi's building: the middle of its roof.
const BUILDING := Vector3(0.0, 36.0, 210.0)


func _shot() -> FlyoverShot:
	var s: FlyoverShot = (load(SCENE) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	return s


# Where world point `p` lands on screen at shot time `t`: -1..1 across both axes, +y up.
func _screen(s: FlyoverShot, p: Vector3, t: float) -> Vector2:
	var local := s.camera_at(t).affine_inverse() * p
	var tan_v := tan(deg_to_rad(s.fov) * 0.5)
	return Vector2(local.x / -local.z / (tan_v * 16.0 / 9.0), local.y / -local.z / tan_v)


func test_root_is_flyover_and_three_seconds() -> void:
	var s := _shot()
	eq(s.name, "Flyover", "root node")
	approx(s.shot_length(), 3.0, 1e-4, "shot length")
	check(s.animation_player.is_playing(), "autoplays")
	s.free()


func test_building_crawls_left_and_down_and_stays_in_frame() -> void:
	var s := _shot()
	var a := _screen(s, BUILDING, 0.0)
	var b := _screen(s, BUILDING, 3.0)
	check(b.x < a.x, "moves left (%s -> %s)" % [a, b])
	check(b.y < a.y, "moves down (%s -> %s)" % [a, b])
	check(a.x < 0.1, "starts centre-left (%s)" % a)
	for p in [a, b]:
		check(absf(p.x) < 0.9 and absf(p.y) < 0.9, "in frame (%s)" % p)
	check(a.distance_to(b) < 0.8, "a crawl, not a sweep (%s -> %s)" % [a, b])
	s.free()


func test_ship_is_high_up() -> void:
	var s := _shot()
	for t in [0.0, 3.0]:
		check(s.ship_at(t).origin.y > 300.0, "over 1000 ft at %.1f s" % t)
	s.free()


func test_bank_starts_late_goes_left_and_is_still_speeding_up() -> void:
	var s := _shot()
	eq(s.bank_amount(s.bank_start - 0.01), 0.0, "no bank before it starts")
	approx(s.bank_amount(3.0), 1.0, 1e-4, "full at the cut")
	var dt := 0.05
	check(s.bank_amount(3.0) - s.bank_amount(3.0 - dt) > s.bank_amount(2.6) - s.bank_amount(2.6 - dt),
			"still speeding up at the cut")
	# Left wing down: the ship's +X (its left) points below the flight line's horizontal.
	var left := s.ship_at(3.0).basis.x.normalized()
	check(left.y < -sin(deg_to_rad(15.0)), "left wing down at the cut (%s)" % left)
	var flight := s.flight_at(3.0)
	var nose := flight.basis.inverse() * s.ship_at(3.0).basis.z
	check(nose.x > 0.0, "nose turning left")
	s.free()


func test_camera_never_rolls_with_the_bank() -> void:
	var s := _shot()
	for t in [1.0, 3.0]:
		var rest := s.flight_at(t).affine_inverse() * s.camera_at(t)
		var still := s.flight_at(1.0).affine_inverse() * s.camera_at(1.0)
		check(rest.basis.get_euler().distance_to(still.basis.get_euler()) < deg_to_rad(1.5),
				"camera only sways at %.1f s" % t)
	s.free()


func test_ship_floats_without_the_bank() -> void:
	var s := _shot()
	var heights := []
	for i in 9:
		var t := 0.25 * i
		heights.append((s.flight_at(t).affine_inverse() * s.ship_at(t)).origin.y)
	check(heights.max() - heights.min() > 0.1, "bobs")
	check(heights.max() - heights.min() <= 0.3 + 1e-4, "only a little")
	s.free()


func test_trails_already_streaming_on_the_first_frame() -> void:
	var s := _shot()
	s.apply(0.0)
	check((s.trail.mesh as ImmediateMesh).get_surface_count() > 0, "trail drawn at 0 s")
	eq(s.trail.nozzles.size(), 3, "three trails")
	check(s.trail.wind != Vector3.ZERO, "blown by the wind")
	s.free()


func test_trail_wind_is_off_by_default() -> void:
	# Shot 1's trails are untouched by the new knobs.
	var t := IntroSpaceTrail.new()
	eq(t.wind, Vector3.ZERO, "no wind")
	eq(t.wind_offset(1.0), Vector3.ZERO, "no drift")
	t.free()
	approx(declared_default_float("res://shaders/space/engine_trail.gdshader", "near_fade_full"), 0.0, 1e-6,
			"no near fade")


# "Speed lines + engine heat": the snow streams nose to tail, like the trails.
func test_snow_flows_nose_to_tail_as_speed_lines() -> void:
	var s := _shot()
	var wind := Vector3(s.storm.wind_direction.x, 0.0, s.storm.wind_direction.y).normalized()
	check(wind.dot(-s.flight_at(0.0).basis.z) > 0.99, "headwind along the flight line (%s)" % wind)
	check(s.storm.streak_time >= 0.1, "long streaks (%.3f)" % s.storm.streak_time)
	s.free()


func test_embers_are_streaming_on_the_first_frame_and_repeat_on_seek() -> void:
	var s := _shot()
	var eye := s.camera_at(0.0).origin
	var v := s.flight_at(0.0).basis.z * s.speed
	var n := s.embers.update_embers(0.0, s.ship_at, eye, v)
	check(n > 20, "embers at 0 s (%d)" % n)
	var mesh := s.embers.mesh as ImmediateMesh
	var a := mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	s.embers.update_embers(1.7, s.ship_at, eye, v)
	s.embers.update_embers(0.0, s.ship_at, eye, v)
	var b := mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	eq(a, b, "same sparks after a seek")
	s.free()


func test_embers_fall_behind_the_ship() -> void:
	var s := _shot()
	s.apply(1.5)
	var mesh := s.embers.mesh as ImmediateMesh
	var verts := mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var flight := s.flight_at(1.5)
	var behind := 0
	for p in verts:
		if (flight.affine_inverse() * p).z < s.trail.nozzles[0].z:
			behind += 1
	check(behind > verts.size() * 0.9, "trailing the nozzles (%d / %d)" % [behind, verts.size()])
	s.free()


func test_shimmer_is_off() -> void:
	var s := _shot()
	eq(s._shimmers.size(), 0, "no shimmer cones")
	s.free()


func test_shimmer_draws_before_the_fog_when_on() -> void:
	var s: FlyoverShot = (load(SCENE) as PackedScene).instantiate()
	s.shimmer_on = true
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	eq(s._shimmers.size(), 3, "one per nozzle")
	for m in s._shimmers:
		check(m.render_priority < s.storm.fog_material.render_priority, "under the fog")
	var main: float = s._shimmers[0].get_shader_parameter(&"strength")
	var pod: float = s._shimmers[1].get_shader_parameter(&"strength")
	approx(pod, main * 0.5, 1e-6, "pods at half strength")
	s.free()
