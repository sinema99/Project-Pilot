extends "res://tests/test_case.gd"

# The LOOK switch, CEL / PIXEL. See docs/specs/pixel-look.md. Whether PIXEL looks good is the
# user's call; this fences what would fail quietly - a slot left on the cel shader (black ink
# in the PIXEL look), a slot that CEL does not put back, a twin that loses its colour, a default
# that boots the game into the test look.

const SETTINGS := preload("res://scripts/settings.gd")
const PIXEL_WORLD := preload("res://scripts/rendering/pixel_world.gd")
const PIXEL_LOOK := preload("res://scripts/rendering/pixel_look.gd")
const CEL_GROUND := preload("res://resources/cel_ground.tres")
const CEL_CHARACTER := preload("res://resources/cel_character.tres")
const LOOK_SHADER := "res://shaders/pixel_look/pixel-look.gdshader"

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

# --- settings ------------------------------------------------------------------

func test_look_defaults_to_cel() -> void:
	eq(SETTINGS.values_of(&"look"), ["cel", "pixel"], "CEL / PIXEL")
	eq(SETTINGS.defaults()[&"look"], "cel", "the game boots in today's look")

func test_dither_row_is_gone() -> void:
	check(not SETTINGS.keys().has(&"dither"), "no DITHER row - the reference has no pattern")
	var sanitised := SETTINGS.sanitise({"version": SETTINGS.CONFIG_VERSION, &"dither": "on"})
	check(not sanitised.has(&"dither"), "an old save's dither key is dropped")

func test_look_rows_sit_in_graphics() -> void:
	eq(SETTINGS.section_of(&"look"), "graphics", "LOOK is a graphics row")

func test_each_look_keeps_its_own_block_size() -> void:
	eq(SETTINGS.defaults()[&"pixel_size"], 0, "CEL defaults to OFF")
	eq(SETTINGS.defaults()[&"pixel_look_size"], 4, "PIXEL defaults to 4X")
	check(not SETTINGS.values_of(&"pixel_look_size").has(0), "PIXEL has no OFF")
	eq(SETTINGS.pixel_filter_key("cel"), &"pixel_size", "the row edits CEL's size in CEL")
	eq(SETTINGS.pixel_filter_key("pixel"), &"pixel_look_size", "and PIXEL's in PIXEL")
	eq(SETTINGS.effective_pixel_size(0, 4, "pixel"), 4, "PIXEL ignores CEL's OFF")
	eq(SETTINGS.effective_pixel_size(3, 6, "pixel"), 6, "PIXEL draws its own size")
	eq(SETTINGS.effective_pixel_size(0, 4, "cel"), 0, "CEL leaves OFF alone")
	eq(SETTINGS.effective_pixel_size(2, 4, "cel"), 2, "CEL draws its own size")

func test_colour_levels() -> void:
	eq(SETTINGS.colour_levels("cel", 0), 0, "CEL is full colour")
	eq(SETTINGS.colour_levels("pixel", 0), 24, "PIXEL bands to 24 levels by default")
	eq(SETTINGS.colour_levels("pixel", 8), 8, "COLOUR DEPTH overrides it")
	eq(SETTINGS.colour_levels("cel", 16), 16, "COLOUR DEPTH applies in CEL too")

# --- PixelWorld ----------------------------------------------------------------

func test_bracket_keys_step_through_the_filter_list() -> void:
	var sizes := [0, 2, 3, 4, 6]
	eq(PIXEL_WORLD.step_block(sizes, 4, 1), 6, "coarser from 4X is 6X")
	eq(PIXEL_WORLD.step_block(sizes, 6, 1), 6, "6X is the coarsest")
	eq(PIXEL_WORLD.step_block(sizes, 2, -1), 2, "finer never steps to OFF")
	eq(PIXEL_WORLD.step_block(sizes, 0, 1), 0, "OFF stays OFF")

func test_pixel_look_supersamples() -> void:
	eq(SETTINGS.pixel_supersample("pixel"), 2, "PIXEL averages 2x2 texels per block")
	eq(SETTINGS.pixel_supersample("cel"), 1, "CEL keeps one texel per block, so ink stays solid")

func test_colour_levels_reach_the_world_pass() -> void:
	var world: PixelWorld = PIXEL_WORLD.new()
	_tree().root.add_child(world)
	world.apply_settings(4, 24, 2)
	eq(world.colour_steps, 24, "colour levels stored")
	eq(world.supersample, 2, "supersample stored")
	world.free()

