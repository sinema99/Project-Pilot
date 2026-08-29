extends PanelContainer

# The one window shape every UI screen is built from: a light header strip
# carrying the title, a charcoal body below it, square corners, ink border.
# Colours and sizes come from resources/ui_theme.tres, never from here.
#
# The chrome is assembled in _build() rather than saved into ui_window.tscn so a
# screen scene can just parent its contents to this instance and let the script
# re-home them into the content area. That keeps the screen scenes free of
# editable-children paths reaching down into this one.
#
# Not a @tool script on purpose: _build() reparents nodes the screen scene owns,
# and doing that in the editor risks serialising them at their moved path.

signal close_requested

const HEADER_HEIGHT := 40
const HEADER_MARGIN := 12
const CONTENT_MARGIN := 16

@export var title: String = "":
	set(value):
		title = value
		if is_instance_valid(_title_label):
			_title_label.text = value

@export var show_close_button: bool = false:
	set(value):
		show_close_button = value
		if is_instance_valid(_close_button):
			_close_button.visible = value

# Where a screen's contents end up. Populated by _build().
var content: MarginContainer

var _title_label: Label
var _close_button: Button

func _ready() -> void:
	_build()

func _build() -> void:
	# Whatever the screen scene parented to us is its content. Take the list
	# before any chrome is added, so the chrome doesn't end up inside itself.
	var payload := get_children()

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var header := PanelContainer.new()
	header.theme_type_variation = &"WindowHeader"
	header.custom_minimum_size.y = HEADER_HEIGHT
	column.add_child(header)

	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", HEADER_MARGIN)
	header.add_child(header_margin)

	var header_row := HBoxContainer.new()
	header_margin.add_child(header_row)

	_title_label = Label.new()
	_title_label.theme_type_variation = &"WindowTitle"
	_title_label.text = title
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_title_label)

	# Focus never lands on the close button: it would put a highlight on the
	# header the moment a screen opens, and every screen with one also closes
	# on Esc.
	_close_button = Button.new()
	_close_button.theme_type_variation = &"CloseButton"
	_close_button.text = "X"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.visible = show_close_button
	_close_button.pressed.connect(func() -> void: close_requested.emit())
	header_row.add_child(_close_button)

	content = MarginContainer.new()
	content.add_theme_constant_override("margin_left", CONTENT_MARGIN)
	content.add_theme_constant_override("margin_top", CONTENT_MARGIN)
	content.add_theme_constant_override("margin_right", CONTENT_MARGIN)
	content.add_theme_constant_override("margin_bottom", CONTENT_MARGIN)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)

	for node in payload:
		remove_child(node)
		content.add_child(node)
