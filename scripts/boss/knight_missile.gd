class_name KnightMissile
extends Area3D

# One of the Knight's six missiles (docs/specs/knight-moveset.md, decision 7): launched up and out,
# it climbs, curves over and homes on pilot with a capped turn rate, so a dash or a hard cut makes
# it overshoot. It meets the reflect contract (`reflectable` group, `shooter`, `reflect()`): a
# normal reflect knocks it away, a perfect one steers it back into the Knight.

const GROUP := &"reflectable"
const GROUP_MISSILE := &"knight_missile"
## Layer 8 "reflectable": what pilot's reflect zone looks for.
const LAYER_REFLECTABLE := 128
## Layer 2 "player_hurtbox", the world (1) and the arena's stop-only wall (10).
const LAYER_HURTBOX := 2
const LAYER_WORLD := 1
const LAYER_STOP_ONLY := 512

## Seconds it climbs on its launch line before it starts turning onto pilot.
@export var climb_time := 0.7
@export var climb_speed := 14.0
## Homing speed (m/s) and the most it turns a second (degrees).
@export var home_speed := 16.0
@export var turn_rate_deg := 100.0
## A perfect-reflected missile turns this hard onto the Knight.
@export var return_turn_deg := 360.0
@export var lifetime := 7.0
## A reflected missile hits the Knight inside this many metres of his chest.
@export var hit_radius := 1.6
## What a reflected missile does to the Knight (carried for whatever listens: he has no health).
@export var damage_normal := 20.0
@export var damage_perfect := 50.0

var shooter: Node3D = null
## The thing it homes on (pilot).
var target: Node3D = null
var velocity := Vector3.ZERO
var reflected := false
var was_perfect := false
var age := 0.0
var spent := false

var _smoke: CPUParticles3D
var _body: Node3D
var _fade := 0.0


func _init() -> void:
	collision_layer = LAYER_REFLECTABLE
	collision_mask = LAYER_HURTBOX | LAYER_WORLD | LAYER_STOP_ONLY
	monitoring = true
	monitorable = true
	add_to_group(GROUP)
	add_to_group(GROUP_MISSILE)


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.35
	shape.shape = sphere
	add_child(shape)
	_build_look()
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	_face()


func _build_look() -> void:
	_body = Node3D.new()
	_body.name = &"Shard"
	add_child(_body)
	# A long red shard pointing along -Z (the way it flies), a white-hot tail behind it.
	var shard := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.16
	cone.height = 0.95
	cone.radial_segments = 5
	cone.rings = 1
	cone.material = KnightFx.glow(KnightFx.RED)
	shard.mesh = cone
	shard.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(shard)
	var core := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.13
	ball.height = 0.26
	ball.radial_segments = 8
	ball.rings = 4
	ball.material = KnightFx.glow(KnightFx.WHITE)
	core.mesh = ball
	core.position = Vector3(0.0, 0.0, 0.42)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(core)
	if KnightFx.effects_on():
		_smoke = CPUParticles3D.new()
		_smoke.name = &"Smoke"
		_smoke.amount = 40
		_smoke.lifetime = 0.9
		_smoke.local_coords = false
		_smoke.position = Vector3(0.0, 0.0, 0.5)
		_smoke.direction = Vector3(0.0, 0.0, 1.0)
		_smoke.spread = 12.0
		_smoke.initial_velocity_min = 0.5
		_smoke.initial_velocity_max = 1.5
		_smoke.gravity = Vector3(0.0, 0.4, 0.0)
		_smoke.scale_amount_min = 0.6
		_smoke.scale_amount_max = 1.0
		var grow := Curve.new()
		grow.add_point(Vector2(0.0, 0.4))
		grow.add_point(Vector2(1.0, 1.6))
		_smoke.scale_amount_curve = grow
		var ramp := Gradient.new()
		ramp.set_color(0, Color(KnightFx.SMOKE.r, KnightFx.SMOKE.g, KnightFx.SMOKE.b, 0.6))
		ramp.set_color(1, Color(KnightFx.SMOKE.r, KnightFx.SMOKE.g, KnightFx.SMOKE.b, 0.0))
		_smoke.color_ramp = ramp
		_smoke.mesh = KnightFx.puff(0.32)
		_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_smoke)


