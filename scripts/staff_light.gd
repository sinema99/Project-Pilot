## The tredge's torch: a pale orange ball floating just above the staff's top end, its halo, the
## OmniLight it casts, and the storm_torch_* globals that warm the blizzard's flakes and fog round
## it. Built at runtime by scripts/pilot9_tredge.gd and faded with the torch arm (`fade`), so it
## only exists while he tredges. See docs/specs/pilot9-tredge.md, "Staff light".
extends Node3D

## Pale orange: the core, the halo, the light and the storm's warm tint.
@export var color := Color(1.0, 0.824, 0.627)

@export_group("Ball")
## The core's radius, metres.
@export_range(0.01, 0.5, 0.005) var radius := 0.07:
	set(v):
		radius = v
		_size_meshes()
## How far past the staff's top end the ball's centre floats, along the staff's own axis, metres.
@export_range(0.0, 1.0, 0.005) var gap := 0.12
## The slow float along the staff's axis: this far either way, metres, over float_period seconds.
@export_range(0.0, 0.1, 0.001) var float_amount := 0.01
@export_range(0.1, 10.0, 0.05) var float_period := 1.5
## The halo's diameter, metres, and how bright its centre is.
@export_range(0.0, 2.0, 0.01) var halo_size := 0.35:
	set(v):
		halo_size = v
		_size_meshes()
@export_range(0.0, 4.0, 0.05) var halo_intensity := 0.7

@export_group("Light")
@export_range(0.0, 16.0, 0.05) var energy := 1.3
@export_range(0.5, 40.0, 0.5) var light_range := 6.0
@export var shadows := true
## The flicker: energy wanders this much either way (0.05 = +-5%), slowly.
@export_range(0.0, 0.5, 0.005) var flicker := 0.05
@export_range(0.05, 10.0, 0.05) var flicker_speed := 1.0
## At a full gust stumble the light dips by this much.
@export_range(0.0, 1.0, 0.01) var gust_dip := 0.15

@export_group("Storm")
## Flakes within this many metres of the ball take its colour.
@export_range(0.0, 20.0, 0.1) var flake_reach := 3.0
## The warm haze the fog pass draws round the ball: its radius, metres, and its strength.
@export_range(0.0, 10.0, 0.05) var fog_glow_radius := 1.0
@export_range(0.0, 2.0, 0.01) var fog_glow := 0.5

## 0..1: the torch arm's weight. Set every tick by pilot9_tredge.gd.
var fade := 0.0
## The gust stumble spring, about 0..1 (overshooting). Set by pilot9_tredge.gd.
var stagger := 0.0
## The staff whose top end the ball floats over; null leaves the ball where it is. The ball is
## placed when the staff's skeleton finishes posing, so it is never a frame behind the staff.
var staff: Node3D = null:
	set(v):
		if v == staff:
			return
		staff = v
		_watch_skeleton(_skeleton_of(v))
## Half the staff's length: its top end is this far up its own +Y.
var staff_half_length := 0.8

var core: MeshInstance3D
var halo: MeshInstance3D
var light: OmniLight3D

var _halo_mat: ShaderMaterial
var _time := 0.0
var _skeleton: Skeleton3D = null
var _globals_live := false


func _init() -> void:
	top_level = true
	core = MeshInstance3D.new()
	core.name = &"Core"
	core.mesh = SphereMesh.new()
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.disable_fog = true
	core.material_override = mat
	add_child(core)

	halo = MeshInstance3D.new()
	halo.name = &"Halo"
	halo.mesh = QuadMesh.new()
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = preload("res://shaders/staff_light_halo.gdshader")
	halo.material_override = _halo_mat
	add_child(halo)

	light = OmniLight3D.new()
	light.name = &"Light"
	add_child(light)
	_size_meshes()
	visible = false


func _size_meshes() -> void:
	if core == null:
		return
	var s := core.mesh as SphereMesh
	s.radius = radius
	s.height = radius * 2.0
	(halo.mesh as QuadMesh).size = Vector2.ONE * halo_size


func _exit_tree() -> void:
	_watch_skeleton(null)
	_set_globals(Vector3.ZERO, 0.0)


static func _skeleton_of(n: Node) -> Skeleton3D:
	while n != null and not n is Skeleton3D:
		n = n.get_parent()
	return n as Skeleton3D


# Connected after the staff's BoneAttachment3D, so the staff has already moved when this runs.
func _watch_skeleton(skel: Skeleton3D) -> void:
	if _skeleton == skel:
		return
	if _skeleton != null and is_instance_valid(_skeleton) 			and _skeleton.skeleton_updated.is_connected(place):
		_skeleton.skeleton_updated.disconnect(place)
	_skeleton = skel
	if _skeleton != null:
		_skeleton.skeleton_updated.connect(place)


## Puts the ball on the staff's axis, `gap` past its top end, with the float along the axis.
func place() -> void:
	if staff == null or not is_instance_valid(staff) or not staff.is_inside_tree():
		return
	var xf := staff.global_transform
	var axis := xf.basis.y.normalized()
	var tip := xf * (Vector3.UP * staff_half_length)
	global_position = tip + axis * (gap + float_amount * sin(_time * TAU / float_period))


func _process(delta: float) -> void:
	_time += delta
	var on := fade > 0.0 and staff != null and is_instance_valid(staff) and staff.is_inside_tree()
	if not on:
		if visible:
			visible = false
			_set_globals(global_position, 0.0)
		return
	if not visible:
		visible = true
		place()

	var bright := strength()
	var mat := core.material_override as StandardMaterial3D
	mat.albedo_color = color
	# The core shrinks into being with the fade rather than popping.
	core.scale = Vector3.ONE * clampf(fade, 0.0, 1.0)
	_halo_mat.set_shader_parameter(&"color", color)
	_halo_mat.set_shader_parameter(&"strength", bright)
	_halo_mat.set_shader_parameter(&"intensity", halo_intensity)
	light.light_color = color
	light.light_energy = energy * bright
	light.omni_range = light_range
	light.shadow_enabled = shadows
	_set_globals(global_position, bright)


## 0..1-ish: the fade, times the flicker, less the gust dip.
func strength() -> float:
	var t := _time * flicker_speed
	# Three incommensurate slow waves: noisy, never a visible beat.
	var n := (sin(t * 2.3) + 0.6 * sin(t * 5.1 + 1.3) + 0.4 * sin(t * 9.7 + 4.1)) / 2.0
	var f := 1.0 + flicker * n
	return clampf(fade, 0.0, 1.0) * f * (1.0 - gust_dip * clampf(stagger, 0.0, 1.0))


func _set_globals(pos: Vector3, bright: float) -> void:
	if bright <= 0.0 and not _globals_live:
		return
	_globals_live = bright > 0.0
	RenderingServer.global_shader_parameter_set(&"storm_torch_pos", pos)
	RenderingServer.global_shader_parameter_set(&"storm_torch_color", color)
	RenderingServer.global_shader_parameter_set(&"storm_torch", Vector3(bright, flake_reach,
			fog_glow_radius))
	RenderingServer.global_shader_parameter_set(&"storm_torch_fog", fog_glow)
