class_name IntroTitleCard
extends CanvasLayer

# The "EARTH 2129" title card in the intro shot's bottom-left corner (spec "Title card"). The title
# and the coordinates fade in staggered, then the ship's flyby wipes them away left to right while
# they shake with the camera. No backing behind the text (user). Everything is a function of the shot time, like the rest of the shot,
# so seeking shows the same frame. intro_space.gd calls update_card() every frame.

@export var title_text := "EARTH 2129"
## Under the storm eye over Florida, where the ship's dive ends.
@export var coords_text := "27°48'14\"N  81°41'52\"W"

@export_group("Timing")
## Shot times each line starts fading in and is fully in.
@export var title_in_start := 1.5
@export var title_in_end := 3.0
@export var coords_in_start := 2.1
@export var coords_in_end := 3.6
## The flyby wipe: starts with the rumble, done just past its 7.2 s peak.
@export var wipe_start := 7.0
@export var wipe_end := 7.3

@export_group("Look")
## Title cap height as a fraction of the screen height; the coordinates are this times coords_scale.
@export var title_size := 0.04
@export var coords_scale := 0.42
## Margins from the left and bottom edges, fractions of the screen height. Set so the block sits on
## the open Pacific, off the snow, for the whole time it is up (user's box, 2026-10-14).
@export var margin_left := 0.13
@export var margin_bottom := 0.07
## Letter spacing, fraction of each line's font size.
@export var spacing := 0.35
@export var title_opacity := 0.9
@export var coords_opacity := 0.75

const _SEMIBOLD := preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
const _REGULAR := preload("res://assets/fonts/BarlowCondensed-Regular.ttf")

const _WIPE_SHADER := """
shader_type canvas_item;
// Left-to-right wipe across the text block. block = (left, right) as fractions of the screen width.
uniform vec2 block = vec2(0.0, 1.0);
uniform float wipe = 0.0;
uniform float soft = 0.25;
void fragment() {
	float x = (SCREEN_UV.x - block.x) / max(block.y - block.x, 0.001);
	float edge = wipe * (1.0 + soft);
	COLOR.a *= smoothstep(edge - soft, edge, x);
}
"""

var _block := Control.new()
var _title := Label.new()
var _coords := Label.new()
var _wipe_mat := ShaderMaterial.new()


func _ready() -> void:
	layer = 10
	_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe_mat.shader = _shader(_WIPE_SHADER)
	_block.material = _wipe_mat
	add_child(_block)
	for l: Label in [_title, _coords]:
		l.use_parent_material = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_block.add_child(l)
	_title.text = title_text
	_coords.text = coords_text
	_layout()
	get_viewport().size_changed.connect(_layout)
	update_card(0.0, Vector2.ZERO)


## Opacity of a line given its fade-in window, before the wipe.
func fade_in(t: float, from: float, to: float) -> float:
	return smoothstep(from, to, t)


func title_alpha(t: float) -> float:
	return fade_in(t, title_in_start, title_in_end)


func coords_alpha(t: float) -> float:
	return fade_in(t, coords_in_start, coords_in_end)


## 0 before the flyby, 1 once the text is fully wiped. Eased so it leaves fast.
func wipe_at(t: float) -> float:
	var w := clampf((t - wipe_start) / (wipe_end - wipe_start), 0.0, 1.0)
	return w * (2.0 - w)


## How much of each line still shows (title, coordinates), wipe included, 0-1. The wipe is
## left to right, so this is the visible share of the line's width.
func visible_at(t: float) -> Vector2:
	var keep := 1.0 - wipe_at(t)
	return Vector2(title_alpha(t), coords_alpha(t)) * keep


## shake_px: the camera rumble as a screen offset, so the text shakes with the picture.
func update_card(t: float, shake_px: Vector2) -> void:
	_title.modulate.a = title_alpha(t) * title_opacity
	_coords.modulate.a = coords_alpha(t) * coords_opacity
	var w := wipe_at(t)
	_wipe_mat.set_shader_parameter(&"wipe", w)
	_block.position = _block_origin() + shake_px
	var vw := get_viewport().get_visible_rect().size.x
	var left := _block.position.x / vw
	_wipe_mat.set_shader_parameter(&"block", Vector2(left, left + _block.size.x / vw))


func _layout() -> void:
	var h := get_viewport().get_visible_rect().size.y
	# Barlow's cap height is about 0.7 of its font size.
	var title_px := int(round(h * title_size / 0.7))
	var coords_px := int(round(title_px * coords_scale))
	_style(_title, _SEMIBOLD, title_px)
	_style(_coords, _REGULAR, coords_px)
	_title.position = Vector2.ZERO
	_title.reset_size()
	_coords.reset_size()
	_coords.position = Vector2(title_px * 0.04, _title.size.y - title_px * 0.12)
	_block.size = Vector2(maxf(_title.size.x, _coords.size.x), _coords.position.y + _coords.size.y)


func _block_origin() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	return Vector2(vp.y * margin_left, vp.y * (1.0 - margin_bottom) - _block.size.y)


func _style(l: Label, font: Font, px: int) -> void:
	var f := FontVariation.new()
	f.base_font = font
	f.spacing_glyph = int(round(px * spacing))
	l.add_theme_font_override(&"font", f)
	l.add_theme_font_size_override(&"font_size", px)
	l.add_theme_color_override(&"font_color", Color.WHITE)


static func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s
