class_name JetpackLook
extends Node

# The Jetpack look (Airframe Ultra / PS1), built from scratch: nothing from cel, RETRO or the
# composite. See docs/specs/jetpack-look.md.
#
# Put it in a scene AFTER the pilot (so his meshes exist when this is ready). It:
# - gives every MeshInstance3D under `world_root` a world-projected PS1 material carrying its own
#   material's colour (texture pass 2: colour pixels, no textures, no tags),
# - gives the pilot's skinned body rest-pose-projected PS1 materials (his mesh is rebuilt once
#   with the rest positions/normals in CUSTOM0/CUSTOM1 so the pixels ride the body),
# - draws the screen filter on a CanvasLayer below the HUD,
# - hardens directional shadows while it lives (restored on exit),
# - answers the QA keys:
#   5 whole look   6 vertex snap   7 affine   8 texel density   9 screen filter

const SURFACE_SHADER := preload("res://shaders/ps1/ps1_surface.gdshader")
const SCREEN_SHADER := preload("res://shaders/ps1/ps1_screen.gdshader")
const SHADOW_QUALITY_SETTING := "rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"

@export var world_root: Node3D
@export var pilot: Node3D
@export var sun: DirectionalLight3D

@export_group("State")
## Off = every mesh's own material back, no filter.
@export var look_enabled: bool = true
@export var snap_enabled: bool = true
@export var affine_enabled: bool = false
@export var filter_enabled: bool = true
@export var show_label: bool = true

@export_group("Surface")
## Project rule: 16 texels per metre. 8 flips to `alt_texels_per_metre`.
@export var texels_per_metre: float = 16.0
@export var alt_texels_per_metre: float = 8.0
## Stepped brightness levels per surface, from shade_dark to shade_light times its colour.
@export_range(1, 8, 1) var shade_count: int = 4
@export_range(0.5, 1.0, 0.01) var shade_dark: float = 0.85
@export_range(1.0, 1.5, 0.01) var shade_light: float = 1.10
## Texels across one clump of shared shade.
@export_range(1.0, 8.0, 0.5) var clump_texels: float = 3.0
## Share of texels nudged one shade off their clump.
@export_range(0.0, 0.5, 0.01) var jitter_chance: float = 0.12
## Snap grid rows over the screen height (the PS1's 240).
@export var snap_lines: float = 240.0

@export_group("Screen Filter")
@export_range(0.0, 1.0, 0.01) var stripe_strength: float = 0.14
@export_range(2.0, 8.0, 0.5) var stripe_period: float = 3.0
@export_range(0.0, 6.0, 0.1) var fringe_px: float = 1.0
@export_range(0.0, 4.0, 0.1) var fringe_edge_boost: float = 1.5
@export_range(0.0, 2.5, 0.01) var saturation: float = 1.2
@export_range(0.5, 2.0, 0.01) var contrast: float = 1.12
@export var lift: Vector3 = Vector3(0.0, 0.0, 0.02)
@export var gain: Vector3 = Vector3(1.02, 1.0, 1.04)

var _base_texels: float
## [mesh, surface, original override Material, ps1 ShaderMaterial]
var _world_surfaces: Array = []
var _pilot_surfaces: Array = []
## [colour, vertex colour flag] -> shared world ShaderMaterial.
var _world_cache: Dictionary = {}
var _ps1_materials: Array[ShaderMaterial] = []
var _filter_layer: CanvasLayer
var _filter_rect: ColorRect
var _filter_material: ShaderMaterial
var _label: Label

func _ready() -> void:
	_base_texels = texels_per_metre
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	_build_filter()
	_build_label()
	if world_root != null:
		_collect_world(world_root)
	if pilot != null:
		_collect_pilot(pilot)
	apply()

func _exit_tree() -> void:
	var quality: int = ProjectSettings.get_setting(SHADOW_QUALITY_SETTING, 2)
	RenderingServer.directional_soft_shadow_filter_set_quality(quality as RenderingServer.ShadowQuality)

