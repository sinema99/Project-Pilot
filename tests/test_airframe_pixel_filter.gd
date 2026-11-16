extends "res://tests/test_case.gd"

# AIRFRAME's pixel filter: PixelWorld back on, for AIRFRAME only, 2X by default, with its own PIXEL
# FILTER row. See docs/specs/airframe-pixel-filter.md. The look is judged by eye; this fences the
# decisions that would fail quietly - RETRO pixelating, a save that cannot reach the row, a map
# without an AirframeLook pixelating under AIRFRAME, the row editable under the wrong look.

const SETTINGS := preload("res://scripts/settings.gd")
const TAB := preload("res://scripts/ui/tabs/tab_settings.gd")

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

# --- settings ------------------------------------------------------------------

func test_airframe_pixels_default_to_2x() -> void:
	eq(SETTINGS.defaults()[&"pixel_airframe_size"], 2, "2X on first launch")
	eq(SETTINGS.values_of(&"pixel_airframe_size"), [0, 2, 3, 4, 6], "OFF / 2X / 3X / 4X / 6X")
	eq(SETTINGS.label_of(&"pixel_airframe_size"), "PIXEL FILTER", "the row's name")

func test_the_row_is_back_and_saves() -> void:
	check(not SETTINGS.HIDDEN_KEYS.has(&"pixel_airframe_size"), "not a hidden key")
	check(not TAB.ROWLESS_KEYS.has(&"pixel_airframe_size"), "it has a menu row")
	var out := SETTINGS.sanitise({"version": SETTINGS.CONFIG_VERSION, &"pixel_airframe_size": 4,
			SETTINGS.AIRFRAME_FLAG: true})
	eq(out[&"pixel_airframe_size"], 4, "a picked size survives a reload")
	var old := SETTINGS.sanitise({"version": SETTINGS.CONFIG_VERSION, SETTINGS.AIRFRAME_FLAG: true})
	eq(old[&"pixel_airframe_size"], 2, "a save from before the key boots at 2X")

func test_the_other_looks_stay_sharp() -> void:
	# RETRO's own key stays hidden and OFF, so nothing a save holds can pixelate it.
	check(SETTINGS.HIDDEN_KEYS.has(&"pixel_size"), "RETRO's key stays hidden")
	eq(SETTINGS.sanitise({"version": SETTINGS.CONFIG_VERSION, &"pixel_size": 3})[&"pixel_size"], 0,
		"and loads OFF")
	for look: String in ["retro", "composite"]:
		eq(SETTINGS.effective_pixel_size(0, 4, look, 2, true), 0, look + " is not pixelated")

func test_airframe_draws_its_own_size_only_where_it_runs() -> void:
	eq(SETTINGS.effective_pixel_size(0, 4, "airframe", 2, true), 2, "trial at 2X")
	eq(SETTINGS.effective_pixel_size(0, 4, "airframe", 6, true), 6, "trial at 6X")
	eq(SETTINGS.effective_pixel_size(0, 4, "airframe", 0, true), 0, "OFF is OFF")
	eq(SETTINGS.effective_pixel_size(0, 4, "airframe", 2, false), 0,
		"a map showing RETRO for AIRFRAME stays sharp")

func test_no_colour_banding_and_no_supersample() -> void:
	eq(SETTINGS.colour_levels("airframe", 0), 0, "full colour")
	eq(SETTINGS.pixel_supersample("airframe"), 2, "2x2 texels per block, averages out the far-ground moire rings")

# --- the menu row --------------------------------------------------------------

func _row(tab: Node, key: StringName) -> Control:
	for control: Control in tab.rows():
		if tab.key_of(control) == key:
			return control
	return null

func test_the_row_greys_out_under_the_other_looks() -> void:
	var settings: Node = _tree().root.get_node(^"Settings")
	var saved := {}
	for key: StringName in [&"look", &"pixel_airframe_size"]:
		saved[key] = settings.get_value(key)
	var tab: Node = TAB.new()
	_tree().root.add_child(tab)
	settings.set_value(&"pixel_airframe_size", 2)
	settings.set_value(&"look", "retro")
	tab.refresh()
	var row := _row(tab, &"pixel_airframe_size")
	check(row != null, "the PIXEL FILTER row is built")
	check(row.disabled, "greyed under RETRO")
	eq(row.value_text, TAB.AIRFRAME_ONLY_TEXT, "and says why")
	check(not _row(tab, &"msaa").disabled, "RETRO keeps MSAA")
	settings.set_value(&"look", "airframe")
	tab.refresh()
	check(not row.disabled, "live under AIRFRAME")
	eq(row.value_text, "2X", "showing its size")
	check(_row(tab, &"msaa").disabled, "MSAA greys while the pixels are on")
	tab._step(-1, &"pixel_airframe_size")
	eq(settings.pixel_airframe_size, 0, "steps to OFF")
	check(not _row(tab, &"msaa").disabled, "and MSAA comes back with it")
	tab.free()
	for key: StringName in saved:
		settings.set_value(key, saved[key])
