## The firing range's target: a box that circles pilot at a distance and fires a laser at him every
## couple of seconds. It cannot die and cannot kill; it only counts what it takes. Dormant until the
## range wakes it. See docs/specs/firing-range.md.
extends AnimatableBody3D

const _Bolt := preload("res://scripts/range/range_bolt.gd")

signal woke
signal slept
## Emitted for every hit it takes: damage, the kind (&"reflect" / &"reflect_perfect"), the point.
signal hit(amount: float, kind: StringName, point: Vector3)
signal fired(bolt: Node)

enum State { DORMANT, WAKING, ACTIVE }

@export_group("Movement")
## Metres from pilot it tries to keep.
@export_range(4.0, 30.0, 0.5) var preferred_range: float = 14.0
## Sideways speed around pilot, m/s.
@export_range(0.0, 12.0, 0.1) var strafe_speed: float = 4.0
## Speed it closes or opens the gap at, m/s, at full error.
@export_range(0.0, 12.0, 0.1) var range_speed: float = 3.0
## Metres off the preferred range it ignores.
@export_range(0.0, 5.0, 0.1) var range_dead_band: float = 1.5
## It reverses its strafe after a random time in this span, seconds.
@export var reverse_min: float = 1.5
@export var reverse_max: float = 3.0
## Half the playable square it stays inside, metres from the range centre, and the margin kept.
@export var bounds_half: float = 25.0
@export var bounds_margin: float = 2.0

@export_group("Firing")
@export var fire_min: float = 2.0
@export var fire_max: float = 3.0
## Charge-up flash before each shot, seconds.
@export_range(0.1, 2.0, 0.05) var charge_time: float = 0.45
## Power-on delay before the first shot after waking, seconds.
@export_range(0.0, 3.0, 0.05) var wake_delay: float = 1.0
@export_range(5.0, 80.0, 1.0) var bolt_speed: float = 28.0
## Where on pilot it aims, metres above his feet.
@export var aim_height: float = 1.2
@export var damage_normal: float = 20.0
@export var damage_perfect: float = 50.0

var state: State = State.DORMANT
## F11: stays awake but stops moving and firing.
var frozen := false
## Centre of the slab in world space. Set by the range.
var centre := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _strafe_sign := 1.0
var _reverse_timer := 2.0
var _since_flip := 1.0
var _fire_timer := 2.5
var _charge := -1.0
var _wake_left := 0.0

var _visual: Node3D = null
## Holds the box's wobble on a hit in ANIME. Built in _build().
var anime_hold: AnimeHold = null
var _mat: StandardMaterial3D = null
var _muzzle: Marker3D = null
var _hitbox: Area3D = null
var _flash := 0.0
var _recoil := 0.0


func _ready() -> void:
	_rng.randomize()
	add_to_group(&"range_dummy")
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_build()
	_set_dormant_look()
	_reverse_timer = _rng.randf_range(reverse_min, reverse_max)


func _build() -> void:
	_visual = Node3D.new()
	_visual.name = &"Visual"
	add_child(_visual)
	# ANIME holds the wobble's first frame when it is hit. See docs/specs/anime-animation.md.
	anime_hold = AnimeHold.new()
	add_child(anime_hold)
	anime_hold.setup()
	anime_hold.inner = [_visual]
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	_mat.roughness = 0.9
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = &"Body"
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 2.0, 1.2)
	box.material = _mat
	body_mesh.mesh = box
	body_mesh.position = Vector3(0.0, 1.0, 0.0)
	_visual.add_child(body_mesh)
	# A snout so it is obvious which way it faces and where the bolt leaves.
	var snout := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.35, 0.35, 0.5)
	sb.material = _mat
	snout.mesh = sb
	snout.position = Vector3(0.0, 1.45, 0.85)
	_visual.add_child(snout)
	_muzzle = Marker3D.new()
	_muzzle.name = &"Muzzle"
	_muzzle.position = Vector3(0.0, 1.45, 1.15)
	_visual.add_child(_muzzle)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.2, 2.0, 1.2)
	col.shape = bs
	col.position = Vector3(0.0, 1.0, 0.0)
	add_child(col)
	_hitbox = Area3D.new()
	_hitbox.name = &"Hitbox"
	_hitbox.collision_layer = _Bolt.LAYER_DUMMY
	_hitbox.collision_mask = 0
	var hs := CollisionShape3D.new()
	var hb := BoxShape3D.new()
	hb.size = Vector3(1.4, 2.2, 1.4)
	hs.shape = hb
	hs.position = Vector3(0.0, 1.0, 0.0)
	_hitbox.add_child(hs)
	add_child(_hitbox)


# --- state ------------------------------------------------------------------------------------

func is_awake() -> bool:
	return state != State.DORMANT


## Pilot stepped onto the slab: power on, then a beat before the first shot.
func wake() -> void:
	if state != State.DORMANT:
		return
	state = State.WAKING
	_wake_left = wake_delay
	_charge = -1.0
	_fire_timer = _rng.randf_range(fire_min, fire_max)
	_flash = 1.0
	woke.emit()


## Pilot left: back to a dim box, nothing in flight.
func sleep() -> void:
	if state == State.DORMANT:
		return
	state = State.DORMANT
	_charge = -1.0
	_wake_left = 0.0
	_set_dormant_look()
	for b in get_tree().get_nodes_in_group(_Bolt.BOLT_GROUP):
		b.queue_free()
	slept.emit()


## F10: skip the wait and fire (still goes through the charge).
func force_fire() -> void:
	if state == State.ACTIVE and not frozen and _charge < 0.0:
		_fire_timer = 0.0


