## What it looks like when pilot is hit: his mesh flashes white then red, sparks fly from the
## contact point, the camera shakes and the screen edge pulses red. Feedback only - no health, no
## knockback, no stun. Built by pilot9.gd::_setup_reflect(). See docs/specs/firing-range.md.
extends Node

const _ApplyStylized := preload("res://scripts/rendering/apply_stylized.gd")

const FLASH_WHITE := 0.07
const FLASH_FADE := 0.18
const SHAKE_TIME := 0.25
const SHAKE_AMOUNT := 0.06
const VIGNETTE_TIME := 0.35
const RED := Color(1.0, 0.12, 0.08)

const _VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float edge = smoothstep(0.25, 0.75, length(d) * 1.4);
	COLOR = vec4(0.9, 0.05, 0.03, edge * strength);
}
"""

## Camera offset (x = h_offset, y = v_offset) the pilot adds to his sway. Zero with CAMERA MOTION off.
var shake_offset := Vector2.ZERO

var _pilot: Node = null
var _flash_mat: StandardMaterial3D = null
var _flash_age := INF
var _shake_age := INF
var _vignette_age := INF
var _vignette_mat: ShaderMaterial = null
var _rect: ColorRect = null
var _rng := RandomNumberGenerator.new()


func setup(pilot: Node) -> void:
	_pilot = pilot
	_rng.randomize()
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.render_priority = 5
	var layer := CanvasLayer.new()
	layer.name = &"HitVignette"
	layer.layer = 20
	add_child(layer)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = _VIGNETTE_SHADER
	_vignette_mat.shader = sh
	_rect.material = _vignette_mat
	_rect.visible = false
	layer.add_child(_rect)


## A bolt hit at `point`. Sparks are MOVEMENT EFFECTS, the shake CAMERA MOTION; the flash and the
## vignette are what tell you you were hit, so they always play.
func hit(point: Vector3) -> void:
	_flash_age = 0.0
	_vignette_age = 0.0
	_shake_age = 0.0
	_apply_flash(true)
	if Settings.movement_effects and _pilot != null and _pilot.has_method(&"spark_burst"):
		var out: Vector3 = (_pilot.global_position + Vector3.UP * 1.2 - point)
		out = out.normalized() if out.length() > 0.01 else Vector3.UP
		_pilot.spark_burst(point, out, 18, 6.0, RED)


func _process(delta: float) -> void:
	if _flash_age < INF:
		_flash_age += delta
		if _flash_age >= FLASH_WHITE + FLASH_FADE:
			_flash_age = INF
			_apply_flash(false)
		else:
			_flash_mat.albedo_color = flash_color(_flash_age)
	if _vignette_age < INF:
		_vignette_age += delta
		var s := vignette_strength(_vignette_age)
		_rect.visible = s > 0.0
		_vignette_mat.set_shader_parameter(&"strength", s)
		if s <= 0.0:
			_vignette_age = INF
	if _shake_age < INF and Settings.camera_motion:
		_shake_age += delta
		var k := clampf(1.0 - _shake_age / SHAKE_TIME, 0.0, 1.0)
		shake_offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) \
			* SHAKE_AMOUNT * k
		if k <= 0.0:
			_shake_age = INF
			shake_offset = Vector2.ZERO
	else:
		shake_offset = Vector2.ZERO


## Puts the flash on every pilot mesh as the overlay, or hands the overlay back to the rim light.
func _apply_flash(on: bool) -> void:
	if _pilot == null or _pilot.character == null:
		return
	if not on:
		_pilot._apply_rim_light()
		return
	var meshes: Array[MeshInstance3D] = []
	_ApplyStylized.collect_meshes(_pilot.character, meshes)
	for mi in meshes:
		if _pilot.item_holder != null and _pilot.item_holder.owns(mi):
			continue
		mi.material_overlay = _flash_mat
	_flash_mat.albedo_color = flash_color(0.0)


# --- pure curves, static so tests can check them ----------------------------------------------

## White for FLASH_WHITE seconds, then red fading to nothing over FLASH_FADE.
static func flash_color(age: float) -> Color:
	if age < FLASH_WHITE:
		return Color(1, 1, 1, 0.75)
	var k := clampf(1.0 - (age - FLASH_WHITE) / FLASH_FADE, 0.0, 1.0)
	return Color(RED.r, RED.g, RED.b, 0.6 * k)


## Red edge strength `age` seconds after a hit: a jump, then a fade.
static func vignette_strength(age: float) -> float:
	return clampf(1.0 - age / VIGNETTE_TIME, 0.0, 1.0) * 0.7
