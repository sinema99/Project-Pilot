extends Node3D

# The speeder's thruster fire, PS1 style (docs/specs/speeder1-pass2.md, "Thruster fire").
#
# Per nozzle: three nested hexagonal flame cones (flat colours, additive, so the overlap goes
# hot) that are redrawn at 12 fps - a new length jitter and a half-turn twist each step, never a
# smooth wobble - and a trail of hard-edged cube sparks that step through a yellow / orange / red
# palette and shrink away. The sparks are left in the world, so the bike draws a line of them
# behind it at speed. A small orange light sits behind the engines.
#
# speeder.gd decides how much each nozzle burns (levels(), a pure function) and calls drive();
# this only draws it. Built in code by the speeder's _ready(), under its `Tilt` root, so a rebuild
# of speeder.tscn cannot lose it. No image files.

## The flame is redrawn this often, seconds.
const STEP := 1.0 / 12.0
## Flame length at level 1, size-1 metres, and the flame's girth against the nozzle's radius.
const MAX_LENGTH := 1.5
const GIRTH := 1.1
## [length share, girth share, colour] outermost first. Additive: the overlap is the hot core.
const LAYERS := [
	[1.0, 1.0, Color(0.55, 0.10, 0.03)],
	[0.74, 0.66, Color(0.50, 0.30, 0.05)],
	[0.46, 0.36, Color(0.45, 0.40, 0.25)],
]
## Spark palette, stepped (no blending between the steps).
const SPARK_OFFSETS := [0.0, 0.3, 0.6, 0.85]
const SPARK_COLORS := [Color(1.0, 0.95, 0.55), Color(1.0, 0.55, 0.10), Color(0.85, 0.20, 0.07),
	Color(0.35, 0.08, 0.05)]
const SPARK_LIFE := 0.45
const SPARK_COUNT := 24
const SPARK_SIZE := 0.08
const LIGHT_COLOR := Color(1.0, 0.55, 0.15)
## Level easing, 1/s, up and down.
const RISE := 14.0
const FALL := 8.0
## Below this a nozzle is dark.
const MIN_LEVEL := 0.03
## Boost speed lines: metres (size 1), count, life, colour; below STREAK_MIN of boost they are off.
const STREAK_LENGTH := 1.6
const STREAK_COUNT := 36
const STREAK_LIFE := 0.35
const STREAK_COLOR := Color(0.55, 0.85, 1.0, 0.7)
const STREAK_MIN := 0.1

var _boost := 0.0
var _streaks: GPUParticles3D = null

var _k := 1.0
var _radius := 0.085
var _roots: Array[Node3D] = []
var _cones: Array = []
var _sparks: Array[GPUParticles3D] = []
var _light: OmniLight3D = null
var _cone_mesh: CylinderMesh = null

var _level := Vector2.ZERO
var _target := Vector2.ZERO
var _on := true
var _t := 0.0
var _jitter := Vector2.ONE
var _twist := false
var _rng := RandomNumberGenerator.new()


## How hard each nozzle burns, (left +X, right -X), 0..~1.3.
##   - nobody on: dark
##   - throttle: long and full, growing with speed
##   - coasting: a low flicker that comes up a little with speed
##   - braking / reversing: almost out
##   - turning: the outside nozzle flares, the inside one dims (D = a right turn, so the left flares)
static func levels(has_rider: bool, throttle_in: float, speed: float, speed_share: float,
		steer_in: float, boost := 0.0) -> Vector2:
	if not has_rider:
		return Vector2.ZERO
	var base: float
	if throttle_in > 0.0:
		base = lerpf(0.6, 1.0, speed_share)
	elif throttle_in < 0.0 and absf(speed) > 0.5:
		base = 0.05
	elif throttle_in < 0.0:
		base = 0.05
	else:
		base = lerpf(0.14, 0.45, speed_share)
	# A boost: both nozzles go long and hot whatever the throttle says.
	base = lerpf(base, 1.25, clampf(boost, 0.0, 1.0))
	var turn := steer_in * clampf(speed_share / 0.6, 0.0, 1.0)
	return Vector2(clampf(base * (1.0 + 0.5 * turn), 0.0, 1.3), clampf(base * (1.0 - 0.6 * turn), 0.0, 1.3))