func _process(_delta: float) -> void:
	if sun != null:
		var towards := sun.global_transform.basis.z.normalized()
		for m in _ps1_materials:
			m.set_shader_parameter(&"sun_dir", towards)

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_5: look_enabled = not look_enabled
		KEY_6: snap_enabled = not snap_enabled
		KEY_7: affine_enabled = not affine_enabled
		KEY_8:
			texels_per_metre = alt_texels_per_metre if is_equal_approx(texels_per_metre, _base_texels) \
				else _base_texels
		KEY_9: filter_enabled = not filter_enabled
		_: return
	apply()
	get_viewport().set_input_as_handled()

## Pushes the current state into every material, the filter and the label.
func apply() -> void:
	for m in _ps1_materials:
		m.set_shader_parameter(&"texels_per_metre", texels_per_metre)
		m.set_shader_parameter(&"shade_count", float(shade_count))
		m.set_shader_parameter(&"shade_dark", shade_dark)
		m.set_shader_parameter(&"shade_light", shade_light)
		m.set_shader_parameter(&"clump_texels", clump_texels)
		m.set_shader_parameter(&"jitter_chance", jitter_chance)
		m.set_shader_parameter(&"snap_enabled", snap_enabled)
		m.set_shader_parameter(&"snap_lines", snap_lines)
		m.set_shader_parameter(&"affine_enabled", affine_enabled)
	for list: Array in [_world_surfaces, _pilot_surfaces]:
		for s: Array in list:
			(s[0] as MeshInstance3D).set_surface_override_material(s[1], s[3] if look_enabled else s[2])
	_update_filter()
	if sun != null:
		_process(0.0)
	_update_label()

func is_world_swapped() -> bool:
	return _swapped(_world_surfaces)

func is_pilot_swapped() -> bool:
	return _swapped(_pilot_surfaces)

static func _swapped(list: Array) -> bool:
	return not list.is_empty() and \
		(list[0][0] as MeshInstance3D).get_surface_override_material(list[0][1]) == list[0][3]

func filter_visible() -> bool:
	return _filter_layer != null and _filter_layer.visible

# -- materials ------------------------------------------------------------------------------

