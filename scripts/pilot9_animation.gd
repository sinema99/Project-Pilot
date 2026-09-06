## A copy of addons/real-controller/animation.gd (fdemir/real-controller, MIT). Feeds
## pilot9's AnimationTree blend positions each frame from the controller's input_dir /
## is_walking / is_sprinting. See docs/specs/pilot9-real-controller.md.
##
## One addition to stock RC, at the bottom of _process: the crouch TimeScale. RC has no
## crouch. Everything above it is unchanged.
extends Node

## The scale on the `crouch` state's TimeScale node, built by
## scripts/pilot9_build_scene.gd::_ensure_crouch_state(). AnimationTree.set() stores an
## unknown parameter path silently rather than erroring, so a rename on either side stops
## the crouch cycle advancing with nothing in the log - hence the const, and
## tests/test_pilot9_crouch.gd asserting the two halves still meet.
const CROUCH_SCALE := "parameters/crouch/CrouchScale/scale"

## Below this the eased scale is snapped to a dead stop. lerp() only ever approaches its
## target, and a crouch clip creeping forward at 0.3% speed reads as a drift, not a hold.
const CROUCH_SCALE_EPSILON := 0.01

@onready var animation_tree: AnimationTree = $"../AnimationTree"
@onready var playback = animation_tree.get("parameters/playback")
@onready var player: CharacterBody3D = $".."

var target_direction: Vector2 = Vector2.ZERO

func _process(delta: float) -> void:
	if player == null or animation_tree == null:
		return

	var is_sprinting = player.is_sprinting
	var is_walking = player.is_walking

	var target_blend = Vector2(player.input_dir.x, -player.input_dir.y)

	# Update blend positions for all movement types
	var current_walk = animation_tree.get("parameters/Locomotion/WalkBlend/blend_position")
	var smooth_walk = current_walk.lerp(target_blend, delta * 10.0)
	animation_tree.set("parameters/Locomotion/WalkBlend/blend_position", smooth_walk)

	var current_run = animation_tree.get("parameters/Locomotion/RunBlend/blend_position")
	var smooth_run = current_run.lerp(target_blend, delta * 10.0)
	animation_tree.set("parameters/Locomotion/RunBlend/blend_position", smooth_run)

	var current_sprint = animation_tree.get("parameters/Locomotion/SprintBlend/blend_position")
	var smooth_sprint = current_sprint.lerp(target_blend, delta * 10.0)
	animation_tree.set("parameters/Locomotion/SprintBlend/blend_position", smooth_sprint)

	var target_walk_run = 0.0 if is_walking else 1.0
	var current_walk_run = animation_tree.get("parameters/Locomotion/WalkRunBlend/blend_amount")
	var smooth_walk_run = lerp(current_walk_run, target_walk_run, delta * 8.0)
	animation_tree.set("parameters/Locomotion/WalkRunBlend/blend_amount", smooth_walk_run)

	var is_moving_backward = player.input_dir.y > 0
	var target_speed = 1.0 if (is_sprinting and not is_moving_backward) else 0.0
	var current_speed = animation_tree.get("parameters/Locomotion/SpeedBlend/blend_amount")
	var smooth_speed = lerp(current_speed, target_speed, delta * 8.0)
	animation_tree.set("parameters/Locomotion/SpeedBlend/blend_amount", smooth_speed)

	_drive_crouch(delta)

## Added on top of RC. pilot9 has a crouch WALK clip and no crouch IDLE, so the state plays
## the one cycle through a TimeScale and this eases the scale to 0 when he is not actually
## moving: he holds the pose he stopped on instead of marching on the spot. Crouched, the
## state owns him whether or not he moves - the scale is about the cycle, not the state.
func _drive_crouch(delta: float) -> void:
	var current: Variant = animation_tree.get(CROUCH_SCALE)
	if current == null:
		return   # crouch state absent - an old pilot9.tscn built before _ensure_crouch_state
	var target := 1.0 if (player.is_crouching and player.input_dir != Vector2.ZERO) else 0.0
	var smooth: float = lerp(float(current), target, delta * 8.0)
	if smooth < CROUCH_SCALE_EPSILON:
		smooth = 0.0
	animation_tree.set(CROUCH_SCALE, smooth)
