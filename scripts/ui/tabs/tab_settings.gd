extends VBoxContainer

# The SETTINGS tab: one row per Settings.DEFS entry over three sections, all read and written through the
# `Settings` autoload. See docs/specs/settings.md and docs/specs/menu-refresh.md.
#
# Instanced twice - once under the shell, once under settings_screen.tscn for the main menu - and
# neither instance holds state: every refresh reads Settings fresh, so the two can never disagree.
#
# A discrete row (WINDOW MODE, RESOLUTION, VSYNC, ...) is a SettingsSelectorRow, `<  VALUE  >`;
# a continuous row (BRIGHTNESS, both sensitivities, FOV) is a SettingsSliderRow. Left and Right
# step either kind, keyboard or pad; the mouse clicks an arrow or drags the track. The rows are
# built once and re-synced, never rebuilt, so the shell's remembered focus stays valid.

const SelectorRow := preload("res://scripts/ui/tabs/settings_selector_row.gd")
const SliderRow := preload("res://scripts/ui/tabs/settings_slider_row.gd")
const MenuRow := preload("res://scripts/ui/menu_row.gd")
# Settings's static helpers, called on the script rather than the autoload instance.
const SettingsScript := preload("res://scripts/settings.gd")

# Rows the pixel filter overrides while it is on: the low-res world has no MSAA and renders at
# exactly window / block. Shown dimmed with OVERRIDDEN_TEXT. See docs/specs/pixel-world.md.
const PIXEL_OVERRIDDEN_KEYS: Array[StringName] = [&"msaa", &"render_scale"]
const OVERRIDDEN_TEXT := "PIXEL FILTER ON"
# PAINTED SHADING only exists in CEL (PIXEL's clumps replace it, RETRO's fills are flat). The row
# shows the look that overrides it. See docs/specs/pixel-look.md and docs/specs/retro-look.md.
const CEL_ONLY_TEXT := "%s LOOK"

# Settings keys with no row of their own. The PIXEL look's block size is shown and stepped on the
# PIXEL FILTER row while PIXEL is on - see _bound_key().
const ROWLESS_KEYS: Array[StringName] = [&"pixel_look_size"]

# Rows that get a SliderRow instead of a SelectorRow - the ones the spec itself calls
# "continuous", stepped in fine fractions rather than a short enum.
const SLIDER_KEYS: Array[StringName] = [
	&"brightness", &"mouse_sensitivity", &"controller_sensitivity", &"fov",
]

const RESET_KEY := &"__reset__"

## How long the display rows wait for you to stop stepping before they ask. See The Display
## Revert at the foot of this file.
const DISPLAY_SETTLE := 1.0

## control -> Settings key (or RESET_KEY), in row order.
var _row_keys: Dictionary = {}
var _rows: Array[Control] = []
var _revert_window_mode: String
var _revert_resolution: Vector2i
## Whether _revert_* already hold the values this run of display steps started from. Set on the
## first step of a run and cleared when the confirm resolves, so stepping four notches reverts
## to where you began rather than to the third notch.
var _display_run := false
var _display_timer: Timer

func _ready() -> void:
	add_theme_constant_override("separation", 2)
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
		{"key": "ESC", "label": "CLOSE"},
	]

## Builds the rows on first use - not in _ready, which can run before the Settings autoload
## exists - then re-reads every value. Called by the host whenever the tab is shown.
func refresh() -> void:
	if _rows.is_empty():
		_build()
	_sync_all()

func focus_first() -> void:
	if _rows.is_empty():
		refresh()
	if not _rows.is_empty():
		_rows[0].grab_focus()

## The rows in order, for the host's tests and focus memory.
func rows() -> Array[Control]:
	return _rows

func key_of(row: Control) -> StringName:
	return _row_keys.get(row, &"")

# Left/Right never reach a focused Button's own input handling (there is nothing to their left or
# right to navigate to), so they fall through here. Caught by whichever of the two live instances
# currently owns GUI focus - the other's rows hold none, so it is a no-op there.
func _input(event: InputEvent) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not _row_keys.has(focused):
		return
	var key: StringName = _row_keys[focused]
	if key == RESET_KEY:
		return
	if event.is_action_pressed(&"ui_left"):
		get_viewport().set_input_as_handled()
		_step(-1, key)
	elif event.is_action_pressed(&"ui_right"):
		get_viewport().set_input_as_handled()
		_step(1, key)

# --- building --------------------------------------------------------------

func _build() -> void:
	var last_section := ""
	for row: Array in Settings.DEFS:
		var key: StringName = row[0]
		var section: String = row[2]
		if ROWLESS_KEYS.has(key):
			continue
		if section != last_section:
			if last_section != "":
				_add_spacer()
			_add_header(section.to_upper())
			if section == "display" and SettingsScript.is_embedded():
				_add_embedded_note()
			last_section = section
		if SLIDER_KEYS.has(key):
			_add_slider_row(key)
		else:
			_add_selector_row(key)
	_add_spacer()
	_add_reset_row()

