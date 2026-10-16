@tool
class_name CockpitSnow
extends MeshInstance3D

# Snow on the cockpit's screen sphere (shaders/cockpit/snow_storm.gdshader): an inward-facing sphere
# just outside the wireframe, like ReentryFire. Holds no time of its own: CockpitStormDriver sets
# every value from the shot time, so a frame is the same however it was reached. See
# docs/specs/cutscene-cockpit-storm.md.

const SHADER := preload("res://shaders/cockpit/snow_storm.gdshader")

## A little outside the wireframe (4 m), so the wire lines sit in front of the snow.
@export var radius := 4.05:
	set(value):
		radius = value
		_rebuild()

var _material: ShaderMaterial


func _ready() -> void:
	_rebuild()


## The shot state, from CockpitStormDriver.
func set_state(t: float, storm: float, travel: float, source: Vector3, gust: float, flash: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"shot_time", t)
	_material.set_shader_parameter(&"storm", storm)
	_material.set_shader_parameter(&"travel", travel)
	_material.set_shader_parameter(&"source_dir", source)
	_material.set_shader_parameter(&"gust", gust)
	_material.set_shader_parameter(&"flash", flash)


## The storm ramp's start and end (StormBeats), so each skimmer's life is decided by the storm at
## its birth.
func set_ramp(start: float, end: float) -> void:
	if _material != null:
		_material.set_shader_parameter(&"ramp", Vector2(start, end))


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 96
	m.rings = 48
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	m.material = _material
	mesh = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
