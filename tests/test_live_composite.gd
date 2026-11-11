extends "res://tests/test_case.gd"

# The COMPOSITE look (docs/specs/live-composite.md). Whether it looks right in play is the user's
# call; this fences what would fail quietly - a sun glowing with its back to you, a default RETRO
# that picked up the composite, a compositor left behind, a removed row a save can still reach.

const SETTINGS := preload("res://scripts/settings.gd")
const RETRO_LOOK := preload("res://scripts/rendering/retro_look.gd")
const DEPTH_COMPOSITE := preload("res://scripts/rendering/depth_composite.gd")
const CINEMA_POST := preload("res://scripts/rendering/cinema_post.gd")
const COMPOSITE_POST := preload("res://resources/composite_post.tres")
const RETRO_POST := preload("res://resources/retro_post.tres")
const SHOT_POST := preload("res://resources/cinema_post.tres")

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _make_scene(with_sun: bool) -> Dictionary:
	var parent := Node3D.new()
	var env_node := WorldEnvironment.new()
	env_node.environment = Environment.new()
	parent.add_child(env_node)
	if with_sun:
		parent.add_child(DirectionalLight3D.new())
	var look: RetroLook = RETRO_LOOK.new()
	parent.add_child(look)
	_tree().root.add_child(parent)
	return {"parent": parent, "look": look, "env": env_node}

# --- the switch ------------------------------------------------------------------

func test_look_row() -> void:
	eq(SETTINGS.values_of(&"look"), ["retro", "composite"], "RETRO / COMPOSITE")
	eq(SETTINGS.defaults()[&"look"], "retro", "the game still boots in RETRO")

func test_old_looks_load_as_retro() -> void:
	for old: String in ["cel", "pixel"]:
		var out := SETTINGS.sanitise({"version": SETTINGS.CONFIG_VERSION, &"look": old})
		eq(out[&"look"], "retro", old + " loads as RETRO")
	var kept := SETTINGS.sanitise({"version": SETTINGS.CONFIG_VERSION, &"look": "composite"})
	eq(kept[&"look"], "composite", "COMPOSITE survives a reload")

func test_removed_rows_cannot_come_back_from_a_save() -> void:
	var raw := {"version": SETTINGS.CONFIG_VERSION, &"pixel_size": 4, &"colour_depth": 8,
			&"painted_shading": "off", &"cel_scatter": "on"}
	var out := SETTINGS.sanitise(raw)
	eq(out[&"pixel_size"], 0, "pixel filter loads OFF")
	eq(out[&"colour_depth"], 0, "colour depth loads FULL")
	eq(out[&"painted_shading"], "on", "Ichi and the cutscenes keep their paint")
	eq(out[&"cel_scatter"], "off", "scatter loads at its default")

func test_removed_rows_have_no_menu_row() -> void:
	var tab := preload("res://scripts/ui/tabs/tab_settings.gd")
	for key: StringName in [&"pixel_size", &"pixel_look_size", &"colour_depth", &"painted_shading", &"cel_scatter"]:
		check(tab.ROWLESS_KEYS.has(key), String(key) + " is not a row")
	check(not tab.ROWLESS_KEYS.has(&"anime_animation"), "ANIMATION stays")
	check(not tab.ROWLESS_KEYS.has(&"look"), "LOOK stays")

# --- the compositor --------------------------------------------------------------

func test_composite_swaps_the_stack_and_retro_gets_it_back() -> void:
	var s := _make_scene(true)
	s.look.apply_look(true)
	var video: Compositor = s.env.compositor
	eq(video.compositor_effects.size(), 1, "RETRO is the video pass alone")
	s.look.apply_composite(true)
	var effects: Array = s.env.compositor.compositor_effects
	eq(effects.size(), 2, "COMPOSITE is two passes")
	check(effects[0] is DepthComposite, "depth first, before the grade")
	check(effects[1] is CinemaPost, "then the finish")
	s.look.apply_composite(false)
	check(s.env.compositor == video, "RETRO gets its own compositor back")
	s.parent.free()

func test_composite_needs_retro_on() -> void:
	var s := _make_scene(true)
	s.look.apply_composite(true)
	check(not s.look.composite, "nothing to sit on")
	s.parent.free()

func test_retro_off_drops_the_composite() -> void:
	var s := _make_scene(true)
	var before: Compositor = s.env.compositor
	s.look.apply_look(true)
	s.look.apply_composite(true)
	s.look.apply_look(false)
	check(not s.look.composite, "composite gone with the look")
	check(s.env.compositor == before, "the map's compositor is exact")
	s.parent.free()

