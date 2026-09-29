extends "res://tests/test_case.gd"

# The static model, asserted headless with no tree behind it - the shape
# test_ui_manager.gd uses on resolve(), and for the same reason: these are the
# parts of docs/specs/settings.md that fail silently. Ranked by how silently
# each fails - see the spec's What The Test Fences.

const SETTINGS_PATH := "res://scripts/settings.gd"

func _script() -> GDScript:
	var script := load(SETTINGS_PATH) as GDScript
	if script == null:
		fail("%s does not exist" % SETTINGS_PATH)
	return script

# --- 1. sanitise() is total --------------------------------------------------

func test_an_empty_dictionary_sanitises_to_defaults() -> void:
	var s := _script()
	if s == null:
		return
	eq(s.sanitise({}), s.defaults(), "an empty raw dict should be a wrong version and default wholesale")

func test_a_missing_section_falls_back_per_key() -> void:
	var s := _script()
	if s == null:
		return
	var raw: Dictionary = {"version": 1, &"window_mode": "borderless"}
	var out: Dictionary = s.sanitise(raw)
	eq(out[&"window_mode"], "borderless", "a present, valid key should round-trip")
	eq(out[&"fov"], s.defaults()[&"fov"], "a key absent from raw should fall back to its default")

func test_an_unknown_value_falls_back_to_default() -> void:
	var s := _script()
	if s == null:
		return
	var raw: Dictionary = s.defaults().duplicate()
	raw["version"] = 1
	raw[&"shadow_quality"] = "ultra"
	var out: Dictionary = s.sanitise(raw)
	eq(out[&"shadow_quality"], "high", "a value outside its own list should default, not pass through")

func test_a_wrong_version_defaults_every_key_wholesale() -> void:
	var s := _script()
	if s == null:
		return
	var raw: Dictionary = s.defaults().duplicate()
	raw["version"] = 2
	raw[&"fov"] = 110.0
	var out: Dictionary = s.sanitise(raw)
	eq(out, s.defaults(), "an otherwise-valid config with the wrong version must still default wholesale")

func test_a_missing_version_defaults_wholesale() -> void:
	var s := _script()
	if s == null:
		return
	var raw: Dictionary = s.defaults().duplicate()
	var out: Dictionary = s.sanitise(raw)
	eq(out, s.defaults(), "a config with no version key at all is not launch-day data and should default")

# --- 2. defaults match project.godot -----------------------------------------

func test_msaa_default_matches_project_godot() -> void:
	var s := _script()
	if s == null:
		return
	var text := _project_godot_text()
	check(text.contains("anti_aliasing/quality/msaa_3d=2"),
		"project.godot no longer sets msaa_3d=2 - the MSAA default below needs re-deriving, not assuming")
	eq(s.defaults()[&"msaa"], "4x", "msaa_3d=2 is Godot's MSAA_4X - the default row must match it")

func test_shadow_quality_default_matches_project_godot() -> void:
	var s := _script()
	if s == null:
		return
	var text := _project_godot_text()
	check(text.contains("lights_and_shadows/directional_shadow/size=8192"),
		"project.godot no longer sets an 8192 shadow atlas - the HIGH default below needs re-deriving")
	eq(s.defaults()[&"shadow_quality"], "high", "8192 is the HIGH atlas size - the default row must match it")

func test_render_scale_and_fov_defaults_are_untouched() -> void:
	var s := _script()
	if s == null:
		return
	eq(s.defaults()[&"render_scale"], 1.0, "no render scale is applied by default")
	eq(s.defaults()[&"fov"], 75.0, "camera_3d.fov in the authored scenes is 75")

# --- 3. step() clamps, does not wrap -----------------------------------------

func test_step_clamps_at_the_floor_on_a_discrete_row() -> void:
	var s := _script()
	if s == null:
		return
	eq(s.step(&"window_mode", 0, -1), 0, "stepping left of index 0 must clamp, not wrap to the end")

func test_step_clamps_at_the_ceiling_on_a_discrete_row() -> void:
	var s := _script()
	if s == null:
		return
	var last: int = s.values_of(&"window_mode").size() - 1
	eq(s.step(&"window_mode", last, 1), last, "stepping past the last index must clamp, not wrap to 0")

func test_step_clamps_on_a_stepped_continuous_row() -> void:
	var s := _script()
	if s == null:
		return
	eq(s.step(&"brightness", 0, -1), 0, "brightness must clamp at its floor")
	var last: int = s.values_of(&"brightness").size() - 1
	eq(s.step(&"brightness", last, 1), last, "brightness must clamp at its ceiling")

func test_step_moves_by_one_in_range() -> void:
	var s := _script()
	if s == null:
		return
	eq(s.step(&"fov", 3, 1), 4, "a normal step should move by exactly one index")
	eq(s.step(&"fov", 3, -1), 2, "a normal step should move by exactly one index")

# --- 4. round-trip -------------------------------------------------------------

func test_every_value_round_trips_through_a_config_file() -> void:
	var s := _script()
	if s == null:
		return
	var path := "user://test_settings_roundtrip.cfg"
	var cfg := ConfigFile.new()
	for row: Array in s.DEFS:
		cfg.set_value(String(row[2]), String(row[0]), row[3][row[4]])
	check(cfg.save(path) == OK, "could not save the round-trip config file")

	var reloaded := ConfigFile.new()
	check(reloaded.load(path) == OK, "could not reload the round-trip config file")
	for row: Array in s.DEFS:
		var key: StringName = row[0]
		var expected: Variant = row[3][row[4]]
		var actual: Variant = reloaded.get_value(String(row[2]), String(key))
		eq(actual, expected, "%s did not round-trip through ConfigFile" % key)
	eq(reloaded.get_value("display", "resolution"), Vector2i(1920, 1080),
		"Vector2i is the one type ConfigFile could plausibly mangle")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# --- 5. every default is a member of its own values --------------------------

