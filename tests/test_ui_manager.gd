extends "res://tests/test_case.gd"

# The transition rules, asserted against the table in docs/specs/ui-shell.md.
#
# resolve() is a pure function precisely so this file can exist: the failures it
# guards against - a world stuck paused, a cursor that never recaptures, a modal
# that swallows the screen underneath it - are all silent, and none of them can
# be caught by looking at the game for a few seconds.

const MANAGER_PATH := "res://scripts/ui/ui_manager.gd"

# Mirrors of the enum in ui_manager.gd, written out as plain ints on purpose:
# these assertions encode the spec, not whatever the script happens to declare.
const BACK := 0
const CLOSE := 1
const PUSH := 2

const SHELL := &"shell"
const CONFIRM := &"confirm"

func _resolve(stack: Array, action: int, enabled := true, arg := &"") -> Dictionary:
	# Runtime load, not preload: preload of a missing path is a parse-time
	# failure, which makes --script fall back to running main.tscn and hang.
	var manager := load(MANAGER_PATH) as GDScript
	if manager == null:
		fail("%s does not exist" % MANAGER_PATH)
		return {}
	return manager.resolve(stack, action, enabled, arg)

func _stack(state: Dictionary) -> Array:
	return state.get("stack", [])

# --- opening and closing -------------------------------------------------------

func test_back_from_gameplay_opens_the_shell_and_freezes_the_world() -> void:
	var state := _resolve([], BACK)
	eq(_stack(state), [SHELL], "Esc with nothing open should open the shell")
	eq(state.get("paused"), true, "the shell should freeze the tree")
	eq(state.get("cursor_captured"), false, "the cursor must be released to click a row")

func test_back_from_the_shell_returns_to_gameplay() -> void:
	var state := _resolve([SHELL], BACK)
	eq(_stack(state), [], "Esc in the shell should close it")
	eq(state.get("paused"), false, "closing the last screen must unfreeze the world")
	eq(state.get("cursor_captured"), true, "closing the last screen must recapture the cursor")

func test_close_returns_to_gameplay() -> void:
	var state := _resolve([SHELL], CLOSE)
	eq(_stack(state), [], "Resume should close the shell")
	eq(state.get("paused"), false, "Resume must unfreeze the world")

# --- the stack -----------------------------------------------------------------

func test_a_modal_stacks_on_top_of_the_shell() -> void:
	var state := _resolve([SHELL], PUSH, true, CONFIRM)
	eq(_stack(state), [SHELL, CONFIRM], "the modal should sit on top, not replace the shell")
	eq(state.get("paused"), true, "the world stays frozen under a modal")

# The case a flat screen enum could not express, and the reason the stack exists.
func test_back_pops_one_level_only() -> void:
	var state := _resolve([SHELL, CONFIRM], BACK)
	eq(_stack(state), [SHELL], "cancelling a modal should return to the shell, not to gameplay")
	eq(state.get("paused"), true, "popping a modal must not unfreeze the world")
	eq(state.get("cursor_captured"), false, "the shell is still open, so the cursor stays free")

func test_close_clears_the_whole_stack() -> void:
	var state := _resolve([SHELL, CONFIRM], CLOSE)
	eq(_stack(state), [], "CLOSE should empty the stack, not pop one level")
	eq(state.get("paused"), false, "an empty stack must unfreeze the world")

# A modal opened straight from the main menu, with no shell under it.
func test_a_modal_can_stand_alone() -> void:
	var state := _resolve([], PUSH, false, CONFIRM)
	eq(_stack(state), [CONFIRM], "the main menu must be able to open a modal with no shell open")
	eq(state.get("cursor_captured"), false, "a modal always needs a pointer")
	state = _resolve([CONFIRM], BACK, false)
	eq(_stack(state), [], "backing out of a lone modal should return to the menu")

# --- shell_enabled -------------------------------------------------------------

func test_the_shell_cannot_be_opened_on_the_main_menu() -> void:
	var state := _resolve([], BACK, false)
	eq(_stack(state), [], "Esc on the title screen should open nothing")
	eq(state.get("paused"), false, "nothing opened, so nothing should freeze")

# Both halves of the cursor rule matter. The main menu has an empty stack and
# still needs a pointer - this is the assertion that stops someone simplifying
# cursor_captured down to "the stack is empty".
func test_an_empty_stack_does_not_capture_the_cursor_without_a_game() -> void:
	eq(_resolve([], CLOSE, false).get("cursor_captured"), false,
		"the main menu has an empty stack and still needs a visible cursor")
	eq(_resolve([], CLOSE, true).get("cursor_captured"), true,
		"in gameplay an empty stack should recapture")

# --- the failure this design is most afraid of ---------------------------------

func test_pause_is_never_true_with_an_empty_stack() -> void:
	for action: int in [BACK, CLOSE, PUSH]:
		for enabled: bool in [true, false]:
			var state := _resolve([], action, enabled)
			if not _stack(state).is_empty():
				continue
			eq(state.get("paused"), false,
				"an empty stack must never leave the world paused (action %d)" % action)

# resolve() takes no nodes and must not write through its argument - the autoload
# passes its own live stack in.
func test_resolve_does_not_mutate_the_stack_it_is_given() -> void:
	var original: Array = [SHELL]
	_resolve(original, PUSH, true, CONFIRM)
	eq(original, [SHELL], "resolve() should return a new stack, not edit the caller's")
