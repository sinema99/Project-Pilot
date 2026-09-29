extends Control

# The main menu's path to the settings rows. The shell is a pause construct and does not exist on
# the title screen - ui-shell.md says so - so this is a second, thin host (a MenuWindow with no
# tab strip) for the same tab_settings.tscn content the shell's SETTINGS tab uses. See
# docs/specs/settings.md, Two Hosts, One Content Scene, and docs/specs/menu-refresh.md.
#
# Registered in ui_manager.gd's SCREENS as &"settings", pauses: true. BACK pops it with no code
# here: the UI autoload's own Esc handling already does that for every screen on the stack.

const BODY_SCENE := "res://scenes/ui/tabs/tab_settings.tscn"

@onready var _window: Control = $MenuWindow

var _body: Control
var _dismiss_generation := 0
var _last_row: Control

func _ready() -> void:
	_body = (load(BODY_SCENE) as PackedScene).instantiate() as Control
	_window.content_root().add_child(_body)
	_window.set_title("SETTINGS")
	_window.set_hints(_body.hints() if _body.has_method("hints") else [])
	get_viewport().gui_focus_changed.connect(_on_focus_changed)

func _on_focus_changed(node: Control) -> void:
	if node != null and _body.is_ancestor_of(node):
		_last_row = node

func body() -> Control:
	return _body

func window() -> Control:
	return _window

## Becomes visible. `skip_fade` is unused here (the settings screen is never in the hologram) but
## kept so the UI autoload can call every screen the same way.
func present(skip_fade := false) -> void:
	_dismiss_generation += 1
	_last_row = null
	if skip_fade:
		_window.process_mode = Node.PROCESS_MODE_INHERIT
		_window.modulate.a = 1.0
	else:
		_window.present()

func dismiss() -> void:
	_dismiss_generation += 1
	var generation := _dismiss_generation
	_window.dismiss()
	await _window.dismissed
	if generation == _dismiss_generation:
		visible = false

func set_behind_dialog(on: bool) -> void:
	_window.set_behind_dialog(on)

# Called by the UI autoload whenever this becomes the top of the stack.
func focus_first() -> void:
	if _body.has_method("refresh"):
		_body.refresh()
	# Keep the row the player was on when a confirm closes over this screen.
	if is_instance_valid(_last_row) and _last_row.is_visible_in_tree():
		_last_row.grab_focus()
		return
	if _body.has_method("focus_first"):
		_body.focus_first()
	_window.set_scroll_position.call_deferred(0)
