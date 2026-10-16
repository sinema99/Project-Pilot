extends CanvasLayer

# Autoload `ScreenPixel`: the PIXEL look over the whole screen, UI and menus included. See
# docs/specs/pixel-look.md, "Whole screen".
#
# PixelWorld only pixelates the 3D render, under the UI. This pass sits above everything (the UI
# is layer 100) and redraws the finished frame in the same blocks and colours, so the
# HUD, the menus, the main menu (which has no PixelWorld) and the hologram panel get the look
# too. It is an autoload rather than part of PixelWorld for that main menu.
#
# On only in the PIXEL look; CEL keeps its sharp UI. Settings drives it through apply_settings().
# While a menu is showing (UI.is_menu_showing()) the pass is off: menus are always sharp
# (2026-10-12, user: "no more pixel menu").

const SHADER := preload("res://shaders/screen_pixel.gdshader")
var _rect: ColorRect
var _mat: ShaderMaterial
## Window pixels per block from Settings; 0 is off.
var block := 0
## Whether a menu is showing, polled from UI each frame.
var menu_showing := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.name = &"Screen"
	_rect.material = _mat
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Or it eats every click on the menus beneath it.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	add_child(_rect)


## `new_block` 0 turns the pass off. Called by Settings for LOOK, PIXEL FILTER and COLOUR DEPTH -
## with the block 0 whenever the look is CEL.
func apply_settings(new_block: int, colour_steps: int) -> void:
	block = maxi(new_block, 0)
	_mat.set_shader_parameter(&"color_steps", colour_steps)
	_update()


func is_on() -> bool:
	return _rect.visible


## The block actually drawn: the Settings block in gameplay, off (0) while a menu shows and in
## CEL.
static func drawn_block(settings_block: int, menu: bool) -> int:
	if settings_block <= 0 or menu:
		return 0
	return settings_block


func current_block() -> int:
	return drawn_block(block, menu_showing)


func _process(_delta: float) -> void:
	var ui := get_node_or_null(^"/root/UI")
	var menu: bool = ui != null and ui.is_menu_showing()
	if menu != menu_showing:
		menu_showing = menu
		_update()


func _update() -> void:
	var b := current_block()
	_mat.set_shader_parameter(&"block", maxi(b, 1))
	_rect.visible = b > 0
