extends VBoxContainer

# The GAME tab: the four things you can do to a running game. Button presses are
# wired in tab_game.tscn. See docs/specs/ui-shell.md.

func _ready() -> void:
	# Hover moves focus rather than drawing a second highlight, so the keyboard
	# and the pointer can never disagree about which entry is selected.
	for button in _buttons():
		button.mouse_entered.connect(button.grab_focus)

func focus_first() -> void:
	var buttons := _buttons()
	if not buttons.is_empty():
		buttons[0].grab_focus()

func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	for node in get_children():
		var button := node as Button
		if button != null:
			out.append(button)
	return out

func _on_resume_pressed() -> void:
	UI.close()

# Not what "restart" will mean once checkpoints exist. It is what restart can
# mean today, and it is the most useful button in the menu during a playtest.
func _on_restart_pressed() -> void:
	UI.close()
	get_tree().reload_current_scene()

func _on_main_menu_pressed() -> void:
	UI.confirm("BACK TO MAIN MENU", "The current run will be lost.", UI.to_main_menu)

func _on_quit_pressed() -> void:
	UI.confirm("QUIT TO DESKTOP", "The current run will be lost.", get_tree().quit)
