extends CharacterBody3D

const SPEED = 6.0
const CROUCH_SPEED = 3.0
const JUMP_VELOCITY = 6.36
const ROTATE_SPEED = 10.0
const MOUSE_SENSITIVITY = 0.0025
const PITCH_MIN = -1.3
const PITCH_MAX = 1.3

const STAND_HEIGHT = 1.8
const CROUCH_HEIGHT = 1.0
const CROUCH_LERP_SPEED = 8.0
const RUN_MODEL_LIFT = 0.08

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
var camera_yaw := 0.0
var camera_pitch := 0.0
var current_height := STAND_HEIGHT
var was_moving := false
var jumping := false

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_pitch_node: Node3D = $CameraPivot/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraPivot/CameraPitch/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/CameraPitch/SpringArm3D/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var player_model: Node3D = $PlayerModel
@onready var anim_player: AnimationPlayer = $PlayerModel/AnimationPlayer

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Don't let the camera's spring arm collide with our own body.
	spring_arm.add_excluded_object(get_rid())
	if anim_player.has_animation("RUN LOOP"):
		anim_player.get_animation("RUN LOOP").loop_mode = Animation.LOOP_LINEAR
	if anim_player.has_animation("IDLE"):
		anim_player.get_animation("IDLE").loop_mode = Animation.LOOP_LINEAR
	if anim_player.has_animation("RUN START"):
		anim_player.get_animation("RUN START").loop_mode = Animation.LOOP_NONE
	if anim_player.has_animation("JUMP"):
		anim_player.get_animation("JUMP").loop_mode = Animation.LOOP_NONE

func enter_vehicle(_vehicle: Node3D) -> void:
	visible = false
	collision_shape.disabled = true
	set_physics_process(false)
	set_process_unhandled_input(false)

func exit_vehicle(exit_position: Vector3) -> void:
	global_position = exit_position
	velocity = Vector3.ZERO
	visible = true
	collision_shape.disabled = false
	set_physics_process(true)
	set_process_unhandled_input(true)
	camera.current = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * MOUSE_SENSITIVITY
		camera_pitch = clamp(camera_pitch - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	var is_crouching := Input.is_key_pressed(KEY_CTRL)
	var target_height := CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	current_height = move_toward(current_height, target_height, CROUCH_LERP_SPEED * delta)
	collision_shape.shape.height = current_height
	collision_shape.position.y = current_height / 2.0
	mesh_instance.mesh.height = current_height
	mesh_instance.position.y = current_height / 2.0
	camera_pivot.position.y = current_height

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor() and not is_crouching:
		velocity.y = JUMP_VELOCITY
		jumping = true
		if anim_player.has_animation("JUMP"):
			anim_player.play("JUMP")

	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	var speed := CROUCH_SPEED if is_crouching else SPEED
	var cam_basis := camera_pivot.global_transform.basis
	var direction := cam_basis * Vector3(input_dir.x, 0, input_dir.y)

	if direction.length() > 0.01:
		direction = direction.normalized()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), ROTATE_SPEED * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	# --- Animation ---
	# JUMP is a one-shot front flip: it starts on the Space press (above). If it finishes
	# before we land, AnimationPlayer holds its last frame because we don't start another
	# clip while `jumping` is true. Landing (on floor, no longer rising) ends the jump state.
	if jumping and is_on_floor() and velocity.y <= 0.0:
		jumping = false

	var moving := is_on_floor() and direction.length() > 0.01
	if not jumping:
		if moving and not was_moving:
			anim_player.play("RUN START")
			anim_player.queue("RUN LOOP")
		elif moving and anim_player.current_animation != "RUN START":
			anim_player.play("RUN LOOP")
		elif not moving and is_on_floor():
			anim_player.play("IDLE")
	# Falling without jumping (walked off a ledge) has no clip - holds the current pose.
	was_moving = moving
	var is_running := moving

	move_and_slide()

	camera_pivot.rotation.y = camera_yaw - rotation.y
	camera_pitch_node.rotation.x = camera_pitch

	# Lower the model root to match the crouched collision/camera height (feet may clip slightly - acceptable jank).
	# Lift slightly while running since the RUN animation's foot-down pose sits lower than IDLE and clips the ground.
	player_model.position.y = current_height - STAND_HEIGHT + (RUN_MODEL_LIFT if is_running else 0.0)
