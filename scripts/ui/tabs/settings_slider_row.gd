extends "res://scripts/ui/menu_row.gd"

# One row of a continuous setting (BRIGHTNESS, both sensitivities, FOV): LABEL, then
# `[=======|------]  72` in the same fixed-width control column the selector rows use. Drawn and
# dragged entirely in script rather than a stock HSlider - HSlider's grabber is a Texture2D, an art
# asset this project does not have. See docs/specs/menu-refresh.md, "SETTINGS rows".
#
# Left/Right still index-step it exactly like a discrete row - tab_settings.gd's _input does not
# know this control is any different. Dragging or clicking the track jumps; that is additive, for
# a mouse. A drag writes straight to Settings and repaints the track from it, but the printed value
# is only ever handed down by sync() (formatting belongs to tab_settings.gd), so a drag emits
# `dragged` and the tab syncs again.

signal dragged

const SettingsScript := preload("res://scripts/settings.gd")
const CONTROL_WIDTH := 300.0
const VALUE_WIDTH := 64.0
const RIGHT_MARGIN := 16.0
const TRACK_HEIGHT := 4.0
const HANDLE_WIDTH := 8.0
const HANDLE_HEIGHT := 16.0
const TRACK_IDLE_ALPHA := 0.25
const FILL_IDLE_ALPHA := 0.45

var key: StringName
var _value_text := ""
var _dragging := false

func setup(k: StringName) -> void:
	key = k

## Called by tab_settings.gd after every value change.
func sync(label: String, value_text: String) -> void:
	text = label
	_value_text = value_text
	queue_redraw()

## The track's horizontal extent, in this control's coordinates.
func track_span() -> Vector2:
	var x0 := size.x - RIGHT_MARGIN - CONTROL_WIDTH
	return Vector2(x0, x0 + CONTROL_WIDTH - VALUE_WIDTH)

func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var span := track_span()
			# A little slack either side so the ends are easy to hit.
			if event.position.x >= span.x - 12.0 and event.position.x <= span.y + 12.0:
				_dragging = true
				grab_focus()
				_set_from_x(event.position.x)
				accept_event()
				return
		elif _dragging:
			_dragging = false
			accept_event()
			return
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x(event.position.x)
		accept_event()
		return
	super._gui_input(event)

func _set_from_x(x: float) -> void:
	var values := SettingsScript.values_of(key)
	var span := track_span()
	if values.is_empty() or span.y <= span.x:
		return
	var ratio := clampf((x - span.x) / (span.y - span.x), 0.0, 1.0)
	var index := clampi(roundi(ratio * float(values.size() - 1)), 0, values.size() - 1)
	Settings.set_value(key, values[index])
	dragged.emit()
	queue_redraw()

func _draw_content() -> void:
	super._draw_content()
	var font := get_theme_font(&"font")
	var font_size := get_theme_font_size(&"font_size")
	var span := track_span()
	var right_edge := size.x - RIGHT_MARGIN
	draw_string(font, Vector2(span.y + 12.0, _baseline(font, font_size)), _value_text,
		HORIZONTAL_ALIGNMENT_RIGHT, right_edge - span.y - 12.0, font_size, text_color())
	_draw_track(span)

func _draw_track(span: Vector2) -> void:
	var values := SettingsScript.values_of(key)
	if values.is_empty():
		return
	var ratio := float(Settings.index_for(key)) / float(maxi(values.size() - 1, 1))
	var y := size.y * 0.5 - TRACK_HEIGHT * 0.5
	var accent := accent_color()
	var pressed_scale := press_scale()
	var track := Color(accent, lerpf(TRACK_IDLE_ALPHA, 0.35, selected_amount) * pressed_scale)
	var fill := Color(accent, lerpf(FILL_IDLE_ALPHA, 1.0, selected_amount) * pressed_scale)
	var width := span.y - span.x
	draw_rect(Rect2(span.x, y, width, TRACK_HEIGHT), track)
	draw_rect(Rect2(span.x, y, width * ratio, TRACK_HEIGHT), fill)
	var handle_x := span.x + width * ratio
	draw_rect(Rect2(handle_x - HANDLE_WIDTH * 0.5, size.y * 0.5 - HANDLE_HEIGHT * 0.5,
		HANDLE_WIDTH, HANDLE_HEIGHT), fill)
