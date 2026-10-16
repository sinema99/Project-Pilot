extends "res://tests/test_case.gd"

# PixelWorld: the low-res world render. See docs/specs/pixel-world.md. The look itself cannot be
# judged headless; this fences the decisions that would fail quietly - a default that drifts, an
# old save that keeps the filter off, a block that is not a whole number of window pixels, a
# panel that ends up pixelated, a node that leaves the root without 3D.

const SETTINGS := preload("res://scripts/settings.gd")
const PIXEL_WORLD := preload("res://scripts/rendering/pixel_world.gd")

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

# --- settings ------------------------------------------------------------------

func test_pixel_filter_is_off_by_default() -> void:
	eq(SETTINGS.defaults()[&"pixel_size"], 0, "first launch is not pixelated")

func test_pixel_filter_offers_off_2x_3x_4x_6x() -> void:
	# 6X added for the PIXEL look test - see docs/specs/pixel-look.md.
	eq(SETTINGS.values_of(&"pixel_size"), [0, 2, 3, 4, 6], "OFF / 2X / 3X / 4X / 6X")

func test_colour_depth_offers_full_32_16_8_default_full() -> void:
	eq(SETTINGS.values_of(&"colour_depth"), [0, 32, 16, 8], "FULL / 32 / 16 / 8")
	eq(SETTINGS.defaults()[&"colour_depth"], 0, "COLOUR DEPTH defaults to FULL")

func test_the_old_pixel_filter_key_is_gone() -> void:
	check(SETTINGS.values_of(&"pixel_filter").is_empty(), "pixel_filter was replaced by pixel_size")

func test_an_old_save_drops_the_old_key() -> void:
	# The user's own settings.cfg has pixel_filter=-1. A new key means it is ignored.
	var raw: Dictionary = SETTINGS.defaults().duplicate()
	raw.erase(&"pixel_size")
	raw[&"pixel_filter"] = -1
	raw["version"] = 1
	var out: Dictionary = SETTINGS.sanitise(raw)
	eq(out[&"pixel_size"], 0, "an old save falls back to the OFF default")
	check(not out.has(&"pixel_filter"), "the old key is dropped, not carried")

# --- sizing --------------------------------------------------------------------

func test_view_size_divides_exactly_when_it_can() -> void:
	eq(PIXEL_WORLD.view_size(Vector2i(2560, 1440), 4), Vector2i(640, 360), "1440p at 4X")
	eq(PIXEL_WORLD.view_size(Vector2i(1920, 1080), 3), Vector2i(640, 360), "1080p at 3X")
	eq(PIXEL_WORLD.view_size(Vector2i(2560, 1440), 2), Vector2i(1280, 720), "1440p at 2X")

func test_view_size_rounds_up_to_cover_the_screen() -> void:
	# 2560 / 3 = 853.3: 854 texels so the last partial block is still drawn.
	eq(PIXEL_WORLD.view_size(Vector2i(2560, 1440), 3), Vector2i(854, 480), "1440p at 3X covers every column")

func test_view_size_never_hits_zero() -> void:
	eq(PIXEL_WORLD.view_size(Vector2i(0, 0), 3), Vector2i(1, 1), "a zero-size window still makes a valid viewport")

# --- the sharp layer -----------------------------------------------------------

func test_the_sharp_layer_is_inside_a_default_camera_mask() -> void:
	# A default Camera3D sees layers 1-20; the panel must still show with the filter OFF.
	var cam := Camera3D.new()
	check(cam.cull_mask & PIXEL_WORLD.SHARP_MASK != 0, "layer %d is in the default cull mask" % PIXEL_WORLD.SHARP_LAYER)
	cam.free()

func test_the_hologram_panel_is_on_the_sharp_layer() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/pilot9_hologram.gd")
	check(src.contains("_panel.layers = PixelWorld.SHARP_MASK"), "the menu panel is drawn sharp")

# --- the node ------------------------------------------------------------------

func _make() -> PixelWorld:
	var world: PixelWorld = PIXEL_WORLD.new()
	_tree().root.add_child(world)
	return world

