class_name FlyoverDotSparks
extends MeshInstance3D

# Dot sparks crackling around the engines in the flyover (docs/specs/cutscene-flyover.md, "Nozzle
# propulsion"): small hard round dots, white-hot or cyan, born in a ring just outside the trail's
# edge behind each nozzle. Unlike the streak embers (FlyoverEmbers) they live in the ship's frame:
# each drifts slowly back and a little outward, so they hang around the engine on screen, and
# winks out hard. About 1 in 6 is flung wider. Rebuilt every frame from the shot time: dot n of a
# nozzle is born at (n + hash) / rate, so seeking shows the same dots and the shot opens with them
# already going. Look: shaders/cutscene/dot_sparks.gdshader.

## Dots born per second from the main engine and from each pod.
@export var main_rate := 150.0
@export var pod_rate := 15.0
## Each dot lives between these (s).
@export var life_min := 0.15
@export var life_max := 0.3
## Ring (m from the nozzle's centre line) the main engine's dots are born in, and how far behind
## the nozzle (m) they can start. The pods use `pod_scale` of these and of the dot sizes.
@export var ring_inner := 0.7
@export var ring_outer := 1.3
@export var birth_back := 1.0
@export var pod_scale := 0.65
## Drift (m/s, ship frame) back from the nozzle and out from the centre line.
@export var drift_back := 5.0
@export var drift_out := 1.2
## Share of dots flung wider, and how fast (m/s) they fly out.
@export_range(0.0, 1.0, 0.01) var fling_chance := 0.17
@export var fling_speed := 9.0
## Dot diameters (m): the small and the large size, and the share that are large.
@export var small_size := 0.07
@export var large_size := 0.12
@export_range(0.0, 1.0, 0.05) var large_chance := 0.3
## Share of dots that are white-hot (the rest are cyan).
@export_range(0.0, 1.0, 0.05) var hot_chance := 0.5

## Nozzle centres in the ship model's space, main engine first (the flyover hands it the trails').
var nozzles := PackedVector3Array()

var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))


## Rebuilds the dots for shot time `t`, with the ship at `ship` (global) and the camera's basis
## `eye` (the dots face it). Returns how many were drawn.
func update_dots(t: float, ship: Transform3D, eye: Basis) -> int:
	_mesh.clear_surfaces()
	var right := eye.x.normalized()
	var up := eye.y.normalized()
	var drawn := 0
	var begun := false
	for k in nozzles.size():
		var main := k == 0
		var rate := main_rate if main else pod_rate
		if rate <= 0.0:
			continue
		var scale_k := 1.0 if main else pod_scale
		var first := floori((t - life_max) * rate) - 1
		var last := floori(t * rate)
		for n in range(first, last + 1):
			var birth := (float(n) + _hash(n, k, 1)) / rate
			var age := t - birth
			if age < 0.0 or age > lerpf(life_min, life_max, _hash(n, k, 2)):
				continue
			var a := TAU * _hash(n, k, 3)
			var radial := Vector3(cos(a), sin(a), 0.0)
			var r0 := lerpf(ring_inner, ring_outer, _hash(n, k, 4)) * scale_k
			var out := drift_out
			if _hash(n, k, 5) < fling_chance:
				out = fling_speed * (0.6 + 0.4 * _hash(n, k, 6))
			# Back out of the nozzle is the ship's -Z.
			var back := (birth_back * _hash(n, k, 7)) * scale_k + drift_back * (0.7 + 0.6 * _hash(n, k, 8)) * age
			var local := nozzles[k] + radial * (r0 + out * age) - Vector3(0.0, 0.0, back)
			var size := (large_size if _hash(n, k, 9) < large_chance else small_size) * scale_k
			var hot := 1.0 if _hash(n, k, 10) < hot_chance else 0.0
			if not begun:
				_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material_override)
				begun = true
			_add_dot(ship * local, right * size * 0.5, up * size * 0.5, hot)
			drawn += 1
	if begun:
		_mesh.surface_end()
	return drawn


func _add_dot(c: Vector3, r: Vector3, u: Vector3, hot: float) -> void:
	var col := Color(hot, 0.0, 0.0, 1.0)
	_vert(c - r - u, Vector2(0.0, 1.0), col)
	_vert(c + r - u, Vector2(1.0, 1.0), col)
	_vert(c + r + u, Vector2(1.0, 0.0), col)
	_vert(c - r - u, Vector2(0.0, 1.0), col)
	_vert(c + r + u, Vector2(1.0, 0.0), col)
	_vert(c - r + u, Vector2(0.0, 0.0), col)


func _vert(p: Vector3, uv: Vector2, col: Color) -> void:
	_mesh.surface_set_color(col)
	_mesh.surface_set_uv(uv)
	_mesh.surface_add_vertex(p)


# 0..1 per (dot, nozzle, channel), the same every call.
static func _hash(n: int, k: int, c: int) -> float:
	var h := (n * 73856093) ^ (k * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)