## `k` the bike's size scale, `nozzles` their positions at size 1 (bike frame), `radius` theirs.
func setup(k: float, nozzles: Array, radius: float) -> void:
	_k = k
	_radius = radius
	_rng.randomize()
	_cone_mesh = CylinderMesh.new()
	_cone_mesh.top_radius = 0.0
	_cone_mesh.bottom_radius = 1.0
	_cone_mesh.height = 1.0
	_cone_mesh.radial_segments = 6
	_cone_mesh.rings = 1
	_cone_mesh.cap_top = false
	_cone_mesh.cap_bottom = false
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3.ONE * SPARK_SIZE * k
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mesh.material = spark_mat
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.offsets = PackedFloat32Array(SPARK_OFFSETS)
	ramp.colors = PackedColorArray(SPARK_COLORS)
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.7, 0.8))
	shrink.add_point(Vector2(1.0, 0.0))
	var shrink_tex := CurveTexture.new()
	shrink_tex.curve = shrink

	for pos: Vector3 in nozzles:
		var root := Node3D.new()
		root.name = "Nozzle"
		root.position = pos * k
		add_child(root)
		_roots.append(root)
		var layer_nodes: Array[MeshInstance3D] = []
		for layer in LAYERS:
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = layer[2]
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			var mi := MeshInstance3D.new()
			mi.mesh = _cone_mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
			layer_nodes.append(mi)
		_cones.append(layer_nodes)

		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.0, 0.0, -1.0)
		pm.spread = 9.0
		pm.initial_velocity_min = 5.0
		pm.initial_velocity_max = 9.0
		pm.gravity = Vector3.ZERO
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = radius * k * 0.8
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		pm.scale_curve = shrink_tex
		pm.color_ramp = ramp_tex
		var sp := GPUParticles3D.new()
		sp.name = "Sparks"
		sp.amount = SPARK_COUNT
		sp.lifetime = SPARK_LIFE
		sp.local_coords = false
		sp.fixed_fps = 20
		sp.process_material = pm
		sp.draw_pass_1 = spark_mesh
		sp.visibility_aabb = AABB(Vector3(-12, -6, -22), Vector3(24, 12, 30))
		sp.emitting = false
		root.add_child(sp)
		sp.position = Vector3(0.0, 0.0, -0.1 * k)
		_sparks.append(sp)

	_light = OmniLight3D.new()
	_light.name = "Glow"
	_light.light_color = LIGHT_COLOR
	_light.omni_range = 4.0 * k
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.315 * k, -1.7 * k)
	add_child(_light)
	_build_streaks()
	_apply()


## The levels the speeder wants this frame (they ease toward them), and whether effects are on.
func drive(left: float, right: float, on: bool, boost := 0.0) -> void:
	_target = Vector2(left, right)
	_on = on
	_boost = boost
	if _streaks != null:
		var lit := on and boost > STREAK_MIN
		_streaks.emitting = lit
		_streaks.amount_ratio = clampf(boost, 0.1, 1.0)


func streaks_emitting() -> bool:
	return _streaks != null and _streaks.emitting


## Thin bolts of light that stream back past the rider while boosting: the bike's own speed lines.
func _build_streaks() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, STREAK_LENGTH) * _k
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = STREAK_COLOR
	mesh.material = mat
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, -1.0)
	pm.spread = 2.0
	pm.initial_velocity_min = 24.0 * _k
	pm.initial_velocity_max = 40.0 * _k
	pm.gravity = Vector3.ZERO
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.5, 0.9, 0.3) * _k
	_streaks = GPUParticles3D.new()
	_streaks.name = "Streaks"
	_streaks.amount = STREAK_COUNT
	_streaks.lifetime = STREAK_LIFE
	_streaks.local_coords = false
	_streaks.fixed_fps = 30
	_streaks.process_material = pm
	_streaks.draw_pass_1 = mesh
	_streaks.visibility_aabb = AABB(Vector3(-20, -10, -40), Vector3(40, 20, 60))
	_streaks.emitting = false
	_streaks.position = Vector3(0.0, 1.0 * _k, 0.4 * _k)
	add_child(_streaks)


func _process(delta: float) -> void:
	for i in 2:
		var to := _target[i] if _on else 0.0
		var rate := RISE if to > _level[i] else FALL
		_level[i] = lerpf(_level[i], to, 1.0 - exp(-rate * delta))
	_t += delta
	if _t >= STEP:
		_t = fmod(_t, STEP)
		_jitter = Vector2(_rng.randf_range(0.8, 1.15), _rng.randf_range(0.8, 1.15))
		_twist = not _twist
	_apply()


## The outer flame cone's current length on nozzle `i`, metres (tests).
func flame_length(i: int) -> float:
	if i >= _roots.size() or not (_cones[i][0] as Node3D).visible:
		return 0.0
	return ((_cones[i][0] as Node3D).transform.basis.get_scale().y)


func sparks_emitting(i: int) -> bool:
	return i < _sparks.size() and _sparks[i].emitting


func level_of(i: int) -> float:
	return _level[i]


func _apply() -> void:
	var twist := deg_to_rad(30.0) if _twist else 0.0
	var glow := 0.0
	for i in _roots.size():
		var lv: float = _level[i] if _on else 0.0
		var lit := lv > MIN_LEVEL
		var layers: Array = _cones[i]
		for j in layers.size():
			var mi: MeshInstance3D = layers[j]
			mi.visible = lit
			if not lit:
				continue
			var share: Array = LAYERS[j]
			var len_m := MAX_LENGTH * _k * lv * _jitter[i] * float(share[0])
			var rad := _radius * _k * GIRTH * (0.75 + 0.25 * minf(lv, 1.0)) * float(share[1])
			var b := Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, twist) \
				* Basis.from_scale(Vector3(rad, len_m, rad))
			mi.transform = Transform3D(b, Vector3(0.0, 0.0, -len_m * 0.5))
		var sp := _sparks[i]
		sp.emitting = lit
		sp.amount_ratio = clampf(lv, 0.1, 1.0)
		glow += lv * _jitter[i]
	_light.light_energy = clampf(glow * 0.6, 0.0, 1.6)
	_light.visible = _light.light_energy > 0.02
