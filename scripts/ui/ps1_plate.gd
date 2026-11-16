class_name Ps1Plate
extends PanelContainer

# The HUD's PS1 window: flat dark plate, hard bright top-left / dark bottom-right bevel with notched
# corners. No alpha blend, no dither pattern. The menus and the inventory draw the same look
# themselves; this is the shared piece for plain Control HUDs. See docs/specs/ps1-ui.md.

const FONT := preload("res://assets/fonts/PixelifySans.ttf")
const CYAN := Color(0.251, 0.949, 0.902)
const PLATE := Color(0.02, 0.055, 0.065)
const SHADE := Color(0.0, 0.42, 0.42)
const TEXT := Color(0.92, 0.95, 0.95)


## A Label in the PS1 face (pixel font, hard 1px drop shadow, no smoothing).
static func make_label(px_size: int, colour: Color = TEXT) -> Label:
	var label := Label.new()
	label.add_theme_font_override(&"font", FONT)
	label.add_theme_font_size_override(&"font_size", px_size)
	label.add_theme_color_override(&"font_color", colour)
	label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override(&"shadow_offset_x", 1)
	label.add_theme_constant_override(&"shadow_offset_y", 1)
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, PLATE)
	draw_rect(Rect2(1, 0, r.size.x - 2, 1), CYAN)
	draw_rect(Rect2(0, 1, 1, r.size.y - 2), CYAN)
	draw_rect(Rect2(1, r.size.y - 1, r.size.x - 2, 1), SHADE)
	draw_rect(Rect2(r.size.x - 1, 1, 1, r.size.y - 2), SHADE)
