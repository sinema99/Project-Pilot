extends "res://tests/test_case.gd"

# AIRFRAME's character look: pilots, mech, speeder and anything alive or driven drawn in their own
# coarser block grid (CHARACTER PIXELS, 4X by default) and lit flat per face, while the world stays
# at its own PIXEL FILTER size. See docs/specs/airframe-character-pixels.md. The look is judged by
# eye; this fences the decisions that would fail quietly - a saved size that cannot reach the
# row, the grid turning on where the world is sharp, a character the layer tag misses.

const SETTINGS := preload("res://scripts/settings.gd")
const TAB := preload("res://scripts/ui/tabs/tab_settings.gd")

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

# --- settings ------------------------------------------------------------------

func test_character_pixels_default_to_4x() -> void:
	eq(SETTINGS.defaults()[&"pixel_char_size"], 4, "4X on first launch")
	eq(SETTINGS.values_of(&"pixel_char_size"), [0, 3, 4, 6], "OFF / 3X / 4X / 6X")
	eq(SETTINGS.label_of(&"pixel_char_size"), "CHARACTER PIXELS", "the row's name")
	check(not SETTINGS.HIDDEN_KEYS.has(&"pixel_char_size"), "not a hidden key")
	var out := SETTINGS.sanitise({"version": SETTINGS.CONFIG_VERSION, &"pixel_char_size": 6})
	eq(out[&"pixel_char_size"], 6, "a picked size survives a reload")
	eq(SETTINGS.sanitise({"version": SETTINGS.CONFIG_VERSION})[&"pixel_char_size"], 4,
		"a save from before the key boots at 4X")

func test_the_character_grid_only_runs_where_airframe_pixels_do() -> void:
	eq(SETTINGS.effective_char_size("airframe", true, 2, 4), 4, "AIRFRAME in trial at 2X: 4X characters")
	eq(SETTINGS.effective_char_size("airframe", true, 2, 0), 0, "OFF is OFF")
	eq(SETTINGS.effective_char_size("airframe", true, 0, 4), 0, "world filter OFF: no grid")
	eq(SETTINGS.effective_char_size("airframe", false, 2, 4), 0, "a map with no AirframeLook")
	for look: String in ["retro", "composite", "cel", "pixel"]:
		eq(SETTINGS.effective_char_size(look, true, 2, 4), 0, look + " is not an AIRFRAME look")

# --- layer tags ------------------------------------------------------------------

func test_characters_are_found_by_body_or_meta() -> void:
	var body := CharacterBody3D.new()
	var mesh := MeshInstance3D.new()
	body.add_child(mesh)
	check(AirframeLook.is_character(mesh), "a mesh under a CharacterBody3D (pilot, mech, speeder)")
	var prop := Node3D.new()
	var prop_mesh := MeshInstance3D.new()
	prop.add_child(prop_mesh)
	check(not AirframeLook.is_character(prop_mesh), "a level prop is not")
	prop.set_meta(&"airframe_character", true)
	check(AirframeLook.is_character(prop_mesh), "the meta marks the range dummy / knight")
	body.free()
	prop.free()

func test_the_character_layer_is_free() -> void:
	eq(PixelWorld.CHAR_MASK, 1 << 17, "layer 18")
	check(PixelWorld.CHAR_MASK & PixelWorld.SHARP_MASK == 0, "not the sharp layer")

# --- the row ---------------------------------------------------------------------

func _row(tab: Node, key: StringName) -> Control:
	for control: Control in tab._row_keys:
		if tab._row_keys[control] == key:
			return control
	return null

func test_the_row_follows_the_look_and_the_world_filter() -> void:
	var settings: Node = _tree().root.get_node(^"Settings")
	var saved := {}
	for key: StringName in [&"look", &"pixel_airframe_size", &"pixel_char_size"]:
		saved[key] = settings.get_value(key)
	var tab: Node = TAB.new()
	_tree().root.add_child(tab)
	settings.set_value(&"pixel_char_size", 4)
	settings.set_value(&"pixel_airframe_size", 2)
	settings.set_value(&"look", "retro")
	tab.refresh()
	var row := _row(tab, &"pixel_char_size")
	check(row != null, "the CHARACTER PIXELS row is built")
	check(row.disabled, "greyed under RETRO")
	eq(row.value_text, TAB.AIRFRAME_ONLY_TEXT, "and says why")
	settings.set_value(&"look", "airframe")
	tab.refresh()
	check(not row.disabled, "live under AIRFRAME")
	eq(row.value_text, "4X", "showing its size")
	settings.set_value(&"pixel_airframe_size", 0)
	tab.refresh()
	check(row.disabled, "greyed while the world filter is OFF")
	eq(row.value_text, TAB.NEEDS_FILTER_TEXT, "and says why")
	tab.free()
	for key: StringName in saved:
		settings.set_value(key, saved[key])
