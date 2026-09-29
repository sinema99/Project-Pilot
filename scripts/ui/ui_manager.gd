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
	&"settings": {"path": "res://scenes/ui/settings_screen.tscn", "pauses": true},
}

const DIM_COLOR := Color(0, 0, 0, 0.65)
## The flat dim fades in over this long, and out over DIM_OUT_TIME. Input is live from the first
## frame of either - see docs/specs/menu-refresh.md, "Motion".
const DIM_IN_TIME := 0.15
const DIM_OUT_TIME := 0.10

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

# The pilot9 hologram rig while the pause menu is drawn as a projection, else null. Chosen once
# when Esc opens the shell and held until the close animation ends - see
# docs/specs/pilot9-hologram-pause.md. The tree stays paused until the rig says it is home.
var _holo: Node
var _dim_tween: Tween

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
		_forward_to_hologram(event)
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
	var before := stack.duplicate()
	var was_empty := stack.is_empty()
	stack.assign(state["stack"])
	if not is_instance_valid(_holo):
		_holo = null
	if _holo == null and was_empty and not stack.is_empty():
		_holo = _pick_hologram()
		if _holo != null:
			_holo.tree_exiting.connect(_on_hologram_gone, CONNECT_ONE_SHOT)
			_holo.closed.connect(_on_hologram_closed)
	_update_screens(before)
	if _holo != null:
		_apply_hologram(state)
		return
	_set_dim(not stack.is_empty())
	get_tree().paused = state["paused"]
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if state["cursor_captured"] else Input.MOUSE_MODE_VISIBLE
	# Only the top screen may hold focus, or arrow keys would walk into a list
	# hidden underneath the one on screen.
	if not stack.is_empty():
		var top: Control = _instances[stack.back()]
		if top.has_method("focus_first"):
			top.focus_first()

## Shows and hides the screens to match the stack. A screen that just arrived is `present()`ed; one
## that just left fades out (flat only - the hologram has its own close) while the tree is already
## unpaused underneath it.
func _update_screens(before: Array) -> void:
	var dialog_on_top: bool = not stack.is_empty() and stack.back() == &"confirm"
	for name: StringName in _instances:
		var node: Control = _instances[name]
		var want := stack.has(name)
		if want:
			if not before.has(name) or not node.visible:
				node.visible = true
				if node.has_method("present"):
					node.present(_holo != null)
		elif node.visible:
			if before.has(name) and _holo == null and node.has_method("dismiss"):
				node.dismiss()
			else:
				node.visible = false
		if node.has_method("set_behind_dialog"):
			node.set_behind_dialog(want and dialog_on_top and name != &"confirm")

func _set_dim(on: bool) -> void:
	if _dim_tween != null:
		_dim_tween.kill()
	if on:
		if not _dim.visible:
			_dim.color = Color(DIM_COLOR, 0.0)
			_dim.visible = true
		_dim_tween = create_tween()
		_dim_tween.tween_property(_dim, "color:a", DIM_COLOR.a, DIM_IN_TIME)
	elif _dim.visible:
		_dim_tween = create_tween()
		_dim_tween.tween_property(_dim, "color:a", 0.0, DIM_OUT_TIME)
		_dim_tween.tween_callback(_dim.hide)

# --- hologram -----------------------------------------------------------------

func _pick_hologram() -> Node:
	# Runtime load for the same reason as _spawn: no preload dragging the rig into headless loads.
	var rig_script := load("res://scripts/pilot9_hologram.gd") as GDScript
	var host := get_tree().get_first_node_in_group(&"hologram_host")
	var body: Node3D = host.get_parent() as Node3D if host != null else null
	var use: bool = rig_script.hologram_mode(
		Settings.hologram_menu,
		host != null and body != null,
		body != null and body.is_visible_in_tree(),
		host != null and host.get("_camera") != null and (host.get("_camera") as Camera3D).current)
	return host if use else null

func _apply_hologram(state: Dictionary) -> void:
	if _dim_tween != null:
		_dim_tween.kill()
	_dim.visible = false
	var screens: Node = _holo.screen_host()
	for name: StringName in [&"shell", &"confirm"]:
		var node: Node = _instances[name]
		if node.get_parent() != screens:
			node.get_parent().remove_child(node)
			screens.add_child(node)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if stack.is_empty():
		# Still paused: the world stays frozen until the camera is back, and _on_hologram_closed
		# finishes the job.
		_holo.close()
	else:
		# Before the tree pauses, so the rig's wall sweep asks a running physics space.
		_holo.open()
		get_tree().paused = state["paused"]
		var top: Control = _instances[stack.back()]
		if top.has_method("focus_first"):
			top.focus_first()

func _on_hologram_closed() -> void:
	_release_hologram()
	# The plain path, from the same stack: unpauses and recaptures the cursor.
	_apply(resolve(stack, Action.PUSH, shell_enabled))

func _on_hologram_gone() -> void:
	# The scene is being freed with the menus still parented into it.
	_release_hologram()
	_apply(resolve(stack, Action.PUSH, shell_enabled))

func _release_hologram() -> void:
	if _holo != null:
		if _holo.closed.is_connected(_on_hologram_closed):
			_holo.closed.disconnect(_on_hologram_closed)
		if _holo.tree_exiting.is_connected(_on_hologram_gone):
			_holo.tree_exiting.disconnect(_on_hologram_gone)
	_holo = null
	for name: StringName in [&"shell", &"confirm"]:
		var node: Node = _instances.get(name)
		if node != null and node.get_parent() != self:
			node.get_parent().remove_child(node)
			add_child(node)

func _forward_to_hologram(event: InputEvent) -> void:
	if _holo == null or not _holo.is_active():
		return
	get_viewport().set_input_as_handled()
	if event is InputEventMouse:
		_holo.forward_mouse(event)
	else:
		_holo.forward_input(event)
