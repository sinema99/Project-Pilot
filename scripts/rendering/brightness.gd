extends CanvasLayer

# Autoload `Brightness`: the gamma overlay. See docs/specs/settings.md.
#
# There is no shared Environment to write adjustment_brightness onto - trial.tscn
# and test_platform.tscn each embed their own, and the main menu has no 3D at
# all - so this is a full-screen pass instead: a ColorRect on a CanvasLayer
# reading hint_screen_texture.
#
# Layer 90: above the world and above PixelWorld (layer -100) - the pixel look
# is a stylistic pass on the render, and brightness belongs after it - and below
# the UI (layer 100), so the menu that would fix an unreadable brightness is
# never the thing brightness darkens.

const BRIGHTNESS_SHADER := preload("res://shaders/brightness.gdshader")

var _mat: ShaderMaterial

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90

func _ready() -> void:
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Or it eats every click on the game beneath it.
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = BRIGHTNESS_SHADER
	rect.material = _mat
	add_child(rect)

func set_gamma(value: float) -> void:
	if _mat:
		_mat.set_shader_parameter("gamma", value)
