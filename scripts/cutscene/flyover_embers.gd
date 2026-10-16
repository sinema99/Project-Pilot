class_name FlyoverEmbers
extends MeshInstance3D

# Engine embers for the flyover (docs/specs/cutscene-flyover.md, "Speed lines + engine heat"):
# sparks shed in world space from the nozzles. Each leaves at the ship's speed plus a kick out of
# the nozzle, then the air drags it toward the wind, so the ship pulls away and it tears back past
# the camera. Rebuilt every frame from the shot time like the trails: ember n of a nozzle is born
# at n / rate (jittered by a hash of n), so seeking shows the same sparks and the shot opens with
# them already streaming. Look: shaders/cutscene/engine_embers.gdshader.

## Embers born per second from the main engine and from each pod.
@export var main_rate := 150.0
@export var pod_rate := 16.0
## Longest life (s); each ember lives 60-100% of it.
@export var life := 0.45
## Kick (m/s) back out of the nozzle, and the random spread (m/s) on top of it.
@export var eject_speed := 12.0
@export var spread := 9.0
## How fast the air drags an ember toward the wind's speed (1/s).
@export var drag := 1.6
## Seconds of camera-relative travel drawn as the streak, its minimum length (m) and width (m).
@export var streak_time := 0.015
@export var min_length := 0.08
@export var width := 0.05

## Nozzle centres in the ship model's space, main engine first (the flyover hands it the trails').
var nozzles := PackedVector3Array()
## The air's velocity (m/s, world): the storm wind.
var air := Vector3.ZERO

var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))


## Rebuilds the embers for shot time `t`. `ship_at(tau)` is the ship's global transform at shot
## time tau; `eye` and `eye_velocity` are the camera's position and velocity (the streaks are drawn
## along the motion the camera sees).
func update_embers(t: float, ship_at: Callable, eye: Vector3, eye_velocity: Vector3) -> int:
	_mesh.clear_surfaces()
	var drawn := 0
	var begun := false
	for k in nozzles.size():
		var rate := main_rate if k == 0 else pod_rate
		if rate <= 0.0:
			continue
		var first := floori((t - life) * rate) - 1
		var last := floori(t * rate)
		for n in range(first, last + 1):
			var r1 := _hash(n, k, 1)
			var birth := (float(n) + r1) / rate
			var age := t - birth
			var span := life * (0.6 + 0.4 * _hash(n, k, 2))
			if age < 0.0 or age > span:
				continue
			var xf: Transform3D = ship_at.call(birth)
			var ship_vel: Vector3 = ((ship_at.call(birth + 0.01) as Transform3D).origin
					- (ship_at.call(birth - 0.01) as Transform3D).origin) / 0.02
			var kick := Vector3(_hash(n, k, 3) - 0.5, _hash(n, k, 4) - 0.5, -1.0)
			kick = Vector3(kick.x * spread * 2.0, kick.y * spread * 2.0, -eject_speed * (0.7 + 0.6 * _hash(n, k, 5)))
			var v0 := ship_vel + xf.basis.orthonormalized() * kick
			# Exponential drag toward the air: v(a) = air + (v0 - air) e^(-drag a).
			var decay := exp(-drag * age)
			var pos := xf * nozzles[k] + air * age + (v0 - air) * (1.0 - decay) / drag
			var vel := air + (v0 - air) * decay
			if not begun:
				_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material_override)
				begun = true
			_add_streak(pos, vel - eye_velocity, eye, age / span, 0.6 + 0.4 * _hash(n, k, 6))
			drawn += 1
	if begun:
		_mesh.surface_end()
	return drawn


func _add_streak(head: Vector3, rel_vel: Vector3, eye: Vector3, age_frac: float, bright: float) -> void:
	var speed := rel_vel.length()
	var along := rel_vel / speed if speed > 1e-3 else Vector3.BACK
	var tail := head - along * maxf(speed * streak_time, min_length)
	var side := along.cross(eye - head)
	side = side.normalized() * width * 0.5 if side.length() > 1e-4 else Vector3.RIGHT * width * 0.5
	var col := Color(age_frac, 0.0, 0.0, bright)
	_vert(tail - side, Vector2(0.0, 0.0), col)
	_vert(head - side, Vector2(0.0, 1.0), col)
	_vert(head + side, Vector2(1.0, 1.0), col)
	_vert(tail - side, Vector2(0.0, 0.0), col)
	_vert(head + side, Vector2(1.0, 1.0), col)
	_vert(tail + side, Vector2(1.0, 0.0), col)


func _vert(p: Vector3, uv: Vector2, col: Color) -> void:
	_mesh.surface_set_color(col)
	_mesh.surface_set_uv(uv)
	_mesh.surface_add_vertex(p)


# 0..1 per (ember, nozzle, channel), the same every call.
static func _hash(n: int, k: int, c: int) -> float:
	var h := (n * 73856093) ^ (k * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)
