extends "res://tests/test_case.gd"

# The RETRO look (docs/specs/retro-look.md). Whether it reads as 90s anime is the user's call;
# this fences what would fail quietly - a twin that keeps the painted patches or black ink, a CEL
# material edited in place, an ink knob that leaks into the cutscenes, a video pass left behind.

const RETRO_LOOK := preload("res://scripts/rendering/retro_look.gd")
const CINEMA_POST := preload("res://scripts/rendering/cinema_post.gd")
const CEL_GROUND := preload("res://resources/cel_ground.tres")
const CEL_CHARACTER := preload("res://resources/cel_character.tres")
const OUTLINE := preload("res://shaders/cel/outline.gdshader")
const CREASE := preload("res://shaders/cel/crease.gdshader")

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _make_scene() -> Dictionary:
	var parent := Node3D.new()
	var ground_node := MeshInstance3D.new()
	ground_node.mesh = BoxMesh.new()
	var ground := CEL_GROUND.duplicate() as ShaderMaterial
	ground.set_shader_parameter(&"color", Color(0.4, 0.5, 0.6))
	ground_node.material_override = ground
	parent.add_child(ground_node)

	var char_node := MeshInstance3D.new()
	char_node.mesh = BoxMesh.new()
	char_node.set_surface_override_material(0, CEL_CHARACTER)
	parent.add_child(char_node)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	parent.add_child(env_node)

	var look: RetroLook = RETRO_LOOK.new()
	parent.add_child(look)
	_tree().root.add_child(parent)
	return {"parent": parent, "look": look, "ground_node": ground_node, "ground": ground,
		"char_node": char_node, "env_node": env_node, "env": env}

# --- the twin --------------------------------------------------------------------

func test_twin_is_flat_cel_with_neutral_shadows() -> void:
	var s := _make_scene()
	s.look.apply_look(true)
	var twin := s.char_node.get_surface_override_material(0) as ShaderMaterial
	check(twin != CEL_CHARACTER, "swapped")
	check(PixelLook.is_cel(twin), "still the cel shader, so the two-tone light is the real one")
	eq(twin.get_shader_parameter(&"flat_fill"), true, "no painted patches or scatter")
	approx((twin.get_shader_parameter(&"specular") as Color).a, 0.0, 1e-6, "no specular")
	approx((twin.get_shader_parameter(&"fresnel") as Color).a, 0.0, 1e-6, "no fresnel")
	var tint: Variant = twin.get_shader_parameter(&"shadow_tint")
	check(tint == null or (tint as Color).a == 0.0, "pass 3: neutral shadow, CEL's palette")
	check(CEL_CHARACTER.get_shader_parameter(&"flat_fill") != true, "the CEL material is not edited in place")
	s.look.apply_look(false)
	check(s.char_node.get_surface_override_material(0) == CEL_CHARACTER, "CEL put back")
	s.parent.free()

func test_every_ink_pass_takes_the_fill_colour() -> void:
	var s := _make_scene()
	# Under a moving body, so it is a cel (inked) rather than painted background.
	var body := CharacterBody3D.new()
	s.parent.add_child(body)
	s.ground_node.reparent(body)
	s.look.apply_look(true)
	var twin := s.ground_node.material_override as ShaderMaterial
	var crease := twin.next_pass as ShaderMaterial
	eq(crease.shader, CREASE, "crease pass kept")
	eq(crease.get_shader_parameter(&"ink_from_fill"), true, "crease inked from the fill")
	eq(crease.get_shader_parameter(&"ink_fill_color"), Color(0.4, 0.5, 0.6), "with this slot's colour")
	var hull := crease.next_pass as ShaderMaterial
	eq(hull.shader, OUTLINE, "outline pass kept")
	eq(hull.get_shader_parameter(&"ink_from_fill"), true, "outline inked from the fill")
	approx(hull.get_shader_parameter(&"ink_width"), 2.5, 1e-6, "thin line")
	check(CEL_GROUND.next_pass.get_shader_parameter(&"ink_from_fill") != true,
		"the shared crease material is not edited in place")
	s.look.apply_look(false)
	s.parent.free()

# --- pass 2: cels over a painted background (docs/specs/retro-look-pass-2.md) ------

