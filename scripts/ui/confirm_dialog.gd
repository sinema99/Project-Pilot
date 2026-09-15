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

var _base_message := ""
var _countdown_left := 0.0

func _ready() -> void:
	for button: Button in [_confirm, _cancel]:
		button.mouse_entered.connect(button.grab_focus)
	set_process(false)

## `countdown` is optional and keeps the dialog reusable by anything: it still
## only reports which button was pressed. A settings row that needs to know a
## display mode reverted wires its own extra listener to `cancelled` - the
## dialog does not learn what a display mode is.
func setup(title: String, message: String, countdown: float = 0.0) -> void:
	# Called before the push, so the labels may not be @onready yet on the very
	# first open.
	if not is_node_ready():
		await ready
	_title.text = title
	_base_message = message
	_countdown_left = countdown
	_update_message()
	set_process(countdown > 0.0)

# Defaults to CANCEL. Every use of this dialog throws away an unsaved run, so
# the safe answer is the one already selected when it appears.
func focus_first() -> void:
	_cancel.grab_focus()

# The timer runs while paused for free: this dialog is a child of the UI
# autoload, which is PROCESS_MODE_ALWAYS, and children inherit it.
func _process(delta: float) -> void:
	_countdown_left = maxf(_countdown_left - delta, 0.0)
	_update_message()
	if _countdown_left <= 0.0:
		set_process(false)
		# The timeout emits the same `cancelled` a click does - ui_manager.gd
		# does not need to know a countdown exists.
		cancelled.emit()

func _update_message() -> void:
	if _countdown_left > 0.0:
		_message.text = "%s (%ds)" % [_base_message, ceili(_countdown_left)]
	else:
		_message.text = _base_message

func _on_confirm_pressed() -> void:
	set_process(false)
	confirmed.emit()

func _on_cancel_pressed() -> void:
	set_process(false)
	cancelled.emit()
