extends "res://tests/test_case.gd"

# docs/specs/menu-refresh.md, "Tests". The layout ones build the shell inside a 1280 x 800
# SubViewport - the hologram's own condition - and sort the containers by hand, because a headless
# test method cannot wait a frame for the deferred layout pass.
#
# Feel (timings, nudge, dim amounts, hologram strength) can only be judged in play.

const SHELL := "res://scenes/ui/shell.tscn"
const SETTINGS_SCREEN := "res://scenes/ui/settings_screen.tscn"
const CONFIRM := "res://scenes/ui/confirm_dialog.tscn"
const MENU_ROW := "res://scripts/ui/menu_row.gd"
const MENU_WINDOW := "res://scripts/ui/menu_window.gd"
const MENU_FRAME := "res://scripts/ui/menu_frame.gd"

var _cleanup: Array[Node] = []

func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root

# Builds `scene` in a 1280 x 800 SubViewport, sorted and ready.
func _host(scene: String) -> Control:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.transparent_bg = true
	_root().add_child(viewport)
	_cleanup.append(viewport)
	var node := (load(scene) as PackedScene).instantiate() as Control
	viewport.add_child(node)
	_sort(node)
	return node

func _sort(node: Node) -> void:
	for child in node.get_children():
		_sort(child)
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)

func _free_all() -> void:
	for node in _cleanup:
		if is_instance_valid(node):
			node.free()
	_cleanup.clear()

func _row_for(tab: Control, key: StringName) -> Control:
	for row: Control in tab.rows():
		if tab.key_of(row) == key:
			return row
	return null

# --- the window ------------------------------------------------------------------

# The regression for "the scale is off": the old shell grew with its content.
func test_the_window_never_grows_with_the_settings_rows() -> void:
	var shell := _host(SHELL)
	var window: Control = shell.window()
	shell._show_tab(3, 0, false)
	_sort(shell)
	eq(window.size, Vector2(1280, 800), "the window should be exactly 1280 x 800")
	var bounds := window.get_global_rect()
	var column: Control = window.get_node("Margin/Column")
	for part in ["Header", "Scroll", "Footer"]:
		var rect: Rect2 = column.get_node(part).get_global_rect()
		check(bounds.encloses(rect), "%s should lie inside the window (%s in %s)" % [part, rect, bounds])
	var scroll: ScrollContainer = window.scroll()
	check(window.content_root().size.y > scroll.size.y,
		"the SETTINGS rows should be taller than the view - they scroll, the window does not grow")
	_free_all()

func test_the_frame_cuts_the_top_left_and_bottom_right_corners() -> void:
	var frame := (load(MENU_FRAME) as GDScript).new() as Control
	var outline: PackedVector2Array = frame.outline(Vector2(100, 60))
	check(not outline.has(Vector2(0, 0)), "the top-left corner should be cut")
	check(not outline.has(Vector2(100, 60)), "the bottom-right corner should be cut")
	check(outline.has(Vector2(100, 0)), "the top-right corner should stay square")
	check(outline.has(Vector2(0, 60)), "the bottom-left corner should stay square")
	frame.free()

# The lead is what keeps the next row visible while walking a long list.
func test_scroll_target_leaves_room_below_and_above() -> void:
	var window := load(MENU_WINDOW) as GDScript
	# A row at 900..952 in 1200 of content, view 500 tall, currently at the top.
	var down: float = window.scroll_target(900.0, 952.0, 0.0, 500.0, 1200.0)
	check(down + 500.0 >= 952.0 + window.SCROLL_LEAD - 0.01, "the row should have lead below it")
	check(down <= 1200.0 - 500.0 + 0.01, "the scroll should not run past the content")
	var up: float = window.scroll_target(100.0, 152.0, 600.0, 500.0, 1200.0)
	check(up <= 100.0 - window.SCROLL_LEAD + 0.01, "the row should have lead above it")
	eq(window.scroll_target(300.0, 352.0, 200.0, 500.0, 1200.0), 200.0,
		"a row already comfortably in view should not scroll")
	eq(window.scroll_target(0.0, 52.0, 300.0, 500.0, 1200.0), 0.0, "the first row scrolls to the very top")

# --- tabs ------------------------------------------------------------------------

func test_q_and_e_wrap_and_every_tab_is_reachable_by_click() -> void:
	var shell := _host(SHELL)
	eq(shell.active_tab(), 0, "the shell should open on GAME")
	shell._show_tab(shell.active_tab() - 1, -1)
	eq(shell.active_tab(), 3, "Q on the first tab should wrap to the last")
	shell._show_tab(shell.active_tab() + 1, 1)
	eq(shell.active_tab(), 0, "E on the last tab should wrap to the first")
	# The regression for "you cannot tab back": from SETTINGS, every tab must be one click away.
	shell._show_tab(3, 0, false)
	var tabs: Array[Button] = shell.window().tab_buttons()
	eq(tabs.size(), 4, "there should be a tab button per tab")
	for i in tabs.size():
		shell._show_tab(3, 0, false)
		tabs[i].pressed.emit()
		eq(shell.active_tab(), i, "clicking tab %d should switch to it from SETTINGS" % i)
	_free_all()

