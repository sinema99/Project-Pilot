extends CanvasLayer

# Registered as the `UI` autoload. Owns exactly three things: which screen is
# open, whether the tree is paused, and the mouse mode. Game state lives
# elsewhere - see docs/specs/ui-system.md.

enum Screen { NONE, PAUSE, INVENTORY }
enum Action { PAUSE, INVENTORY, CANCEL }

# Loaded at runtime rather than preloaded: a preload resolves at parse time, so
# merely loading this script headlessly would drag both screen scenes in with it.
const PAUSE_MENU_PATH := "res://scenes/ui/pause_menu.tscn"
const INVENTORY_PATH := "res://scenes/ui/inventory.tscn"

var screen := Screen.NONE

var _pause_menu: Control
var _inventory: Control

# The whole rule set, as a pure function: no nodes, no tree, no side effects.
# This is the only part of the UI that can be silently wrong - a cursor that
# never recaptures, a world stuck paused - so it is the part that gets asserted.
# The table this implements is in docs/specs/ui-system.md.
static func resolve(current: Screen, action: Action) -> Dictionary:
	var next := current
	match action:
		Action.PAUSE:
			# Pause is reachable from anywhere, including the inventory. Wanting
			# to stop the game shouldn't mean dismissing something else first.
			next = Screen.NONE if current == Screen.PAUSE else Screen.PAUSE
		Action.INVENTORY:
			if current == Screen.PAUSE:
				# Ignored. Opening a non-pausing screen from a paused one would
				# either unfreeze the world or show it over a frozen one, and
				# both contradict a decision made elsewhere.
				next = Screen.PAUSE
			elif current == Screen.INVENTORY:
				next = Screen.NONE
			else:
				next = Screen.INVENTORY
		Action.CANCEL:
			next = Screen.NONE
	return {
		"screen": next,
		"paused": next == Screen.PAUSE,
		"cursor_captured": next == Screen.NONE,
	}

func _init() -> void:
	# Without ALWAYS this node is paused by its own pause menu and nothing can
	# unpause it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

func _ready() -> void:
	_pause_menu = _spawn(PAUSE_MENU_PATH)
	_inventory = _spawn(INVENTORY_PATH)
	_inventory.close_requested.connect(close)

func _spawn(path: String) -> Control:
	var packed := load(path) as PackedScene
	var node := packed.instantiate() as Control
	node.visible = false
	add_child(node)
	return node

# Read in _input and consumed, rather than left to _unhandled_input, because Tab
# is Godot's built-in ui_focus_next: any focused Control would swallow it before
# the inventory ever saw it.
func _input(event: InputEvent) -> void:
	var action := Action.CANCEL
	if event.is_action_pressed("pause"):
		action = Action.PAUSE
	elif event.is_action_pressed("inventory"):
		action = Action.INVENTORY
	elif event.is_action_pressed("ui_cancel"):
		# With nothing open there is nothing to back out of, so Esc is left
		# alone rather than consumed.
		if screen == Screen.NONE:
			return
		action = Action.CANCEL
	else:
		return
	get_viewport().set_input_as_handled()
	_dispatch(action)

func toggle_pause() -> void:
	_dispatch(Action.PAUSE)

func toggle_inventory() -> void:
	_dispatch(Action.INVENTORY)

func close() -> void:
	_dispatch(Action.CANCEL)

func _dispatch(action: Action) -> void:
	_apply(resolve(screen, action))

func _apply(state: Dictionary) -> void:
	screen = state["screen"]
	_pause_menu.visible = screen == Screen.PAUSE
	_inventory.visible = screen == Screen.INVENTORY
	get_tree().paused = state["paused"]
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if state["cursor_captured"] else Input.MOUSE_MODE_VISIBLE
	if screen == Screen.PAUSE:
		_pause_menu.focus_first()
