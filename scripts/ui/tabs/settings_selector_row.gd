extends "res://scripts/ui/menu_row.gd"

# A discrete SETTINGS row: LABEL on the left, `<  VALUE  >` in a fixed-width column on the right
# so every control lines up. See docs/specs/menu-refresh.md, "SETTINGS rows".
#
# The arrows are drawn as chevrons rather than the typographic guillemets: Barlow Condensed has
# no arrow glyphs and a missing one renders as a box. Clicking an arrow steps one value and keeps
# focus on the row; clicking the row itself only focuses it. At either end the arrow that would go
# further is drawn at ARROW_END_ALPHA and does nothing - the list clamps, it does not wrap.
#
# The row only reports `stepped(direction)`; what a step means (Settings, the display revert) is
# tab_settings.gd's business.

signal stepped(direction: int)

## Width of the control column, and the arrow click zones at its two ends. Shared with the slider
## row so both kinds line up.
const CONTROL_WIDTH := 300.0
const ARROW_ZONE := 44.0
const ARROW_HALF_HEIGHT := 7.0
const ARROW_DEPTH := 5.0
const ARROW_IDLE_ALPHA := 0.4
const ARROW_END_ALPHA := 0.35
const RIGHT_MARGIN := 16.0

var value_text := ""
var can_left := true
var can_right := true
## Two-value rows (on/off) let ENTER flip them; a longer list has no obvious "next".
var toggles_on_confirm := false

func sync(label: String, value: String, left_ok: bool, right_ok: bool) -> void:
	text = label
	value_text = value
	can_left = left_ok
	can_right = right_ok
	queue_redraw()

func control_rect() -> Rect2:
	return Rect2(size.x - RIGHT_MARGIN - CONTROL_WIDTH, 0.0, CONTROL_WIDTH, size.y)

func left_zone() -> Rect2:
	var rect := control_rect()
	return Rect2(rect.position.x, 0.0, ARROW_ZONE, size.y)

func right_zone() -> Rect2:
	var rect := control_rect()
	return Rect2(rect.end.x - ARROW_ZONE, 0.0, ARROW_ZONE, size.y)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not disabled:
		var pos: Vector2 = event.position
		var direction := 0
		if left_zone().has_point(pos):
			direction = -1
		elif right_zone().has_point(pos):
			direction = 1
		if direction != 0:
			accept_event()
			grab_focus()
			if (direction < 0 and can_left) or (direction > 0 and can_right):
				stepped.emit(direction)
			return
	super._gui_input(event)

func _confirm() -> void:
	if toggles_on_confirm:
		stepped.emit(-1 if can_left and not can_right else 1)

func _draw_content() -> void:
	super._draw_content()
	var rect := control_rect()
	var font := get_theme_font(&"font")
	var font_size := get_theme_font_size(&"font_size")
	draw_string(font, Vector2(rect.position.x + ARROW_ZONE, _baseline(font, font_size)), value_text,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - ARROW_ZONE * 2.0, font_size, text_color())
	var lit := lerpf(ARROW_IDLE_ALPHA, 1.0, selected_amount) * press_scale()
	_draw_chevron(left_zone().get_center(), -1.0, lit if can_left else minf(lit, ARROW_END_ALPHA))
	_draw_chevron(right_zone().get_center(), 1.0, lit if can_right else minf(lit, ARROW_END_ALPHA))

func _draw_chevron(center: Vector2, facing: float, alpha: float) -> void:
	var base := get_theme_color(&"text", &"MenuRow") if has_theme_color(&"text", &"MenuRow") else FALLBACK_TEXT
	var color := Color(base, alpha * (DISABLED_ALPHA / IDLE_ALPHA if disabled else 1.0))
	var tip := center + Vector2(facing * ARROW_DEPTH * 0.5, 0.0)
	var back := center - Vector2(facing * ARROW_DEPTH * 0.5, 0.0)
	draw_polyline(PackedVector2Array([back + Vector2(0.0, -ARROW_HALF_HEIGHT), tip,
		back + Vector2(0.0, ARROW_HALF_HEIGHT)]), color, 2.0, true)