## A PS1 material wearing `source`'s colour. mapping: 0 world, 1 object, 2 rest pose.
func _new_ps1(source: Material, mapping: int, scale: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter(&"mapping", mapping)
	m.set_shader_parameter(&"object_scale", scale)
	var std := source as BaseMaterial3D
	if std != null:
		m.set_shader_parameter(&"albedo_color", std.albedo_color)
		m.set_shader_parameter(&"use_vertex_color", std.vertex_color_use_as_albedo)
	_ps1_materials.append(m)
	return m

static func _surface_material(mi: MeshInstance3D, i: int) -> Material:
	var m := mi.get_surface_override_material(i)
	if m == null:
		m = mi.material_override
	if m == null:
		m = mi.mesh.surface_get_material(i)
	return m

func _collect_world(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var source := _surface_material(mi, i)
			var std := source as BaseMaterial3D
			var key := [std.albedo_color, std.vertex_color_use_as_albedo] if std != null \
				else [Color.WHITE, false]
			if not _world_cache.has(key):
				_world_cache[key] = _new_ps1(source, 0, 1.0)
			_world_surfaces.append([mi, i, mi.get_surface_override_material(i), _world_cache[key]])

func _collect_pilot(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		# His skinned body only: not held items, hats or effects hung on bones.
		if mi.mesh == null or not (mi.get_parent() is Skeleton3D):
			continue
		var skel := mi.get_parent() as Skeleton3D
		var baked := bake_rest_pose(mi)
		var scale := _rest_scale(mi, skel)
		for i in mi.mesh.get_surface_count():
			var ps1 := _new_ps1(_surface_material(mi, i), 2 if baked else 1, scale)
			_pilot_surfaces.append([mi, i, mi.get_surface_override_material(i), ps1])

## Rebuilds a skinned mesh with its mesh-space rest positions in CUSTOM0 and rest normals in
## CUSTOM1 (RGB float), so the pixel grid can be laid on the body's rest shape and ride it
## through every animation. Surface overrides are kept. False if the mesh can't be rebuilt.
static func bake_rest_pose(mi: MeshInstance3D) -> bool:
	var src := mi.mesh as ArrayMesh
	if src == null:
		return false
	var out := ArrayMesh.new()
	out.resource_name = src.resource_name
	out.blend_shape_mode = src.blend_shape_mode
	for b in src.get_blend_shape_count():
		out.add_blend_shape(src.get_blend_shape_name(b))
	var custom := (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null \
			else PackedVector3Array()
		var pos := PackedFloat32Array()
		var nrm := PackedFloat32Array()
		pos.resize(verts.size() * 3)
		nrm.resize(verts.size() * 3)
		for v in verts.size():
			var n := norms[v] if v < norms.size() else Vector3.UP
			for k in 3:
				pos[v * 3 + k] = verts[v][k]
				nrm[v * 3 + k] = n[k]
		arrays[Mesh.ARRAY_CUSTOM0] = pos
		arrays[Mesh.ARRAY_CUSTOM1] = nrm
		var flags := custom | (src.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays,
			src.surface_get_blend_shape_arrays(s), {}, flags)
		out.surface_set_material(s, src.surface_get_material(s))
		out.surface_set_name(s, src.surface_get_name(s))
	var overrides: Array[Material] = []
	for s in src.get_surface_count():
		overrides.append(mi.get_surface_override_material(s))
	mi.mesh = out
	for s in overrides.size():
		mi.set_surface_override_material(s, overrides[s])
	return true

## Metres per mesh unit of a skinned mesh at rest (an FBX body in centimetres gives ~0.01).
static func _rest_scale(mi: MeshInstance3D, skel: Skeleton3D) -> float:
	var t := mi.global_transform
	if mi.skin != null and mi.skin.get_bind_count() > 0:
		var bone := mi.skin.get_bind_bone(0)
		if bone < 0:
			bone = skel.find_bone(mi.skin.get_bind_name(0))
		if bone >= 0:
			t = skel.global_transform * skel.get_bone_global_rest(bone) * mi.skin.get_bind_pose(0)
	var sc := t.basis.get_scale()
	return (absf(sc.x) + absf(sc.y) + absf(sc.z)) / 3.0

# -- screen filter + label ------------------------------------------------------------------

func _build_filter() -> void:
	_filter_layer = CanvasLayer.new()
	_filter_layer.name = "Ps1Filter"
	# Below the HUD and menus (layer 0 and up): they stay clean.
	_filter_layer.layer = -1
	add_child(_filter_layer)
	_filter_rect = ColorRect.new()
	_filter_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter_material = ShaderMaterial.new()
	_filter_material.shader = SCREEN_SHADER
	_filter_rect.material = _filter_material
	_filter_layer.add_child(_filter_rect)

func _update_filter() -> void:
	_filter_layer.visible = look_enabled and filter_enabled
	_filter_material.set_shader_parameter(&"stripe_strength", stripe_strength)
	_filter_material.set_shader_parameter(&"stripe_period", stripe_period)
	_filter_material.set_shader_parameter(&"fringe_px", fringe_px)
	_filter_material.set_shader_parameter(&"fringe_edge_boost", fringe_edge_boost)
	_filter_material.set_shader_parameter(&"saturation", saturation)
	_filter_material.set_shader_parameter(&"contrast", contrast)
	_filter_material.set_shader_parameter(&"lift", lift)
	_filter_material.set_shader_parameter(&"gain", gain)

func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Ps1Label"
	layer.layer = 50
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override(&"font_size", 15)
	_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_label.add_theme_constant_override(&"shadow_offset_y", 1)
	layer.add_child(_label)

func _update_label() -> void:
	_label.visible = show_label
	var on := func(b: bool) -> String: return "ON" if b else "off"
	_label.text = "JETPACK LOOK\n5 look %s\n6 vertex snap %s\n7 affine %s\n8 texels %d/m\n9 filter %s" % [
		on.call(look_enabled), on.call(snap_enabled), on.call(affine_enabled),
		int(texels_per_metre), on.call(filter_enabled)]
