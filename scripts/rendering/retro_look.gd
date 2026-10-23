class_name RetroLook
extends PixelLook

# The RETRO look: a 90s anime cel. See docs/specs/retro-look.md.
#
# The third position of the LOOK switch. It is PixelLook's machinery with a different twin: walk
# every cel-base slot, record it, swap in a twin, restore exactly, swap nodes as they arrive. The
# inherited `pixel` flag means "this look is on".
#
# The twin is the same cel material (so the two-tone light is the real cel light) with flat fills,
# no specular or fresnel, and its ink passes coloured from the fill under them at a thinner width.
# The WorldEnvironment gets the video pass (resources/retro_post.tres) as its compositor.
#
# Pass 2 (docs/specs/retro-look-pass-2.md) splits the frame the way a 90s anime is made: CELS
# (anything skinned or under a moving body) keep the flat tones and ink; everything else is the
# painted BACKGROUND - no ink, a soft light/shadow gradient, brush grain, a little darker and cooler.
# The ground subtrees named in floor_paths also get panel lines. Each body gets a
# RetroContactShadow and the clouds are painted shapes.
#
# Pass 3 (docs/specs/retro-look-pass-3.md): the palette is CEL's. Same environment (Filmic, full
# ambient, CEL fog, no grade), same sky colours, neutral shadows, no background tint, CEL's floor.
#
# Gameplay only: nothing in a cutscene scene has one of these. Settings switches it; the I key
# lives on PixelLook.

const OUTLINE_SHADER := preload("res://shaders/cel/outline.gdshader")
const CREASE_SHADER := preload("res://shaders/cel/crease.gdshader")
const VIDEO_PASS := preload("res://resources/retro_post.tres")

@export_group("Ink")
## Visible line width in pixels at 1080p, scaled with the resolution (CEL draws 2 px at any size).
@export_range(0.5, 6.0, 0.25) var ink_width := 2.5
## Line brightness next to its fill, sRGB terms.
@export_range(0.0, 1.0, 0.01) var ink_value := 0.25
## How far the line moves toward red-brown.
@export_range(0.0, 1.0, 0.01) var ink_warmth := 0.1

@export_group("Paint")
## Cels only: shifts the light/shadow step so more of each form sits in shadow (negative = more).
@export_range(-0.5, 0.5, 0.01) var cel_shade_bias := -0.25

@export_group("Background")
## Multiplies the background fill (white = the fill's own colour).
@export var bg_tint := Color(1, 1, 1)
## Width of the soft painted light/shadow gradient (0 = the hard cel step).
@export_range(0.0, 0.5, 0.01) var bg_soft := 0.12
## Background shadow brightness (cels and CEL use 0.45).
@export_range(0.0, 1.0, 0.01) var bg_shadow_tone := 0.45
## World-space brush grain strength.
@export_range(0.0, 0.3, 0.005) var bg_brush := 0.06

@export_group("Floor")
## Ground subtrees (relative to this node) that get panel lines.
@export var floor_paths: Array[NodePath] = []
## Panel line colour; alpha is its strength. Black at a low alpha = a darker shade of the floor.
@export var floor_line := Color(0, 0, 0, 0.3)
@export var floor_panel_size := 4.0

@export_group("Contact shadow")
@export var contact_shadows := true
@export var contact_tint := Color(0.6, 0.6, 0.6)

@export_group("Sky")
## The painted clouds' underside; their tops keep the CEL sky's cloud colour.
@export var cloud_shade := Color(0.5, 0.5, 0.5)

var _cel_compositor: Compositor
## cel material -> its background twin, and its floor twin.
var _bg_twins: Dictionary = {}
var _floor_twins: Dictionary = {}
var _shadows: Array[RetroContactShadow] = []


func _ready() -> void:
	add_to_group(&"retro_look")
	var settings := get_node_or_null(^"/root/Settings")
	if settings and settings.look == "retro":
		apply_look.call_deferred(true)


func apply_look(on: bool) -> void:
	var was := pixel
	super(on)
	if pixel != was:
		_apply_contact_shadows(pixel)


## Cel or painted background, by what the node hangs off.
func twin_for(node: GeometryInstance3D, cel: ShaderMaterial) -> ShaderMaterial:
	if is_cel_node(node):
		return twin_of(cel)
	return background_twin(cel, is_floor_node(node))


## A cel: skinned, or riding something that moves.
static func is_cel_node(node: Node) -> bool:
	var n := node
	while n != null:
		if n is Skeleton3D or n is CharacterBody3D or n is RigidBody3D or n is AnimatableBody3D:
			return true
		n = n.get_parent()
	return false


func is_floor_node(node: Node) -> bool:
	for path in floor_paths:
		var root := get_node_or_null(path)
		if root != null and (root == node or root.is_ancestor_of(node)):
			return true
	return false


## The retro cel twin for a cel material.
func twin_of(cel: ShaderMaterial) -> ShaderMaterial:
	if _twins.has(cel):
		return _twins[cel]
	var twin := _flat(cel)
	twin.set_shader_parameter(&"shade_bias", cel_shade_bias)
	twin.next_pass = ink_chain(cel.next_pass, cel)
	_twins[cel] = twin
	return twin


