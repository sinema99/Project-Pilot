extends VBoxContainer

# The SETTINGS tab: thirteen rows over three sections, all read and written
# through the `Settings` autoload. See docs/specs/settings.md.
#
# Instanced twice - once under the shell, once under settings_screen.tscn for
# the main menu - and neither instance holds state: every rebuild reads
# Settings fresh, so the two can never disagree with each other.
#
# A row is a themed Button, the same white-selected-row look GAME's entries
# already have. Left and Right come off ui_left / ui_right, which are not
# bound to the tab strip any more - see docs/specs/settings.md, Left And Right.
#
# Clicking a discrete row (WINDOW MODE, RESOLUTION, VSYNC, ...) no longer just
# steps it forward one notch - a mouse click could change a value but never
# undo the click. It now expands an inline list of every value the row can
# take, right below it, closed by picking one. A continuous row (BRIGHTNESS,
# both sensitivities, FOV) is a SettingsSliderRow instead of a Button, so it
# can be dragged directly. Left/Right still index-step either kind exactly as
# before - the mouse got new options, the keyboard lost nothing.

const SettingsSliderRow := preload("res://scripts/ui/tabs/settings_slider_row.gd")

# The 16:9 list RESOLUTION offers before it is filtered to the screen.
const PIXEL_PRESETS := [
	Vector2i(160, 90), Vector2i(240, 135), Vector2i(320, 180),
	Vector2i(480, 270), Vector2i(640, 360),
]

# Rows that get a SettingsSliderRow instead of a Button - the ones the spec
# itself calls "continuous", stepped in fine fractions rather than a short
# enum.
const SLIDER_KEYS: Array[StringName] = [
	&"brightness", &"mouse_sensitivity", &"controller_sensitivity", &"fov",
]

const ROW_WIDTH := 58

## How long the display rows wait for you to stop stepping before they ask. See The Display
## Revert at the foot of this file.
const DISPLAY_SETTLE := 1.0

var _row_keys: Dictionary = {}
var _buttons: Array[Control] = []
var _expanded_key: StringName = &""
var _revert_window_mode: String
var _revert_resolution: Vector2i
## Whether _revert_* already hold the values this run of display steps started from. Set on the
## first step of a run and cleared when the confirm resolves, so stepping four notches reverts
## to where you began rather than to the third notch.
var _display_run := false
var _display_timer: Timer

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_display_timer = Timer.new()
	_display_timer.one_shot = true
	_display_timer.wait_time = DISPLAY_SETTLE
	_display_timer.timeout.connect(_show_display_confirm)
	add_child(_display_timer)

func hints() -> Array:
	return [
		{"key": "W/S", "label": "SELECT"},
		{"key": "LEFT/RIGHT", "label": "ADJUST"},
		{"key": "ENTER", "label": "CONFIRM"},
		{"key": "Q/E", "label": "TAB"},
		{"key": "ESC", "label": "CLOSE"},
	]

# Rebuilt every time the tab is shown, the same reason tab_abilities.gd rebuilds:
# it cannot be allowed to go stale, and here that means against a config that
# may have just been reverted or reset out from under it.
func focus_first() -> void:
	_rebuild()

# Left/Right never reach a focused Button's own input handling (there is
# nothing to their left or right to navigate to), so they fall through here.
# Caught by whichever of the two live instances currently owns GUI focus -
# the other's rows hold none, so it is a no-op there.
func _input(event: InputEvent) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not _row_keys.has(focused):
		return
	var key: StringName = _row_keys[focused]
	if key == &"__reset__":
		return
	if event.is_action_pressed(&"ui_left"):
		get_viewport().set_input_as_handled()
		_step(key, -1)
	elif event.is_action_pressed(&"ui_right"):
		get_viewport().set_input_as_handled()
		_step(key, 1)

# --- building --------------------------------------------------------------

## `focus_key` forces which row gets focus after the rebuild - used when a
## click or a selection triggers the rebuild itself, so focus lands on the row
## that was just acted on rather than whatever `gui_get_focus_owner()` still
## reports mid-rebuild.
func _rebuild(focus_key: StringName = &"") -> void:
	var focused_key: StringName = focus_key
	if focused_key == &"":
		focused_key = _row_keys.get(get_viewport().gui_get_focus_owner(), &"")
	for child in get_children():
		# Every row is rebuilt from scratch, but _display_timer is state, not a row: freeing it
		# mid-run would swallow the confirm for a display mode that has already been applied.
		if child == _display_timer:
			continue
		remove_child(child)
		child.queue_free()
	_row_keys.clear()
	_buttons.clear()

	var last_section := ""
	for row: Array in Settings.DEFS:
		var key: StringName = row[0]
		var section: String = row[2]
		if section != last_section:
			if last_section != "":
				_add_spacer()
			_add_header(section.to_upper())
			last_section = section
		if SLIDER_KEYS.has(key):
			_add_slider_row(key)
		else:
			_add_row(key)
			if _expanded_key == key:
				_add_options(key)
	_add_reset_row()

	_restore_focus(focused_key)

