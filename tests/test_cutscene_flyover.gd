extends "res://tests/test_case.gd"

# docs/specs/cutscene-flyover.md. The shot's length, the hero ruin crawling left and down while
# staying in frame, the dead city in place of Ichi, the lightning, the hull rim, the bank (late, leftward, still speeding up at the cut, the camera never
# rolling with it), the float, the height, and the trails streaming from the first frame. How it
# looks is judged by eye (tests/_probe_flyover_shot.gd).

const SCENE := "res://scenes/cutscene_flyover.tscn"


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
	var hero := s.city.hero_point(0.5)
	var a := _screen(s, hero, 0.0)
	var b := _screen(s, hero, 3.0)
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


func test_dot_sparks_hang_around_the_engines_and_repeat_on_seek() -> void:
	var s := _shot()
	s.apply(0.0)
	var mesh := s.dots.mesh as ImmediateMesh
	var a := mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var n := a.size() / 6
	check(n > 25 and n < 70, "dots alive at 0 s (%d)" % n)
	s.apply(1.7)
	s.apply(0.0)
	eq(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array, a, "same dots after a seek")
	# Ship frame: every dot within a few metres of a nozzle, behind its lip.
	s.apply(1.5)
	var verts := mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var inv := s.ship.global_transform.affine_inverse()
	var near := 0
	for p in verts:
		var l := inv * p
		for z in s.trail.nozzles:
			if l.distance_to(z) < 4.5 and l.z < z.z + 0.2:
				near += 1
				break
	eq(near, verts.size(), "dots by the nozzles")
	s.free()


func test_main_engine_has_a_bloom_halo() -> void:
	var s := _shot()
	var halo := s.ship.get_node("MainHalo") as MeshInstance3D
	approx(halo.position.distance_to(s.trail.nozzles[0]), 0.0, 1e-4, "on the main nozzle")
	approx(halo.transform.basis.x.length(), s.halo_size, 1e-4, "halo size")
	check(s.halo_size > s.main_glow_size * 2.0, "wider than the glow disc")
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


# "Dead city + storm": no Ichi, a gutted skeleton hero ~220 m tall with a thin city slice round it.
func test_dead_city_replaces_ichi() -> void:
	var s := _shot()
	check(s.get_node_or_null("OP_1") == null, "no Ichi map")
	check(s.city.hero_height > 200.0 and s.city.hero_height < 240.0, "hero ~220 m (%.0f)" % s.city.hero_height)
	var n := s.city.ruins.size()
	check(n >= 8 and n <= 12, "8-12 other ruins (%d)" % n)
	var kinds := {}
	for r: Dictionary in s.city.ruins:
		kinds[r.kind] = true
	for k: StringName in [&"snapped", &"toppled", &"facade", &"crane"]:
		check(kinds.has(k), "has a %s" % k)
	for r: Dictionary in s.city.ruins:
		check(r.height < s.city.hero_height, "%s shorter than the hero" % r.kind)
	s.free()


func test_lightning_is_one_double_flicker_then_a_far_one() -> void:
	var s := _shot()
	eq(s.flash_at(0.0), 0.0, "dark at the start")
	eq(s.flash_at(s.flash_time - 0.01), 0.0, "dark just before")
	check(s.flash_at(s.flash_time + 0.02) > 0.9, "main hit")
	check(s.flash_at(s.flash_time + s.flash_gap + 0.02) > s.flash_at(s.flash_time + s.flash_gap - 0.005), "second flicker")
	check(s.flash_at(s.flash_time + 0.6) < 0.05, "gone by ~0.4 s after")
	var far := s.flash_at(s.far_flash_time + 0.02)
	check(far > 0.1 and far < 0.5, "faint far flicker (%.2f)" % far)
	s.free()


func test_storm_is_dark_and_flash_lights_the_scene() -> void:
	var s := _shot()
	check(s.storm.near_color.get_luminance() < 0.2 and s.storm.far_color.get_luminance() < 0.2, "dark fog")
	s.apply(0.0)
	check(not s.flash_light.visible, "flash light off")
	s.apply(s.flash_time + 0.02)
	check(s.flash_light.visible and s.flash_light.light_energy > 0.0, "flash light on")
	s.free()


func test_hull_has_a_rim_that_pops_in_the_flash() -> void:
	var s := _shot()
	check(s._hull.size() > 0, "ship materials found")
	s.apply(0.0)
	var calm: Color = s._hull[0].get_shader_parameter(&"fresnel")
	approx(calm.a, s.rim_color.a, 1e-4, "faint rim")
	s.apply(s.flash_time + 0.02)
	var lit: Color = s._hull[0].get_shader_parameter(&"fresnel")
	check(lit.a > calm.a + 0.2, "rim pops in the flash")
	s.free()


