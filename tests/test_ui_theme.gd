extends "res://tests/test_case.gd"

const THEME_PATH := "res://resources/ui_theme.tres"

# Every expected value here comes from the palette table in
# docs/specs/ui-system.md, never from reading the .tres back.
const BODY := "3a3532"
const HEADER := "efe9df"
const INK := "1a1410"
const BODY_TEXT := "ede6da"
const HOVER := "5a534e"
const PRESSED := "2e2a27"

func _theme() -> Theme:
	return load(THEME_PATH) as Theme

func _flat(theme: Theme, name: String, type: String) -> StyleBoxFlat:
	return theme.get_stylebox(name, type) as StyleBoxFlat

func test_theme_loads() -> void:
	check(_theme() != null, "%s should load" % THEME_PATH)

func test_window_body_is_warm_charcoal_inside_a_thin_ink_border() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	var body := _flat(theme, "panel", "PanelContainer")
	eq(body.bg_color.to_html(false), BODY, "the window body should be warm charcoal")
	eq(body.border_color.to_html(false), INK, "the border should be the Moebius ink colour, not black")
	eq(body.border_width_top, 1, "the border should be 1px")
	eq(body.border_width_left, 1, "the border should be 1px")

# "Very basic rectangular shape" was the brief, and the reference is square.
func test_the_window_has_square_corners() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	var body := _flat(theme, "panel", "PanelContainer")
	eq(body.corner_radius_top_left, 0, "corners should be square")
	eq(body.corner_radius_bottom_right, 0, "corners should be square")

func test_header_is_light_with_ink_title_text() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	eq(theme.get_type_variation_base("WindowHeader"), &"PanelContainer",
		"WindowHeader should vary PanelContainer")
	eq(_flat(theme, "panel", "WindowHeader").bg_color.to_html(false), HEADER,
		"the header strip should be warm off-white")
	eq(theme.get_type_variation_base("WindowTitle"), &"Label",
		"WindowTitle should vary Label")
	eq(theme.get_color("font_color", "WindowTitle").to_html(false), INK,
		"title text on the light header should be ink")
	eq(theme.get_font_size("font_size", "WindowTitle"), 20, "title text should be 20px")

func test_button_text_and_sizes() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	eq(theme.get_color("font_color", "Button").to_html(false), BODY_TEXT,
		"button text should be the warm off-white body colour")
	eq(theme.get_font_size("font_size", "Button"), 18, "buttons should be 18px")
	eq(theme.default_font_size, 16, "body text should default to 16px")

# Hover moves focus rather than drawing a second highlight, so the two states
# must look identical - otherwise the pointer and the keyboard can appear to
# disagree about which entry is selected.
func test_button_hover_and_focus_are_the_same_colour() -> void:
	var theme := _theme()
	if theme == null:
		fail("%s does not exist" % THEME_PATH)
		return
	eq(_flat(theme, "hover", "Button").bg_color.to_html(false), HOVER, "hover should be the lifted grey")
	eq(_flat(theme, "focus", "Button").bg_color.to_html(false), HOVER, "focus should match hover exactly")
	eq(_flat(theme, "pressed", "Button").bg_color.to_html(false), PRESSED, "pressed should be the darkest grey")
