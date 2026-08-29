extends Control

# The inventory window. Intentionally empty - it is the frame and nothing else
# until there are items to put in it. Slots, selection, and item data all land
# here. See docs/specs/ui-system.md.
#
# The world keeps running while this is open; only the cursor changes, which is
# what stops the camera (player.gd and mech.gd both gate mouse-look on the mouse
# being captured).

signal close_requested

@onready var _window: PanelContainer = $Center/UIWindow

func _ready() -> void:
	_window.close_requested.connect(func() -> void: close_requested.emit())
