extends CanvasLayer

# Runtime control for the full-screen retro downsample (shaders/pixelate.gdshader).
# Attached to the PixelFilter CanvasLayer in scenes/test_platform.tscn.
#
# The PIXEL FILTER settings row is the only one that does not drive a global -
# it reaches this node through the pixel_filter group (join below) rather than
# through Settings' own _apply(), because this node may not exist: the main
# menu has none. See docs/specs/settings.md, The Pixel Filter.
#
# QA keys, so the effect can be A/B'd without leaving the game:
#   O   toggle the filter on/off
#   [   coarser  (drop to the next lower resolution preset)
#   ]   finer    (up to the next higher preset, ending at native = off-looking)
#   \   cycle colour banding: off -> 8 -> 16 -> 32 -> off
#
# O, [ and ] write back through Settings rather than the local state directly,
# so pressing one mid-playtest and then opening the menu shows agreement
# rather than a lie. \ has no settings row and stays purely local.

@export var screen_path: NodePath = ^"Screen"
## Effective resolutions, coarest first is not required - index with [ and ].
@export var presets: Array[Vector2i] = [
	Vector2i(160, 90),
	Vector2i(240, 135),
	Vector2i(320, 180),
	Vector2i(480, 270),
	Vector2i(640, 360),
]
## Colour-banding steps the \ key walks through. 0 means no quantise.
@export var color_step_cycle: Array[int] = [0, 8, 16, 32]
@export var start_color_step: int = 0

var _mat: ShaderMaterial
var _preset_i: int = 0
var _color_i: int = 0


func _ready() -> void:
	add_to_group(&"pixel_filter")
	var rect := get_node_or_null(screen_path) as ColorRect
	if rect == null:
		push_warning("pixelate: ColorRect not found at '%s'; filter disabled." % screen_path)
		set_process_input(false)
		return
	_mat = rect.material as ShaderMaterial
	if _mat == null:
		push_warning("pixelate: '%s' has no ShaderMaterial; filter disabled." % screen_path)
		set_process_input(false)
		return
	_color_i = clampi(color_step_cycle.find(start_color_step), 0, color_step_cycle.size() - 1)
	if _color_i < 0:
		_color_i = 0
	apply_setting(Settings.pixel_filter)


## Called by Settings._apply() through the pixel_filter group, and by this
## node's own QA keys after they write through Settings. -1 is off; 0..n-1
## indexes `presets`.
func apply_setting(value: int) -> void:
	if _mat == null:
		return
	visible = value >= 0
	if value >= 0:
		_preset_i = clampi(value, 0, presets.size() - 1)
	_apply()


func _apply() -> void:
	_mat.set_shader_parameter("pixel_grid", Vector2(presets[_preset_i]))
	_mat.set_shader_parameter("color_steps", color_step_cycle[_color_i])


func _sync_settings() -> void:
	Settings.set_value(&"pixel_filter", _preset_i if visible else -1)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_O:
			visible = not visible
			_sync_settings()
		KEY_BRACKETLEFT:
			_preset_i = maxi(_preset_i - 1, 0)
			_apply()
			_sync_settings()
		KEY_BRACKETRIGHT:
			_preset_i = mini(_preset_i + 1, presets.size() - 1)
			_apply()
			_sync_settings()
		KEY_BACKSLASH:
			_color_i = (_color_i + 1) % color_step_cycle.size()
			_apply()