# --- the shader ----------------------------------------------------------------

func test_pixel_shader_compiles_and_shares_names_with_cel() -> void:
	var names := shader_uniform_names(LOOK_SHADER)
	check(not names.is_empty(), "pixel-look.gdshader compiles")
	for n in ["color", "base_texture", "uv_scale", "uv_offset", "clump_anchor"]:
		check(names.has(n), "uniform %s" % n)

func test_project_declares_the_look_globals() -> void:
	for key in ["look_clump_strength", "look_clump_value", "look_clump_hue",
			"look_clump_world_size", "look_clump_uv_size", "look_wrap", "look_light_steps",
			"look_light_softness"]:
		check(ProjectSettings.has_setting("shader_globals/" + key), "%s declared" % key)

# --- the swap ------------------------------------------------------------------

# A parent with a PixelLook child and three kinds of cel slot, plus one non-cel material.
func _make_scene() -> Dictionary:
	var parent := Node3D.new()
	var by_override := MeshInstance3D.new()
	by_override.mesh = BoxMesh.new()
	var ground := CEL_GROUND.duplicate() as ShaderMaterial
	ground.set_shader_parameter(&"color", Color(0.1, 0.2, 0.3))
	by_override.material_override = ground
	parent.add_child(by_override)

	var by_surface := MeshInstance3D.new()
	by_surface.mesh = BoxMesh.new()
	by_surface.set_surface_override_material(0, CEL_CHARACTER)
	parent.add_child(by_surface)

	var by_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.material = CEL_GROUND
	by_mesh.mesh = mesh
	parent.add_child(by_mesh)

	var plain := MeshInstance3D.new()
	plain.mesh = BoxMesh.new()
	var standard := StandardMaterial3D.new()
	plain.material_override = standard
	parent.add_child(plain)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.fog_density = 0.0004
	env_node.environment = env
	parent.add_child(env_node)

	var look: PixelLook = PIXEL_LOOK.new()
	parent.add_child(look)
	_tree().root.add_child(parent)
	return {
		"parent": parent, "look": look, "by_override": by_override, "ground": ground,
		"by_surface": by_surface, "by_mesh": by_mesh, "plain": plain, "standard": standard,
		"env_node": env_node, "env": env,
	}

func _is_pixel(mat: Material) -> bool:
	return mat is ShaderMaterial and (mat as ShaderMaterial).shader.resource_path == LOOK_SHADER

func test_pixel_swaps_every_kind_of_cel_slot() -> void:
	var s := _make_scene()
	s.look.apply_look(true)
	check(_is_pixel(s.by_override.material_override), "material_override swapped")
	check(_is_pixel(s.by_surface.get_surface_override_material(0)), "surface override swapped")
	check(_is_pixel(s.by_mesh.get_surface_override_material(0)), "mesh's own material covered by an override")
	check(s.plain.material_override == s.standard, "non-cel material untouched")
	s.look.apply_look(false)
	s.parent.free()

func test_twins_drop_the_ink_and_keep_the_colour() -> void:
	var s := _make_scene()
	s.look.apply_look(true)
	var twin := s.by_override.material_override as ShaderMaterial
	check(twin.next_pass == null, "no outline / crease pass")
	eq(twin.get_shader_parameter(&"color"), Color(0.1, 0.2, 0.3), "slot colour carried")
	eq(twin.get_shader_parameter(&"clump_anchor"), 1, "ground's World anchor carried")
	var char_twin := s.by_surface.get_surface_override_material(0) as ShaderMaterial
	eq(char_twin.get_shader_parameter(&"clump_anchor"), 0, "characters stay on UV")
	check(s.look.twin_of(CEL_CHARACTER) == char_twin, "a shared material shares one twin")
	s.look.apply_look(false)
	s.parent.free()

func test_cel_puts_back_exactly_what_was_there() -> void:
	var s := _make_scene()
	s.look.apply_look(true)
	s.look.apply_look(false)
	check(s.by_override.material_override == s.ground, "override restored")
	check(s.by_surface.get_surface_override_material(0) == CEL_CHARACTER, "surface override restored")
	check(s.by_mesh.get_surface_override_material(0) == null, "a slot that had no override has none again")
	s.parent.free()

func test_toggling_twice_does_not_stack() -> void:
	var s := _make_scene()
	s.look.apply_look(true)
	s.look.apply_look(false)
	s.look.apply_look(true)
	s.look.apply_look(false)
	check(s.by_override.material_override == s.ground, "still the original after two round trips")
	s.parent.free()

