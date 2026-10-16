class_name PixelWorld
extends CanvasLayer

# The pixel look: the 3D world rendered low-res and drawn back at an exact whole-number block
# size, with the UI left sharp on top. See docs/specs/pixel-world.md.
#
# Drop one into a scene and that scene is pixelated; it builds everything it needs in code.
# Nothing in the scene moves: WorldView *shares* the main World3D and its camera copies whichever
# camera the root viewport has current, every frame. The root viewport stops drawing 3D while
# this is on, but its cameras stay current, so get_viewport().get_camera_3d() everywhere else
# keeps working.
#
# Settings reach this through the pixel_world group (there is none on the main menu).
#
# QA keys, so the look can be A/B'd without leaving the game - each writes through Settings:
#   O   toggle OFF / the last block size
#   [   coarser (bigger blocks)     ]   finer (smaller blocks), through the PIXEL FILTER list
#   \   step COLOUR DEPTH  FULL -> 32 -> 16 -> 8 -> FULL

const WORLD_SHADER := preload("res://shaders/pixel_world.gdshader")
const COLOUR_SHADER := preload("res://shaders/colour_depth.gdshader")

## Render layer (1-based) drawn at full resolution over the pixel world. The hologram menu panel
## lives here.
const SHARP_LAYER := 20
const SHARP_MASK := 1 << (SHARP_LAYER - 1)

var _world_view: SubViewport
var _world_cam: Camera3D
var _sharp_view: SubViewport
var _sharp_cam: Camera3D
var _world_rect: ColorRect
var _sharp_rect: ColorRect
var _colour_rect: ColorRect
var _world_mat: ShaderMaterial
var _sharp_mat: ShaderMaterial
var _colour_mat: ShaderMaterial

## Window pixels per block; 0 is OFF.
var block := 0
var colour_steps := 0
## Rendered texels per block side; each block is their average. 1 is a plain low-res render.
var supersample := 1
## The block size `O` turns back on to.
var _last_block := 3
## Whoever has asked for the sharp layer to render (the hologram, while it is open).
var _sharp_requests: Dictionary = {}


func _init() -> void:
	layer = -100
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After every camera rig, so the copy is of this frame's camera, not last frame's.
	process_priority = 10000


func _ready() -> void:
	add_to_group(&"pixel_world")
	var root := get_viewport()

	_world_view = _make_view(&"WorldView", root)
	_world_cam = _make_camera(_world_view)
	_sharp_view = _make_view(&"SharpView", root)
	_sharp_view.transparent_bg = true
	_sharp_cam = _make_camera(_sharp_view)

	_world_mat = _make_material(WORLD_SHADER)
	_world_mat.set_shader_parameter(&"view_tex", _world_view.get_texture())
	_world_rect = _make_rect(&"World", _world_mat)
	_sharp_mat = _make_material(WORLD_SHADER)
	_sharp_mat.set_shader_parameter(&"view_tex", _sharp_view.get_texture())
	_sharp_mat.set_shader_parameter(&"block", 1)
	_sharp_mat.set_shader_parameter(&"opaque", false)
	_sharp_rect = _make_rect(&"Sharp", _sharp_mat)
	_colour_mat = _make_material(COLOUR_SHADER)
	_colour_rect = _make_rect(&"ColourOnly", _colour_mat)

	root.size_changed.connect(_resize)
	var settings := get_node_or_null(^"/root/Settings")
	if settings:
		apply_settings(
			settings.effective_pixel_size(settings.pixel_size, settings.pixel_look_size, settings.look),
			settings.colour_levels(settings.look, settings.colour_depth),
			settings.pixel_supersample(settings.look))
	else:
		apply_settings(0, 0)


func _exit_tree() -> void:
	# The main menu has no PixelWorld: hand 3D back to the root and the shaders back to 1 px.
	var root := get_viewport()
	if root:
		root.disable_3d = false
	RenderingServer.global_shader_parameter_set(&"pixel_block", 1.0)


## Called by Settings through the pixel_world group, and on _ready().
func apply_settings(new_block: int, new_colour_steps: int, new_supersample := 1) -> void:
	block = maxi(new_block, 0)
	if block > 0:
		_last_block = block
	colour_steps = maxi(new_colour_steps, 0)
	supersample = maxi(new_supersample, 1)
	_apply()


## The hologram asks for its panel to be drawn sharp while it is open.
func set_sharp_needed(who: Object, needed: bool) -> void:
	var id := who.get_instance_id()
	if needed:
		_sharp_requests[id] = true
	else:
		_sharp_requests.erase(id)
	_apply()


func is_pixelated() -> bool:
	return block > 0


## The next block size from `current` in `sizes` (the PIXEL FILTER list, 0 = OFF first), `direction`
## +1 coarser, -1 finer. Stays put at either end and never steps to OFF; OFF stays OFF.
static func step_block(sizes: Array, current: int, direction: int) -> int:
	var i := sizes.find(current)
	if current <= 0 or i < 0:
		return current
	var target := clampi(i + direction, 0, sizes.size() - 1)
	return current if int(sizes[target]) <= 0 else int(sizes[target])


