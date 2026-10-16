## The dummy's laser: a fast streak that meets the reflect contract (`reflectable` group, `shooter`,
## `reflected`, `reflect()`). Unreflected, it hurts pilot's hurtbox; reflected, it hurts the dummy's
## hitbox. Either way it is spent on impact. See docs/specs/firing-range.md.
extends Area3D

const GROUP := &"reflectable"
const BOLT_GROUP := &"range_bolt"
## 3d_physics layer 8, "reflectable": what pilot's reflect zone looks for.
const LAYER_REFLECTABLE := 128
## Layer 2, "player_hurtbox": pilot.
const LAYER_HURTBOX := 2
## Layer 9, "range_dummy": the dummy's hitbox.
const LAYER_DUMMY := 256
## The world (layer 1), so a bolt stops on a wall.
const LAYER_WORLD := 1

const COLOR_HOSTILE := Color(1.0, 0.18, 0.12)
const COLOR_NORMAL := Color(1.0, 0.9, 0.3)
const COLOR_PERFECT := Color(0.3, 1.0, 0.5)
## How hard a perfect-reflected bolt turns onto its shooter, per second (1.0 = fully aimed in a second).
const PERFECT_HOMING := 6.0
const LENGTH := 1.6
const THICKNESS := 0.14

var shooter: Node3D = null
var velocity: Vector3 = Vector3.ZERO
var lifetime: float = 4.0
var reflected: bool = false
var was_perfect: bool = false
## Damage dealt to the dummy when reflected, set by the dummy from its exports.
var damage_normal: float = 20.0
var damage_perfect: float = 50.0

var _age := 0.0
var _spent := false
var _mat: StandardMaterial3D = null


func _init() -> void:
	collision_layer = LAYER_REFLECTABLE
	collision_mask = LAYER_HURTBOX | LAYER_DUMMY | LAYER_WORLD
	monitoring = true
	monitorable = true
	add_to_group(GROUP)
	add_to_group(BOLT_GROUP)


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.35, 0.35, LENGTH)
	shape.shape = box
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(THICKNESS, THICKNESS, LENGTH)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = COLOR_HOSTILE
	bm.material = _mat
	mesh.mesh = bm
	mesh.name = &"Streak"
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	_face_velocity()


func _physics_process(delta: float) -> void:
	# A perfect reflect is sent "back at its shooter", and a shooter that strafes would slip out from
	# under a straight return: it steers onto the shooter's chest as it flies.
	if reflected and was_perfect and shooter != null and is_instance_valid(shooter):
		velocity = steer_toward(velocity, global_position,
			shooter.global_position + Vector3.UP * 1.0, PERFECT_HOMING * delta)
	global_position += velocity * delta
	_face_velocity()
	_age += delta
	if _age >= lifetime:
		queue_free()


func _face_velocity() -> void:
	if velocity.length() > 0.01 and is_inside_tree():
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT
		look_at(global_position + velocity, up)


## Turns the bolt to fly along `direction` at the speed it had. Called by the reflect zone.
func reflect(direction: Vector3, perfect: bool) -> void:
	reflected = true
	was_perfect = perfect
	velocity = direction.normalized() * velocity.length()
	_age = 0.0
	if _mat != null:
		_mat.albedo_color = COLOR_PERFECT if perfect else COLOR_NORMAL


func _on_area_entered(area: Area3D) -> void:
	if _spent:
		return
	if area.collision_layer & LAYER_HURTBOX and not reflected:
		var pilot := _owner_with(area, &"take_hit")
		if pilot != null:
			_spent = true
			pilot.take_hit(0.0, &"range_bolt", global_position)
			queue_free()
	elif area.collision_layer & LAYER_DUMMY and reflected:
		var dummy := _owner_with(area, &"take_hit")
		if dummy != null:
			_spent = true
			var amount := damage_perfect if was_perfect else damage_normal
			dummy.take_hit(amount, &"reflect_perfect" if was_perfect else &"reflect", global_position)
			queue_free()


func _on_body_entered(_body: Node3D) -> void:
	# The dummy's own body is on layer 1 too: a bolt just leaving it must not die on it. Pilot's
	# body is as well, but he is hurt through his hurtbox, so the body is no wall.
	if _spent or (shooter != null and _body == shooter) or _body.is_in_group(&"range_dummy") \
			or _body.is_in_group(&"reflect_target"):
		return
	_spent = true
	queue_free()


## `velocity` turned `weight` (0..1) of the way toward `target`, speed kept.
static func steer_toward(vel: Vector3, from: Vector3, target: Vector3, weight: float) -> Vector3:
	var want := target - from
	if want.length() < 0.001 or vel.length() < 0.001:
		return vel
	var dir := vel.normalized().slerp(want.normalized(), clampf(weight, 0.0, 1.0))
	return dir.normalized() * vel.length()


## The nearest ancestor of `node` (or itself) that answers `method`.
static func _owner_with(node: Node, method: StringName) -> Node:
	var n := node
	while n != null:
		if n.has_method(method):
			return n
		n = n.get_parent()
	return null