func test_flipping_reuses_the_passes() -> void:
	var s := _make_scene(true)
	s.look.apply_look(true)
	s.look.apply_composite(true)
	var first: Compositor = s.env.compositor
	s.look.apply_composite(false)
	s.look.apply_composite(true)
	check(s.env.compositor == first, "no shader rebuild on the second flip")
	s.parent.free()

func test_settings_flip() -> void:
	var settings: Node = _tree().root.get_node(^"Settings")
	var saved: Variant = settings.get_value(&"look")
	settings.set_value(&"look", "retro")
	var s := _make_scene(true)
	s.look.apply_look(true)
	settings.set_value(&"look", "composite")
	check(s.look.pixel and s.look.composite, "COMPOSITE keeps RETRO on")
	settings.set_value(&"look", "retro")
	check(s.look.pixel and not s.look.composite, "RETRO is RETRO again")
	s.parent.free()
	settings.set_value(&"look", saved)

# --- the map's values ------------------------------------------------------------

func test_no_sun_means_no_light_and_no_wrap() -> void:
	var s := _make_scene(false)
	s.look.apply_look(true)
	s.look.apply_composite(true)
	var depth: DepthComposite = s.env.compositor.compositor_effects[0]
	eq(depth.light_energy, 0.0, "no light")
	eq(depth.wrap_strength, 0.0, "no wrap")
	approx(depth.near_value, s.look.composite_near_value, 1e-6, "the band still runs")
	s.parent.free()

func test_a_map_override_reaches_the_pass() -> void:
	var s := _make_scene(true)
	s.look.composite_near_end = 3.0
	s.look.composite_wrap = 0.5
	s.look.apply_look(true)
	s.look.apply_composite(true)
	var depth: DepthComposite = s.env.compositor.compositor_effects[0]
	eq(depth.near_end, 3.0, "band distance")
	eq(depth.wrap_strength, 0.5, "wrap")
	s.parent.free()

# --- the sun ---------------------------------------------------------------------

func _view(dir: Vector3) -> Vector3:
	# A camera looking down -Z at 60 deg vertical, 16:9.
	return RETRO_LOOK.sun_view(Basis.IDENTITY, dir.normalized(), tan(deg_to_rad(30.0)), 16.0 / 9.0, 0.35)

func test_sun_dead_ahead_is_the_screen_centre_at_full() -> void:
	var v := _view(Vector3(0, 0, -1))
	approx(v.x, 0.5, 1e-5, "centre x")
	approx(v.y, 0.5, 1e-5, "centre y")
	approx(v.z, 1.0, 1e-5, "full strength")

func test_sun_up_is_up_the_screen() -> void:
	check(_view(Vector3(0, 0.2, -1)).y < 0.5, "UV y runs down")
	check(_view(Vector3(0.2, 0, -1)).x > 0.5, "and x runs right")

func test_sun_behind_is_gone_not_mirrored() -> void:
	eq(_view(Vector3(0, 0, 1)).z, 0.0, "dead behind")
	eq(_view(Vector3(0.1, 0.1, 1)).z, 0.0, "behind and off to a side")
	check(_view(Vector3(0, 0, 1)).x < -1.0, "and far off screen, so the haze lobe goes too")

func test_sun_fades_past_the_edge() -> void:
	var edge := _view(Vector3(0, tan(deg_to_rad(30.0)), -1))
	approx(edge.z, 1.0, 1e-3, "full at the frame edge")
	var past := _view(Vector3(0, tan(deg_to_rad(30.0)) * 1.35, -1))
	check(past.z > 0.0 and past.z < 1.0, "part way out, it is fading")
	eq(_view(Vector3(0, 3.0, -1)).z, 0.0, "well past the margin it is gone")

# --- the cutscenes ---------------------------------------------------------------

func test_chroma_keep_is_off_by_default() -> void:
	eq(DEPTH_COMPOSITE.new().dark_keep_chroma, 0.0, "the shots do not change")

func test_finish_is_the_cutscene_grade_with_retros_softness() -> void:
	eq(COMPOSITE_POST.contrast, SHOT_POST.contrast, "contrast")
	eq(COMPOSITE_POST.saturation, SHOT_POST.saturation, "saturation")
	eq(COMPOSITE_POST.grain, SHOT_POST.grain, "grain")
	eq(COMPOSITE_POST.vignette_strength, SHOT_POST.vignette_strength, "vignette")
	eq(COMPOSITE_POST.aberration, SHOT_POST.aberration, "fringing")
	eq(COMPOSITE_POST.soften, RETRO_POST.soften, "soften")
	eq(COMPOSITE_POST.bleed, RETRO_POST.bleed, "bleed")
	eq(COMPOSITE_POST.bleed_amount, RETRO_POST.bleed_amount, "bleed amount")
	eq(COMPOSITE_POST.streak_intensity, 0.0, "no streaks, ever")
