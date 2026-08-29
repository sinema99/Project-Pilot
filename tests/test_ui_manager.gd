extends "res://tests/test_case.gd"

const MANAGER_PATH := "res://scripts/ui/ui_manager.gd"

# Mirrors of the enums in ui_manager.gd, written out as plain ints on purpose:
# the assertions below encode the table in docs/specs/ui-system.md, not whatever
# the script happens to declare today.
const NONE := 0
const PAUSE := 1
const INVENTORY := 2

const ACT_PAUSE := 0
const ACT_INVENTORY := 1
const ACT_CANCEL := 2

func _resolve(current: int, action: int) -> Dictionary:
	# Runtime load, not preload: preload of a missing script is a parse-time
	# failure, which makes --script fall back to running main.tscn and hang.
	var manager := load(MANAGER_PATH) as GDScript
	if manager == null:
		fail("%s does not exist" % MANAGER_PATH)
		return {}
	return manager.resolve(current, action)

func test_pause_opens_from_gameplay_and_freezes_the_world() -> void:
	var state := _resolve(NONE, ACT_PAUSE)
	eq(state.get("screen"), PAUSE, "P with nothing open should open the pause menu")
	eq(state.get("paused"), true, "the pause menu should freeze the tree")
	eq(state.get("cursor_captured"), false, "the cursor must be released to click Resume")

func test_pause_closes_and_unfreezes() -> void:
	var state := _resolve(PAUSE, ACT_PAUSE)
	eq(state.get("screen"), NONE, "P while paused should close the menu")
	eq(state.get("paused"), false, "closing the pause menu must unfreeze the tree")
	eq(state.get("cursor_captured"), true, "the cursor should be recaptured on returning to gameplay")

# Pause is reachable from anywhere. Wanting to stop the game should not mean
# dismissing the inventory first.
func test_pause_is_reachable_from_the_inventory() -> void:
	var state := _resolve(INVENTORY, ACT_PAUSE)
	eq(state.get("screen"), PAUSE, "P should swap the inventory out for the pause menu")
	eq(state.get("paused"), true, "swapping to pause should freeze the tree")

func test_inventory_opens_without_freezing_the_world() -> void:
	var state := _resolve(NONE, ACT_INVENTORY)
	eq(state.get("screen"), INVENTORY, "Tab with nothing open should open the inventory")
	eq(state.get("paused"), false, "the inventory must not freeze the tree")
	eq(state.get("cursor_captured"), false, "releasing the cursor is what stops the camera")

func test_inventory_closes() -> void:
	var state := _resolve(INVENTORY, ACT_INVENTORY)
	eq(state.get("screen"), NONE, "Tab while the inventory is open should close it")
	eq(state.get("cursor_captured"), true, "the cursor should be recaptured on close")

# Opening a non-pausing screen from a paused one would either unfreeze the world
# or show the inventory over a frozen one. Both contradict a decision made
# elsewhere, so the input does nothing at all.
func test_inventory_is_ignored_while_paused() -> void:
	var state := _resolve(PAUSE, ACT_INVENTORY)
	eq(state.get("screen"), PAUSE, "Tab while paused should change nothing")
	eq(state.get("paused"), true, "an ignored input must not unfreeze the tree")
	eq(state.get("cursor_captured"), false, "an ignored input must not recapture the cursor")

func test_cancel_closes_whichever_screen_is_open() -> void:
	var from_pause := _resolve(PAUSE, ACT_CANCEL)
	eq(from_pause.get("screen"), NONE, "Esc should close the pause menu")
	eq(from_pause.get("paused"), false, "Esc out of pause must unfreeze the tree")

	var from_inventory := _resolve(INVENTORY, ACT_CANCEL)
	eq(from_inventory.get("screen"), NONE, "Esc should close the inventory")

# The failure this guards is silent: a cursor left visible during gameplay looks
# almost right until mouse-look stops working.
func test_cursor_is_captured_only_when_nothing_is_open() -> void:
	eq(_resolve(NONE, ACT_CANCEL).get("cursor_captured"), true, "gameplay should own the cursor")
	eq(_resolve(NONE, ACT_PAUSE).get("cursor_captured"), false, "the pause menu should release the cursor")
	eq(_resolve(NONE, ACT_INVENTORY).get("cursor_captured"), false, "the inventory should release the cursor")

# Only the pause screen ever pauses. Stated separately because it is the one
# invariant tying the two screens together.
func test_only_the_pause_screen_freezes_the_tree() -> void:
	for action in [ACT_PAUSE, ACT_INVENTORY, ACT_CANCEL]:
		for current in [NONE, PAUSE, INVENTORY]:
			var state := _resolve(current, action)
			eq(state.get("paused"), state.get("screen") == PAUSE,
				"paused should be true exactly when the pause screen is open (from %d via %d)" % [current, action])