func _add_header(text: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"SectionHeader"
	label.text = text
	add_child(label)

func _add_spacer() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	add_child(spacer)

func _add_row(key: StringName) -> void:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = _row_text(key)
	# Hover moves focus rather than drawing a second highlight, so the keyboard
	# and the pointer can never disagree about which entry is selected -
	# tab_game.gd's own rule.
	button.mouse_entered.connect(button.grab_focus)
	button.pressed.connect(_toggle_expand.bind(key))
	add_child(button)
	_row_keys[button] = key
	_buttons.append(button)

## The inline "dropdown": every value the row can take, added as rows of
## their own directly under it. No PopupMenu, no OptionButton - both need
## panel/hover/separator styling the theme does not have (docs/specs/
## settings.md says so explicitly) - just more of the same Button this whole
## screen is already built from.
func _add_options(key: StringName) -> void:
	var options: Array = _resolution_options() if key == &"resolution" else Settings.values_of(key)
	var current: Variant = Settings.get_value(key)
	for value: Variant in options:
		var option := Button.new()
		option.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var marker := "> " if value == current else "    "
		option.text = marker + _format_value(key, value)
		option.mouse_entered.connect(option.grab_focus)
		option.pressed.connect(_select_value.bind(key, value))
		add_child(option)
		# Not entered into _row_keys: Left/Right has nothing to do on an
		# option row, and _input() already ignores anything not in that map.
		_buttons.append(option)

func _add_slider_row(key: StringName) -> void:
	var row := SettingsSliderRow.new()
	row.setup(key)
	add_child(row)
	row.sync(Settings.label_of(key), _format_value(key, Settings.get_value(key)))
	# A drag writes straight to Settings and repaints the track itself, but it
	# has no way to reformat its own printed value - that's _format_value()
	# below, which belongs to this file. Without this the handle tracks the
	# mouse and the number next to it does not.
	row.dragged.connect(_refresh_row.bind(key))
	_row_keys[row] = key
	_buttons.append(row)

func _add_reset_row() -> void:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = "RESET TO DEFAULTS"
	button.mouse_entered.connect(button.grab_focus)
	button.pressed.connect(_on_reset_pressed)
	add_child(button)
	_row_keys[button] = &"__reset__"
	_buttons.append(button)

func _restore_focus(key: StringName) -> void:
	for control: Control in _row_keys:
		if _row_keys[control] == key:
			control.grab_focus()
			return
	if not _buttons.is_empty():
		_buttons[0].grab_focus()

func _row_text(key: StringName) -> String:
	var label := Settings.label_of(key)
	var value := _format_value(key, Settings.get_value(key))
	var dots := ROW_WIDTH - label.length() - value.length() - 2
	return "%s %s %s" % [label, ".".repeat(maxi(dots, 3)), value]

func _refresh_row(key: StringName) -> void:
	for control: Control in _row_keys:
		if _row_keys[control] != key:
			continue
		if control is SettingsSliderRow:
			control.sync(Settings.label_of(key), _format_value(key, Settings.get_value(key)))
		else:
			(control as Button).text = _row_text(key)
		return

# --- display -----------------------------------------------------------------

func _format_value(key: StringName, value: Variant) -> String:
	match key:
		&"window_mode", &"vsync", &"shadow_quality":
			return String(value).to_upper()
		&"msaa":
			return "OFF" if value == "off" else String(value).to_upper()
		&"resolution":
			var v: Vector2i = value
			return "%dx%d" % [v.x, v.y]
		&"max_fps":
			return "UNCAPPED" if value == 0 else str(value)
		&"brightness":
			return "%.2f" % value
		&"render_scale":
			return "%d%%" % roundi(float(value) * 100.0)
		&"pixel_filter":
			var index := int(value)
			if index < 0:
				return "OFF"
			var preset: Vector2i = PIXEL_PRESETS[index]
			return "%dx%d" % [preset.x, preset.y]
		&"mouse_sensitivity", &"controller_sensitivity":
			return "%.2fx" % value
		&"fov":
			return str(int(value))
		_:
			return str(value)

# --- the dropdown: expand, collapse, pick -------------------------------------

func _toggle_expand(key: StringName) -> void:
	_expanded_key = &"" if _expanded_key == key else key
	_rebuild(key)

func _select_value(key: StringName, value: Variant) -> void:
	var old_window_mode := Settings.window_mode
	var old_resolution := Settings.resolution
	Settings.set_value(key, value)
	_expanded_key = &""
	_rebuild(key)
	if key == &"window_mode" or key == &"resolution":
		_queue_display_confirm(old_window_mode, old_resolution)

# --- stepping ------------------------------------------------------------------
#
# Left/Right on a focused row, keyboard or pad. A row with its dropdown open
# is, by construction, the focused row (_toggle_expand and _select_value both
# refocus the row they act on) - so stepping it here always means the open
# list is now describing a value it no longer points at, and gets closed
# rather than left stale.

func _step(key: StringName, direction: int) -> void:
	var was_expanded := _expanded_key == key
	_expanded_key = &""
	if was_expanded:
		_rebuild(key)
	match key:
		&"resolution":
			_step_resolution(direction)
		&"window_mode":
			var old_window_mode := Settings.window_mode
			var old_resolution := Settings.resolution
			Settings.step_value(key, direction)
			_refresh_row(key)
			_queue_display_confirm(old_window_mode, old_resolution)
		_:
			Settings.step_value(key, direction)
			_refresh_row(key)

# RESOLUTION is a hand-written 16:9 list, filtered to those at or below the
# screen and with the screen's own size appended if it is not already there.
# Godot has no API to enumerate windowed modes, so this list - not
# Settings.DEFS's full one - is what gets stepped and clamped.
func _resolution_options() -> Array:
	var screen := DisplayServer.screen_get_size()
	var options: Array = []
	for v: Vector2i in Settings.values_of(&"resolution"):
		if v.x <= screen.x and v.y <= screen.y:
			options.append(v)
	if not options.has(screen):
		options.append(screen)
	options.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	return options

func _step_resolution(direction: int) -> void:
	var options := _resolution_options()
	var current: Vector2i = Settings.resolution
	var index: int = maxi(options.find(current), 0)
	var old_window_mode := Settings.window_mode
	var old_resolution := current
	var new_value: Vector2i = options[clampi(index + direction, 0, options.size() - 1)]
	Settings.set_value(&"resolution", new_value)
	_refresh_row(&"resolution")
	_queue_display_confirm(old_window_mode, old_resolution)

# --- reset to defaults ---------------------------------------------------------

func _on_reset_pressed() -> void:
	UI.confirm("RESET TO DEFAULTS?", "Every setting reverts to its shipped value.",
		_on_reset_confirmed)

func _on_reset_confirmed() -> void:
	Settings.reset_to_defaults()
	_expanded_key = &""
	_rebuild()

# --- the display revert ---------------------------------------------------------------
#
# WINDOW MODE and RESOLUTION apply instantly like every other row, but either can strand a
# player behind a display the monitor rejects or a window bigger than the screen. So on top of
# applying, they raise the confirm modal with a countdown, reverting if it expires.
#
# The confirm is debounced rather than per-step. It used to fire on every arrow press and take
# focus with it, so walking the resolution list from 1280x720 to 3840x2160 was four separate
# modal round-trips - the row interrogated you once per notch about a change you were still in
# the middle of making. Now stepping is silent and a step restarts DISPLAY_SETTLE; one second
# after you stop, a single confirm covers the whole run.
#
# Which is why _revert_* is captured on the *first* step of a run and held, rather than
# overwritten each time. Four steps forward and CANCEL returns you to where you started, not to
# the third notch - reverting to a value you were only passing through would leave you stranded
# in a different way than the one this exists to prevent.
#
# The dialog itself stays ignorant: it still only reports which button was pressed, and
# ui_manager.gd's own `back` wiring to `cancelled` is untouched. This adds one listener for the
# single thing that needs to know a display mode reverted.

func _confirm_dialog() -> Control:
	# Looked up on demand rather than cached in _ready(): SCREENS spawns shell
	# before confirm, so the confirm instance does not exist yet the first time
	# a shell-hosted tab_settings would otherwise have cached it.
	return UI._instances[&"confirm"]

## Called by every display change. Starts a run if one is not already open, then pushes the
## confirm back by another DISPLAY_SETTLE.
func _queue_display_confirm(old_window_mode: String, old_resolution: Vector2i) -> void:
	if not _display_run:
		_display_run = true
		_revert_window_mode = old_window_mode
		_revert_resolution = old_resolution
	_display_timer.start(DISPLAY_SETTLE)

func _show_display_confirm() -> void:
	if not _display_run:
		return
	var dialog := _confirm_dialog()
	if dialog.cancelled.is_connected(_on_display_reverted):
		dialog.cancelled.disconnect(_on_display_reverted)
	dialog.cancelled.connect(_on_display_reverted, CONNECT_ONE_SHOT)
	UI.confirm("KEEP THIS DISPLAY MODE?", "Reverting to the previous display mode.",
		_on_display_kept)
	# UI.confirm() calls setup() without a countdown, so the countdown is armed here rather than
	# taught to ui_manager.gd - the dialog stays reusable by the three callers that do not want
	# one. Same title and message, so the player sees no flicker between the two calls.
	dialog.setup("KEEP THIS DISPLAY MODE?", "Reverting to the previous display mode.", 15.0)

func _on_display_kept() -> void:
	_display_run = false
	var dialog := _confirm_dialog()
	if dialog.cancelled.is_connected(_on_display_reverted):
		dialog.cancelled.disconnect(_on_display_reverted)

func _on_display_reverted() -> void:
	_display_run = false
	Settings.set_value(&"window_mode", _revert_window_mode)
	Settings.set_value(&"resolution", _revert_resolution)
	# Those two set_value calls do not re-queue a confirm - _queue_display_confirm() is only
	# reached from a row the player stepped, never from here.
	_expanded_key = &""
	_rebuild()