func test_on_disables_root_3d_and_off_restores_it() -> void:
	var world := _make()
	var root := _tree().root
	# pixel_block itself cannot be read back under the headless dummy renderer.
	world.apply_settings(3, 0)
	check(root.disable_3d, "pixelated: the root stops drawing 3D")
	world.apply_settings(0, 0)
	check(not root.disable_3d, "OFF: the root draws 3D again")
	world.free()

func test_leaving_the_tree_hands_3d_back() -> void:
	var world := _make()
	world.apply_settings(4, 0)
	world.free()
	check(not _tree().root.disable_3d, "the main menu must not inherit a root with 3D off")

func test_project_declares_pixel_block_at_1() -> void:
	eq(ProjectSettings.get_setting("shader_globals/pixel_block", {}).get("value"), 1.0,
		"the outline / crease / rim shaders read pixel_block; OFF is 1")

func test_supersample_renders_that_many_texels_per_block() -> void:
	var world := _make()
	world.apply_settings(3, 0, 2)
	var view := world.get_node(^"WorldView") as SubViewport
	eq(view.size, PIXEL_WORLD.view_size(world._render_size(), 3) * 2, "2x2 texels per block")
	world.apply_settings(3, 0)
	eq(view.size, PIXEL_WORLD.view_size(world._render_size(), 3), "callers without it get 1")
	world.apply_settings(0, 0)
	world.free()

func test_world_view_shares_the_main_world_without_msaa() -> void:
	var world := _make()
	world.apply_settings(3, 0)
	var view := world.get_node(^"WorldView") as SubViewport
	check(view.world_3d == _tree().root.find_world_3d(), "WorldView shares the main World3D")
	eq(view.msaa_3d, Viewport.MSAA_DISABLED, "no MSAA in the pixel world")
	eq(view.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "renders while on")
	world.apply_settings(0, 0)
	eq(view.render_target_update_mode, SubViewport.UPDATE_DISABLED, "idle while OFF")
	world.free()

func test_sharp_view_only_renders_when_asked() -> void:
	var world := _make()
	world.apply_settings(3, 0)
	var view := world.get_node(^"SharpView") as SubViewport
	eq(view.render_target_update_mode, SubViewport.UPDATE_DISABLED, "nothing asked: idle")
	var asker := RefCounted.new()
	world.set_sharp_needed(asker, true)
	eq(view.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "the hologram asked: renders")
	world.set_sharp_needed(asker, false)
	eq(view.render_target_update_mode, SubViewport.UPDATE_DISABLED, "released: idle again")
	world.free()

func test_colour_depth_alone_uses_the_screen_pass() -> void:
	var world := _make()
	world.apply_settings(0, 16)
	check((world.get_node(^"ColourOnly") as CanvasItem).visible, "pixels OFF + 16 levels: the screen pass draws")
	check(not (world.get_node(^"World") as CanvasItem).visible, "no pixel world while OFF")
	world.apply_settings(3, 16)
	check(not (world.get_node(^"ColourOnly") as CanvasItem).visible, "pixelated: banding happens in the world pass")
	world.free()

func test_the_mirror_camera_follows_the_root_camera() -> void:
	var cam := Camera3D.new()
	_tree().root.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(3, 4, 5)
	cam.fov = 91.0
	cam.h_offset = 0.6
	var world := _make()
	world.apply_settings(3, 0)
	world._process(0.016)
	var mirror := world.get_node(^"WorldView/Mirror") as Camera3D
	check(mirror.global_position.is_equal_approx(Vector3(3, 4, 5)), "position copied")
	approx(mirror.fov, 91.0, 1e-4, "FOV copied (sprint / dash kick ride along)")
	approx(mirror.h_offset, 0.6, 1e-4, "shoulder offset copied")
	check(mirror.cull_mask & PIXEL_WORLD.SHARP_MASK == 0, "the pixel world leaves the sharp layer out")
	check(_tree().root.get_camera_3d() == cam, "the root camera stays current")
	world.free()
	cam.free()

func test_trial_has_exactly_one_pixel_world() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/trial.tscn")
	eq(src.count("res://scripts/rendering/pixel_world.gd"), 1, "trial.tscn instances PixelWorld")
	check(not src.contains("pixelate"), "the old filter is gone from trial.tscn")
	check(not FileAccess.get_file_as_string("res://scenes/test_platform.tscn").contains("pixelate"),
		"the old filter is gone from test_platform.tscn")