func test_static_geometry_is_painted_background_without_ink() -> void:
	var s := _make_scene()
	s.look.apply_look(true)
	var twin := s.ground_node.material_override as ShaderMaterial
	check(twin != s.ground, "swapped")
	check(twin.next_pass == null, "no crease or outline on the background")
	check(twin.get_shader_parameter(&"paint_soft") > 0.0, "soft painted light")
	approx(twin.get_shader_parameter(&"shadow_tone"), 0.45, 1e-6, "pass 3: CEL's shadow value")
	var bg: Color = twin.get_shader_parameter(&"bg_paint")
	check(bg.a > 0.0, "brush grain")
	eq(Color(bg.r, bg.g, bg.b), Color(1, 1, 1), "pass 3: no background tint")
	var fc: Variant = twin.get_shader_parameter(&"floor_color")
	check(fc == null or (fc as Color).a == 0.0, "not in floor_paths, so no deck")
	check(s.ground.next_pass != null, "the CEL material keeps its ink")
	s.look.apply_look(false)
	check(s.ground_node.material_override == s.ground, "CEL put back")
	s.parent.free()

func test_cels_take_the_shade_bias() -> void:
	check(RetroLook.is_cel_node(Skeleton3D.new()), "skinned is a cel")
	var s := _make_scene()
	var body := AnimatableBody3D.new()
	s.parent.add_child(body)
	s.char_node.reparent(body)
	s.look.apply_look(true)
	var twin := s.char_node.get_surface_override_material(0) as ShaderMaterial
	check(twin.get_shader_parameter(&"shade_bias") < 0.0, "more of the form in shadow")
	check(twin.get_shader_parameter(&"paint_soft") == null
			or twin.get_shader_parameter(&"paint_soft") == 0.0, "hard cel step kept")
	s.look.apply_look(false)
	s.parent.free()

func test_floor_paths_get_panel_lines_on_their_own_colour() -> void:
	var s := _make_scene()
	s.look.floor_paths = Array([s.look.get_path_to(s.ground_node)], TYPE_NODE_PATH, &"", null)
	s.look.apply_look(true)
	var twin := s.ground_node.material_override as ShaderMaterial
	var fc: Variant = twin.get_shader_parameter(&"floor_color")
	check(fc == null or (fc as Color).a == 0.0, "pass 3: no slate deck, CEL's floor")
	check((twin.get_shader_parameter(&"floor_panel") as Color).a > 0.0, "panel lines")
	s.look.apply_look(false)
	s.parent.free()

func test_bodies_get_a_contact_shadow_while_retro_is_on() -> void:
	var s := _make_scene()
	var body := CharacterBody3D.new()
	s.parent.add_child(body)
	s.look.apply_look(true)
	var shadows: Array[Node] = s.look.find_children("*", "RetroContactShadow", false, false)
	eq(shadows.size(), 1, "one per body")
	eq(shadows[0].body, body, "on that body")
	s.look.apply_look(false)
	check(shadows[0].is_queued_for_deletion(), "gone with RETRO")
	s.parent.free()

func test_pass_two_knobs_default_to_todays_look() -> void:
	# Source checks: the headless renderer has no parameter defaults to ask.
	var inc := FileAccess.get_file_as_string("res://shaders/cel/includes/base-cel-shader.gdshaderinc")
	for line in ["uniform float shade_bias = 0.0;", "uniform float paint_soft = 0.0;",
			"uniform float shadow_tone = 0.45;"]:
		check(inc.contains(line), line)
	var base := FileAccess.get_file_as_string("res://shaders/cel/cel-shader-base.gdshader")
	check(base.contains("uniform vec4 bg_paint: source_color = vec4(1.0, 1.0, 1.0, 0.0);"),
			"bg_paint neutral")
	check(base.contains("vec4(0.55, 0.62, 0.66, 0.0)") and base.contains("vec4(0.2, 0.24, 0.3, 0.0)"),
			"floor colour and panels off")
	var sky := FileAccess.get_file_as_string("res://shaders/cel/vfx/sky.gdshader")
	check(sky.contains("uniform float clouds_paint: hint_range(0.0, 1.0) = 0.0;"),
			"clouds as they were outside RETRO")

func test_sky_is_painted_and_the_cel_sky_untouched() -> void:
	var s := _make_scene()
	var cel_sky: ShaderMaterial = load("res://resources/cel_sky.tres")
	var sky := Sky.new()
	sky.sky_material = cel_sky
	s.env.sky = sky
	s.look.apply_look(true)
	var env: Environment = s.env_node.environment
	var painted := env.sky.sky_material as ShaderMaterial
	check(painted != cel_sky, "own sky material")
	approx(painted.get_shader_parameter(&"clouds_paint"), 1.0, 1e-6, "painted clouds")
	check(cel_sky.get_shader_parameter(&"clouds_paint") != 1.0, "CEL sky not edited in place")
	eq(env.fog_density, s.env.fog_density, "pass 3: CEL's fog")
	eq(painted.get_shader_parameter(&"day_top_color"), cel_sky.get_shader_parameter(&"day_top_color"),
			"pass 3: CEL's sky colours")
	s.look.apply_look(false)
	s.parent.free()

