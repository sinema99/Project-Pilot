extends CharacterBody3D

const SPEED = 6.0
const CROUCH_SPEED = 3.0
const JUMP_VELOCITY = 4.5
const ROTATE_SPEED = 10.0
const MOUSE_SENSITIVITY = 0.0025
const PITCH_MIN = -1.3
const PITCH_MAX = 1.3

const STAND_CAMERA_HEIGHT = 3.7
const CROUCH_CAMERA_HEIGHT = 2.5
const CROUCH_LERP_SPEED = 8.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var pilot: Node3D = null
var player_in_range: Node3D = null
var camera_yaw := 0.0
var camera_pitch := 0.0
var current_camera_height := STAND_CAMERA_HEIGHT

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_pitch_node: Node3D = $CameraPivot/CameraPitch
@onready var camera: Camera3D = $CameraPivot/CameraPitch/Camera3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var exit_point: Marker3D = $ExitPoint
@onready var prompt_label: Label = $UI/PromptLabel

func _ready() -> void:
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_vehicle"):
		player_in_range = body
		_update_prompt()

func _on_body_exited(body: Node3D) -> void:
	if body == player_in_range:
		player_in_range = null
		_update_prompt()

func _update_prompt() -> void:
	if pilot != null:
		prompt_label.text = "Press F to exit"
		prompt_label.visible = true
	elif player_in_range != null:
		prompt_label.text = "Press F to enter"
		prompt_label.visible = true
	else:
		prompt_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if pilot != null and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * MOUSE_SENSITIVITY
		camera_pitch = clamp(camera_pitch - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		if pilot == null and player_in_range != null:
			_enter_mech()
		elif pilot != null:
			_exit_mech()

func _enter_mech() -> void:
	pilot = player_in_range
	pilot.enter_vehicle(self)
	camera.current = true
	_update_prompt()

func _exit_mech() -> void:
	var former_pilot := pilot
	pilot = null
	former_pilot.exit_vehicle(exit_point.global_position)
	_update_prompt()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if pilot == null:
		velocity.x = move_toward(velocity.x, 0, SPEED * delta)
		velocity.z = move_toward(velocity.z, 0, SPEED * delta)
		move_and_slide()
		return

	var is_crouching := Input.is_key_pressed(KEY_CTRL)
	var target_camera_height := CROUCH_CAMERA_HEIGHT if is_crouching else STAND_CAMERA_HEIGHT
	current_camera_height = move_toward(current_camera_height, target_camera_height, CROUCH_LERP_SPEED * delta)
	camera_pivot.position.y = current_camera_height

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor() and not is_crouching:
		velocity.y = JUMP_VELOCITY

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

	move_and_slide()

	camera_pivot.rotation.y = camera_yaw - rotation.y
	camera_pitch_node.rotation.x = camera_pitch
