extends "res://tests/test_case.gd"

# docs/specs/cutscene-intro-space.md. Timing, where the ship is at the start and end of its flight,
# the push-in, the planet framing, finished / restart. How it looks is judged by eye
# (tests/_probe_intro_space_shot.gd).

const SCENE := "res://scenes/cutscene_intro_space.tscn"
const PLANET_RADIUS := 4000.0
const SPAN := 10.3  # vanguard_1.glb wingspan; sinestro_1.glb is scaled to match
const ASPECT := 16.0 / 9.0


func _shot() -> Node3D:
	var s: Node3D = (load(SCENE) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	return s


func _at(s: Node3D, t: float) -> void:
	var ap: AnimationPlayer = s.get_node("AnimationPlayer")
	ap.pause()
	ap.seek(t, true)


func _cam(s: Node3D) -> Camera3D:
	return s.get_node("CameraRig/Camera3D")


func _ship(s: Node3D) -> Node3D:
	return s.get_node("CameraRig/ShipPath/ShipFollow/Ship")


func _planet_centre(s: Node3D) -> Vector3:
	return (s.get_node("PlanetTilt/Planet") as Node3D).global_position


# Horizontal and vertical screen position of `p` in -1..1 (no viewport needed headless).
func _ndc(cam: Camera3D, p: Vector3) -> Vector2:
	var local := cam.global_transform.affine_inverse() * p
	var tan_v := tan(deg_to_rad(cam.fov) * 0.5)
	return Vector2(local.x / -local.z / (tan_v * ASPECT), local.y / -local.z / tan_v)


func test_shot_is_twelve_point_three_seconds_and_autoplays() -> void:
	var s := _shot()
	var ap: AnimationPlayer = s.get_node("AnimationPlayer")
	approx(ap.get_animation(&"shot").length, 12.3, 0.001, "12.3 s shot")
	eq(ap.current_animation, "shot", "plays on load")
	check(not ap.get_animation(&"shot").loop_mode, "plays once")
	s.free()


func test_ship_hidden_for_the_first_seven_seconds() -> void:
	var s := _shot()
	var follow: Node3D = s.get_node("CameraRig/ShipPath/ShipFollow")
	for t in [0.0, 3.0, 6.95]:
		_at(s, t)
		check(not follow.visible, "ship hidden at %.2f s" % t)
	_at(s, 7.0)
	check(follow.visible, "ship shows at 7 s")
	_at(s, 12.3)
	check(follow.visible, "ship still there at the end")
	s.free()


# Revision 5: the path is the user's tube sketch. Midline = screen position, width = ship size.
# Starts off frame past the top-left corner.
func test_ship_starts_off_frame_top_left() -> void:
	var s := _shot()
	_at(s, 7.0)
	var p := _ndc(_cam(s), _ship(s).global_position)
	check(p.x < -1.2 and p.y > 1.2, "past the top-left corner at 7 s (%.2f, %.2f)" % [p.x, p.y])
	s.free()


# Sweeps down to the right, bottoms out over the rust continent, then hooks up near the limb.
func test_ship_sweeps_down_right_then_hooks_up() -> void:
	var s := _shot()
	var cam := _cam(s)
	var low := Vector2(0.0, INF)
	var low_t := 0.0
	var t := 7.1
	while t <= 12.0:
		_at(s, t)
		var p := _ndc(cam, _ship(s).global_position)
		check(absf(p.x) < 1.0 and absf(p.y) < 1.0, "in frame at %.2f s (%.2f, %.2f)" % [t, p.x, p.y])
		if p.y < low.y:
			low = p
			low_t = t
		t += 0.05
	check(low.y < -0.48 and low.x > 0.4 and low.x < 0.55, "bottom of the curve lower right (%.2f, %.2f)" % [low.x, low.y])
	# The hook: from the bottom it only climbs the screen, ending at the sketch's tip.
	var last_y := low.y
	t = low_t + 0.1
	while t <= 12.0:
		_at(s, t)
		var y := _ndc(cam, _ship(s).global_position).y
		check(y >= last_y - 0.002, "climbs the screen in the hook at %.2f s" % t)
		last_y = y
		t += 0.1
	_at(s, 12.0)
	var tip := _ndc(cam, _ship(s).global_position)
	check(tip.distance_to(Vector2(0.46, -0.06)) < 0.05, "ends at the hook tip (%.2f, %.2f)" % [tip.x, tip.y])
	s.free()


# Size from the tube: a sixth of the frame or so coming in, a speck at the tip, shrinking all the way.
func test_ship_shrinks_from_big_to_a_speck() -> void:
	var s := _shot()
	var cam := _cam(s)
	var width_px := func(t: float) -> float:
		_at(s, t)
		var d := -(cam.global_transform.affine_inverse() * _ship(s).global_position).z
		return SPAN / d * (932.0 * 0.5) / tan(deg_to_rad(cam.fov) * 0.5)  # on the sketch's 1664 x 932
	# Size the moment its centre comes into frame (the tube's first full cross-section).
	var t_in := 7.0
	while t_in < 7.5:
		_at(s, t_in)
		var p := _ndc(cam, _ship(s).global_position)
		if p.x > -1.0 and p.y < 1.0:
			break
		t_in += 0.002
	var w_in: float = width_px.call(t_in)
	check(w_in > 250.0 and w_in < 450.0, "big coming in (%.0f px of 1664 at %.3f s)" % [w_in, t_in])
	var w_end: float = width_px.call(12.0)
	check(w_end > 3.0 and w_end < 9.0, "a speck at the tip (%.1f px)" % w_end)
	var last := INF
	for t in [7.05, 7.2, 7.5, 8.0, 9.0, 10.0, 11.0, 12.0]:
		var w: float = width_px.call(t)
		check(w < last, "smaller at %.2f s" % t)
		last = w
	s.free()


# User, after rev 5: "always arcing smoothly, no weird turns". One turn direction (a fixed axis, no
# S-bends), never straight, and the turn rate never jumps.
func test_ship_always_arcs_one_way_without_kinks() -> void:
	var s := _shot()
	var follow: Node3D = s.get_node("CameraRig/ShipPath/ShipFollow")
	var dt := 0.02
	var heads: Array[Vector3] = []
	var t := 7.04  # inside the curve's end handles (the ship is still off frame at 7.0)
	while t <= 11.98:
		_at(s, t)
		var a := follow.position
		_at(s, t + 0.005)
		heads.append((follow.position - a).normalized())
		t += dt
	var axes: Array[Vector3] = []
	var rates: Array[float] = []
	for i in range(1, heads.size()):
		axes.append(heads[i - 1].cross(heads[i]).normalized())
		rates.append(rad_to_deg(heads[i - 1].angle_to(heads[i])) / dt)
	var mean := Vector3.ZERO
	for ax in axes:
		mean += ax
	mean = mean.normalized()
	for i in axes.size():
		check(axes[i].dot(mean) > 0.9, "turning the same way at %.2f s" % (7.04 + i * dt))
		check(rates[i] > 2.5, "still arcing at %.2f s (%.1f deg/s)" % [7.04 + i * dt, rates[i]])
		check(rates[i] < 70.0, "no snap turn at %.2f s (%.1f deg/s)" % [7.04 + i * dt, rates[i]])
		if i > 0:
			check(absf(rates[i] - rates[i - 1]) < maxf(3.0, rates[i - 1] * 0.25),
					"turn rate eases at %.2f s (%.1f -> %.1f)" % [7.04 + i * dt, rates[i - 1], rates[i]])
	s.free()


# Constant real speed: perspective, not the key curve, makes it slow down on screen.
func test_ship_flies_at_constant_speed() -> void:
	var s := _shot()
	var follow: Node3D = s.get_node("CameraRig/ShipPath/ShipFollow")
	var steps := []
	var t := 7.0
	while t < 11.95:
		_at(s, t)
		var a := follow.position
		_at(s, t + 0.1)
		steps.append(a.distance_to(follow.position))
		t += 0.5
	for d in steps:
		approx(d, steps[0], steps[0] * 0.03, "same distance every 0.1 s (%.1f m)" % d)
	s.free()


# Nose along the path, top always aimed at the planet's centre (as far as the nose allows), so we
# see its belly as it flies by.
func test_ship_rolls_its_top_towards_the_planet() -> void:
	var s := _shot()
	var ship := _ship(s)
	for t in [7.05, 7.3, 8.0, 9.5, 11.0, 11.9]:
		_at(s, t)
		var a := ship.global_position
		_at(s, t + 0.02)
		var v := (ship.global_position - a).normalized()
		var nose := ship.global_basis.z.normalized()
		check(nose.dot(v) > 0.99, "nose along the path at %.2f s" % t)
		var to_planet := (_planet_centre(s) - ship.global_position).normalized()
		var best := sqrt(maxf(0.0, 1.0 - pow(v.dot(to_planet), 2.0)))
		check(ship.global_basis.y.normalized().dot(to_planet) > best * 0.98,
				"top at the planet at %.2f s" % t)
	for t in [7.05, 7.2, 7.4]:
		_at(s, t)
		var to_cam := (_cam(s).global_position - ship.global_position).normalized()
		check(ship.global_basis.y.dot(to_cam) < -0.1, "belly to the camera at %.2f s" % t)
	s.free()


func test_camera_rumbles_only_as_the_ship_flies_by() -> void:
	var s := _shot()
	for t in [0.0, 6.9, 7.0, 7.8, 9.0, 12.3]:
		eq(s.shake_at(t), Vector3.ZERO, "still at %.1f s" % t)
	var peak := 0.0
	var t := 7.0
	while t < 7.8:
		peak = maxf(peak, rad_to_deg(s.shake_at(t).length()))
		t += 0.01
	check(peak > 0.2 and peak < 0.6, "small rumble, peak %.2f deg" % peak)
	eq(s.shake_at(7.3), s.shake_at(7.3), "same time, same shake (seekable)")
	s.free()


func test_ship_ends_over_the_planet() -> void:
	var s := _shot()
	_at(s, 12.3)
	var cam := _cam(s)
	var ship := _ship(s)
	check(not cam.is_position_behind(ship.global_position), "ship in front of the camera")
	check(_planet_centre(s).distance_to(ship.global_position) > PLANET_RADIUS + 100.0, "above the surface")
	var dir := (ship.global_position - cam.global_position).normalized()
	var oc := cam.global_position - _planet_centre(s)
	var b := oc.dot(dir)
	check(b * b - (oc.length_squared() - PLANET_RADIUS * PLANET_RADIUS) > 0.0, "planet behind the ship")
	s.free()


func test_camera_pushes_in_a_little() -> void:
	var s := _shot()
	_at(s, 0.0)
	var d0 := _cam(s).global_position.distance_to(_planet_centre(s))
	_at(s, 12.3)
	var d1 := _cam(s).global_position.distance_to(_planet_centre(s))
	var push := 1.0 - d1 / d0
	check(push > 0.01 and push < 0.02, "push-in is 1-2%% of the distance (%.3f)" % push)
	s.free()


func test_planet_fills_the_left_with_the_limb_on_the_right() -> void:
	var s := _shot()
	for t in [0.0, 12.3]:
		_at(s, t)
		var cam := _cam(s)
		var c := _planet_centre(s)
		var local := cam.global_transform.affine_inverse() * c
		var dist := local.length()
		var alpha := asin(PLANET_RADIUS / dist)
		var centre_angle := atan2(local.x, -local.z)
		var tan_h := tan(deg_to_rad(cam.fov) * 0.5) * ASPECT
		var limb_x := tan(centre_angle + alpha) / tan_h
		check(limb_x > 0.5 and limb_x < 0.9, "right limb at 75-95%% of the width at %.0f s (ndc %.2f)" % [t, limb_x])
		check(centre_angle - alpha < -atan(tan_h), "planet runs off the left edge at %.0f s" % t)
		check(alpha > deg_to_rad(cam.fov) * 0.5, "planet covers top to bottom at %.0f s" % t)
	s.free()


func test_finished_fires_at_the_end_and_restart_rewinds() -> void:
	var s := _shot()
	var ap: AnimationPlayer = s.get_node("AnimationPlayer")
	var count := [0]
	s.finished.connect(func() -> void: count[0] += 1)
	ap.seek(12.25, true)
	ap.advance(0.2)
	eq(count[0], 1, "finished fires once at the end")
	approx(ap.current_animation_position, 12.3, 0.001, "holds the last frame")
	s.restart()
	approx(ap.current_animation_position, 0.0, 0.001, "restart goes back to 0")
	check(not (s.get_node("CameraRig/ShipPath/ShipFollow") as Node3D).visible, "ship hidden again after restart")
	check(ap.is_playing(), "and plays")
	s.free()


# --- Planet upgrade: a desolate future Earth ---------------------------------------------------

# Must match shaders/space/planet_earth.gdshaderinc and tools/gen_planet_earth.gd.
const CROP_LAT := Vector2(-8.0, 52.0)
const CROP_LON := Vector2(-142.0, -32.0)
const FLORIDA := Vector2(27.8, -81.7)


func _hit_planet(s: Node3D, o: Vector3, d: Vector3) -> Vector3:
	var c := _planet_centre(s)
	var oc := o - c
	var b := oc.dot(d)
	var disc := b * b - (oc.length_squared() - PLANET_RADIUS * PLANET_RADIUS)
	if disc < 0.0:
		return Vector3.INF
	return o + d * (-b - sqrt(disc))


# Earth latitude / longitude (degrees) of a world point on the planet. Object space is Earth
# space: +y north, x = cos(lat) cos(lon), z = -cos(lat) sin(lon).
func _lat_lon(s: Node3D, p: Vector3) -> Vector2:
	var planet: Node3D = s.get_node("PlanetTilt/Planet")
	var e := (planet.global_transform.affine_inverse() * p).normalized()
	return Vector2(rad_to_deg(asin(e.y)), rad_to_deg(atan2(-e.z, e.x)))


func test_florida_is_under_the_end_of_the_dive() -> void:
	var s := _shot()
	_at(s, 12.0)
	var cam := _cam(s)
	var hit := _hit_planet(s, cam.global_position,
			(_ship(s).global_position - cam.global_position).normalized())
	check(hit != Vector3.INF, "line of sight through the ship meets the planet")
	var ll := _lat_lon(s, hit)
	check(absf(ll.x - FLORIDA.x) < 1.0 and absf(ll.y - FLORIDA.y) < 1.0,
			"Florida under the ship at 12 s (%.1f, %.1f)" % [ll.x, ll.y])
	s.free()


# North stays the spin axis, so the planet's turn moves the surface east like the real Earth.
func test_planet_turns_east_about_north() -> void:
	var s := _shot()
	var planet: Node3D = s.get_node("PlanetTilt/Planet")
	var p := _planet_centre(s) + planet.global_transform.basis * Vector3(1, 0, 0) * PLANET_RADIUS
	_at(s, 0.0)
	var a := _lat_lon(s, p)
	_at(s, 12.3)
	var b := _lat_lon(s, p)
	approx(b.x, a.x, 0.01, "latitude of a fixed point is unchanged by the turn")
	check(b.y < a.y, "a fixed point in space sees the surface move east (lon %.2f -> %.2f)" % [a.y, b.y])
	s.free()


# Detail only where the camera looks: everything the frame sees, at both ends of the shot, is
# inside the baked crop (outside it the old noise planet takes over).
func test_the_frame_only_sees_the_baked_crop() -> void:
	var s := _shot()
	var c := _planet_centre(s)
	for t in [0.0, 12.3]:
		_at(s, t)
		var cam := _cam(s)
		var tan_v := tan(deg_to_rad(cam.fov) * 0.5)
		for yi in 21:
			for xi in 31:
				var ndc := Vector2(xi / 15.0 - 1.0, yi / 10.0 - 1.0)
				var d := (cam.global_transform.basis * Vector3(ndc.x * tan_v * ASPECT, ndc.y * tan_v, -1.0)).normalized()
				var hit := _hit_planet(s, cam.global_position, d)
				if hit == Vector3.INF:
					var p := cam.global_position + d * (c - cam.global_position).dot(d)
					hit = c + (p - c).normalized() * PLANET_RADIUS
				var ll := _lat_lon(s, hit)
				var inside := ll.x > CROP_LAT.x and ll.x < CROP_LAT.y and ll.y > CROP_LON.x and ll.y < CROP_LON.y
				if not inside:
					check(false, "ndc %s at %.1f s sees (%.1f, %.1f), outside the crop" % [ndc, t, ll.x, ll.y])
					s.free()
					return
	check(true, "whole frame inside the crop")
	s.free()


func test_cloud_shell_and_halo_wrap_the_planet() -> void:
	var s := _shot()
	var clouds: MeshInstance3D = s.get_node("PlanetTilt/Planet/Clouds")
	var halo: MeshInstance3D = s.get_node("PlanetTilt/Halo")
	var cr: float = (clouds.mesh as SphereMesh).radius
	var hr: float = (halo.mesh as SphereMesh).radius
	check(cr > PLANET_RADIUS and cr < PLANET_RADIUS * 1.01, "clouds just above the surface (%.0f m)" % cr)
	check(hr > cr, "halo outside the clouds (%.0f m)" % hr)
	var hm: ShaderMaterial = halo.mesh.surface_get_material(0)
	approx(float(hm.get_shader_parameter(&"halo_radius")), hr, 0.5, "halo shader knows its own radius")
	approx(float(hm.get_shader_parameter(&"planet_radius")), PLANET_RADIUS, 0.5, "and the planet's")
	s.free()


func test_clouds_drift_with_the_shot_time() -> void:
	var s := _shot()
	approx(s.cloud_drift_at(0.0), 0.0, 0.0001, "no drift at the start")
	approx(s.cloud_drift_at(12.3), s.cloud_drift_degrees, 0.0001, "full drift at the end")
	check(s.cloud_drift_degrees > 0.0 and s.cloud_drift_degrees < 2.0, "a fraction of a degree or so")
	_at(s, 6.0)
	s._process(0.0)
	var want: float = s.cloud_drift_at(6.0)
	for path in ["PlanetTilt/Planet", "PlanetTilt/Planet/Clouds"]:
		var m: ShaderMaterial = (s.get_node(path) as MeshInstance3D).mesh.surface_get_material(0)
		approx(float(m.get_shader_parameter(&"cloud_drift")), want, 0.0001, "%s shadows / clouds share the drift" % path)
	s.free()


# VRAM compression would wreck the elevation encoding (sea level is a single 8-bit step).
func test_earth_texture_imports_lossless() -> void:
	var cfg := ConfigFile.new()
	eq(cfg.load("res://assets/textures/planet_earth_na.png.import"), OK, "import file present")
	eq(cfg.get_value("params", "compress/mode"), 0, "lossless")
	eq(cfg.get_value("params", "detect_3d/compress_to"), 0, "not switched to VRAM compression when used in 3D")


# --- Effects pass: trails, storm, lightning, heat, glint ----------------------------------------

func test_trail_reads_the_ship_off_the_animation() -> void:
	var s := _shot()
	for t in [7.05, 7.3, 9.0, 11.9]:
		_at(s, t)
		var want := _ship(s).global_transform
		var got: Transform3D = s.ship_model_at(t)
		check(got.origin.distance_to(want.origin) < 0.05, "position at %.2f s (off %.3f m)" % [t, got.origin.distance_to(want.origin)])
		check(got.basis.z.normalized().dot(want.basis.z.normalized()) > 0.9999, "heading at %.2f s" % t)
	s.free()


# The Sinestro shell replaced Vanguard: scaled to Vanguard's 10.3 m wingspan and centred where its
# hull was (follow-space z +0.415), so the approved path and sizes still hold.
func test_ship_shell_matches_vanguards_size_and_centre() -> void:
	var s := _shot()
	var follow: Node3D = s.get_node("CameraRig/ShipPath/ShipFollow")
	var box := AABB()
	var first := true
	for mi in _ship(s).find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var x := follow.global_transform.affine_inverse() * m.global_transform
		var b := x * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	approx(box.size.x, SPAN, 0.1, "wingspan matches Vanguard's")
	approx(box.get_center().z, 0.415, 0.1, "hull centred where Vanguard's was")
	s.free()


func _trail_points(s: Node3D) -> PackedVector3Array:
	var m := (s.get_node("EngineTrails") as MeshInstance3D).mesh as ImmediateMesh
	if m.get_surface_count() == 0:
		return PackedVector3Array()
	return m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func test_three_trails_start_with_the_ship_and_last_their_life() -> void:
	var s := _shot()
	var trail: IntroSpaceTrail = s.get_node("EngineTrails")
	eq(trail.nozzles.size(), 3, "one trail per engine")
	check(trail.width_at(0.0, trail.nozzle_widths[0]) > trail.width_at(0.0, trail.nozzle_widths[1]) * 1.3, "main engine trail is wider")
	approx(trail.life, 4.0, 0.001, "4 s life")
	_at(s, 6.9)
	s._process(0.0)
	eq(_trail_points(s).size(), 0, "no trail before the ship shows")
	_at(s, 7.4)
	s._process(0.0)
	var pts := _trail_points(s)
	check(pts.size() > 0, "a trail once it flies")
	var ship := _ship(s).global_transform
	for nozzle in trail.nozzles:
		var near := INF
		for p in pts:
			near = minf(near, p.distance_to(ship * nozzle))
		check(near < trail.width_start, "a ribbon starts on the nozzle at %s (%.2f m)" % [nozzle, near])
	check(trail.width_at(trail.life) > trail.width_at(0.0) * 4.0, "spreads with age")
	s.free()


func test_storm_frame_is_still_and_only_the_inner_layers_turn() -> void:
	var s := _shot()
	eq(s.storm_spin_at(0.0), Vector2.ZERO, "still at the start")
	var end: Vector2 = s.storm_spin_at(12.3)
	check(end.x > end.y and end.y > 0.0, "eyewall turns faster than the bands")
	check(end.x < 25.0, "very subtle (eyewall %.1f deg over the shot)" % end.x)
	var e := Vector3(1, 0.4, -0.3).normalized()
	check(s.storm_local(e, 2.0).distance_to(s.storm_local(e, 11.0)) < 0.5, "storm frame doesn't turn")
	_at(s, 6.0)
	s._process(0.0)
	for path in ["PlanetTilt/Planet", "PlanetTilt/Planet/Clouds"]:
		var m: ShaderMaterial = (s.get_node(path) as MeshInstance3D).mesh.surface_get_material(0)
		approx(float(m.get_shader_parameter(&"storm_spin_wall")), s.storm_spin_at(6.0).x, 0.0001, "%s gets the eyewall turn" % path)
		approx(float(m.get_shader_parameter(&"storm_spin_band")), s.storm_spin_at(6.0).y, 0.0001, "%s gets the band turn" % path)
	s.free()


func _flash_count(s: Node3D, from: float, to: float) -> int:
	var n := 0
	for f in s.lightning.flashes:
		if f != s.lightning.sting and f.start >= from and f.start < to:
			n += 1
	return n


func test_lightning_runs_the_whole_shot_builds_and_ends_on_the_sting() -> void:
	var s := _shot()
	var early := _flash_count(s, 0.0, 7.0) / 7.0
	var late := _flash_count(s, 10.0, 11.5) / 1.5
	check(early > 1.5, "going from the start, %.2f / s" % early)
	check(_flash_count(s, 0.0, 1.0) > 0, "a flash in the first second")
	check(late > early * 1.4, "builds up, %.2f / s late" % late)
	# Never dark for long before the sting.
	var starts: Array[float] = []
	for f in s.lightning.flashes:
		if f != s.lightning.sting:
			starts.append(f.start)
	starts.sort()
	var gap := starts[0]
	for i in range(1, starts.size()):
		gap = maxf(gap, starts[i] - starts[i - 1])
	check(gap < 1.6, "longest dark gap %.2f s" % gap)
	eq(_flash_count(s, s.lightning_last, 99.0), 0, "only the sting after lightning_last")
	var sting: IntroSpaceLightning.Flash = s.lightning.sting
	check(sting != null and sting.peak > 1.0, "a big final sting")
	check(sting.end_time(s.lightning.decay) < 12.3, "dark again by the last frame")
	eq(s.lightning.active_at(7.3, 8), s.lightning.active_at(7.3, 8), "same time, same flashes (seekable)")
	# On the sting's second pulse.
	var t: float = s.sting_time + 0.075
	_at(s, t)
	s._process(0.0)
	var aim: Vector2 = s.storm_local(s.ship_aim_on_planet(s.sting_time), t)
	var live: PackedVector4Array = (s.get_node("PlanetTilt/Planet/Clouds") as MeshInstance3D).mesh.surface_get_material(0).get_shader_parameter(&"flashes")
	eq(live.size(), 8, "8 flash slots")
	check(live[0].w > 1.0 and Vector2(live[0].x, live[0].y).distance_to(aim) < 0.01, "sting is the brightest, where the ship is heading (%s vs %s)" % [live[0], aim])
	check(aim.length() < s.storm_radius_degrees * 1.5, "and inside the storm (%.1f deg from the eye)" % aim.length())
	s.free()


func test_heat_builds_through_the_dive() -> void:
	var s := _shot()
	eq(s.heat_at(8.9), 0.0, "cold before the dive")
	check(s.heat_at(10.5) > 0.2 and s.heat_at(10.5) < 0.8, "building")
	eq(s.heat_at(12.0), 1.0, "full by the end")
	s.free()


func test_glint_flashes_once_at_the_flyby() -> void:
	var s := _shot()
	eq(s.glint_at(s.glint_time - s.glint_duration), 0.0, "dark before")
	approx(s.glint_at(s.glint_time), 1.0, 0.001, "peak at glint_time")
	eq(s.glint_at(s.glint_time + s.glint_duration), 0.0, "dark after")
	check(s.glint_time > s.shake_start and s.glint_time < s.shake_end, "during the flyby rumble")
	s.free()


func test_only_hdr_effects_glow() -> void:
	var s := _shot()
	var env := (s.get_node("WorldEnvironment") as WorldEnvironment).environment
	check(env.glow_enabled, "glow on")
	check(env.glow_hdr_threshold >= 1.0, "only brighter than white glows (planet stays crisp)")
	s.free()


# Spec "Title card": EARTH 2129 + Florida coordinates, bottom left, staggered fade in, wiped away
# left to right by the flyby.
func test_title_card_fades_in_staggered_and_is_wiped_by_the_flyby() -> void:
	var s := _shot()
	var card: IntroTitleCard = s.get_node("TitleCard")
	for t in [0.0, 1.0, 1.5]:
		eq(card.visible_at(t), Vector2.ZERO, "nothing on screen at %.1f s" % t)
	check(card.visible_at(2.1).x > 0.0 and card.visible_at(2.1).y == 0.0,
			"title is coming in before the coordinates start")
	check(card.visible_at(2.8).x > card.visible_at(2.8).y, "coordinates lag the title")
	for t in [3.6, 5.0, 7.0]:
		eq(card.visible_at(t), Vector2.ONE, "both lines fully in at %.1f s" % t)
	var mid := card.visible_at(7.15)
	check(mid.x > 0.0 and mid.x < 1.0, "half wiped at the rumble's peak")
	for t in [7.3, 9.0, 12.3]:
		eq(card.visible_at(t), Vector2.ZERO, "gone at %.1f s" % t)
	check(card.wipe_at(7.0) == 0.0 and card.wipe_at(7.3) == 1.0, "wipe runs 7.0 -> 7.3 s")
	check(card.wipe_at(7.15) > 0.5, "the wipe leaves fast (eased out)")
	s.free()


func test_title_card_text_and_corner() -> void:
	var s := _shot()
	var card: IntroTitleCard = s.get_node("TitleCard")
	eq(card.title_text, "EARTH 2129", "title")
	eq(card.coords_text, "27°48'14\"N  81°41'52\"W", "Florida coordinates in DMS")
	var labels := card.find_children("*", "Label", true, false)
	eq(labels.size(), 2, "title + coordinates")
	var vp := s.get_viewport().get_visible_rect().size
	for l: Label in labels:
		var r := l.get_global_rect()
		check(r.position.x < vp.x * 0.25, "%s sits at the left" % l.text)
		check(r.end.y > vp.y * 0.75 and r.end.y < vp.y, "%s sits at the bottom, on screen" % l.text)
	s.free()


func test_title_card_shakes_with_the_camera() -> void:
	var s := _shot()
	eq(s.shake_on_screen(Vector3.ZERO), Vector2.ZERO, "no rumble, no offset")
	var o: Vector2 = s.shake_on_screen(s.shake_at(7.2))
	check(o.length() > 1.0 and o.length() < 40.0, "a few pixels of shake at the peak, %.1f" % o.length())
	s.free()