func _add_header(text: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"SectionHeader"
	label.text = text
	add_child(label)

## Under the DISPLAY header when the game is playing inside the editor's Game tab, which accepts
## neither a mode nor a size - see docs/specs/settings.md, Embedded In The Editor. Without it the
## two rows save, do nothing, and look broken.
func _add_embedded_note() -> void:
	var label := Label.new()
	label.theme_type_variation = &"BodyDim"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "RUNNING INSIDE THE EDITOR'S GAME TAB - WINDOW MODE AND RESOLUTION SAVE BUT CANNOT APPLY. TURN OFF EMBED GAME ON NEXT PLAY IN THE GAME TAB."
	add_child(label)

func _add_spacer() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	add_child(spacer)

func _add_selector_row(key: StringName) -> void:
	var row := SelectorRow.new()
	row.name = "Row_" + String(key)
	row.text = SettingsScript.label_of(key)
	row.toggles_on_confirm = _options_of(key).size() == 2
	row.stepped.connect(_step.bind(key))
	add_child(row)
	_row_keys[row] = key
	_rows.append(row)

func _add_slider_row(key: StringName) -> void:
	var row := SliderRow.new()
	row.name = "Row_" + String(key)
	row.setup(key)
	row.text = SettingsScript.label_of(key)
	add_child(row)
	# A drag writes straight to Settings and repaints the track itself, but it has no way to
	# reformat its own printed value - that's _format_value() below, which belongs to this file.
	row.dragged.connect(_refresh_row.bind(key))
	_row_keys[row] = key
	_rows.append(row)

func _add_reset_row() -> void:
	var button := MenuRow.new()
	button.name = "Row_reset"
	button.text = "RESET TO DEFAULTS"
	button.destructive = true
	button.pressed.connect(_on_reset_pressed)
	add_child(button)
	_row_keys[button] = RESET_KEY
	_rows.append(button)

# --- syncing ---------------------------------------------------------------

func _sync_all() -> void:
	for control: Control in _rows:
		var key: StringName = _row_keys[control]
		if key != RESET_KEY:
			_refresh_row(key)

func _refresh_row(key: StringName) -> void:
	for control: Control in _row_keys:
		if _row_keys[control] != key:
			continue
		var label := SettingsScript.label_of(key)
		var value := _format_value(key, Settings.get_value(_bound_key(key)))
		if control is SliderRow:
			control.sync(label, value)
		elif PIXEL_OVERRIDDEN_KEYS.has(key):
			_sync_maybe_disabled(control, key, label, value,
				SettingsScript.effective_pixel_size(Settings.pixel_size, Settings.pixel_look_size, Settings.look) > 0,
				OVERRIDDEN_TEXT)
		elif key == &"painted_shading" or key == &"cel_scatter":
			_sync_maybe_disabled(control, key, label, value, Settings.look != "cel", CEL_ONLY_TEXT % Settings.look.to_upper())
		else:
			control.sync(label, value, _can_step(key, -1), _can_step(key, 1))
		return

func _sync_maybe_disabled(control: Control, key: StringName, label: String, value: String,
		disabled: bool, disabled_text: String) -> void:
	control.set_row_disabled(disabled)
	if disabled:
		control.sync(label, disabled_text, false, false)
	else:
		control.sync(label, value, _can_step(key, -1), _can_step(key, 1))

## The Settings key a row reads and writes. Itself, except PIXEL FILTER, which edits the active
## look's own block size (PIXEL's has no OFF and defaults to 4X).
func _bound_key(key: StringName) -> StringName:
	return SettingsScript.pixel_filter_key(Settings.look) if key == &"pixel_size" else key

## The list a row steps through. RESOLUTION's is filtered to the screen; the rest are Settings'.
func _options_of(key: StringName) -> Array:
	return _resolution_options() if key == &"resolution" else SettingsScript.values_of(_bound_key(key))

func _index_of(key: StringName) -> int:
	if key == &"resolution":
		return maxi(_resolution_options().find(Settings.resolution), 0)
	return Settings.index_for(_bound_key(key))

## Whether a step that way lands on a value. False at either end: the list clamps, it does not
## wrap, and the row draws that arrow at 35 %.
func _can_step(key: StringName, direction: int) -> bool:
	var target := _index_of(key) + direction
	return target >= 0 and target < _options_of(key).size()

# --- display -----------------------------------------------------------------

func _format_value(key: StringName, value: Variant) -> String:
	match key:
		&"window_mode", &"vsync", &"shadow_quality", &"camera_motion", &"hologram_menu", &"movement_effects", &"painted_shading", &"cel_scatter", &"look":
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
		&"pixel_size":
			return "OFF" if int(value) == 0 else "%dX" % int(value)
		&"colour_depth":
			return "FULL" if int(value) == 0 else str(value)
		&"mouse_sensitivity", &"controller_sensitivity":
			return "%.2fx" % value
		&"fov":
			return str(int(value))
		_:
			return str(value)

# --- stepping ------------------------------------------------------------------
#
# Left/Right on a focused row, keyboard or pad, or a click on an arrow.

func _step(direction: int, key: StringName) -> void:
	if not _can_step(key, direction):
		return
	match key:
		&"resolution":
			_step_resolution(direction)
		&"window_mode":
			var old_window_mode := Settings.window_mode
			var old_resolution := Settings.resolution
			Settings.step_value(key, direction)
			_refresh_row(key)
			_queue_display_confirm(old_window_mode, old_resolution)
		&"pixel_size", &"look":
			Settings.step_value(_bound_key(key), direction)
			# MSAA and RENDER SCALE grey out or come back with the filter; PAINTED SHADING and the
			# PIXEL FILTER row's own value with the look.
			_sync_all()
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
	for v: Vector2i in SettingsScript.values_of(&"resolution"):
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
	_sync_all()

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
	# Embedded, nothing on screen changed, so there is nothing to keep or revert.
	if SettingsScript.is_embedded():
		return
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
	_sync_all()
