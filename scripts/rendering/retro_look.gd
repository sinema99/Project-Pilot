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
# COMPOSITE (docs/specs/live-composite.md) is this look with the cutscene composite on top: a
# DepthComposite placed on the map's sun every frame, then resources/composite_post.tres instead of
# the video pass. The Composite exports are the map's values; override them on a map's node.
#
# Gameplay only: nothing in a cutscene scene has one of these. Settings switches it; the I key
# lives on PixelLook.

const OUTLINE_SHADER := preload("res://shaders/cel/outline.gdshader")
const CREASE_SHADER := preload("res://shaders/cel/crease.gdshader")
const VIDEO_PASS := preload("res://resources/retro_post.tres")
const COMPOSITE_PASS := preload("res://resources/composite_post.tres")

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

@export_group("Composite")
## The near band: full dark up to the first distance, gone by the second (m).
@export var composite_near_end := 6.0
@export var composite_lit_start := 60.0
## Perceived brightness of the near band (the cutscenes use 0.28).
@export_range(0.0, 1.0, 0.01) var composite_near_value := 0.6
## The band's hue, and what it adds to the blacks. A dark map wants both near neutral, or it goes navy.
@export var composite_dark_tint := Color(0.72, 0.75, 0.92)
@export var composite_dark_lift := Color(0.011, 0.014, 0.03)
## HDR brightness and colourfulness that escape the band, so bolts, rails and dash effects stay lit.
@export var composite_keep := 2.5
@export var composite_keep_chroma := 0.75
## Haze: where it starts and is full (m), its colour, how much it replaces at full distance near the
## sun, and how much of that is left away from it.
@export var composite_haze_start := 60.0
@export var composite_haze_end := 500.0
@export var composite_haze_color := Color(0.8, 0.77, 0.86)
@export_range(0.0, 1.0, 0.01) var composite_haze_amount := 0.5
@export_range(0.0, 1.0, 0.01) var composite_haze_floor := 0.25
## The sun's glow on far pixels, and its size as a fraction of the screen height.
@export var composite_light_energy := 0.3
@export var composite_light_radius := 0.15
## How far past the screen edge the sun has faded out, in screens.
@export var composite_sun_margin := 0.35
## The far pixels wrap over the nearer ones: counted from the first distance, full by the second (m).
@export var composite_wrap_near := 150.0
@export var composite_wrap_far := 500.0
@export_range(0.0, 1.0, 0.01) var composite_wrap := 0.25

## Whether the composite is on top of this look.
var composite := false
var _cel_compositor: Compositor
var _video_compositor: Compositor
var _composite_compositor: Compositor
var _depth: DepthComposite
var _sun: DirectionalLight3D
## cel material -> its background twin, and its floor twin.
var _bg_twins: Dictionary = {}
var _floor_twins: Dictionary = {}
var _shadows: Array[RetroContactShadow] = []


func _ready() -> void:
	add_to_group(&"retro_look")
	# After the cameras, so the glow sits on this frame's view.
	process_priority = 100
	set_process(false)
	var settings := get_node_or_null(^"/root/Settings")
	if settings and settings.is_retro(settings.look):
		apply_look.call_deferred(true)
		apply_composite.call_deferred(settings.look == "composite")


func apply_look(on: bool) -> void:
	if not on:
		apply_composite(false)
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
		# A body can ask for a heavier line (the knight boss's ink_scale meta).
		ink.set_shader_parameter(&"ink_width", ink_width * float(sm.get_meta(&"ink_scale", 1.0)))
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
		_video_compositor = compositor


# --- composite --------------------------------------------------------------------

## Called by Settings when LOOK changes. Needs this look on: it swaps the look's own compositor.
func apply_composite(on: bool) -> void:
	if on == composite or (on and (not pixel or _env_node == null)):
		return
	composite = on
	set_process(on)
	if on:
		_sun = find_sun(get_parent())
		if _composite_compositor == null:
			_depth = DepthComposite.new()
			_composite_compositor = Compositor.new()
			_composite_compositor.compositor_effects = [_depth, COMPOSITE_PASS.duplicate()]
		configure_depth(_depth, _sun != null)
		_place_sun()
		_env_node.compositor = _composite_compositor
	elif _env_node != null and is_instance_valid(_env_node):
		_env_node.compositor = _video_compositor


## The map's values onto `depth`. With no sun there is no light and nothing bright to wrap.
func configure_depth(depth: DepthComposite, has_sun: bool) -> void:
	depth.near_end = composite_near_end
	depth.lit_start = composite_lit_start
	depth.near_value = composite_near_value
	depth.dark_tint = composite_dark_tint
	depth.dark_lift = composite_dark_lift
	depth.dark_keep = composite_keep
	depth.dark_keep_chroma = composite_keep_chroma
	depth.haze_start = composite_haze_start
	depth.haze_end = composite_haze_end
	depth.haze_color = composite_haze_color
	depth.haze_amount = composite_haze_amount
	depth.haze_floor = composite_haze_floor
	depth.light_radius = composite_light_radius
	depth.light_stretch = 1.0
	depth.light_energy = 0.0
	depth.wrap_near = composite_wrap_near
	depth.wrap_far = composite_wrap_far
	depth.wrap_strength = composite_wrap if has_sun else 0.0


## The first directional light under `node`, or null.
static func find_sun(node: Node) -> DirectionalLight3D:
	if node == null:
		return null
	if node is DirectionalLight3D:
		return node
	for child in node.get_children():
		var found := find_sun(child)
		if found:
			return found
	return null


## A direction as seen through a camera: x, y = screen UV, z = 0-1, full on screen and gone once
## `margin` screens past the edge or behind the camera. DepthComposite.screen_uv mirrors points
## behind the camera, which would put the sun in front of you with it at your back.
static func sun_view(camera_basis: Basis, sun_dir: Vector3, tan_v: float, aspect: float, margin: float) -> Vector3:
	var local := camera_basis.inverse() * sun_dir
	if local.z >= -0.01:
		return Vector3(-10.0, -10.0, 0.0)
	var depth := -local.z
	var uv := Vector2(0.5 + 0.5 * local.x / depth / (tan_v * aspect), 0.5 - 0.5 * local.y / depth / tan_v)
	uv = uv.clamp(Vector2(-10.0, -10.0), Vector2(10.0, 10.0))
	var past := maxf(maxf(absf(uv.x - 0.5), absf(uv.y - 0.5)) - 0.5, 0.0)
	return Vector3(uv.x, uv.y, 1.0 - smoothstep(0.0, maxf(margin, 1e-4), past))


func _process(_delta: float) -> void:
	_place_sun()


func _place_sun() -> void:
	var camera := get_viewport().get_camera_3d()
	if _sun == null or not is_instance_valid(_sun) or camera == null:
		return
	var size := get_viewport().get_visible_rect().size
	var view := sun_view(camera.get_global_transform_interpolated().basis.orthonormalized(),
			_sun.global_basis.z, tan(deg_to_rad(camera.fov) * 0.5), size.x / maxf(size.y, 1.0),
			composite_sun_margin)
	_depth.light_uv = Vector2(view.x, view.y)
	_depth.light_energy = composite_light_energy * view.z


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
