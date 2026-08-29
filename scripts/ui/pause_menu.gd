extends Control

# The pause screen: dimmed world behind, one shrink-to-fit window in front.
# Button presses are wired in pause_menu.tscn - connections are made at
# instantiation, so they survive the window re-homing this menu into its
# content area.

func _ready() -> void:
	# Hover moves focus rather than drawing a second highlight, so the keyboard
	# and the pointer can never disagree about which entry is selected.
	for button in _buttons():
		button.mouse_entered.connect(button.grab_focus)

func focus_first() -> void:
	var buttons := _buttons()
	if not buttons.is_empty():
		buttons[0].grab_focus()

# Searched rather than held as an @onready path: ui_window.gd reparents this
# menu into the window's content area, so any path captured up front goes stale.
#
# Filtered on focus_mode because the search also reaches the window's own close
# button, which sits ahead of the menu in tree order - unfiltered, focus_first()
# would aim at the header instead of Resume.
func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	for node in find_children("*", "Button", true, false):
		var button := node as Button
		if button.focus_mode != Control.FOCUS_NONE:
			out.append(button)
	return out

func _on_resume_pressed() -> void:
	UI.close()

func _on_options_pressed() -> void:
	print("[UI] Options - not implemented yet.")

func _on_back_to_main_menu_pressed() -> void:
	print("[UI] Back to Main Menu - no main menu scene exists yet.")

func _on_quit_pressed() -> void:
	get_tree().quit()
