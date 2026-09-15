extends Control

# The full-screen tabbed shell: title, tab strip, content box, hint bar.
# Every menu screen in the game is a tab in here rather than a window of its own,
# so a new screen is a new entry in TABS and nothing else. See
# docs/specs/ui-shell.md.
#
# The tab strip and the hint bar are built in _ready rather than saved into the
# scene, because both are derived from TABS and from whatever the active tab
# declares - keeping them in the .tscn would mean editing two places to add one
# screen.

const TABS := [
	{"label": "GAME", "scene": "res://scenes/ui/tabs/tab_game.tscn"},
	{"label": "ABILITIES", "scene": "res://scenes/ui/tabs/tab_abilities.tscn"},
	{"label": "INVENTORY", "scene": "res://scenes/ui/tabs/tab_inventory.tscn"},
	{"label": "SETTINGS", "scene": "res://scenes/ui/tabs/tab_settings.tscn"},
]

# Shown when a tab does not declare its own. Written as real bindings, not
# symbols: Barlow Condensed has no arrow glyphs and a missing one renders as a box.
const DEFAULT_HINTS := [
	{"key": "W/S", "label": "SELECT"},
	{"key": "ENTER", "label": "CONFIRM"},
	{"key": "Q/E", "label": "TAB"},
	{"key": "ESC", "label": "CLOSE"},
]

const INACTIVE_ALPHA := 0.45

@onready var _tab_strip: HBoxContainer = $Margin/Column/TabStrip
@onready var _content: PanelContainer = $Margin/Column/Content
@onready var _hint_bar: HBoxContainer = $Margin/Column/HintBar

var _active := 0
var _tab_buttons: Array[Button] = []
var _tab_underlines: Array[ColorRect] = []
var _tab_bodies: Array[Control] = []

func _ready() -> void:
	for i in TABS.size():
		_build_tab_button(i, TABS[i]["label"])
		_build_tab_body(TABS[i]["scene"])
	_show_tab(0)

func _build_tab_button(index: int, label: String) -> void:
	# A tab is a button with a rule under it. The rule is a sibling rather than a
	# bottom border so it spans the label exactly, not the button's padding.
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_tab_strip.add_child(column)

	var button := Button.new()
	button.theme_type_variation = &"TabButton"
	button.text = label
	# Tabs are switched with Q/E and by clicking. They never take keyboard focus,
	# which belongs to the row list inside the content box.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_show_tab.bind(index))
	column.add_child(button)

	var underline := ColorRect.new()
	underline.color = Color(1, 1, 1, 1)
	underline.custom_minimum_size.y = 2
	column.add_child(underline)

	_tab_buttons.append(button)
	_tab_underlines.append(underline)

func _build_tab_body(path: String) -> void:
	var body := (load(path) as PackedScene).instantiate() as Control
	body.visible = false
	_content.add_child(body)
	_tab_bodies.append(body)

func _show_tab(index: int) -> void:
	_active = wrapi(index, 0, TABS.size())
	for i in _tab_bodies.size():
		_tab_bodies[i].visible = i == _active
		_tab_underlines[i].visible = i == _active
		# Inactive tabs dim rather than switching to a second variation - a tab
		# is one control changing state, not two controls.
		_tab_buttons[i].modulate.a = 1.0 if i == _active else INACTIVE_ALPHA
	_build_hint_bar()
	focus_first()

func _build_hint_bar() -> void:
	for child in _hint_bar.get_children():
		child.queue_free()
		_hint_bar.remove_child(child)

	var body := _tab_bodies[_active]
	var hints: Array = body.hints() if body.has_method("hints") else DEFAULT_HINTS
	for hint: Dictionary in hints:
		_hint_bar.add_child(_build_hint(hint["key"], hint["label"]))

func _build_hint(key: String, label: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var cap := PanelContainer.new()
	cap.theme_type_variation = &"Keycap"
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)

	var key_label := Label.new()
	key_label.theme_type_variation = &"HintKey"
	key_label.text = key
	cap.add_child(key_label)

	var text := Label.new()
	text.theme_type_variation = &"HintLabel"
	text.text = label
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text)
	return row

# Read in _input rather than _unhandled_input: a focused Button consumes
# ui_left / ui_right for its own focus navigation, so left and right would never
# reach the tab strip.
#
# tab_prev / tab_next no longer bind Left / Right themselves (see
# docs/specs/settings.md, Left And Right) - only Q/E and the shoulder buttons
# reach here now, freeing the arrow keys for a row to adjust its own value.
func _input(event: InputEvent) -> void:
	# Visible is not enough: with a modal pushed on top, the shell is still
	# visible underneath it, and Q/E would silently switch tabs behind the dialog.
	if not visible or UI.stack.is_empty() or UI.stack.back() != &"shell":
		return
	if event.is_action_pressed("tab_next"):
		get_viewport().set_input_as_handled()
		_show_tab(_active + 1)
	elif event.is_action_pressed("tab_prev"):
		get_viewport().set_input_as_handled()
		_show_tab(_active - 1)

# Called by the UI autoload whenever this becomes the top of the stack, so a
# modal closing over the shell hands focus back to the list rather than nowhere.
func focus_first() -> void:
	if _tab_bodies.is_empty():
		return
	var body := _tab_bodies[_active]
	if body.has_method("focus_first"):
		body.focus_first()
