extends Button

# The one selectable thing every menu screen is built from: GAME's buttons, the main menu's, the
# ABILITIES list, the SETTINGS rows, the confirm dialog's buttons, and (as `MenuTab`) the tabs.
# See docs/specs/menu-refresh.md, "The rows".
#
# It draws its own state instead of swapping styleboxes, because the nudge and the bar animate
# and a StyleBox cannot tween. The theme carries the colours and font sizes (type `MenuRow`); the
# Button's own text colours are transparent there so the label is only ever drawn once, here.
#
#   idle       text at IDLE_ALPHA, no fill
#   selected   focus - which hover gives - teal fill, a bar on the left edge, label nudged right
#   pressed    fill and text dim while held; keyboard confirm holds the look for KEY_FLASH
#   disabled   text at DISABLED_ALPHA, no hover, not focusable (so W/S skip it)
#
# Subclasses (the settings selector and slider) override `_draw_content()` to draw their own
# right-hand control after the label, and call `super._gui_input()` for the keyboard confirm.

const SELECT_TIME := 0.08
const PRESS_TIME := 0.04
## How long the pressed look is held after a keyboard confirm, so the dim is always seen.
const KEY_FLASH := 0.09
const NUDGE := 6.0
const BAR_WIDTH := 3.0
const IDLE_ALPHA := 0.7
const DISABLED_ALPHA := 0.35
const FILL_ALPHA := 0.16
## Fraction of the selected look that is left while the row is held.
const PRESS_DIM := 0.55

const FALLBACK_ACCENT := Color(0.251, 0.949, 0.902)
const FALLBACK_DESTRUCTIVE := Color(1.0, 0.416, 0.239)
const FALLBACK_TEXT := Color(0.91, 0.945, 0.949)

## Engine frame of the most recent pointer hover. The window reads it so a row lit by the pointer
## is not scrolled into view (see menu_window.gd::_on_focus_changed).
static var last_hover_frame := -1

## Selected fill and bar go red-orange instead of teal - rows that lose progress.
@export var destructive := false:
	set(value):
		destructive = value
		queue_redraw()

## 0..1, how selected the row looks right now. Public so a test can read the settled state.
var selected_amount := 0.0
## 0..1, how held-down the row looks right now.
var pressed_amount := 0.0

## A tab: never takes keyboard focus, lights on hover or while it is the active tab, and draws
## no fill or bar (the strip's sliding underline marks the active one instead).
var tab_mode := false:
	set(value):
		tab_mode = value
		if value:
			theme_type_variation = &"MenuTab"
			focus_mode = Control.FOCUS_NONE
			alignment = HORIZONTAL_ALIGNMENT_CENTER
		queue_redraw()
var active := false:
	set(value):
		active = value
		queue_redraw()

var _held := false
var _flash := 0.0
var _hovered := false

func _init() -> void:
	theme_type_variation = &"MenuRow"
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(func() -> void: _hovered = false)
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

## The only way to disable a row: it also drops focusability, which is what makes W/S skip it.
func set_row_disabled(value: bool) -> void:
	disabled = value
	focus_mode = Control.FOCUS_NONE if value else Control.FOCUS_ALL
	if value and has_focus():
		release_focus()
	queue_redraw()

func is_selected() -> bool:
	if tab_mode:
		return (_hovered or active) and not disabled
	return has_focus() and not disabled

func accent_color() -> Color:
	var name := &"destructive" if destructive else &"accent"
	var fallback := FALLBACK_DESTRUCTIVE if destructive else FALLBACK_ACCENT
	return get_theme_color(name, &"MenuRow") if has_theme_color(name, &"MenuRow") else fallback

## The label colour right now: idle -> selected brightness, dimmed while held.
func text_color() -> Color:
	var base := get_theme_color(&"text", &"MenuRow") if has_theme_color(&"text", &"MenuRow") else FALLBACK_TEXT
	var alpha := DISABLED_ALPHA if disabled else lerpf(IDLE_ALPHA, 1.0, selected_amount)
	return Color(base, alpha * press_scale())

## 1 at rest, PRESS_DIM fully held.
func press_scale() -> float:
	return lerpf(1.0, PRESS_DIM, pressed_amount)

func _on_hover() -> void:
	_hovered = true
	last_hover_frame = Engine.get_process_frames()
	if not disabled and focus_mode != Control.FOCUS_NONE:
		grab_focus()

func _on_down() -> void:
	_held = true

func _on_up() -> void:
	_held = false

func _process(delta: float) -> void:
	var sel_target := 1.0 if is_selected() else 0.0
	var press_target := 1.0 if (_held or _flash > 0.0) and not disabled else 0.0
	_flash = maxf(_flash - delta, 0.0)
	var new_sel := move_toward(selected_amount, sel_target, delta / SELECT_TIME)
	var new_press := move_toward(pressed_amount, press_target, delta / PRESS_TIME)
	if new_sel != selected_amount or new_press != pressed_amount:
		selected_amount = new_sel
		pressed_amount = new_press
		queue_redraw()

# The mouse fires on release (BaseButton's default), so a press can be cancelled by dragging off.
# The keyboard and pad fire on press: waiting for key-up feels laggy.
func _gui_input(event: InputEvent) -> void:
	if disabled or not has_focus():
		return
	if event.is_action_pressed(&"ui_accept", false, true):
		accept_event()
		_flash = KEY_FLASH
		_confirm()

## What a keyboard/pad confirm does. A plain row presses; a selector overrides it.
func _confirm() -> void:
	pressed.emit()

func _draw() -> void:
	var accent := accent_color()
	if selected_amount > 0.0 and not tab_mode:
		var k := selected_amount * press_scale()
		draw_rect(Rect2(Vector2.ZERO, size), Color(accent, FILL_ALPHA * k))
		draw_rect(Rect2(0.0, 0.0, BAR_WIDTH, size.y), Color(accent, k))
	_draw_content()

## The label. Left-aligned text sits after the bar and nudges right when selected; centred text
## (the confirm buttons, the tabs) stays put.
func _draw_content() -> void:
	var font := get_theme_font(&"font")
	var font_size := get_theme_font_size(&"font_size")
	var y := _baseline(font, font_size)
	if alignment == HORIZONTAL_ALIGNMENT_CENTER:
		draw_string(font, Vector2(0.0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, text_color())
	else:
		draw_string(font, Vector2(label_x(), y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color())

func label_x() -> float:
	return float(get_theme_stylebox(&"normal").get_margin(SIDE_LEFT)) + NUDGE * selected_amount

func _baseline(font: Font, font_size: int) -> float:
	return (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
