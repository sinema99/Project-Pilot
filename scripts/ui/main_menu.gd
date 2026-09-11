extends Control

# The title screen. A scene, not a stack entry - which is what `shell_enabled`
# exists for: with it off, Esc opens nothing and the cursor stays visible even
# though the screen stack is empty. See docs/specs/ui-shell.md.
#
# It is deliberately NOT the boot scene. project.godot still starts at
# test_platform.tscn and the dev loop is F6 on trial.tscn; a menu gate in front
# of every playtest is friction paid on every iteration.

## Where START goes. Points at the scene actually being played; re-point it at
## map 1 when there is a map 1.
@export_file("*.tscn") var start_scene: String = "res://scenes/trial.tscn"

func _ready() -> void:
	UI.shell_enabled = false
	for button in _buttons():
		button.mouse_entered.connect(button.grab_focus)
	var buttons := _buttons()
	if not buttons.is_empty():
		buttons[0].grab_focus()

func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	for node in $Margin/Column/Menu.get_children():
		var button := node as Button
		if button != null:
			out.append(button)
	return out

func _on_start_pressed() -> void:
	UI.start_game(start_scene)

func _on_settings_pressed() -> void:
	# Matches the shell's empty settings tab. Options need persistence, which is
	# out of scope in the spec.
	print("[UI] Settings - not implemented yet.")

func _on_quit_pressed() -> void:
	UI.confirm("QUIT TO DESKTOP", "Close the game.", get_tree().quit)