func _set_dormant_look() -> void:
	if _mat == null:
		return
	_mat.albedo_color = Color(0.25, 0.26, 0.3)
	_mat.emission = Color(0.0, 0.0, 0.0)
	_mat.emission_energy_multiplier = 0.0


# --- hits -------------------------------------------------------------------------------------

## The hook every attack uses. It never dies: the damage is only reported.
func take_hit(amount: float, kind: StringName, point: Vector3) -> void:
	if state == State.DORMANT:
		return
	_flash = 1.0
	_recoil = 1.0
	anime_hold.accent(&"hit", 1.0 if kind == &"reflect_perfect" else 0.0)
	hit.emit(amount, kind, point)


# --- per frame --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _mat == null:
		return
	_flash = move_toward(_flash, 0.0, delta / 0.2)
	_recoil = move_toward(_recoil, 0.0, delta / 0.25)
	if state == State.DORMANT:
		_set_dormant_look()
	else:
		_mat.albedo_color = Color(0.55, 0.25, 0.2)
		_mat.emission = Color(1.0, 0.25, 0.15)
		_mat.emission_energy_multiplier = 0.35
		if _charge >= 0.0:
			var k := clampf(_charge / charge_time, 0.0, 1.0)
			_mat.emission = Color(1.0, 0.9, 0.5)
			_mat.emission_energy_multiplier = 0.35 + 3.0 * k * k
	if _flash > 0.0:
		_mat.emission = Color(1, 1, 1)
		_mat.emission_energy_multiplier = maxf(_mat.emission_energy_multiplier, 4.0 * _flash)
	# The wobble: a quick shake of the visual only, so the box's path is untouched.
	_visual.rotation = Vector3(sin(_recoil * 40.0) * 0.12 * _recoil, 0.0,
		cos(_recoil * 33.0) * 0.12 * _recoil)


func _physics_process(delta: float) -> void:
	if state == State.DORMANT:
		return
	var pilot := _find_pilot()
	if pilot == null:
		return
	_face(pilot)
	if state == State.WAKING:
		_wake_left -= delta
		if _wake_left <= 0.0:
			state = State.ACTIVE
		return
	if frozen:
		return
	_move(pilot, delta)
	_fire_step(pilot, delta)


func _find_pilot() -> Node3D:
	var players := get_tree().get_nodes_in_group(&"reflect_target")
	return players[0] as Node3D if not players.is_empty() else null


func _face(pilot: Node3D) -> void:
	var to := pilot.global_position - global_position
	to.y = 0.0
	if to.length() > 0.01:
		rotation.y = atan2(to.x, to.z)


func _move(pilot: Node3D, delta: float) -> void:
	_since_flip += delta
	_reverse_timer -= delta
	if _reverse_timer <= 0.0:
		_flip()
	var to := pilot.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.01:
		return
	var dir := to / dist
	var tangent := dir.cross(Vector3.UP) * _strafe_sign
	var vel := tangent * strafe_speed + dir * range_velocity(dist, preferred_range,
		range_dead_band, range_speed)
	var want := global_position + vel * delta
	var clamped := clamp_to_bounds(want, centre, bounds_half - bounds_margin)
	if clamped.distance_to(want) > 0.001 and _since_flip > 0.4:
		_flip()
	global_position = clamped


func _flip() -> void:
	_strafe_sign = -_strafe_sign
	_since_flip = 0.0
	_reverse_timer = _rng.randf_range(reverse_min, reverse_max)


func _fire_step(pilot: Node3D, delta: float) -> void:
	if _charge >= 0.0:
		_charge += delta
		if _charge >= charge_time:
			_charge = -1.0
			_fire_timer = _rng.randf_range(fire_min, fire_max)
			_shoot(pilot)
		return
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		if _has_line(pilot):
			_charge = 0.0
		else:
			_fire_timer = 0.3


func _has_line(pilot: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var from := _muzzle.global_position
	var to := pilot.global_position + Vector3.UP * aim_height
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var found := space.intersect_ray(q)
	# Pilot's own body is on layer 1: a ray that ends on him has a clear line.
	return found.is_empty() or found.get("collider") == pilot


func _shoot(pilot: Node3D) -> Node:
	var bolt := _Bolt.new()
	bolt.shooter = self
	bolt.damage_normal = damage_normal
	bolt.damage_perfect = damage_perfect
	# Bolts outlive the dummy, so they go in the scene; a bare tree (tests) has none.
	var host := get_tree().current_scene if get_tree().current_scene != null else get_parent()
	host.add_child(bolt)
	bolt.global_position = _muzzle.global_position
	var aim := pilot.global_position + Vector3.UP * aim_height - bolt.global_position
	bolt.velocity = aim.normalized() * bolt_speed
	fired.emit(bolt)
	return bolt


# --- pure helpers, static so tests can check them without a rig ------------------------------

## Closing (+) or opening (-) velocity along the line to pilot: nothing inside the dead band,
## then ramping to `speed` over two more metres of error. Positive means toward pilot.
static func range_velocity(dist: float, preferred: float, dead_band: float, speed: float) -> float:
	var err := dist - preferred
	if absf(err) <= dead_band:
		return 0.0
	return signf(err) * minf((absf(err) - dead_band) / 2.0, 1.0) * speed


## `p` kept inside the square of half-size `half` around `centre_` (x and z only).
static func clamp_to_bounds(p: Vector3, centre_: Vector3, half: float) -> Vector3:
	return Vector3(clampf(p.x, centre_.x - half, centre_.x + half), p.y,
		clampf(p.z, centre_.z - half, centre_.z + half))
