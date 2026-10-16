@tool
class_name WireSphere
extends MeshInstance3D

# The cockpit's screen as clear glass: only the edges of a UV sphere, drawn as thin light-grey
# lines, like Blender's wireframe view. Faces are not drawn at all. See
# docs/specs/cutscene-cockpit.md.

@export var radius := 4.0:
	set(value):
		radius = value
		_rebuild()
## Meridians round the pole (Blender's UV sphere "Segments").
@export_range(3, 128) var segments := 32:
	set(value):
		segments = value
		_rebuild()
## Bands from pole to pole (Blender's "Rings"); there is one line fewer than this between the poles.
@export_range(2, 64) var rings := 16:
	set(value):
		rings = value
		_rebuild()
@export var line_color := Color(0.78, 0.78, 0.78):
	set(value):
		line_color = value
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var verts := PackedVector3Array()
	# Parallels: rings - 1 circles between the poles.
	for k in range(1, rings):
		var lat := PI * 0.5 - PI * float(k) / rings
		for s in segments:
			verts.append(_point(lat, TAU * float(s) / segments))
			verts.append(_point(lat, TAU * float(s + 1) / segments))
	# Meridians: pole to pole, meeting in a fan at each pole.
	for s in segments:
		var lon := TAU * float(s) / segments
		for k in rings:
			verts.append(_point(PI * 0.5 - PI * float(k) / rings, lon))
			verts.append(_point(PI * 0.5 - PI * float(k + 1) / rings, lon))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = line_color
	mat.disable_fog = true
	m.surface_set_material(0, mat)
	mesh = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _point(lat: float, lon: float) -> Vector3:
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)) * radius
