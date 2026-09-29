extends "res://scripts/ui/menu_row.gd"

# One entry in the ABILITIES list: the ability's name on the left, a status tag on the right.
# Focusable so the detail pane can follow it; pressing it does nothing. See
# docs/specs/menu-refresh.md, "The other tabs".

const TAG_COLUMN_MARGIN := 16.0

var unlocked := false:
	set(value):
		unlocked = value
		queue_redraw()
var status_text := "LOCKED"

func _init() -> void:
	super._init()
	# Tighter than a settings row so the whole list fits without scrolling.
	var tight := StyleBoxEmpty.new()
	tight.content_margin_left = 22.0
	tight.content_margin_right = 16.0
	tight.content_margin_top = 5.0
	tight.content_margin_bottom = 5.0
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(state, tight)

func _draw_content() -> void:
	super._draw_content()
	var font := get_theme_font(&"font")
	var font_size := get_theme_font_size(&"font_size") - 6
	var color := accent_color() if unlocked else text_color()
	color.a = text_color().a if not unlocked else press_scale()
	draw_string(font, Vector2(0.0, _baseline(font, font_size)), status_text,
		HORIZONTAL_ALIGNMENT_RIGHT, size.x - TAG_COLUMN_MARGIN, font_size, color)
