extends "res://tests/test_case.gd"

# Asserts the SHAPE of the theme, never its values. See docs/specs/ui-shell.md and
# docs/specs/menu-refresh.md.
#
# The old version of this file pinned every colour to a hex string, which meant each deliberate
# nudge to a border or a dim was a two-file change. What is worth catching here is the theme
# failing to load or a variation losing its base type - both silent failures, because Godot just
# falls back to engine defaults and the game still runs, looking like a different program.
#
# The one rule that IS asserted structurally is "a row draws its own state", because the whole
# look depends on it and it can be broken by accident: a row that regains a filled stylebox would
# paint a second, static highlight under MenuRow's animated one.

const THEME_PATH := "res://resources/ui_theme.tres"

# variation -> the type it must vary. Adding a variation to the theme without
# adding it here is fine; renaming one out from under a scene is what this catches.
const VARIATIONS := {
	"ScreenTitle": &"Label",
	"DialogTitle": &"Label",
	"MenuRow": &"Button",
	"MenuTab": &"Button",
	"SectionHeader": &"Label",
	"Body": &"Label",
	"BodyDim": &"Label",
	"HintLabel": &"Label",
	"HintKey": &"Label",
	"Keycap": &"PanelContainer",
}

func _theme() -> Theme:
	# Runtime load, not preload: preload of a missing path is a parse-time
	# failure, which makes --script fall back to running main.tscn and hang.
	return load(THEME_PATH) as Theme

func test_theme_loads() -> void:
	check(_theme() != null, "%s should load" % THEME_PATH)

func test_the_font_resolves_and_is_barlow_condensed() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	check(theme.default_font != null, "the theme should carry a default font")
	if theme.default_font == null:
		return
	# The face is the identity of this UI - with no fills and no colour there is
	# very little else. A missing .ttf import silently yields the engine default.
	eq(theme.default_font.get_font_name(), "Barlow Condensed",
		"the default font should be Barlow Condensed, not the engine fallback")

func test_every_variation_exists_with_its_base_type() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	for name: String in VARIATIONS:
		eq(theme.get_type_variation_base(name), VARIATIONS[name],
			"%s should vary %s" % [name, VARIATIONS[name]])

# A FontVariation with a broken base_font resolves to null and every control
# using it silently drops to the engine face at the wrong size.
func test_every_text_variation_resolves_a_font() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	for name: String in ["ScreenTitle", "MenuTab", "SectionHeader", "Body", "HintLabel"]:
		check(theme.get_font("font", name) != null, "%s should resolve a font" % name)
	check(theme.get_font("font", "Button") != null, "menu rows should resolve a font")
	check(theme.get_font("font", "MenuRow") != null, "the MenuRow variation should resolve a font")

# Not exact sizes - those move every time the look is tuned - but the ordering,
# which is the actual design decision.
func test_the_type_hierarchy_holds() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	var title := theme.get_font_size("font_size", "ScreenTitle")
	var row := theme.get_font_size("font_size", "Button")
	var tab := theme.get_font_size("font_size", "MenuTab")
	var hint := theme.get_font_size("font_size", "HintLabel")
	check(title > row, "the screen title should be larger than a menu row")
	check(row > tab, "a menu row should be larger than a tab label")
	check(tab > hint, "a tab label should be larger than the hint bar")

# Panels and keycaps: a keycap is a hairline outline, and the plain panel draws nothing (the
# window's fill and rim belong to MenuFrame, which can cut a corner).
func test_keycaps_are_unfilled_hairlines_and_panels_draw_nothing() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	var keycap := theme.get_stylebox("panel", "Keycap") as StyleBoxFlat
	if keycap == null:
		fail("Keycap should use a StyleBoxFlat panel")
	else:
		check(not keycap.draw_center, "a keycap should not be filled")
		eq(keycap.border_width_top, 1, "a keycap should have a 1px border")
		eq(keycap.corner_radius_top_left, 0, "keycap corners should be square")
	check(theme.get_stylebox("panel", "PanelContainer") is StyleBoxEmpty,
		"a plain PanelContainer should draw nothing - MenuFrame draws the window")

# MenuRow paints fill, bar and label itself (a StyleBox cannot tween), so every stylebox it has
# must be empty and its own font colours transparent, or the label would be drawn twice.
func test_menu_rows_and_tabs_draw_nothing_themselves() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	for type: String in ["MenuRow", "MenuTab"]:
		for state: String in ["normal", "hover", "focus", "pressed", "disabled"]:
			check(theme.get_stylebox(state, type) is StyleBoxEmpty,
				"%s should draw no box in the %s state" % [type, state])
		eq(theme.get_color("font_color", type).a, 0.0,
			"%s should have a transparent Button label - MenuRow draws the label" % type)

# The two colours the row states are drawn from.
func test_menu_row_carries_its_palette() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	for name: String in ["accent", "destructive", "text"]:
		check(theme.has_color(name, "MenuRow"), "MenuRow should carry a %s colour" % name)