func test_ink_defaults_leave_cel_and_cutscenes_black() -> void:
	for path in ["res://shaders/cel/outline.gdshader", "res://shaders/cel/crease.gdshader"]:
		var names := shader_uniform_names(path)
		check(names.has("ink_from_fill"), path + " has the RETRO ink switch")
		check(names.has("ink_fill_color"), path + " takes a fill colour")
	var hull := ShaderMaterial.new()
	hull.shader = OUTLINE
	check(hull.get_shader_parameter(&"ink_from_fill") != true, "off unless a twin sets it")
	var names := shader_uniform_names("res://shaders/cel/cel-shader-base.gdshader")
	check(names.has("flat_fill") and names.has("shadow_tint"), "cel base compiles with the RETRO knobs")

# --- environment + video pass ----------------------------------------------------

func test_environment_keeps_cels_light_and_the_video_pass_comes_and_goes() -> void:
	var s := _make_scene()
	s.look.apply_look(true)
	var env: Environment = s.env_node.environment
	check(env != s.env, "RETRO uses its own environment")
	eq(env.tonemap_mode, Environment.TONE_MAPPER_FILMIC, "pass 3: CEL's tonemap")
	eq(env.ambient_light_energy, s.env.ambient_light_energy, "pass 3: full ambient")
	check(not env.adjustment_enabled, "pass 3: no grade ramp")
	eq(s.env.tonemap_mode, Environment.TONE_MAPPER_FILMIC, "CEL's environment untouched")
	var compositor: Compositor = s.env_node.compositor
	check(compositor != null and compositor.compositor_effects.size() == 1, "video pass on")
	var post = compositor.compositor_effects[0]
	check(post.soften > 0.0 and post.bleed_amount > 0.0, "soften + chroma bleed on in RETRO")
	s.look.apply_look(false)
	check(s.env_node.environment == s.env, "CEL environment back")
	check(s.env_node.compositor == null, "video pass gone")
	s.parent.free()

func test_cutscene_post_has_no_video_softness() -> void:
	var post = CINEMA_POST.new()
	approx(post.soften, 0.0, 1e-6, "soften off by default")
	approx(post.bleed_amount, 0.0, 1e-6, "bleed off by default")
	var shared = load("res://resources/cinema_post.tres")
	approx(shared.soften, 0.0, 1e-6, "the cutscenes' shared CinemaPost stays sharp")
	approx(shared.bleed_amount, 0.0, 1e-6, "and has no bleed")

func test_rim_light_suppressed_like_pixel() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/rendering/pixel_look.gd")
	check(src.contains("pilot.rim_light_suppressed = on"), "the shared apply_look turns the rim off")

# --- wiring ----------------------------------------------------------------------

func test_trial_has_one_retro_look_and_cutscenes_none() -> void:
	var trial := FileAccess.get_file_as_string("res://scenes/trial.tscn")
	eq(trial.count("res://scripts/rendering/retro_look.gd"), 1, "trial.tscn instances RetroLook")
	for path in ["res://scenes/cutscene_intro_space.tscn", "res://scenes/cockpit.tscn",
			"res://scenes/cockpit_storm.tscn", "res://scenes/cutscene_descent.tscn",
			"res://scenes/cutscene_flyover.tscn", "res://Intro_Movie.tscn"]:
		var src := FileAccess.get_file_as_string(path)
		check(not src.contains("retro_look.gd"), path + " never loads RETRO")

func test_settings_switch_hands_materials_over() -> void:
	var settings: Node = _tree().root.get_node(^"Settings")
	var saved: Variant = settings.get_value(&"look")
	var s := _make_scene()
	var pixel_look: PixelLook = PixelLook.new()
	s.parent.add_child(pixel_look)
	settings.set_value(&"look", "cel")
	check(s.char_node.get_surface_override_material(0) == CEL_CHARACTER, "CEL")
	settings.set_value(&"look", "retro")
	check(s.look.pixel, "RETRO on")
	settings.set_value(&"look", "pixel")
	check(not s.look.pixel and pixel_look.pixel, "PIXEL took over")
	settings.set_value(&"look", "cel")
	check(s.char_node.get_surface_override_material(0) == CEL_CHARACTER, "and CEL is exact after both")
	s.parent.free()
	settings.set_value(&"look", saved)