func test_nodes_added_while_pixel_are_swapped() -> void:
	var s := _make_scene()
	s.look.apply_look(true)
	var late := MeshInstance3D.new()
	late.mesh = BoxMesh.new()
	late.material_override = CEL_GROUND
	s.parent.add_child(late)
	s.look._swap_late(late)
	check(_is_pixel(late.material_override), "a respawn / late build gets the PIXEL look")
	s.look._swap_late(late)
	s.look.apply_look(false)
	check(late.material_override == CEL_GROUND, "a second arrival does not record the twin as original")
	s.parent.free()

func test_pixel_swaps_the_environment_and_cel_restores_it() -> void:
	var s := _make_scene()
	s.look.apply_look(true)
	var env: Environment = s.env_node.environment
	check(env != s.env, "PIXEL uses its own environment")
	approx(env.fog_density, s.look.fog_density, 1e-6, "haze density")
	check(env.fog_enabled and env.adjustment_enabled, "fog and grade on")
	approx(s.env.fog_density, 0.0004, 1e-7, "the CEL environment is not edited in place")
	s.look.apply_look(false)
	check(s.env_node.environment == s.env, "CEL environment back")
	s.parent.free()

# --- wiring --------------------------------------------------------------------

func test_trial_has_exactly_one_pixel_look() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/trial.tscn")
	eq(src.count("res://scripts/rendering/pixel_look.gd"), 1, "trial.tscn instances PixelLook")

func test_pilot_rim_light_is_suppressible() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/pilot9.gd")
	check(src.contains("rim_light_enabled and not rim_light_suppressed"), "the rim stays off in PIXEL")

# --- whole screen (UI and menus) -----------------------------------------------

func test_screen_pass_follows_the_look() -> void:
	var settings: Node = _tree().root.get_node(^"Settings")
	var screen: CanvasLayer = _tree().root.get_node(^"ScreenPixel")
	var saved := {}
	for key: StringName in [&"look", &"pixel_size", &"pixel_look_size", &"colour_depth"]:
		saved[key] = settings.get_value(key)
	settings.set_value(&"pixel_size", 0)
	settings.set_value(&"pixel_look_size", 6)
	settings.set_value(&"look", "cel")
	check(not screen.is_on(), "CEL keeps the UI sharp")
	settings.set_value(&"look", "pixel")
	check(screen.is_on() or screen.menu_showing, "PIXEL pixelates the HUD")
	eq(screen.block, 6, "the UI blocks match PIXEL's own size, whatever CEL's filter says")
	for key: StringName in saved:
		settings.set_value(key, saved[key])

func test_menus_are_never_pixelated() -> void:
	var screen_script := preload("res://scripts/rendering/screen_pixel.gd")
	eq(screen_script.drawn_block(3, true), 0, "a menu at 3X stays sharp")
	eq(screen_script.drawn_block(6, true), 0, "a menu at 6X stays sharp")
	eq(screen_script.drawn_block(4, false), 4, "gameplay keeps the filter's size")
	eq(screen_script.drawn_block(0, true), 0, "CEL menus stay sharp")

func test_ui_reports_menus() -> void:
	var ui: Node = _tree().root.get_node(^"UI")
	var was: bool = ui.shell_enabled
	ui.shell_enabled = false
	check(ui.is_menu_showing(), "the main menu counts as a menu")
	ui.shell_enabled = true
	if ui.stack.is_empty():
		check(not ui.is_menu_showing(), "gameplay with nothing open is not a menu")
	ui.shell_enabled = was

func test_screen_pass_sits_over_the_ui_and_lets_clicks_through() -> void:
	var screen: CanvasLayer = _tree().root.get_node(^"ScreenPixel")
	check(screen.layer > 100, "above the UI layer")
	var rect: ColorRect = screen.get_child(0)
	eq(rect.mouse_filter, Control.MOUSE_FILTER_IGNORE, "never eats a menu click")

func test_screen_and_world_share_one_quantize() -> void:
	# The screen pass leaves the world unchanged only if both use the very same quantize.
	for path in ["res://shaders/pixel_world.gdshader", "res://shaders/screen_pixel.gdshader"]:
		var src := FileAccess.get_file_as_string(path)
		check(src.contains('#include "res://shaders/pixel_quantize.gdshaderinc"'), path + " uses the shared quantize")