## The painted background twin: no ink, soft light and brush grain; on the floor, panel lines too.
func background_twin(cel: ShaderMaterial, is_floor: bool) -> ShaderMaterial:
	var cache := _floor_twins if is_floor else _bg_twins
	if cache.has(cel):
		return cache[cel]
	var twin := _flat(cel)
	twin.set_shader_parameter(&"paint_soft", bg_soft)
	twin.set_shader_parameter(&"shadow_tone", bg_shadow_tone)
	twin.set_shader_parameter(&"bg_paint", Color(bg_tint.r, bg_tint.g, bg_tint.b, bg_brush))
	if is_floor:
		twin.set_shader_parameter(&"floor_panel", floor_line)
		twin.set_shader_parameter(&"floor_panel_size", floor_panel_size)
	twin.next_pass = strip_ink(cel.next_pass)
	cache[cel] = twin
	return twin


## What every RETRO twin shares: flat fills, no specular or fresnel.
func _flat(cel: ShaderMaterial) -> ShaderMaterial:
	var twin := cel.duplicate() as ShaderMaterial
	twin.set_shader_parameter(&"flat_fill", true)
	for param: StringName in [&"specular", &"fresnel"]:
		var value: Variant = cel.get_shader_parameter(param)
		var c: Color = value if value is Color else Color(0, 0, 0)
		c.a = 0.0
		twin.set_shader_parameter(param, c)
	return twin


## The pass chain without its outline and crease passes; anything else is kept.
func strip_ink(pass_mat: Material) -> Material:
	var sm := pass_mat as ShaderMaterial
	if sm == null:
		return pass_mat
	if sm.shader == OUTLINE_SHADER or sm.shader == CREASE_SHADER:
		return strip_ink(sm.next_pass)
	var kept := sm.duplicate() as ShaderMaterial
	kept.next_pass = strip_ink(sm.next_pass)
	return kept


## A copy of an ink pass chain (crease, outline) with every pass coloured from `fill`. Anything
## else in the chain is kept as it is.
func ink_chain(pass_mat: Material, fill: ShaderMaterial) -> Material:
	var sm := pass_mat as ShaderMaterial
	if sm == null:
		return pass_mat
	if sm.shader != OUTLINE_SHADER and sm.shader != CREASE_SHADER:
		return sm
	var ink := sm.duplicate() as ShaderMaterial
	ink.set_shader_parameter(&"ink_from_fill", true)
	ink.set_shader_parameter(&"ink_value", ink_value)
	ink.set_shader_parameter(&"ink_warmth", ink_warmth)
	var color: Variant = fill.get_shader_parameter(&"color")
	ink.set_shader_parameter(&"ink_fill_color", color if color != null else Color(1, 1, 1))
	var texture: Variant = fill.get_shader_parameter(&"base_texture")
	if texture != null:
		ink.set_shader_parameter(&"ink_fill_texture", texture)
	for pair: Array in [[&"uv_scale", &"ink_uv_scale"], [&"uv_offset", &"ink_uv_offset"]]:
		var value: Variant = fill.get_shader_parameter(pair[0])
		if value != null:
			ink.set_shader_parameter(pair[1], value)
	if sm.shader == OUTLINE_SHADER:
		ink.set_shader_parameter(&"ink_width", ink_width)
	ink.next_pass = ink_chain(sm.next_pass, fill)
	return ink


## The environment swap is PixelLook's; the video pass rides on the same WorldEnvironment.
func _apply_environment(on: bool) -> void:
	# Before super: turning off forgets _env_node.
	if not on and _env_node != null and is_instance_valid(_env_node):
		_env_node.compositor = _cel_compositor
		_cel_compositor = null
	super(on)
	if on and _env_node != null:
		_cel_compositor = _env_node.compositor
		var compositor := Compositor.new()
		compositor.compositor_effects = [VIDEO_PASS.duplicate()]
		_env_node.compositor = compositor


## A copy of `cel_env` with only the clouds painted: CEL's light, fog and colours.
func pixel_environment(cel_env: Environment) -> Environment:
	var env := cel_env.duplicate() as Environment
	if env.sky != null and env.sky.sky_material is ShaderMaterial:
		env.sky = env.sky.duplicate() as Sky
		env.sky.sky_material = painted_sky(env.sky.sky_material)
	return env


## A copy of the cel sky material with painted two-tone clouds in its own colours. Only the
## parameters the sky shader has are set (cel/vfx/sky.gdshader).
func painted_sky(cel_sky: ShaderMaterial) -> ShaderMaterial:
	var sky := cel_sky.duplicate() as ShaderMaterial
	var names := {}
	for u in sky.shader.get_shader_uniform_list():
		names[StringName(u.name)] = true
	var values := {&"clouds_shade_color": cloud_shade, &"clouds_paint": 1.0}
	for key: StringName in values:
		if names.has(key):
			sky.set_shader_parameter(key, values[key])
	return sky


# --- contact shadows --------------------------------------------------------------

func _apply_contact_shadows(on: bool) -> void:
	for s in _shadows:
		if is_instance_valid(s):
			s.queue_free()
	_shadows.clear()
	if not on or not contact_shadows:
		return
	for body in _bodies(get_parent()):
		var s := RetroContactShadow.for_body(body, contact_tint)
		add_child(s)
		_shadows.append(s)


static func _bodies(root: Node) -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	if root == null:
		return out
	if root is CharacterBody3D or root is AnimatableBody3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_bodies(child))
	return out


func _input(_event: InputEvent) -> void:
	pass