func test_each_tab_remembers_its_row_until_the_menu_closes() -> void:
	var shell := _host(SHELL)
	shell._show_tab(3, 0, false)
	var settings: Control = shell.body(3)
	var fifth: Control = settings.rows()[5]
	fifth.grab_focus()
	shell._show_tab(0, -1)
	shell._show_tab(3, 1)
	eq(shell.get_viewport().gui_get_focus_owner(), fifth, "coming back should restore the fifth row")
	# Close and reopen: the shell starts on GAME, first row.
	shell.present(true)
	eq(shell.active_tab(), 0, "reopening should start on GAME")
	eq(shell.get_viewport().gui_get_focus_owner(), shell.body(0).get_child(0),
		"reopening should focus the first GAME row")
	shell._show_tab(3, 0, false)
	eq(shell.get_viewport().gui_get_focus_owner(), settings.rows()[0],
		"reopening should have forgotten the fifth SETTINGS row")
	_free_all()

func test_the_settings_screen_has_no_tab_strip() -> void:
	var screen := _host(SETTINGS_SCREEN)
	var area: Control = screen.window().get_node("Margin/Column/Header/TabArea")
	check(not area.visible, "the standalone settings screen should not show a tab strip")
	_free_all()

# --- SETTINGS rows ---------------------------------------------------------------

func test_the_dropdown_is_gone() -> void:
	var shell := _host(SHELL)
	shell._show_tab(3, 0, false)
	var top_level := 0
	var pending: Array[Node] = [shell.body(3)]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Control and (node as Control).top_level:
			top_level += 1
		pending.append_array(node.get_children())
	eq(top_level, 0, "the SETTINGS tab should not create a floating top-level control")
	check(shell.body(3).get("_options_panel") == null, "the dropdown's panel is removed")
	_free_all()

func test_a_selector_clamps_and_reports_its_end() -> void:
	var shell := _host(SHELL)
	shell._show_tab(3, 0, false)
	var tab: Control = shell.body(3)
	var row := _row_for(tab, &"vsync")
	Settings.set_value(&"vsync", "adaptive")
	tab.refresh()
	check(not row.can_right, "at the last value the right arrow should be disabled")
	tab._step(1, &"vsync")
	eq(Settings.get_value(&"vsync"), "adaptive", "stepping past the end should do nothing")
	check(row.can_left, "the left arrow should still work")

	# Clicking the left arrow steps down and keeps focus on the row.
	row.grab_focus()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = row.left_zone().get_center()
	row._gui_input(click)
	eq(Settings.get_value(&"vsync"), "on", "clicking the left arrow should step down at once")
	check(row.has_focus(), "clicking an arrow should keep focus on the row")
	Settings.set_value(&"vsync", Settings.defaults()[&"vsync"])
	_free_all()

# --- rows --------------------------------------------------------------------------

func test_a_disabled_row_cannot_be_focused_and_a_destructive_one_is_tinted() -> void:
	var row := (load(MENU_ROW) as GDScript).new() as Button
	row.text = "TEST"
	var plain: Color = row.accent_color()
	row.destructive = true
	check(row.accent_color() != plain, "a destructive row should be tinted differently")
	row.set_row_disabled(true)
	eq(row.focus_mode, Control.FOCUS_NONE, "a disabled row should not take focus, so W/S skip it")
	row.free()

func test_keyboard_confirm_fires_on_press() -> void:
	var shell := _host(SHELL)
	var resume: Control = shell.body(0).get_child(0)
	var fired := [0]
	resume.pressed.connect(func() -> void: fired[0] += 1)
	# Detach the real handler: this row would close the shell.
	for connection in resume.pressed.get_connections():
		if connection["callable"].get_object() == shell.body(0):
			resume.pressed.disconnect(connection["callable"])
	resume.grab_focus()
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	resume._gui_input(accept)
	eq(fired[0], 1, "ui_accept should fire on the press, not wait for the release")
	_free_all()

# --- the confirm dialog ----------------------------------------------------------------

func test_the_dialog_starts_on_cancel_and_its_confirm_is_destructive() -> void:
	var dialog := _host(CONFIRM)
	dialog.setup("QUIT", "Sure?")
	dialog.focus_first()
	eq(dialog.get_viewport().gui_get_focus_owner(), dialog.get_node("Window/Margin/Column/Buttons/Cancel"),
		"focus should start on CANCEL")
	check(dialog.get_node("Window/Margin/Column/Buttons/Confirm").destructive,
		"a plain confirm loses progress, so it should be destructive")
	dialog.setup("KEEP THIS DISPLAY MODE?", "Reverting.", 15.0)
	check(not dialog.get_node("Window/Margin/Column/Buttons/Confirm").destructive,
		"a keep-or-revert confirm is not destructive")
	dialog.set_process(false)
	eq(dialog.get_node("Window").size, Vector2(560, 260), "the dialog window should be 560 x 260")
	_free_all()

# --- the UI autoload -------------------------------------------------------------------

# The tree unpauses on the Esc press, not after the fade; the window is still on screen fading.
func test_closing_the_flat_shell_unpauses_before_the_fade_ends() -> void:
	UI.close()
	UI.open(&"shell")
	var tree := Engine.get_main_loop() as SceneTree
	eq(tree.paused, true, "the open shell should pause the tree")
	UI.back()
	eq(tree.paused, false, "closing the shell should unpause the tree in the same frame")
	check(UI._instances[&"shell"].visible, "the window should still be fading out")
	# Leave the autoload as found.
	UI.close()
	UI._instances[&"shell"].visible = false
	tree.paused = false
