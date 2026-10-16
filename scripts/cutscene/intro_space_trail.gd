class_name IntroSpaceTrail
extends MeshInstance3D

# The ship's three engine trails (docs/specs/cutscene-intro-space.md, "Effects pass"). Rebuilt every
# frame as camera-facing ribbons from where the nozzles WERE over the last `life` seconds, asked of
# intro_space.gd by shot time, so the trail is a function of the shot time like everything else:
# seeking or restarting shows the same trail. Look: shaders/space/engine_trail.gdshader.

## Seconds a bit of trail lasts.
@export var life := 4.0
## Ribbon samples per second of trail.
@export var samples_per_second := 90.0
## Ribbon width (m) at the nozzle and at the end of its life; it spreads between with this curve
## (below 1 = spreads fast at first).
@export var width_start := 0.6
@export var width_end := 2.6
@export var spread_curve := 0.6
## Nozzle centres in the ship model's space (sinestro_1.glb: the main engine's rim on the centreline,
## then the two wing pods' rims).
@export var nozzles := PackedVector3Array([Vector3(0.0, 1.47, -3.72), Vector3(-6.89, 1.47, -1.94), Vector3(6.89, 1.47, -1.94)])
## Width multiplier per nozzle, same order: the main engine is ~1.4x the pods across.
@export var nozzle_widths := PackedFloat32Array([1.4, 1.0, 1.0])
## Opacity multiplier per nozzle, same order; a missing entry is 1 (shot 1 leaves it empty).
@export var nozzle_opacities := PackedFloat32Array()
## Wind (m/s, world) the trail blows downwind in, easing up to full speed over about `wind_ease`
## seconds of age, so the ribbon curves off downwind. Zero for no wind (shot 1).
@export var wind := Vector3.ZERO
@export var wind_ease := 0.3

var _mesh := ImmediateMesh.new()
# The ribbon being built's `nozzle_opacities` entry, carried to the shader in COLOR.a.
var _opacity := 1.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Spans kilometres and moves every frame: never cull it.
	custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))


## Rebuilds the trail for shot time `t`. `ship_at(tau)` gives the ship model's global transform
## at shot time tau; `heat_at(tau)` the re-entry heat 0..1 then. Trail starts at `start` (when the
## ship appears). `eye` is the camera position the ribbons face.
func update_trail(t: float, start: float, ship_at: Callable, heat_at: Callable, eye: Vector3) -> void:
	_mesh.clear_surfaces()
	var from := maxf(start, t - life)
	if t - from < 1e-3:
		return
	var n := maxi(2, ceili((t - from) * samples_per_second) + 1)
	var taus := PackedFloat32Array()
	var xforms: Array[Transform3D] = []
	for i in n:
		# Newest first, so sample 0 sits exactly on the nozzle.
		var tau := lerpf(t, from, float(i) / float(n - 1))
		taus.append(tau)
		xforms.append(ship_at.call(tau))
	var heats := PackedFloat32Array()
	for tau in taus:
		heats.append(heat_at.call(tau))
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material_override)
	for k in nozzles.size():
		var pts := PackedVector3Array()
		for i in n:
			pts.append(xforms[i] * nozzles[k] + wind_offset(t - taus[i]))
		var w := nozzle_widths[k] if k < nozzle_widths.size() else 1.0
		_opacity = nozzle_opacities[k] if k < nozzle_opacities.size() else 1.0
		_add_ribbon(pts, taus, heats, t, eye, w)
	_mesh.surface_end()


## How far (m) the wind has blown a bit of trail `age` seconds old: it leaves the nozzle still and
## eases up to wind speed.
func wind_offset(age: float) -> Vector3:
	if wind == Vector3.ZERO or age <= 0.0:
		return Vector3.ZERO
	return wind * (age - wind_ease * (1.0 - exp(-age / wind_ease)))


## Width (m) of the trail at `age` seconds old, times the nozzle's `nozzle_widths` entry.
func width_at(age: float, width_scale := 1.0) -> float:
	return lerpf(width_start, width_end, pow(clampf(age / life, 0.0, 1.0), spread_curve)) * width_scale


func _add_ribbon(pts: PackedVector3Array, taus: PackedFloat32Array, heats: PackedFloat32Array,
		t: float, eye: Vector3, width_scale: float) -> void:
	var n := pts.size()
	var lefts := PackedVector3Array()
	var rights := PackedVector3Array()
	for i in n:
		var tangent := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		var side := tangent.cross(eye - pts[i])
		if side.length_squared() < 1e-8:
			side = Vector3.UP
		side = side.normalized() * width_at(t - taus[i], width_scale) * 0.5
		lefts.append(pts[i] - side)
		rights.append(pts[i] + side)
	for i in n - 1:
		var a := i
		var b := i + 1
		_vert(lefts[a], taus[a], heats[a], t, -1.0)
		_vert(rights[a], taus[a], heats[a], t, 1.0)
		_vert(rights[b], taus[b], heats[b], t, 1.0)
		_vert(lefts[a], taus[a], heats[a], t, -1.0)
		_vert(rights[b], taus[b], heats[b], t, 1.0)
		_vert(lefts[b], taus[b], heats[b], t, -1.0)


func _vert(p: Vector3, tau: float, heat: float, t: float, across: float) -> void:
	_mesh.surface_set_color(Color(heat, 0.0, 0.0, _opacity))
	_mesh.surface_set_uv(Vector2((t - tau) / life, across))
	_mesh.surface_set_uv2(Vector2(tau, 0.0))
	_mesh.surface_add_vertex(p)
