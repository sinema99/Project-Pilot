extends "res://tests/test_case.gd"

# Asserts the SHAPE of the theme, never its values. See docs/specs/ui-shell.md.
#
# The old version of this file pinned every colour to a hex string, which meant
# each deliberate nudge to a border or a dim was a two-file change. What is worth
# catching here is the theme failing to load or a variation losing its base type -
# both silent failures, because Godot just falls back to engine defaults and the
# game still runs, looking like a different program.
#
# The one rule that IS asserted structurally is "nothing is filled except a
# selected row", because that is the whole look and it can be broken by accident.

const THEME_PATH := "res://resources/ui_theme.tres"

# variation -> the type it must vary. Adding a variation to the theme without
# adding it here is fine; renaming one out from under a scene is what this catches.
const VARIATIONS := {
	"ScreenTitle": &"Label",
	"DialogTitle": &"Label",
	"TabButton": &"Button",
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
	for name: String in ["ScreenTitle", "TabButton", "SectionHeader", "Body", "HintLabel"]:
		check(theme.get_font("font", name) != null, "%s should resolve a font" % name)
	check(theme.get_font("font", "Button") != null, "menu rows should resolve a font")

# Not exact sizes - those move every time the look is tuned - but the ordering,
# which is the actual design decision.
func test_the_type_hierarchy_holds() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	var title := theme.get_font_size("font_size", "ScreenTitle")
	var row := theme.get_font_size("font_size", "Button")
	var tab := theme.get_font_size("font_size", "TabButton")
	var hint := theme.get_font_size("font_size", "HintLabel")
	check(title > row, "the screen title should be larger than a menu row")
	check(row > tab, "a menu row should be larger than a tab label")
	check(tab > hint, "a tab label should be larger than the hint bar")

# The whole look: hairline boxes over the dim, nothing filled.
func test_boxes_are_unfilled_hairlines_with_square_corners() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	for type: String in ["PanelContainer", "Keycap"]:
		var box := theme.get_stylebox("panel", type) as StyleBoxFlat
		if box == null:
			fail("%s should use a StyleBoxFlat panel" % type)
			continue
		check(not box.draw_center, "%s should not be filled - the dim shows through" % type)
		eq(box.border_width_top, 1, "%s should have a 1px border" % type)
		eq(box.border_width_left, 1, "%s should have a 1px border" % type)
		eq(box.corner_radius_top_left, 0, "%s corners should be square" % type)
		eq(box.corner_radius_bottom_right, 0, "%s corners should be square" % type)

# The single bright mass on screen. If an unselected row ever gains a fill, the
# eye loses the one anchor the design gives it.
func test_only_the_selected_row_is_filled() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	var normal := theme.get_stylebox("normal", "Button")
	check(normal is StyleBoxEmpty, "an unselected row should draw no box at all")
	var selected := theme.get_stylebox("focus", "Button") as StyleBoxFlat
	if selected == null:
		fail("a selected row should use a StyleBoxFlat")
		return
	check(selected.draw_center, "a selected row should be filled")
	eq(selected.bg_color.a, 1.0, "the selected fill should be fully opaque")

# Hover moves focus rather than drawing a second highlight, so these must be the
# same stylebox - not merely two boxes that happen to match today.
func test_hover_and_focus_are_the_same_stylebox() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	check(theme.get_stylebox("hover", "Button") == theme.get_stylebox("focus", "Button"),
		"hover and focus should be the identical stylebox, so pointer and keyboard cannot disagree")

# Tabs are marked with an underline drawn by shell.gd. A filled tab would put a
# second solid white block on screen, competing with the selected row.
func test_tabs_are_never_filled() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	for state: String in ["normal", "hover", "focus", "pressed"]:
		check(theme.get_stylebox(state, "TabButton") is StyleBoxEmpty,
			"a tab should draw no box in the %s state" % state)