## The WorldView size for a render target of `render_size` window pixels at `block_size`: enough
## texels to cover it, the last column/row partly off screen when it does not divide evenly.
static func view_size(render_size: Vector2i, block_size: int) -> Vector2i:
	var b := maxi(block_size, 1)
	return Vector2i(maxi(ceili(float(render_size.x) / b), 1), maxi(ceili(float(render_size.y) / b), 1))


func _apply() -> void:
	if _world_view == null:
		return
	var on := block > 0
	var sharp := on and not _sharp_requests.is_empty()
	get_viewport().disable_3d = on
	RenderingServer.global_shader_parameter_set(&"pixel_block", float(block) if on else 1.0)

	_world_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_sharp_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if sharp else SubViewport.UPDATE_DISABLED
	_world_rect.visible = on
	_sharp_rect.visible = sharp
	_colour_rect.visible = not on and colour_steps > 1

	_world_mat.set_shader_parameter(&"block", maxi(block, 1))
	_world_mat.set_shader_parameter(&"color_steps", colour_steps)
	_world_mat.set_shader_parameter(&"supersample", supersample)
	_colour_mat.set_shader_parameter(&"color_steps", colour_steps)
	_resize()
	_sync_cameras()


func _resize() -> void:
	var render_size := _render_size()
	if block > 0:
		_world_view.size = view_size(render_size, block) * supersample
	_sharp_view.size = render_size


## The root's render target in window pixels: the letterboxed content area, not the canvas's
## 1920x1080 base size. Not get_texture().get_size(): on the root window in 4.6 that applies the
## stretch scale twice (3122x1756 for a 2448x1377 target).
func _render_size() -> Vector2i:
	var vp := get_viewport()
	var s := vp.get_visible_rect().size * vp.get_final_transform().get_scale()
	return Vector2i(maxi(roundi(s.x), 1), maxi(roundi(s.y), 1))


func _process(_delta: float) -> void:
	if block > 0:
		_sync_cameras()


func _sync_cameras() -> void:
	var source := get_viewport().get_camera_3d()
	if source == null:
		return
	_copy_camera(source, _world_cam)
	_world_cam.cull_mask = source.cull_mask & ~SHARP_MASK
	if _sharp_view.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		_copy_camera(source, _sharp_cam)
		_sharp_cam.cull_mask = source.cull_mask & SHARP_MASK


static func _copy_camera(from: Camera3D, to: Camera3D) -> void:
	to.global_transform = from.get_global_transform_interpolated()
	to.projection = from.projection
	to.fov = from.fov
	to.size = from.size
	to.frustum_offset = from.frustum_offset
	to.near = from.near
	to.far = from.far
	to.keep_aspect = from.keep_aspect
	to.h_offset = from.h_offset
	to.v_offset = from.v_offset
	to.environment = from.environment
	to.attributes = from.attributes
	to.compositor = from.compositor


# --- building ------------------------------------------------------------------

func _make_view(view_name: StringName, root: Viewport) -> SubViewport:
	var view := SubViewport.new()
	view.name = view_name
	view.world_3d = root.find_world_3d()
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	view.use_taa = false
	view.scaling_3d_scale = 1.0
	view.audio_listener_enable_3d = false
	view.handle_input_locally = false
	view.gui_disable_input = true
	# The root's own lighting setup, so omni/spot shadows look the same pixelated as not.
	view.positional_shadow_atlas_size = root.positional_shadow_atlas_size
	view.positional_shadow_atlas_16_bits = root.positional_shadow_atlas_16_bits
	for q in 4:
		view.set_positional_shadow_atlas_quadrant_subdiv(q, root.get_positional_shadow_atlas_quadrant_subdiv(q))
	view.mesh_lod_threshold = root.mesh_lod_threshold
	view.use_occlusion_culling = root.use_occlusion_culling
	view.use_debanding = root.use_debanding
	add_child(view)
	return view


func _make_camera(view: SubViewport) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = &"Mirror"
	# Copied from an already-interpolated transform every frame; interpolating again would lag.
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.add_child(cam)
	cam.current = true
	return cam


func _make_material(shader: Shader) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _make_rect(rect_name: StringName, mat: ShaderMaterial) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = rect_name
	rect.material = mat
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	add_child(rect)
	return rect


# --- QA keys -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var settings := get_node_or_null(^"/root/Settings")
	if settings == null:
		return
	match event.keycode:
		KEY_O:
			# The PIXEL look has no OFF.
			if settings.look != "pixel":
				settings.set_value(&"pixel_size", 0 if settings.pixel_size > 0 else _last_block)
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			# The active look's own size - see Settings.pixel_filter_key().
			var key: StringName = settings.pixel_filter_key(settings.look)
			var next := step_block(settings.values_of(key), block,
				1 if event.keycode == KEY_BRACKETLEFT else -1)
			if next != block:
				settings.set_value(key, next)
		KEY_BACKSLASH:
			var levels: Array = settings.values_of(&"colour_depth")
			var next := (levels.find(colour_steps) + 1) % levels.size()
			settings.set_value(&"colour_depth", levels[next])
