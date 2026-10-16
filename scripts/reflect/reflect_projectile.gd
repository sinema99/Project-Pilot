## A ball that can be reflected. Also the contract a real enemy bullet has to meet: be in the
## `reflectable` group, carry a `shooter`, and answer reflect(). See docs/specs/pilot9-reflect.md.
extends Area3D

## The layer the reflect zone looks at (3d_physics layer 8, "reflectable").
const LAYER := 128
const GROUP := &"reflectable"

## Who fired it. A perfect reflect sends it back here. May be freed by then - check validity.
var shooter: Node3D = null
var velocity: Vector3 = Vector3.ZERO
## Seconds until it despawns whatever it hit.
var lifetime: float = 6.0
## True once a reflect has turned it. The zone skips these, so one spin turns a ball once.
var reflected: bool = false
## Whether that reflect was a perfect one.
var was_perfect: bool = false

var _age := 0.0


func _init() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	add_to_group(GROUP)


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	shape.shape = sphere
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.2)
	sm.material = mat
	mesh.mesh = sm
	mesh.name = &"Ball"
	add_child(mesh)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	_age += delta
	if _age >= lifetime:
		queue_free()


## Turns the ball to fly along `direction` at the speed it had. Called by the reflect zone.
func reflect(direction: Vector3, perfect: bool) -> void:
	reflected = true
	was_perfect = perfect
	var speed := velocity.length()
	velocity = direction.normalized() * speed
	# A reflected ball is on the player's side now: green, so a test reads at a glance.
	var ball := get_node_or_null("Ball") as MeshInstance3D
	if ball != null:
		var mat := (ball.mesh as SphereMesh).material as StandardMaterial3D
		mat.albedo_color = Color(0.3, 1.0, 0.5) if perfect else Color(1.0, 0.9, 0.3)
	# Fresh clock so it lives long enough to arrive.
	_age = 0.0
