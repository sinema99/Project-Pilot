extends Control

# The one modal. Pushed over whatever is already open, which is the case a flat screen enum could
# not express and the reason the UI autoload holds a stack at all. See docs/specs/ui-shell.md and
# docs/specs/menu-refresh.md ("Confirm dialog").
#
# It never runs the action itself - it reports which button was pressed and the autoload, which
# owns the callback, decides. That keeps the dialog reusable by anything, including the main menu,
# where there is no game to act on.

signal confirmed
signal cancelled

const OPEN_TIME := 0.10
const OPEN_FROM_SCALE := 0.95

@onready var _window: Control = $Window
@onready var _title: Label = $Window/Margin/Column/Title
@onready var _message: Label = $Window/Margin/Column/Message
@onready var _confirm: Button = $Window/Margin/Column/Buttons/Confirm
@onready var _cancel: Button = $Window/Margin/Column/Buttons/Cancel

var _base_message := ""
var _countdown_left := 0.0
var _fade: Tween

func _ready() -> void:
	set_process(false)

## `countdown` is optional and keeps the dialog reusable by anything: it still only reports which
## button was pressed. A settings row that needs to know a display mode reverted wires its own
## extra listener to `cancelled` - the dialog does not learn what a display mode is.
##
## The confirm button is destructive-tinted unless there is a countdown: every plain use of this
## dialog throws away a run, while the countdown one asks whether to KEEP something.
func setup(title: String, message: String, countdown: float = 0.0) -> void:
	# Called before the push, so the labels may not be @onready yet on the very first open.
	if not is_node_ready():
		await ready
	_title.text = title
	_base_message = message
	_countdown_left = countdown
	_confirm.destructive = countdown <= 0.0
	_update_message()
	set_process(countdown > 0.0)

## Fade and 95 -> 100 % over OPEN_TIME. In the hologram the panel's own reveal is the open.
func present(skip_fade := false) -> void:
	if _fade != null:
		_fade.kill()
	_window.modulate.a = 1.0
	_window.scale = Vector2.ONE
	if skip_fade:
		return
	_window.modulate.a = 0.0
	_window.scale = Vector2(OPEN_FROM_SCALE, OPEN_FROM_SCALE)
	_fade = create_tween()
	_fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade.set_parallel(true)
	_fade.tween_property(_window, "modulate:a", 1.0, OPEN_TIME)
	_fade.tween_property(_window, "scale", Vector2.ONE, OPEN_TIME)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# Defaults to CANCEL. Every use of this dialog throws away an unsaved run, so the safe answer is
# the one already selected when it appears.
func focus_first() -> void:
	_cancel.grab_focus()

# The timer runs while paused for free: this dialog is a child of the UI autoload, which is
# PROCESS_MODE_ALWAYS, and children inherit it.
func _process(delta: float) -> void:
	_countdown_left = maxf(_countdown_left - delta, 0.0)
	_update_message()
	if _countdown_left <= 0.0:
		set_process(false)
		# The timeout emits the same `cancelled` a click does - ui_manager.gd does not need to
		# know a countdown exists.
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
