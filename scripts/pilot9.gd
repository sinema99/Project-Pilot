## pilot9's controller. A copy of addons/real-controller/character.gd
## (fdemir/real-controller, MIT) with three changes, each marked at its site:
##
## 1. Every `Input.mouse_mode` write is removed. Cursor state is owned by
##    scripts/ui/ui_manager.gd project-wide, and RC grabbing the mouse on _ready /
##    on click / on _exit_tree fought it. The ESC and left-click handlers in
##    _unhandled_input existed only to toggle capture, so they go with it; the
##    mouse-look maths they wrapped stays.
## 2. Controller pitch is subtracted, not added, in _handle_controller_camera -
##    stock disagreed in sign with its own mouse path and inverted the right stick.
## 3. Character rotation is gated on movement input in _handle_character_rotation,
##    so the camera can orbit to pilot9's front while he stands still.
##
## Nothing else is ported - see docs/specs/pilot9-real-controller.md ("Stock Real
## Controller feel").
##
## Added on top of RC, which has no crouch at all: the `crouch` toggle (C / controller B)
## and `crouch_speed`. The AnimationTree reads `is_crouching` directly through
## advance_expression, so it is a plain property and not a setter - see
## scripts/pilot9_build_scene.gd::_ensure_crouch_state().
##
## Requires a CameraPivot (Node3D) and Camera3D as children, and a character mesh as a child node.
extends CharacterBody3D

enum CameraMode {
	FIRST_PERSON,
	THIRD_PERSON
}

## Node References
## -----------------------------------------------------------------------------
## These nodes must exist in the scene tree for the controller to work properly.

@onready var camera_pivot: Node3D = %CameraPivot
@onready var camera_3d: Camera3D = %Camera3D
@onready var spring_arm: SpringArm3D = camera_pivot.get_node("SpringArm3D")
@onready var character: Node3D = $character

## Movement Settings
## -----------------------------------------------------------------------------
## Configure the character's movement speed and jump behavior.

@export_group("Movement")
@export_range(0.1, 20.0, 0.1, "or_greater") var speed: float = 5.0
## Speed when walking. Should be lower than normal speed.
@export_range(0.1, 10.0, 0.1, "or_greater") var walk_speed: float = 2.5
## Speed multiplier when sprinting. Should be higher than normal speed.
@export_range(0.1, 30.0, 0.1, "or_greater") var sprint_speed: float = 8.0
## Vertical velocity applied when jumping.
@export_range(1.0, 20.0, 0.1) var jump_velocity: float = 4.5
@export var can_walk: bool = true
## Speed while crouched. Slower than walk_speed - the crouch clip's own cadence is what
## this is matched against, so changing one without the other makes him skate or moonwalk.
@export_range(0.1, 10.0, 0.1, "or_greater") var crouch_speed: float = 1.6

## Camera Settings
## -----------------------------------------------------------------------------
## Adjust camera sensitivity and rotation limits.

@export_group("Camera")
## Mouse sensitivity for camera rotation. Higher values = faster rotation.
@export_range(0.0, 1.0, 0.001) var mouse_sensitivity: float = 0.005
## Enable controller support for camera look.
@export var controller_support: bool = true
## Controller stick sensitivity for camera rotation.
@export_range(0.1, 10.0, 0.1) var controller_sensitivity: float = 2.0
## Maximum vertical camera tilt angle in radians (prevents over-rotation).
@export_range(0.0, 1.57, 0.01) var tilt_limit: float = deg_to_rad(75)
## Speed at which the character mesh rotates to face movement direction.
@export_range(0.1, 50.0, 0.1) var rotation_speed: float = 10.0
## Camera mode: FIRST_PERSON or THIRD_PERSON.
@export var camera_mode: CameraMode = CameraMode.THIRD_PERSON:
	set(value):
		camera_mode = value
		if is_node_ready():
			_update_camera_mode()
## Camera distance (SpringArm length) for third-person mode.
@export_range(0.0, 10.0, 0.1) var camera_distance: float = 3.5
## Speed at which the camera transitions between modes.
@export_range(1.0, 20.0, 0.1) var camera_transition_speed: float = 8.0
## Allow switching between camera modes with V key.
@export var allow_camera_mode_switch: bool = false

var input_dir: Vector2 = Vector2.ZERO
var input_strength: float = 0.0
var direction: Vector3 = Vector3.ZERO
var is_sprinting: bool = false
var is_walking: bool = false
var is_jumping: bool = false
## Toggled by the `crouch` action, never held. Read every frame by the AnimationTree's
## advance expressions and by _apply_movement.
var is_crouching: bool = false

# Freeze the character. It may be useful when you want to pause the character.
var frozen: bool = false

var target_camera_distance: float = 3.5
var is_transitioning_camera: bool = false

func _ready() -> void:
	target_camera_distance = 0.0 if camera_mode == CameraMode.FIRST_PERSON else camera_distance
	spring_arm.spring_length = target_camera_distance
	if character:
		character.visible = camera_mode == CameraMode.THIRD_PERSON

func _physics_process(delta: float) -> void:
	_handle_crouch_toggle()
	_handle_gravity_and_jump(delta)
	_handle_camera_transition(delta)
	_handle_controller_camera(delta)

	if frozen:
		handle_frozen_movement()
		move_and_slide()
		return

	_handle_movement_input()
	if camera_mode == CameraMode.THIRD_PERSON:
		_handle_character_rotation(delta)
	_apply_movement()
	move_and_slide()