func test_every_def_default_index_is_in_range() -> void:
	var s := _script()
	if s == null:
		return
	for row: Array in s.DEFS:
		var key: StringName = row[0]
		var values: Array = row[3]
		var default_index: int = row[4]
		check(default_index >= 0 and default_index < values.size(),
			"%s's default index %d is out of range for its own %d values" %
				[key, default_index, values.size()])

# --- 6. Left/Right are not bound to tab_prev / tab_next ----------------------

func test_left_and_right_are_not_bound_to_tab_prev() -> void:
	var block := _input_block("tab_prev")
	check(block != "", "could not find tab_prev in project.godot's [input] section")
	check(not block.contains("\"keycode\":4194319"),
		"tab_prev is still bound to Left (4194319) - Left must fall through to ui_left for row adjustment")
	check(block.contains("\"physical_keycode\":81"), "tab_prev should still carry Q")

func test_left_and_right_are_not_bound_to_tab_next() -> void:
	var block := _input_block("tab_next")
	check(block != "", "could not find tab_next in project.godot's [input] section")
	check(not block.contains("\"keycode\":4194321"),
		"tab_next is still bound to Right (4194321) - Right must fall through to ui_right for row adjustment")
	check(block.contains("\"physical_keycode\":69"), "tab_next should still carry E")

# --- 7. the display rows - see docs/specs/settings.md, Display Modes ---------

func test_first_launch_is_a_1080p_window() -> void:
	var s := _script()
	if s == null:
		return
	eq(s.defaults()[&"window_mode"], "windowed", "first launch is WINDOWED")
	eq(s.defaults()[&"resolution"], Vector2i(1920, 1080), "first launch is 1920x1080")

func test_project_godot_has_no_window_override() -> void:
	var text := _project_godot_text()
	check(not text.contains("window_width_override"),
		"project.godot overrides the window size again - it applies to exports too and fights the 1080p default")

func test_the_modes_are_windowed_borderless_fullscreen() -> void:
	var s := _script()
	if s == null:
		return
	eq(s.values_of(&"window_mode"), ["windowed", "borderless", "fullscreen"],
		"the row is WINDOWED / BORDERLESS / FULLSCREEN")

func test_an_old_exclusive_save_loads_as_fullscreen() -> void:
	var s := _script()
	if s == null:
		return
	var out: Dictionary = s.sanitise({"version": 1, &"window_mode": "exclusive"})
	eq(out[&"window_mode"], "fullscreen", "EXCLUSIVE was renamed, not removed - an old save keeps its mode")

func test_a_window_that_fits_the_desktop_fits() -> void:
	var s := _script()
	if s == null:
		return
	var usable := Rect2i(0, 0, 2560, 1400)
	check(s.window_fits(Vector2i(1920, 1080), usable, 31), "1080p fits a 1440p desktop with room to spare")
	check(not s.window_fits(Vector2i(2560, 1440), usable, 31),
		"a native-size window is taller than the desktop once the taskbar and title bar count")
	check(not s.window_fits(Vector2i(1920, 1080), Rect2i(0, 0, 1920, 1040), 31),
		"a 1080p window on a 1080p monitor does not fit under the taskbar")

func test_3d_scale_in_a_window_is_just_render_scale() -> void:
	var s := _script()
	if s == null:
		return
	eq(s.scale_3d(Vector2i(1280, 720), Vector2i(1280, 720), 0.75), 0.75,
		"a window the size of the resolution renders at render scale alone")

func test_3d_scale_in_fullscreen_is_the_resolution_over_the_screen() -> void:
	var s := _script()
	if s == null:
		return
	eq(s.scale_3d(Vector2i(1280, 720), Vector2i(2560, 1440), 1.0), 0.5,
		"720p on a 1440p screen renders the 3D at half size")
	eq(s.scale_3d(Vector2i(1280, 720), Vector2i(2560, 1440), 0.5), 0.25,
		"RESOLUTION and RENDER SCALE multiply")

func test_3d_scale_never_supersamples() -> void:
	var s := _script()
	if s == null:
		return
	eq(s.scale_3d(Vector2i(2560, 1440), Vector2i(2560, 1400), 1.0), 1.0,
		"a maximized window slightly smaller than the resolution renders at window size, not above it")

func test_3d_scale_on_a_non_16_9_screen_measures_the_letterboxed_area() -> void:
	var s := _script()
	if s == null:
		return
	eq(s.scale_3d(Vector2i(1920, 1080), Vector2i(1920, 1200), 1.0), 1.0,
		"stretch aspect is keep, so 16:10 letterboxes to 1920x1080 - 1080p already fills it")
	eq(s.scale_3d(Vector2i(960, 540), Vector2i(1920, 1200), 1.0), 0.5,
		"540p is half the letterboxed 1920x1080 area, not half of anything involving 1200")

# --- helpers -----------------------------------------------------------------

func _project_godot_text() -> String:
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	if f == null:
		fail("could not read project.godot")
		return ""
	return f.get_as_text()

func _input_block(action: String) -> String:
	var text := _project_godot_text()
	var start := text.find(action + "={")
	if start < 0:
		return ""
	var stop := text.find("\n}\n", start)
	if stop < 0:
		return ""
	return text.substr(start, stop - start)
