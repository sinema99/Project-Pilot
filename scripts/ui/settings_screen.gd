extends Control

# The main menu's path to the settings rows. The shell is a pause construct and
# does not exist on the title screen - ui-shell.md says so - so this is a
# second, thin host (title, content box, hint bar) for the same
# tab_settings.tscn content the shell's SETTINGS tab uses. See
# docs/specs/settings.md, Two Hosts, One Content Scene.
#
# Registered in ui_manager.gd's SCREENS as &"settings", pauses: true. BACK pops
# it with no code here: the UI autoload's own Esc handling already does that
# for every screen on the stack.

@onready var _body: Control = $Margin/Column/Content/TabSettings
@onready var _hint_bar: HBoxContainer = $Margin/Column/HintBar

func _ready() -> void:
	_build_hint_bar()

# Called by the UI autoload whenever this becomes the top of the stack.
func focus_first() -> void:
	if _body.has_method("focus_first"):
		_body.focus_first()

func _build_hint_bar() -> void:
	for child in _hint_bar.get_children():
		child.queue_free()
		_hint_bar.remove_child(child)
	var hints: Array = _body.hints() if _body.has_method("hints") else []
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