func handle_frozen_movement() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	input_dir = Vector2.ZERO
	is_sprinting = false
	is_walking = false

## Toggles the crouch. Read here rather than in _input so it lands on the same frame as
## every other movement input; the AnimationTree samples is_crouching after this.
func _handle_crouch_toggle() -> void:
	if frozen:
		return
	if Input.is_action_just_pressed("crouch"):
		is_crouching = not is_crouching

## Handles gravity application and jump mechanics.
func _handle_gravity_and_jump(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
		is_jumping = velocity.y > 0
	else:
		is_jumping = false

	if not frozen and Input.is_action_just_pressed("jump") and is_on_floor():
		# Jumping stands him up rather than being swallowed by the crouch. There is no
		# crouch-jump clip, and a dead jump key reads as broken input.
		is_crouching = false
		velocity.y = jump_velocity
		is_jumping = true

## Processes movement input and calculates movement direction relative to camera.
func _handle_movement_input() -> void:
	input_dir = Input.get_vector("left", "right", "forward", "backward")
	input_strength = minf(input_dir.length(), 1.0)
	
	var camera_basis = Transform3D(Basis(Vector3.UP, camera_pivot.rotation.y), Vector3.ZERO).basis
	direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

## Rotates the character mesh to face the movement direction smoothly.
##
## Deviation from stock RC: the lerp is gated on movement input. Stock welds the
## body to camera-back every frame, so orbiting just dragged pilot9 around with
## the camera and his face was unreachable. Standing still he now holds his world
## facing and the camera orbits freely around him; the frame input resumes he
## re-welds to camera-back at rotation_speed. Nothing else changes on re-entry -
## direction is already camera-relative in _handle_movement_input, so he walks off
## camera-forward immediately and the body catches up mid-stride. That re-weld is
## what keeps backing up and strafing reading against the camera rather than
## against wherever he happened to be left pointing.
func _handle_character_rotation(delta: float) -> void:
	if camera_mode == CameraMode.FIRST_PERSON:
		return
	if input_dir == Vector2.ZERO:
		return
	character.rotation.y = lerp_angle(character.rotation.y, camera_pivot.rotation.y + PI, rotation_speed * delta)

## Handles controller stick input for camera rotation.
func _handle_controller_camera(delta: float) -> void:
	if not controller_support or frozen:
		return
	if not InputMap.has_action("look_left") or not InputMap.has_action("look_right") or not InputMap.has_action("look_up") or not InputMap.has_action("look_down"):
		return
	var look_dir = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_dir != Vector2.ZERO:
		camera_pivot.rotation.y -= look_dir.x * controller_sensitivity * delta
		camera_pivot.rotation.x -= look_dir.y * controller_sensitivity * delta
		camera_pivot.rotation.x = clampf(camera_pivot.rotation.x, -tilt_limit, tilt_limit)

## Handles smooth camera transition between modes.
func _handle_camera_transition(delta: float) -> void:
	spring_arm.spring_length = lerp(spring_arm.spring_length, target_camera_distance, camera_transition_speed * delta)
	
	if character and camera_distance > 0.0:
		var transition_progress = spring_arm.spring_length / camera_distance
		var visibility_threshold = 0.3
		character.visible = transition_progress > visibility_threshold
	elif character:
		character.visible = camera_mode == CameraMode.THIRD_PERSON

## Updates camera mode (sets target for smooth transition).
func _update_camera_mode() -> void:
	if camera_mode == CameraMode.FIRST_PERSON:
		target_camera_distance = 0.0
	else:
		target_camera_distance = camera_distance

## Applies horizontal movement velocity based on input and sprint/walk state.
func _apply_movement() -> void:
	var is_moving = input_dir != Vector2.ZERO and is_on_floor()
	# Crouch outranks both gaits: it owns the whole locomotion state, so leaving either
	# flag set would keep pilot9_animation.gd feeding the walk/run blends underneath it.
	is_sprinting = Input.is_action_pressed("sprint") and is_moving and not Input.is_action_pressed("walk") and not is_crouching
	is_walking = Input.is_action_pressed("walk") and is_moving and not Input.is_action_pressed("sprint") and can_walk and not is_crouching
	
	var current_speed: float
	if is_crouching:
		current_speed = crouch_speed
	elif is_sprinting:
		current_speed = sprint_speed
	elif is_walking and can_walk:
		current_speed = walk_speed
	else:
		current_speed = speed
	
	if direction:
		velocity.x = direction.x * current_speed * input_strength
		velocity.z = direction.z * current_speed * input_strength
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

## Handles mouse input for camera rotation with tilt limits.
func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return

	if event is InputEventMouseMotion:
		camera_pivot.rotation.x -= event.relative.y * mouse_sensitivity
		camera_pivot.rotation.x = clampf(camera_pivot.rotation.x, -tilt_limit, tilt_limit)
		camera_pivot.rotation.y += -event.relative.x * mouse_sensitivity

func _input(event: InputEvent) -> void:
	if InputMap.has_action("camera_mode_switch") and event.is_action_pressed("camera_mode_switch") and allow_camera_mode_switch:
		camera_mode = CameraMode.THIRD_PERSON if camera_mode == CameraMode.FIRST_PERSON else CameraMode.FIRST_PERSON
		_update_camera_mode()