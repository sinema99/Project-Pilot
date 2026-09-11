extends CanvasLayer

# Registered as the `UI` autoload. Owns exactly four things: the screen stack,
# whether the tree is paused, the mouse mode, and the dim behind everything.
# Game state lives elsewhere - see docs/specs/ui-shell.md.
#
# An EMPTY STACK MEANS GAMEPLAY: nothing drawn, no dim, tree running, cursor
# captured. Every other state is derived from what is on the stack, never stored
# alongside it, so "the world is stuck paused" cannot happen by the two falling
# out of sync.

enum Action { BACK, CLOSE, PUSH }

# The registry. `pauses` is read by resolve(), which is why this is a const and
# not built at runtime - the rules stay a pure function with no tree behind them.
const SCREENS := {
	&"shell": {"path": "res://scenes/ui/shell.tscn", "pauses": true},
	&"confirm": {"path": "res://scenes/ui/confirm_dialog.tscn", "pauses": true},
}

const DIM_COLOR := Color(0, 0, 0, 0.65)

# False while the main menu is the current scene. It keeps the main menu out of
# the stack entirely rather than modelling a screen that is also a scene: with it
# off, Esc opens nothing and the cursor stays visible on an empty stack.
#
# Modals still work with it off - the main menu's QUIT needs one.
var shell_enabled := true:
	set(value):
		shell_enabled = value
		# A no-op PUSH: recomputes pause and cursor from the same stack. The
		# guard is for the setter firing before _ready has built the dim.
		if is_instance_valid(_dim):
			_apply(resolve(stack, Action.PUSH, shell_enabled))

var stack: Array[StringName] = []

var _dim: ColorRect
var _instances: Dictionary = {}
var _confirm_callback: Callable

# The whole rule set, as a pure function: no nodes, no tree, no side effects.
# This is the only part of the UI that can be silently wrong - a cursor that
# never recaptures, a world stuck paused - so it is the part that gets asserted.
# The table this implements is in docs/specs/ui-shell.md.
static func resolve(current: Array, action: int, enabled: bool, arg: StringName = &"") -> Dictionary:
	var next: Array[StringName] = []
	for name: StringName in current:
		next.append(name)

	match action:
		Action.BACK:
			if next.is_empty():
				# Esc from gameplay opens the shell. On the main menu it does
				# nothing at all, rather than opening a pause screen over a
				# game that is not running.
				if enabled:
					next.append(&"shell")
			else:
				# One level, not all of them. A modal over the shell backs out
				# to the shell; the shell backs out to gameplay. Tabs are not
				# levels, so a tab never absorbs an Esc.
				next.pop_back()
		Action.CLOSE:
			next.clear()
		Action.PUSH:
			if arg != &"":
				next.append(arg)

	var paused := false
	for name: StringName in next:
		if SCREENS.get(name, {}).get("pauses", false):
			paused = true
			break

	return {
		"stack": next,
		"paused": paused,
		# Captured only with nothing open AND a game running behind it. Both
		# halves matter: the main menu has an empty stack and still needs a
		# pointer.
		"cursor_captured": next.is_empty() and enabled,
	}

func _init() -> void:
	# Without ALWAYS this node is paused by its own screens and nothing can
	# unpause it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

func _ready() -> void:
	_dim = ColorRect.new()
	_dim.color = DIM_COLOR
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	add_child(_dim)

	for name: StringName in SCREENS:
		_instances[name] = _spawn(SCREENS[name]["path"])

	var dialog: Control = _instances[&"confirm"]
	dialog.confirmed.connect(_on_confirm_accepted)
	dialog.cancelled.connect(back)

	# Apply the opening state rather than assuming the engine already matches
	# it. mouse_mode starts VISIBLE, so without this the cursor stays free and
	# mouse look is dead until a menu is opened and closed.
	_apply(resolve(stack, Action.CLOSE, shell_enabled))

func _spawn(path: String) -> Control:
	# Loaded at runtime rather than preloaded: a preload resolves at parse time,
	# so merely loading this script headlessly would drag every screen in with it.
	var packed := load(path) as PackedScene
	var node := packed.instantiate() as Control
	node.visible = false
	add_child(node)
	return node

func _input(event: InputEvent) -> void:
	if not (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		return
	# With nothing open and no game running there is nothing to back out of, so
	# the key is left alone rather than consumed.
	if stack.is_empty() and not shell_enabled:
		return
	get_viewport().set_input_as_handled()
	_dispatch(Action.BACK)

# --- public API ---------------------------------------------------------------

func open(name: StringName) -> void:
	_dispatch(Action.PUSH, name)

func back() -> void:
	_dispatch(Action.BACK)

func close() -> void:
	_dispatch(Action.CLOSE)

## Pushes the confirm modal over whatever is open. `on_confirm` runs only if the
## player picks CONFIRM; cancelling just pops the modal.
func confirm(title: String, message: String, on_confirm: Callable) -> void:
	_confirm_callback = on_confirm
	var dialog: Control = _instances[&"confirm"]
	dialog.setup(title, message)
	open(&"confirm")

## Leaves the menus and enters a gameplay scene. Re-arms the shell, which the
## main menu turned off.
func start_game(path: String) -> void:
	close()
	shell_enabled = true
	get_tree().change_scene_to_file(path)

## Returns to the title screen. The main menu turns the shell back off itself,
## in its own _ready, so this does not have to know the order things load in.
func to_main_menu() -> void:
	close()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

# --- internals ----------------------------------------------------------------

func _on_confirm_accepted() -> void:
	var callback := _confirm_callback
	_confirm_callback = Callable()
	back()
	if callback.is_valid():
		callback.call()

func _dispatch(action: Action, arg: StringName = &"") -> void:
	_apply(resolve(stack, action, shell_enabled, arg))

func _apply(state: Dictionary) -> void:
	stack.assign(state["stack"])
	for name: StringName in _instances:
		_instances[name].visible = stack.has(name)
	_dim.visible = not stack.is_empty()
	get_tree().paused = state["paused"]
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if state["cursor_captured"] else Input.MOUSE_MODE_VISIBLE
	# Only the top screen may hold focus, or arrow keys would walk into a list
	# hidden underneath the one on screen.
	if not stack.is_empty():
		var top: Control = _instances[stack.back()]
		if top.has_method("focus_first"):
			top.focus_first()
