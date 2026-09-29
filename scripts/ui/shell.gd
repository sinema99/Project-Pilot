extends Control

# The pause menu: a MenuWindow with a tab strip. Every menu screen in the game is a tab in here
# rather than a window of its own, so a new screen is a new entry in TABS and nothing else. See
# docs/specs/ui-shell.md (the tab model) and docs/specs/menu-refresh.md (the window, the strip,
# row memory).
#
# The tab bodies are tab_*.tscn scenes parented under the window's scrolling middle. A body may
# declare `hints()`, `refresh()` (re-read live data) and `focus_first()`.

const TABS := [
	{"label": "GAME", "scene": "res://scenes/ui/tabs/tab_game.tscn"},
	{"label": "ABILITIES", "scene": "res://scenes/ui/tabs/tab_abilities.tscn"},
	{"label": "INVENTORY", "scene": "res://scenes/ui/tabs/tab_inventory.tscn"},
	{"label": "SETTINGS", "scene": "res://scenes/ui/tabs/tab_settings.tscn"},
]

# Shown when a tab does not declare its own. Written as real bindings, not symbols: Barlow
# Condensed has no arrow glyphs and a missing one renders as a box. Q/E live on the tab strip.
const DEFAULT_HINTS := [
	{"key": "W/S", "label": "SELECT"},
	{"key": "ENTER", "label": "CONFIRM"},
	{"key": "ESC", "label": "CLOSE"},
]

@onready var _window: Control = $MenuWindow

var _active := 0
var _bodies: Array[Control] = []
## Per tab, while the menu stays open: {"focus": NodePath relative to the body, "scroll": int}.
var _memory: Array[Dictionary] = []
var _dismiss_generation := 0

func _ready() -> void:
	var labels: Array[String] = []
	for tab: Dictionary in TABS:
		labels.append(tab["label"])
		var body := (load(tab["scene"]) as PackedScene).instantiate() as Control
		body.visible = false
		_window.content_root().add_child(body)
		_bodies.append(body)
		_memory.append(_blank_memory())
	_window.set_title("PAUSED")
	_window.set_tabs(labels)
	_window.tab_selected.connect(func(index: int) -> void: _show_tab(index, signi(index - _active)))
	get_viewport().gui_focus_changed.connect(_remember_focus)
	_show_tab(0, 0, false)

func _blank_memory() -> Dictionary:
	return {"focus": NodePath(), "scroll": 0}

func active_tab() -> int:
	return _active

func window() -> Control:
	return _window

func body(index: int) -> Control:
	return _bodies[index]

# --- opening and closing (called by the UI autoload) ---------------------------------

## Becomes visible: forget every remembered row, start on GAME, play the flat open. `skip_fade`
## is the hologram, whose reveal wipe is the open.
func present(skip_fade := false) -> void:
	_dismiss_generation += 1
	# Dropped first: switching tabs records the focused row, which would put the old one back.
	get_viewport().gui_release_focus()
	for i in _memory.size():
		_memory[i] = _blank_memory()
	_show_tab(0, 0, false)
	if skip_fade:
		_window.process_mode = Node.PROCESS_MODE_INHERIT
		_window.modulate.a = 1.0
		_window.scale = Vector2.ONE
	else:
		_window.present()

## Flat close: the window fades, then this hides. The UI has already unpaused the tree.
func dismiss() -> void:
	_dismiss_generation += 1
	var generation := _dismiss_generation
	_window.dismiss()
	await _window.dismissed
	if generation == _dismiss_generation:
		visible = false

func set_behind_dialog(on: bool) -> void:
	_window.set_behind_dialog(on)

# --- tabs ------------------------------------------------------------------------------

func _show_tab(index: int, direction: int, animate := true) -> void:
	_remember_focus(get_viewport().gui_get_focus_owner())
	var previous := _active
	_active = wrapi(index, 0, TABS.size())
	for i in _bodies.size():
		_bodies[i].visible = i == _active
	_window.set_active_tab(_active, animate)
	var body := _bodies[_active]
	_window.set_hints(body.hints() if body.has_method("hints") else DEFAULT_HINTS)
	if animate and _active != previous:
		_window.play_tab_switch(direction)
	focus_first()

# Records where focus and scroll are in the active tab, so coming back restores them.
func _remember_focus(node: Control) -> void:
	if _bodies.is_empty():
		return
	var body := _bodies[_active]
	if node != null and body.is_ancestor_of(node):
		_memory[_active]["focus"] = body.get_path_to(node)
	_memory[_active]["scroll"] = _window.scroll_position()

# Read in _input rather than _unhandled_input: a focused Button consumes ui_left / ui_right for
# its own focus navigation, so left and right would never reach the tab strip.
#
# tab_prev / tab_next bind only Q/E and the shoulder buttons (see docs/specs/settings.md, Left
# And Right), freeing the arrow keys for a row to adjust its own value. Both wrap.
func _input(event: InputEvent) -> void:
	# Visible is not enough: with a modal pushed on top, the shell is still visible underneath
	# it, and Q/E would silently switch tabs behind the dialog.
	if not visible or UI.stack.is_empty() or UI.stack.back() != &"shell":
		return
	if event.is_action_pressed("tab_next"):
		get_viewport().set_input_as_handled()
		_show_tab(_active + 1, 1)
	elif event.is_action_pressed("tab_prev"):
		get_viewport().set_input_as_handled()
		_show_tab(_active - 1, -1)

# Called by the UI autoload whenever this becomes the top of the stack, so a modal closing over
# the shell hands focus back to the row that was lit rather than nowhere.
func focus_first() -> void:
	if _bodies.is_empty():
		return
	var body := _bodies[_active]
	if body.has_method("refresh"):
		body.refresh()
	var memory := _memory[_active]
	# Read before grab_focus: the focus change records the scroll position, which at this moment
	# is still the previous tab's.
	var saved_scroll: int = memory["scroll"]
	var target: Control = null
	if memory["focus"] != NodePath():
		target = body.get_node_or_null(memory["focus"]) as Control
	if target != null and target.is_visible_in_tree() and target.focus_mode != Control.FOCUS_NONE:
		target.grab_focus()
	elif body.has_method("focus_first"):
		body.focus_first()
	_restore_scroll.call_deferred(_active, saved_scroll)

# Deferred so the body has been laid out and the scroll range exists.
func _restore_scroll(tab: int, scroll: int) -> void:
	if tab == _active:
		_window.set_scroll_position(scroll)
		_memory[tab]["scroll"] = scroll
