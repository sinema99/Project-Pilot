extends Control

# The one modal. Pushed over whatever is already open, which is the case a flat
# screen enum could not express and the reason the UI autoload holds a stack at
# all. See docs/specs/ui-shell.md.
#
# It never runs the action itself - it reports which button was pressed and the
# autoload, which owns the callback, decides. That keeps the dialog reusable by
# anything, including the main menu, where there is no game to act on.

signal confirmed
signal cancelled

@onready var _title: Label = $Center/Box/Column/Title
@onready var _message: Label = $Center/Box/Column/Message
@onready var _confirm: Button = $Center/Box/Column/Confirm
@onready var _cancel: Button = $Center/Box/Column/Cancel

func _ready() -> void:
	for button: Button in [_confirm, _cancel]:
		button.mouse_entered.connect(button.grab_focus)

func setup(title: String, message: String) -> void:
	# Called before the push, so the labels may not be @onready yet on the very
	# first open.
	if not is_node_ready():
		await ready
	_title.text = title
	_message.text = message

# Defaults to CANCEL. Every use of this dialog throws away an unsaved run, so
# the safe answer is the one already selected when it appears.
func focus_first() -> void:
	_cancel.grab_focus()

func _on_confirm_pressed() -> void:
	confirmed.emit()

func _on_cancel_pressed() -> void:
	cancelled.emit()
