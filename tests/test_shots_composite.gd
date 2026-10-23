extends "res://tests/test_case.gd"

# docs/specs/shots-composite.md: the composite look on the four other cutscene shots. Each carries
# [DepthComposite, CinemaPost], all five share one CinemaPost file, and each shot's driver moves its
# light and its beats on the shot clock. How it looks is judged by eye (probe screenshots).

const SHOTS := {
	intro = "res://scenes/cutscene_intro_space.tscn",
	cockpit = "res://scenes/cockpit.tscn",
	storm = "res://scenes/cockpit_storm.tscn",
	flyover = "res://scenes/cutscene_flyover.tscn",
	descent = "res://scenes/cutscene_descent.tscn",
}
const SHARED_POST := "res://resources/cinema_post.tres"


func _shot(key: String) -> Node:
	var s: Node = (load(SHOTS[key]) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	return s


func _env(s: Node) -> WorldEnvironment:
	return s.find_child("WorldEnvironment", true, false)


func test_every_shot_runs_depth_composite_then_cinema_post() -> void:
	for key: String in SHOTS:
		var s := _shot(key)
		var we := _env(s)
		check(we.compositor != null, "%s: a compositor" % key)
		if we.compositor:
			var fx := we.compositor.compositor_effects
			eq(fx.size(), 2, "%s: two effects" % key)
			check(fx[0] is DepthComposite, "%s: DepthComposite first" % key)
			check(fx[1] is CinemaPost, "%s: CinemaPost after it" % key)
		s.free()


func test_all_shots_share_one_cinema_post_file_but_not_one_instance() -> void:
	var a := _shot("intro")
	var b := _shot("cockpit")
	var pa: CompositorEffect = _env(a).compositor.compositor_effects[1]
	var pb: CompositorEffect = _env(b).compositor.compositor_effects[1]
	check(pa != pb, "each shot gets its own copy (its own GPU buffers in Intro_Movie)")
	var base := load(SHARED_POST) as CinemaPost
	check(base != null and base.resource_local_to_scene, "the shared file is local to scene")
	for key: String in SHOTS:
		var text := FileAccess.get_file_as_string(SHOTS[key])
		check(text.contains(SHARED_POST), "%s: points at the shared CinemaPost" % key)
		check(not text.contains("cinema_post.gd"), "%s: no CinemaPost of its own" % key)
	a.free()
	b.free()


func test_find_in_and_screen_uv() -> void:
	check(DepthComposite.find_in(null) == null, "no environment, no composite")
	var s := _shot("flyover")
	check(DepthComposite.find_in(_env(s)) is DepthComposite, "finds the shot's composite")
	var cam: Camera3D = s.camera
	var ahead := cam.global_position - cam.global_basis.z * 100.0
	var uv := DepthComposite.screen_uv(cam, ahead)
	approx(uv.x, 0.5, 1e-3, "straight ahead is the screen centre (x)")
	approx(uv.y, 0.5, 1e-3, "straight ahead is the screen centre (y)")
	s.free()


func test_sky_distance_and_dark_keep_are_off_by_default() -> void:
	var c := DepthComposite.new()
	approx(c.sky_distance, 0.0, 0.0, "the sky is infinitely far unless a shot says so")
	approx(c.dark_keep, 0.0, 0.0, "nothing escapes the near band unless a shot says so")


# Row 3: the light toward the sun (off the left edge), fading in as the opening pan lands; no haze; the ship darkens.
func test_intro_light_sits_toward_the_sun_and_fades_in() -> void:
	var s := _shot("intro")
	var ap: AnimationPlayer = s.get_node("AnimationPlayer")
	var look := DepthComposite.find_in(_env(s))
	approx(look.haze_amount, 0.0, 0.0, "no haze in a vacuum")
	check(look.near_end < 300.0 and look.lit_start < 2000.0, "the ship is near, the planet (2.9 km+) is not")
	s.seek_shot(-3.0)
	ap.pause()
	s._process(0.0)
	approx(look.light_energy, 0.0, 1e-4, "dark during the opening pan")
	s.seek_shot(7.2)
	ap.pause()
	s._process(0.0)
	approx(look.light_energy, s.light_energy, 1e-4, "full once the pan has landed")
	check(look.light_uv.x < 0.0, "the light is off the left edge, toward the sun")
	check(look.light_uv.y < 0.5, "and up, where the sun is")
	check(look.light_uv.is_equal_approx(s.sun_uv()), "placed from the sun")
	s.free()


# Row 4: the light at the fire's entry, dimmed by the jolts, grown by the push.
func test_cockpit_light_dims_on_jolts_and_grows_on_the_push() -> void:
	var s := _shot("cockpit")
	var re: CockpitReentry = s.get_node("Reentry")
	var look := DepthComposite.find_in(_env(s))
	approx(look.haze_amount, 0.0, 0.0, "no haze inside the sphere")
	check(look.near_value > 0.85, "no dark band on him, just a tint")
	check(look.wrap_near > 2.0, "pilot9 (about 1.5 m off the camera) is not the background")
	re.apply(0.3)
	var calm_e := look.light_energy
	var calm_r := look.light_radius
	var jolt: float = re.shake.jolts[0].time
	re.apply(jolt + 0.02)
	check(look.light_energy < calm_e * 0.7, "a jolt dims the light")
	check(look.wrap_strength < re._wrap_rest * 0.7, "and the wrap")
	re.apply(7.9)
	check(look.light_radius > calm_r * 1.5, "the swallow grows the light")
	var uv := look.light_uv
	check(uv.x >= -re.edge_margin - 1e-4 and uv.x <= 1.0 + re.edge_margin + 1e-4, "light kept at the frame edge (x)")
	check(uv.y >= -re.edge_margin - 1e-4 and uv.y <= 1.0 + re.edge_margin + 1e-4, "light kept at the frame edge (y)")
	s.free()


# Row 5: the vanishing point swallowed 3-7 s; lightning lifts.
func test_storm_swallows_the_vanishing_point_and_lightning_lifts() -> void:
	var s := _shot("storm")
	var d: CockpitStormDriver = s.get_node("Storm")
	var look := DepthComposite.find_in(_env(s))
	d.apply(0.5)
	var calm := look.light_energy
	var calm_wrap := look.wrap_strength
	check(look.light_uv.x > 0.3 and look.light_uv.x < 0.8, "the vanishing point is behind him, in frame")
	d.apply(7.3)
	check(look.light_energy < calm * 0.5, "the storm swallows the light")
	check(look.wrap_strength < calm_wrap * 0.3, "and the wrap")
	check(look.dark_tint.b > look.dark_tint.r + 0.1, "the tint heads for descent's slate-violet")
	approx(look.flash, 0.0, 1e-3, "no lightning before 7.5 s")
	d.apply(7.52)
	check(look.flash > 0.5, "the 7.5 s strike lifts the near band")
	check(look.wrap_strength > calm_wrap * 0.5, "and the wrap")
	s.free()


# Row 6: the break off the top of the frame, shafts, the ship dark with its glows kept, the flash lift.
func test_flyover_break_shafts_and_flash() -> void:
	var s := _shot("flyover") as FlyoverShot
	var look := DepthComposite.find_in(_env(s))
	check(look.near_end < 40.0 and look.lit_start < 400.0, "the ship (12-20 m) is near, the city (450 m+) is lit")
	check(look.dark_keep > 0.0, "the nozzle glows escape the dark band")
	check(look.sky_distance > 400.0, "the street ground (painted in the sky) is not infinitely far")
	for t: float in [0.0, 1.5, 3.0]:
		s.apply(t)
		check(look.light_uv.y < 0.0, "t=%.1f: the break sits just above the frame" % t)
		check(look.light_uv.x > 0.0 and look.light_uv.x < 1.0, "t=%.1f: across the frame" % t)
	s.apply(0.5)
	approx(look.flash, 0.0, 1e-3, "no flash before the strike")
	s.apply(s.flash_time + 0.02)
	check(look.flash > 0.5, "the strike lifts the ship")
	var cards := s.shaft_cards()
	eq(cards.size(), FlyoverShot.SHAFTS.size(), "one card per shaft row")
	for c: Array in cards:
		approx(c[1].y, 0.0, 1e-3, "shaft foot on the ground")
		check(c[0].y > 500.0, "shaft top up toward the deck")
	approx(float(s.shafts.material.get_shader_parameter(&"time")), s.flash_time + 0.02, 1e-4,
			"shafts breathe on the shot clock")
	s.free()