func _physics_process(delta: float) -> void:
	step(delta)


## One tick of flight. The suite calls this by hand.
func step(delta: float) -> void:
	if spent:
		_fade -= delta
		if _fade <= 0.0:
			queue_free()
		return
	age += delta
	if reflected:
		if was_perfect and shooter != null and is_instance_valid(shooter):
			var h: float = shooter.get(&"homing_height") if &"homing_height" in shooter else 2.0
			var aim := shooter.global_position + Vector3.UP * h
			velocity = turn_toward(velocity, aim - global_position, deg_to_rad(return_turn_deg) * delta)
		_check_shooter()
	elif age > climb_time and target != null and is_instance_valid(target):
		var aim := target.global_position + Vector3.UP * 1.1
		var speed := move_toward(velocity.length(), home_speed, 12.0 * delta)
		velocity = turn_toward(velocity, aim - global_position, deg_to_rad(turn_rate_deg) * delta)
		velocity = velocity.normalized() * speed
	global_position += velocity * delta
	_face()
	if age >= lifetime:
		explode(false)


## A reflected missile reaching the Knight's chest.
func _check_shooter() -> void:
	if shooter == null or not is_instance_valid(shooter) or not shooter.has_method(&"take_hit"):
		return
	var h: float = shooter.get(&"homing_height") if &"homing_height" in shooter else 2.0
	if global_position.distance_to(shooter.global_position + Vector3.UP * h) <= hit_radius:
		shooter.take_hit(damage_perfect if was_perfect else damage_normal,
			&"reflect_perfect" if was_perfect else &"reflect", global_position)
		explode(true)


## `vel` turned toward `want` by at most `max_angle` radians, speed kept.
static func turn_toward(vel: Vector3, want: Vector3, max_angle: float) -> Vector3:
	if want.length() < 0.001 or vel.length() < 0.001:
		return vel
	var a := vel.normalized()
	var b := want.normalized()
	var ang := a.angle_to(b)
	if ang <= max_angle:
		return b * vel.length()
	var axis := a.cross(b)
	if axis.length() < 0.0001:
		axis = a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT)
	return a.rotated(axis.normalized(), max_angle) * vel.length()


## Turned to fly along `direction` at its speed. Called by pilot's reflect zone.
func reflect(direction: Vector3, perfect: bool) -> void:
	reflected = true
	was_perfect = perfect
	velocity = direction.normalized() * maxf(velocity.length(), home_speed)
	age = 0.0


## Hit pilot (he was in its path).
func hit_pilot(pilot: Node) -> void:
	if spent or reflected or pilot == null or not pilot.has_method(&"take_hit"):
		return
	pilot.take_hit(0.0, &"knight_missile", global_position)
	explode(true)


## Done: a small burst, the shard gone, its smoke left to fade.
func explode(burst := true) -> void:
	if spent:
		return
	spent = true
	set_deferred(&"monitoring", false)
	set_deferred(&"monitorable", false)
	remove_from_group(GROUP)
	if _body != null:
		_body.visible = false
	if _smoke != null:
		_smoke.emitting = false
	_fade = 1.0 if _smoke != null else 0.0
	if burst and is_inside_tree():
		KnightFx.burst(get_parent(), global_position, 16, 6.0, KnightFx.RED, 0.16, 0.4)


func _face() -> void:
	if velocity.length() > 0.01 and is_inside_tree():
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT
		look_at(global_position + velocity, up)


func _on_area_entered(area: Area3D) -> void:
	if area.collision_layer & LAYER_HURTBOX:
		var n: Node = area
		while n != null and not n.has_method(&"take_hit"):
			n = n.get_parent()
		hit_pilot(n)


func _on_body_entered(body: Node3D) -> void:
	# Pilot's own body is on the world layer: he is hurt through his hurtbox, so it is no wall.
	if spent or body.is_in_group(&"reflect_target") or body == shooter:
		return
	explode(true)
