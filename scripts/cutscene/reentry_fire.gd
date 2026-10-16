@tool
class_name ReentryFire
extends MeshInstance3D

# Re-entry fire on the cockpit's screen sphere, plus the flicker it throws on the seat. Builds an
# inward-facing sphere with shaders/cockpit/reentry_fire.gdshader and drives one shared flicker
# value into both the shader and the warm fill light. See docs/specs/cutscene-cockpit.md.

const SHADER := preload("res://shaders/cockpit/reentry_fire.gdshader")
## The shader's room for dropped panels at once.
const MAX_DROPS := 8
## The wire screen's grid (WireSphere segments x rings): what a dropped "panel" is.
const GRID_SEGMENTS := 32
const GRID_RINGS := 16

## A little outside the wireframe (4 m), so the dimmed wire lines sit in front of the fire.
@export var radius := 4.05:
	set(value):
		radius = value
		_rebuild()
## The hot point the flames stream from, in sphere space: ahead of the seat (17 deg to his right,
## 17 deg low), off screen left. The flames meet again at its antipode, past the top right corner, so
## they run up-right along the seat and tear open on the wake.
@export var source_direction := Vector3(-0.3, -0.3, 1.0):
	set(value):
		source_direction = value
		_apply_params()
## Radians of flow per second round the sphere.
@export var flow_speed := 0.8:
	set(value):
		flow_speed = value
		_apply_params()
## 0 = steady. The flicker multiplies the fire's heat and the fill light's energy.
@export_range(0.0, 0.5) var flicker_amount := 0.08
## The warm light from the hot side that flickers with the fire.
@export var fill_light: Light3D
@export var fill_energy := 0.9
## The cool rim from the wake (open space behind the ship). Dies as the wake closes.
@export var rim_light: Light3D
@export var rim_energy := 0.9
## A jolt's flare on top of the flicker, 0 = none. Set by CockpitReentry; it heats the screen and
## pumps the fill.
var flare := 0.0
## Multiplies flow_speed: the ship's answer to the push. Set by CockpitReentry.
var speed_scale := 1.0
## 0..1: the fire closing over the wake (the ship answering the push). Set by CockpitReentry.
var swallow := 0.0:
	set(value):
		swallow = value
		_apply_swallow()

var _material: ShaderMaterial
var _time := 0.0
var _phase := 0.0


func _ready() -> void:
	_rebuild()
	if fill_light != null:
		# Light comes from the hot point toward the seat.
		var from := global_transform * (source_direction.normalized() * radius)
		fill_light.look_at_from_position(from, global_position, Vector3.UP)


func _process(delta: float) -> void:
	_time += delta
	_phase += delta * flow_speed * speed_scale
	var f := flicker_at(_time, flicker_amount)
	if _material != null:
		_material.set_shader_parameter(&"flow_phase", _phase)
		_material.set_shader_parameter(&"flicker", f + flare * 0.35)
	if fill_light != null:
		fill_light.light_energy = fill_energy * f * (1.0 + flare * 0.8)


## Knocks out panels of the wire grid: each Vector4 is (segment, ring, kind, seconds), kind 0 black,
## 1 no signal, 2 shifted; `age` is the seconds since they were thrown (negative = none).
func set_drops(drops: Array[Vector4], age: float) -> void:
	if _material == null:
		return
	var packed := PackedVector4Array()
	packed.resize(MAX_DROPS)
	for i in mini(drops.size(), MAX_DROPS):
		packed[i] = drops[i]
	_material.set_shader_parameter(&"drops", packed)
	_material.set_shader_parameter(&"drop_count", mini(drops.size(), MAX_DROPS))
	_material.set_shader_parameter(&"drop_age", age)


func _apply_swallow() -> void:
	if _material != null:
		_material.set_shader_parameter(&"swallow", swallow)
	if rim_light != null:
		rim_light.light_energy = rim_energy * (1.0 - swallow)
		rim_light.visible = swallow < 1.0


## The shader parameter, for tests.
func get_param(param: StringName) -> Variant:
	return _material.get_shader_parameter(param) if _material != null else null


## The shared flicker, around 1.0: three incommensurate sines, so it never visibly repeats.
static func flicker_at(t: float, amount: float) -> float:
	var n := sin(t * 23.0) * 0.5 + sin(t * 37.3 + 1.3) * 0.3 + sin(t * 61.7 + 4.1) * 0.2
	return 1.0 + amount * n


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
	_apply_params()


func _apply_params() -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"source_dir", source_direction.normalized())
	_material.set_shader_parameter(&"flow_speed", flow_speed)
	_material.set_shader_parameter(&"segments", GRID_SEGMENTS)
	_material.set_shader_parameter(&"rings", GRID_RINGS)
	_apply_swallow()
