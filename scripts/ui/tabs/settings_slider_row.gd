extends Control

# One row of a continuous setting (BRIGHTNESS, both sensitivities, FOV),
# drawn and dragged entirely in script rather than a stock HSlider - see
# docs/specs/settings.md, A Row Is A Button. HSlider's grabber is a
# Texture2D, an art asset this project does not have; this draws a flat
# white handle instead, matching the theme's hairline aesthetic with no new
# resources.
#
# Left/Right still index-step it exactly like a discrete row - _input() in
# tab_settings.gd does not know this control is any different. The drag
# below is additive, for a mouse.
#
# A drag writes straight to Settings and repaints the track from it, but the
# printed value (_value_text) is only ever handed down by sync() - it has no
# way to reformat itself, since _format_value() belongs to tab_settings.gd.
# So a drag emits `dragged` and tab_settings.gd calls sync() again in
# response, the same refresh a keyboard step already gets. Without this the
# handle tracks the mouse and the number next to it does not.
signal dragged

const TRACK_HEIGHT := 3.0
const HANDLE_WIDTH := 4.0
const HANDLE_HEIGHT := 14.0
const SIDE_MARGIN := 16.0

var key: StringName
var _label := ""
var _value_text := ""

func setup(k: StringName) -> void:
	key = k
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = 52
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_entered.connect(grab_focus)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)

## Called by tab_settings.gd after every value change - it owns formatting
## (_format_value), this control only ever draws strings it is handed.
func sync(label: String, value_text: String) -> void:
	_label = label
	_value_text = value_text
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		_set_from_x(event.position.x)
		accept_event()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_set_from_x(event.position.x)
		accept_event()

func _set_from_x(x: float) -> void:
	var values := Settings.values_of(key)
	var span := size.x - SIDE_MARGIN * 2.0
	if values.is_empty() or span <= 0.0:
		return
	var ratio := clampf((x - SIDE_MARGIN) / span, 0.0, 1.0)
	var index := clampi(roundi(ratio * float(values.size() - 1)), 0, values.size() - 1)
	Settings.set_value(key, values[index])
	dragged.emit()
	queue_redraw()

func _draw() -> void:
	var selected := has_focus()
	if selected:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 1))
	var font: Font = get_theme_font(&"font", &"Button")
	var font_size: int = get_theme_font_size(&"font_size", &"Button")
	var color := Color.BLACK if selected else Color.WHITE
	var baseline := size.y * 0.5 - 8.0
	draw_string(font, Vector2(SIDE_MARGIN, baseline), _label,
		HORIZONTAL_ALIGNMENT_LEFT, size.x - SIDE_MARGIN * 2.0, font_size, color)
	draw_string(font, Vector2(SIDE_MARGIN, baseline), _value_text,
		HORIZONTAL_ALIGNMENT_RIGHT, size.x - SIDE_MARGIN * 2.0, font_size, color)
	_draw_track(selected)

func _draw_track(selected: bool) -> void:
	var values := Settings.values_of(key)
	if values.is_empty():
		return
	var index := Settings.index_for(key)
	var ratio := float(index) / float(maxi(values.size() - 1, 1))
	var span := size.x - SIDE_MARGIN * 2.0
	var y := size.y - 14.0
	var track_color := Color(0, 0, 0, 0.35) if selected else Color(1, 1, 1, 0.25)
	var fill_color := Color(0, 0, 0, 0.85) if selected else Color(1, 1, 1, 0.85)
	draw_rect(Rect2(SIDE_MARGIN, y, span, TRACK_HEIGHT), track_color)
	draw_rect(Rect2(SIDE_MARGIN, y, span * ratio, TRACK_HEIGHT), fill_color)
	var handle_x := SIDE_MARGIN + span * ratio
	draw_rect(Rect2(handle_x - HANDLE_WIDTH * 0.5, y - (HANDLE_HEIGHT - TRACK_HEIGHT) * 0.5,
		HANDLE_WIDTH, HANDLE_HEIGHT), fill_color)