func test_snow_character_is_off_unless_asked() -> void:
	var st := Storm.new()
	eq(st.lane_amount, 0.0, "no lanes by default")
	eq(st.clump_chance, 0.0, "no clumps by default")
	eq(st.shade_chance, 0.0, "no shaded flakes by default")
	st.free()
	var s := _shot()
	check(s.storm.lane_amount > 0.0 and s.storm.clump_chance > 0.0, "on in the flyover")
	s.free()


# "Ground mist": a low layer on the snow, drawn after the crease ink, drifting on the shot clock.
func test_ground_mist_lies_low_and_follows_the_shot() -> void:
	var s := _shot()
	check(s._mist != null, "mist pass built")
	check(s.mist_height < s.city.hero_height * 0.5, "low: only the ruins' feet (%.0f m)" % s.mist_height)
	eq(s._mist_material.render_priority, 0, "same priority as the crease ink")
	s.apply(1.7)
	approx(s._mist_material.get_shader_parameter(&"shot_time"), 1.7, 1e-6, "drift on the shot clock")
	var ahead := s.camera.global_transform.affine_inverse() * s._mist.global_position
	check(ahead.z < -50.0, "sorted ahead of the camera (%s)" % ahead)
	s.free()


# "City detail pass": the packed city out to the fog, a clear zone round the hero, the highway
# with its snapped span, cars, windows on the walls.
func test_packed_city_fills_out_to_the_fog() -> void:
	var s := _shot()
	var c := s.city
	check(c.lots.size() > 1000, "thousands of lots (%d)" % c.lots.size())
	var kinds := {}
	var reach := 0.0
	var tallest := 0.0
	for lot: Dictionary in c.lots:
		kinds[lot.kind] = int(kinds.get(lot.kind, 0)) + 1
		var flat := Vector2(lot.at.x - c.hero_at.x, lot.at.z - c.hero_at.z).length()
		reach = maxf(reach, flat)
		tallest = maxf(tallest, lot.height)
		check(flat > c.clear_radius, "nothing new in the hero's clear zone (%.0f m)" % flat)
	for k: StringName in [&"shell", &"stump", &"collapsed", &"empty"]:
		check(kinds.has(k), "has %s lots" % k)
	var standing: float = kinds[&"shell"] + kinds[&"stump"]
	approx(standing / c.lots.size(), 0.6, 0.06, "~60% standing")
	check(reach > c.city_radius * 0.9, "out to the fog (%.0f m)" % reach)
	check(tallest < c.hero_height * 0.3, "packed city well under the hero (%.0f m)" % tallest)
	s.free()


func test_packed_city_is_taller_toward_the_hero() -> void:
	var s := _shot()
	var c := s.city
	var near := [0.0, 0]
	var far := [0.0, 0]
	for lot: Dictionary in c.lots:
		if lot.height <= 0.0:
			continue
		var flat := Vector2(lot.at.x - c.hero_at.x, lot.at.z - c.hero_at.z).length()
		var bucket: Array = near if flat < 400.0 else (far if flat > 1000.0 else [])
		if bucket.is_empty():
			continue
		bucket[0] += lot.height
		bucket[1] += 1
	check(near[0] / near[1] > far[0] / far[1] * 1.5, "taller near (%.0f vs %.0f m)" % [near[0] / near[1], far[0] / far[1]])
	s.free()


func test_highway_crosses_with_a_snapped_span_and_cars() -> void:
	var s := _shot()
	var c := s.city
	check(not c.highway.is_empty(), "highway built")
	var length: float = (c.highway.end - c.highway.start).length()
	check(length > 2000.0, "crosses the city (%.0f m)" % length)
	var gap: Vector3 = c.highway.break_at
	var screen := _screen(s, gap, 3.0)
	check(absf(screen.x) < 1.0 and absf(screen.y) < 1.0, "snapped span in frame at the cut (%s)" % screen)
	check(c.deck_cars > 50, "stalled cars on the deck (%d)" % c.deck_cars)
	check(c.street_cars > 500, "cars in the streets (%d)" % c.street_cars)
	s.free()


func test_walls_carry_the_window_grid() -> void:
	var s := _shot()
	var windowed := 0
	for mi: MeshInstance3D in s.city.get_node("Ruins").get_children():
		var m := mi.material_override as ShaderMaterial
		check(m.get_shader_parameter(&"tile_texture") != null, "window tile set")
		var uvs: PackedVector2Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		for uv in uvs:
			if uv != FlyoverCity.SOLID_UV:
				windowed += 1
				break
	check(windowed >= 5, "the five tones have windowed walls (%d meshes)" % windowed)
	s.free()
