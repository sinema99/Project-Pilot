@tool
class_name HoloPanel
extends Node3D

# One cockpit hologram panel: a HoloDisplay drawn into its own SubViewport, shown on a quad (or a
# curved strip) of translucent green glass facing local +Z. Built at load, also in the editor.
# See docs/specs/cutscene-cockpit.md, "Atmosphere pass".

const SHADER := preload("res://shaders/cockpit/holo_panel.gdshader")
## The glass's opacity at full fade (the shader's default).
const OPACITY := 0.92

@export var kind := HoloDisplay.Kind.HORIZON:
	set(value):
		kind = value
		_rebuild()
## Metres, width x height. For a bent strip the width runs along the curve.
@export var panel_size := Vector2(0.3, 0.2):
	set(value):
		panel_size = value
		_rebuild()
## 0 = flat. Otherwise the panel curves round toward its viewer by this many degrees, end to end.
@export_range(0.0, 120.0) var bend_degrees := 0.0:
	set(value):
		bend_degrees = value
		_rebuild()
## Drawn resolution.
@export var pixels_per_metre := 1200.0

## 0 = folded to a horizontal line, 1 = full height: the pop-open.
var open_amount := 1.0
## 1 = fully shown, 0 = gone.
var fade := 1.0
## Glitch on top of the shot's (the warning tears as it is flicked away).
var extra_glitch := 0.0
## Stretches the glass sideways (the warning on its way out).
var stretch := 1.0

var display: HoloDisplay
var mesh_instance: MeshInstance3D
var _viewport: SubViewport
var _material: ShaderMaterial


func _ready() -> void:
	_rebuild()


## Feeds the shot state to the drawing and the glass.
func set_state(t: float, flash: float, glitch: float, roll: float, pitch: float) -> void:
	if display == null:
		return
	display.t = t
	display.flash = flash
	display.roll = roll
	display.pitch = pitch
	display.queue_redraw()
	_material.set_shader_parameter(&"glitch", maxf(glitch, extra_glitch))
	_material.set_shader_parameter(&"opacity", OPACITY * fade)
	mesh_instance.scale = Vector3(stretch, maxf(open_amount, 0.02), 1.0)


## The shot time the ship answers the push: the readouts climb from then.
func set_surge(time: float) -> void:
	if display != null:
		display.surge_from = time


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta(&"generated"):
			remove_child(c)
			c.queue_free()
	var px := Vector2i(maxi(int(panel_size.x * pixels_per_metre), 8), maxi(int(panel_size.y * pixels_per_metre), 8))
	_viewport = SubViewport.new()
	_viewport.name = "Screen"
	_viewport.size = px
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.set_meta(&"generated", true)
	display = HoloDisplay.new()
	display.kind = kind
	display.size = Vector2(px)
	_viewport.add_child(display)
	add_child(_viewport)

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"screen_tex", _viewport.get_texture())
	_material.set_shader_parameter(&"seed", float(kind) * 3.7 + 1.0)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Glass"
	mesh_instance.mesh = _glass_mesh()
	mesh_instance.material_override = _material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.set_meta(&"generated", true)
	add_child(mesh_instance)


func _glass_mesh() -> Mesh:
	if bend_degrees <= 0.01:
		var q := QuadMesh.new()
		q.size = panel_size
		return q
	# A cylinder slice, its middle at the origin and its ends curling toward +Z.
	var span := deg_to_rad(bend_degrees)
	var radius := panel_size.x / span
	var segs := 24
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in segs + 1:
		var u := float(i) / segs
		var a := (u - 0.5) * span
		var p := Vector3(radius * sin(a), 0.0, radius * (1.0 - cos(a)))
		var n := Vector3(-sin(a), 0.0, cos(a))
		for row in 2:
			verts.append(p + Vector3(0.0, panel_size.y * (0.5 - row), 0.0))
			uvs.append(Vector2(u, row))
			normals.append(n)
	for i in segs:
		var b := i * 2
		idx.append_array([b, b + 1, b + 2, b + 2, b + 1, b + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
