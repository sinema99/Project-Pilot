extends "res://tests/test_case.gd"

# docs/specs/cutscene-descent.md. The shot's timing, the locked camera, the trail head flying the
# sketch's blue line as one arc bending one way (out of the deck at the breach, at Finish at the
# cut), the whole line still there at the cut, the flash at the breach, the city, and the land
# landing on the sketch. How it looks is judged by eye (tests/_probe_descent_shot.gd).

const SCENE := "res://scenes/cutscene_descent.tscn"
# Sketch pixels a placed point may miss its sketch spot by.
const PX_TOL := 4.0


func _shot() -> DescentShot:
	var s: DescentShot = (load(SCENE) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	return s


func test_root_is_descent_and_twenty_seconds() -> void:
	var s := _shot()
	eq(s.name, "Descent", "root node")
	approx(s.shot_length(), 20.0, 1e-4, "shot length")
	check(s.animation_player.is_playing(), "autoplays")
	s.free()


func test_camera_is_locked_and_puts_the_horizon_on_the_sketch() -> void:
	var s := _shot()
	var before := s.camera.global_transform
	s.apply(10.0)
	s.apply(20.0)
	check(s.camera.global_transform.is_equal_approx(before), "camera never moves")
	var far_ground := Vector3(0.0, 0.0, -1e6)
	approx(DescentShot.to_sketch(far_ground).y, DescentShot.HORIZON_PX, PX_TOL, "horizon at the sketch's horizon")
	s.free()


func test_sketch_helpers_round_trip() -> void:
	for px in [Vector2(100, 100), Vector2(953, 423), Vector2(1800, 700)]:
		var p := DescentShot.sketch_point(px, 2000.0)
		check(DescentShot.to_sketch(p).distance_to(px) < 0.5, "sketch_point lands on %s" % px)
		approx(Vector2(p.x, p.z).length(), 2000.0, 0.5, "at its horizontal distance")


func test_head_breaks_out_of_the_deck_at_the_breach_time() -> void:
	var s := _shot()
	var breach := DescentShot.breach_point()
	check(s.head_at(s.breach_time).distance_to(breach) < 3.0, "head at the breach at %.2f s" % s.breach_time)
	approx(breach.y, DescentShot.DECK_BASE, 0.1, "breach is on the deck base")
	check(DescentShot.to_sketch(breach).distance_to(DescentShot.SKETCH_BREACH) < 8.0,
			"breach on the sketch's (%s)" % DescentShot.to_sketch(breach))
	check(s.head_at(s.breach_time - 0.15).y > DescentShot.DECK_BASE, "inside the deck before")
	check(s.head_at(s.breach_time + 0.15).y < DescentShot.DECK_BASE, "below it after")
	check(s.start_time < s.breach_time, "already moving inside the deck before the breach")
	s.free()


func test_head_is_at_finish_at_the_cut() -> void:
	var s := _shot()
	var finish: Vector2 = DescentShot.TRAIL_ARC[DescentShot.TRAIL_ARC.size() - 1][0]
	var at := DescentShot.to_sketch(s.head_at(20.0))
	check(at.distance_to(finish) < PX_TOL, "head at Finish at 20 s (%s vs %s)" % [at, finish])
	s.free()


func test_head_dives_then_levels_and_is_still_flying_at_the_cut() -> void:
	var s := _shot()
	var dt := 0.05
	var early := s.head_at(s.breach_time + dt).distance_to(s.head_at(s.breach_time))
	var late := s.head_at(20.0).distance_to(s.head_at(20.0 - dt))
	check(late < early, "slower at the cut than at the breach")
	check(late > 0.2 * early, "still flying at the cut")
	var drop_early := s.head_at(1.0).y - s.head_at(3.0).y
	var drop_late := s.head_at(18.0).y - s.head_at(20.0).y
	check(drop_early > 2.0 * drop_late, "steep first, levelling at the end")
	check(s.head_at(20.0).y > 100.0, "still well above the ground")
	s.free()


func test_arc_bends_one_way_only() -> void:
	# One smooth arc, no squiggles: on screen the line turns the same way all along.
	var c := DescentShot.trail_curve()
	var pts: Array[Vector2] = []
	for i in 61:
		pts.append(DescentShot.to_sketch(c.sample_baked(c.get_baked_length() * i / 60.0)))
	var sign := 0.0
	for i in range(1, pts.size() - 1):
		var turn := (pts[i] - pts[i - 1]).cross(pts[i + 1] - pts[i])
		if absf(turn) < 1e-3:
			continue
		if sign == 0.0:
			sign = signf(turn)
		check(signf(turn) == sign, "same turn at sample %d" % i)


func test_trail_is_thin() -> void:
	var s := _shot()
	check(s.trail.width_start <= 2.0 and s.trail.width_end <= 9.0, "2 m at the head, 9 m at the old end")
	s.free()


func test_head_star_hidden_until_the_breach() -> void:
	var s := _shot()
	s.apply(0.3)
	check(not s.head_star.visible, "no star inside the deck")
	s.apply(s.breach_time + 0.01)
	check(s.head_star.visible, "star once out")
	s.free()


func test_whole_trail_still_there_at_the_cut() -> void:
	var s := _shot()
	check(20.0 - s.breach_time < s.trail.life, "oldest trail younger than its life at the cut")
	eq(s.trail.nozzles.size(), 1, "one ribbon")
	s.apply(20.0)
	var mesh := s.trail.mesh as ImmediateMesh
	check(mesh.get_surface_count() > 0, "trail drawn at the cut")
	s.free()


func test_big_flash_lights_the_breach() -> void:
	var s := _shot()
	var breach := DescentShot.breach_point()
	s.apply(0.53)
	var live := s.lightning.active_at(0.53, 8)
	check(live[0].w > 1.0, "a big flash just before the punch")
	check(Vector2(live[0].x, live[0].y).distance_to(Vector2(breach.x, breach.z)) < 1.0, "at the breach")
	check(s.flash_light.visible and s.flash_light.light_energy > 0.1, "it lights the land")
	approx(s.flash_light.light_energy, s.flash_light_energy * s.flash_opacity * live[0].w, 1e-4, "at flash_opacity")
	s.apply(0.2)
	check(not s.flash_light.visible, "dark before it")
	s.free()


func test_deck_edge_follows_the_cloud_line() -> void:
	for x in [200.0, 953.0, 1690.0]:
		var y := DescentShot.polyline_y(DescentShot.CLOUD_LINE, x)
		var p := DescentShot.sketch_at_height(Vector2(x, y), DescentShot.DECK_BASE)
		approx(p.y, DescentShot.DECK_BASE, 0.1, "edge on the base at x %d" % x)
		check(-p.z > 1000.0 and -p.z < 2000.0, "edge 1-2 km out at x %d (%.0f)" % [x, -p.z])


func test_land_is_built() -> void:
	var s := _shot()
	for n in ["SnowField", "Ruins", "NearRange", "FarRange", "CloudDeck", "SnowCurtain"]:
		check(s.land.has_node(n), "has %s" % n)
	eq(s.land.get_node("Ruins").owner, null, "generated, not saved")
	s.free()


func test_city_has_every_kind_of_ruin() -> void:
	var s := _shot()
	var kinds := {}
	for r: Dictionary in s.land.ruins:
		kinds[r.kind] = true
	for k in DescentLand.RUIN_KINDS:
		check(kinds.has(k), "has a %s ruin" % k)
	s.free()


func test_city_is_dense_downtown_thinning_right() -> void:
	var s := _shot()
	var core := DescentShot.CITY_CORE
	var in_core := 0
	var right := 0
	var tallest_core := 0.0
	var tallest_sprawl := 0.0
	var depths: Array[float] = []
	for r: Dictionary in s.land.ruins:
		var x := DescentShot.to_sketch(r.base).x
		depths.append(Vector2(r.base.x, r.base.z).length())
		if x >= core.position.x and x <= core.end.x:
			in_core += 1
			tallest_core = maxf(tallest_core, r.height)
		elif x > core.end.x and x < DescentShot.CITY_SPRAWL.end.x and r.kind != &"toppled":
			right += 1
			tallest_sprawl = maxf(tallest_sprawl, r.height)
	check(in_core >= 15, "dense downtown (%d)" % in_core)
	check(right >= 8 and right < in_core, "sprawl thinner than downtown (%d)" % right)
	check(tallest_core > 200.0 and tallest_core > 2.0 * tallest_sprawl, "downtown towers over the sprawl (%.0f vs %.0f m)" % [tallest_core, tallest_sprawl])
	depths.sort()
	check(depths[0] < 3000.0 and depths[depths.size() - 1] > 5000.0, "spread in depth (%.0f-%.0f m)" % [depths[0], depths[depths.size() - 1]])
	s.free()


func test_city_skyline_stays_under_the_trail() -> void:
	# The trail ends well above the skyline: the tallest roof stays below Finish on screen.
	var s := _shot()
	var finish_y: float = DescentShot.TRAIL_ARC[DescentShot.TRAIL_ARC.size() - 1][0].y
	for r: Dictionary in s.land.ruins:
		var top := DescentShot.to_sketch(r.base + Vector3(0.0, r.height, 0.0))
		check(top.y > finish_y + 40.0, "%s roof under Finish (%.0f)" % [r.kind, top.y])
	s.free()


func test_near_ridge_matches_the_sketch() -> void:
	var profile := DescentLand.ridge_profile(DescentShot.NEAR_RIDGE, DescentShot.NEAR_RANGE_DISTANCE)
	for i in profile.size():
		check(profile[i].y > 20.0, "ridge point %d stands above the field (%.0f m)" % [i, profile[i].y])
		if i > 0:
			check(profile[i].x > profile[i - 1].x, "ridge sorted by azimuth")


func test_no_corner_mountains() -> void:
	# The user cut the bottom corners: no silhouettes, no terrain hung on the camera.
	var s := _shot()
	for n in ["SilhouetteLeft", "SilhouetteRight", "CornerLeft", "CornerRight"]:
		check(not s.camera.has_node(n), "no %s" % n)
	s.free()


func test_ruin_rides_the_camera() -> void:
	# Rows 39-42: the room is a child of the camera, so the wrapper moving the shot never shifts it.
	var s := _shot()
	eq(s.camera.get_child_count(), 1, "only the ruin rides the camera")
	check(s.ruin.get_parent() == s.camera, "ruin under the camera")
	for n in ["Ceiling", "CeilingRebar", "Pillar", "PillarRebar", "Floor", "Pipe", "DanglingWire", "SnowSift"]:
		check(s.ruin.has_node(n), "has %s" % n)
	eq(DescentRuin.WIRES.size(), 3, "three sagging wires plus the dangling one")
	s.free()


func test_ruin_frames_without_covering_the_trail() -> void:
	var s := _shot()
	# The ceiling breaks off before the breach; its thickest point stays near the spec's 8-15%.
	var end_x: float = DescentRuin.CEILING_BREAK[0].x
	check(end_x < DescentShot.SKETCH_BREACH.x - 150.0, "ceiling ends well left of the breach")
	check(end_x / DescentShot.SKETCH_SIZE.x < 0.76, "ceiling ends by about 75% across")
	var thickest := 0.0
	for p: Vector2 in DescentRuin.CEILING_EDGE:
		thickest = maxf(thickest, p.y)
	check(thickest / DescentShot.SKETCH_SIZE.y < 0.17, "ceiling at most ~15%% of the frame (%.0f px)" % thickest)
	# Hanging pieces stay left of Finish and above the horizon.
	var finish: Vector2 = DescentShot.TRAIL_ARC[DescentShot.TRAIL_ARC.size() - 1][0]
	for p: Vector2 in DescentRuin.PIPE_PATH + DescentRuin.DANGLING_WIRE:
		check(p.y < DescentShot.HORIZON_PX - 150.0, "hangs above the horizon")
	for p: Vector2 in DescentRuin.DANGLING_WIRE:
		check(absf(p.x - finish.x) > 100.0 or p.y < finish.y - 100.0, "dangling wire clear of Finish")
	# The pillar's top stays below the trail wherever they share a column.
	for t in range(0, 21):
		var at := DescentShot.to_sketch(s.head_at(float(t)))
		for p: Vector2 in DescentRuin.PILLAR:
			if absf(p.x - at.x) < 40.0:
				check(p.y > at.y + 40.0, "pillar under the trail at %d s" % t)
	# Floor lip under 6% of the frame.
	for p: Vector2 in DescentRuin.FLOOR_EDGE:
		check(p.y > DescentShot.SKETCH_SIZE.y * 0.94, "floor lip thin (%s)" % p)
	s.free()


func test_ruin_is_black_until_lightning() -> void:
	var s := _shot()
	s.apply(15.0)
	approx(float(s.ruin.material.get_shader_parameter(&"flash")), 0.0, 1e-4, "no rim at 15 s")
	s.apply(0.55)
	check(float(s.ruin.material.get_shader_parameter(&"flash")) > 0.3, "rim during the breach flash")
	s.apply(3.21)
	check(float(s.ruin.material.get_shader_parameter(&"flash")) > 0.1, "rim on a background bolt")
	eq(s.ruin.ink, Color("#0a0d12"), "near-black ink")
	s.free()


func test_ruin_moves_subtly() -> void:
	var s := _shot()
	var pipe := s.ruin.get_node("Pipe") as Node3D
	var wire := s.ruin.get_node("Wire0") as Node3D
	s.apply(2.0)
	var pa := pipe.transform
	var wa := wire.transform
	s.apply(3.5)
	check(not pipe.transform.is_equal_approx(pa), "pipe swings")
	check(not wire.transform.is_equal_approx(wa), "wires sway")
	var tilt := pipe.transform.basis.get_euler().length()
	check(tilt < deg_to_rad(s.ruin.pipe_swing) + 1e-4, "pipe swing within %.1f deg" % s.ruin.pipe_swing)
	s.free()


func test_lens_keeps_the_ruin_sharp() -> void:
	# Row 45: no near blur, so the silhouettes, wires and rebar stay crisp.
	var s := _shot()
	var attrs := s.camera.attributes as CameraAttributesPractical
	check(attrs == null or not attrs.dof_blur_near_enabled, "near depth of field off")
	check(attrs == null or not attrs.dof_blur_far_enabled, "the city stays sharp")
	s.free()


func test_lightning_at_half_opacity() -> void:
	var s := _shot()
	approx(s.flash_opacity, 0.5, 1e-4, "50%")
	approx(float(s.land.deck_material.get_shader_parameter(&"flash_opacity")), 0.5, 1e-4, "deck rings at 50%")
	s.free()


func test_background_bolts() -> void:
	var s := _shot()
	var n := s.bolt_table.size()
	check(n >= 6 and n <= 9, "about 7 strikes (%d)" % n)
	eq(s.bolts.strikes.size(), n, "one bolt each")
	var under_flash := 0
	var xs: Array[float] = []
	for row: Array in s.bolt_table:
		check(row[0] >= 2.0, "none in the first 2 s (%.2f)" % row[0])
		xs.append(row[1])
		for f: Array in s.flash_table:
			if absf(f[0] - row[0]) < 0.1:
				under_flash += 1
				break
	check(under_flash >= 2 and under_flash <= 3, "two or three under deck flashes (%d)" % under_flash)
	xs.sort()
	check(xs[0] < 400.0 and xs[xs.size() - 1] > 1500.0, "spread over the width")
	s.apply(2.5)
	for st: Dictionary in s.bolts.strikes:
		check(not (st.mesh as MeshInstance3D).visible, "dark at 2.5 s")
	var first: Array = s.bolt_table[0]
	s.apply(first[0] + 0.01)
	check((s.bolts.strikes[0].mesh as MeshInstance3D).visible, "first bolt lit")
	s.free()


func test_bolts_hide_their_ends() -> void:
	# Top behind the deck's edge, foot under the horizon behind the near ridge.
	var s := _shot()
	for st: Dictionary in s.bolts.strikes:
		var verts: PackedVector3Array = (st.mesh as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var top := 1e9
		var foot := -1e9
		for v in verts:
			var px := DescentShot.to_sketch(v)
			top = minf(top, px.y)
			foot = maxf(foot, px.y)
		check(top < DescentShot.lip_y(st.x), "bolt at x %d starts behind the deck" % st.x)
		check(foot > DescentShot.HORIZON_PX, "and ends under the horizon")
		approx(Vector2(verts[0].x, verts[0].z).length(), DescentShot.BOLT_DISTANCE, 300.0, "10 km out")
	s.free()


func test_storm_wall_comes_down_on_the_left() -> void:
	# The deck's edge drops to just above the left ridge and rejoins the cloud line by the centre.
	approx(DescentShot.lip_y(0.0), DescentShot.polyline_y(DescentShot.SHELF_LINE, 0.0), 2.0, "lip on the shelf line at the left")
	check(DescentShot.lip_y(0.0) < DescentShot.polyline_y(DescentShot.NEAR_RIDGE, 0.0), "above the left ridge")
	check(DescentShot.lip_y(0.0) > 400.0, "but down low")
	approx(DescentShot.lip_y(1400.0), DescentShot.polyline_y(DescentShot.CLOUD_LINE, 1400.0), 1.0, "right side unchanged")
	var last := 1e9
	for x in range(0, 1001, 100):
		var y := DescentShot.lip_y(float(x))
		check(y <= last + 1.0, "climbs left to right at x %d" % x)
		last = y
	check(DescentShot.deck_edge_point(0.0).y < DescentShot.DECK_BASE, "lip below the deck base")
	var risers := 0
	var was := 0.0
	for i in 401:
		var st := DescentLand.shelf_stair(i / 400.0)
		if st.y > 0.5 and was < 0.5:
			risers += 1
		was = st.y
	eq(risers, DescentShot.SHELF_BANDS, "stepped bands")
	approx(DescentLand.shelf_stair(0.0).x, 0.0, 1e-4, "starts at the lip")
	approx(DescentLand.shelf_stair(1.0).x, 1.0, 1e-4, "ends on the base")


func test_snow_curtain_sits_behind_the_city() -> void:
	var s := _shot()
	var mi: MeshInstance3D = s.land.get_node("SnowCurtain")
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for r: Dictionary in s.land.ruins:
		if DescentShot.to_sketch(r.base).x < 900.0:
			check(Vector2(r.base.x, r.base.z).length() < DescentShot.CURTAIN_DISTANCE, "%s in front of the curtain" % r.kind)
	check(Vector2(verts[0].x, verts[0].z).length() > 5000.0, "about 6 km out")
	check(DescentShot.CURTAIN_DISTANCE < DescentShot.NEAR_RANGE_DISTANCE, "in front of the left mountains")
	s.free()


func test_wrecks_in_the_open_field() -> void:
	var s := _shot()
	eq(s.land.wrecks.size(), 6, "six wrecks")
	var kinds := {}
	for w: Dictionary in s.land.wrecks:
		var d := Vector2(w.at.x, w.at.z).length()
		check(d >= 290.0 and d <= 2010.0, "between 300 m and 2 km (%.0f)" % d)
		check(w.lean_degrees >= 10.0, "tilted (%.0f deg)" % w.lean_degrees)
		check(w.sink >= 0.3 and w.sink <= 0.6, "sunk 30-60%%")
		check(w.foot.y < 0.0, "foot under the snow")
		check(d < DescentShot.CITY_SPRAWL.position.y, "in front of the city")
		kinds[w.kind] = int(kinds.get(w.kind, 0)) + 1
	eq(kinds.get(&"snapped", 0), 3, "three snapped towers")
	for k in [&"side", &"skeleton", &"poking"]:
		eq(kinds.get(k, 0), 1, "one %s" % k)
	s.free()


func test_storm_is_the_calm_eye_with_far_fog() -> void:
	var s := _shot()
	var storm: Storm = s.get_node("Storm")
	approx(storm.visibility, 14000.0, 0.1, "visibility")
	approx(storm.gust_visibility, storm.visibility, 0.1, "no gust whiteout")
	eq(storm.gust_amount, 0.0, "no gusts")
	check(storm.wind_speed < 1.0, "barely any wind")
	var fall := storm.wind_speed * storm.fall_ratio
	check(fall > 0.8 and fall < 2.0, "flakes drift down at about a metre a second")
	check(fall > 2.0 * storm.wind_speed, "nearly straight down")
	eq(storm.drift_opacity, 0.0, "no ground drift")
	check(storm.fine_count <= 8000 and storm.near_count <= 700, "light snowfall, not a blizzard")
	s.free()


func test_clouds_turn_and_churn_on_the_shot_clock() -> void:
	var s := _shot()
	var mat := s.land.deck_material
	var edge_speed := float(mat.get_shader_parameter(&"spin_rate")) * DescentShot.deck_edge_distance()
	approx(edge_speed, s.cloud_edge_speed, 0.01, "deck edge moves at cloud_edge_speed")
	check(s.cloud_edge_speed > 0.0 and s.cloud_edge_speed <= 5.0, "subtle drift")
	check(float(mat.get_shader_parameter(&"churn_rate")) > 0.0, "billows reshape")
	s.apply(7.5)
	approx(float(mat.get_shader_parameter(&"cloud_time")), 7.5, 1e-4, "driven by shot time")
	s.free()


# docs/specs/descent-composite.md: the composite look.
func test_composite_runs_before_cinema_post() -> void:
	var s := _shot()
	var we := s.get_node("WorldEnvironment") as WorldEnvironment
	check(we.compositor != null, "the environment has a compositor")
	if we.compositor:
		var fx := we.compositor.compositor_effects
		eq(fx.size(), 2, "two effects")
		check(fx[0] is DepthComposite, "DepthComposite first")
		check(fx[1] is CinemaPost, "CinemaPost after it")
	var look := s.composite()
	check(look != null, "composite() finds it")
	if look:
		check(look.light_uv.is_equal_approx(s.light_px / DescentShot.SKETCH_SIZE), "light placed from the sketch")
		check(look.light_uv.x > 0.5, "the light is right of centre")
		check(look.light_uv.y < DescentShot.HORIZON_PX / DescentShot.SKETCH_SIZE.y, "and above the horizon")
		check(look.near_end < look.lit_start, "dark band ends before the lit band")
		check(look.lit_start < 1000.0, "the wrecks (320 m+) are mostly in the lit band")
		check(look.flash_start > 10.0, "the ruin around the camera (1-10 m) never flash-lifts")
	s.free()


func test_near_band_is_dark_and_flash_lifts_it() -> void:
	var tint := Color(0.72, 0.75, 0.92)
	var base := DepthComposite.near_multiplier(tint, 0.28, Color(0.8, 0.9, 1.0), 0.6, 0.0)
	var lit := DepthComposite.near_multiplier(tint, 0.28, Color(0.8, 0.9, 1.0), 0.6, 1.0)
	var lum := func(c: Color) -> float: return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	approx(lum.call(base), pow(0.28, 2.2), 1e-4, "near band at 28% perceived")
	approx(lum.call(lit), pow(0.6, 2.2), 1e-4, "a full flash lifts it to 60%")
	check(base.b > base.r, "the darks lean blue-violet")


func test_flash_reaches_the_composite_and_shafts() -> void:
	var s := _shot()
	var look := s.composite()
	s.apply(0.55)
	var during := look.flash
	s.apply(9.0)
	check(during > 0.1, "the breach flash pushes flash into the composite")
	approx(look.flash, 0.0, 1e-3, "and it is gone between strikes")
	approx(float(s.shafts.material.get_shader_parameter(&"time")), 9.0, 1e-4, "shafts breathe on the shot clock")
	s.free()


func test_shafts_fall_from_the_deck_onto_the_city() -> void:
	var mesh := DescentShafts.shaft_mesh(DescentShot.SHAFTS)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	eq(verts.size(), DescentShot.SHAFTS.size() * 6, "one quad per shaft")
	for i in DescentShot.SHAFTS.size():
		var top := verts[i * 6]
		var foot := (verts[i * 6 + 2] + verts[i * 6 + 5]) * 0.5
		check(top.y > DescentShot.DECK_BASE, "shaft %d: top tucked above the deck base" % i)
		approx(foot.y, 0.0, 1e-3, "shaft %d: foot on the ground" % i)
		var px := DescentShot.to_sketch(foot)
		check(px.x > 900.0 and px.x < 1650.0, "shaft %d: on the bright right side" % i)
