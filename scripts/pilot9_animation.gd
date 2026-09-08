## A copy of addons/real-controller/animation.gd (fdemir/real-controller, MIT). Feeds
## pilot9's AnimationTree blend positions each frame from the controller's input_dir /
## is_walking / is_sprinting. See docs/specs/pilot9-real-controller.md.
##
## Four changes from stock RC:
##
## 1. The blend position is the travel direction in BODY space, not input space - see
##    _travel_blend(). Required by turn-to-face; docs/specs/pilot9-turn-to-face.md.
## 2. The crouch TimeScale at the bottom of _process. RC has no crouch.
## 3. The `air_jumped` listener. RC has no double jump.
## 4. The slide TimeScale beside the crouch's, which freezes the slide clip on its hold
##    pose. RC has no slide; docs/specs/pilot9-slide-hold.md.
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

## The `slide` state's TimeScale, built by scripts/pilot9_build_scene.gd::_ensure_slide_state().
## Same silent-rename hazard as CROUCH_SCALE, with a different symptom: the clip would run
## past the hold pose and play itself out while the controller sat frozen at the hold frame,
## so he would come up out of the slide and then keep travelling flat on his feet.
const SLIDE_SCALE := "parameters/slide/SlideScale/scale"

## The state the double jump restarts. There is no second-jump clip and no fall -> jump
## transition in the tree, so the air jump replays this one - see _on_air_jumped().
const JUMP_STATE := "jump"

@onready var animation_tree: AnimationTree = $"../AnimationTree"
@onready var playback = animation_tree.get("parameters/playback")
@onready var player: CharacterBody3D = $".."

var target_direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	if player != null and player.has_signal("air_jumped"):
		player.air_jumped.connect(_on_air_jumped)

## Restarts the jump clip on an air jump. playback.start() rather than travel(): a travel
## to a state the tree is already in is a no-op, and from `fall` there is no transition to
## take. start() re-enters `jump` from frame 0 from wherever he is, which is the whole ask -
## the cut is hard, and a hard cut is what makes the second jump read as a second jump.
func _on_air_jumped() -> void:
	if playback == null:
		return
	playback.start(JUMP_STATE)

func _process(delta: float) -> void:
	if player == null or animation_tree == null:
		return

	var is_sprinting = player.is_sprinting
	var is_walking = player.is_walking

	var target_blend := _travel_blend()

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

	# Facing travel there is no backward, so the gate that suppressed a sprint while
	# reversing only means anything in strafe mode.
	var is_moving_backward = player.input_dir.y > 0
	var target_speed = 1.0 if (is_sprinting and (player.face_travel_direction or not is_moving_backward)) else 0.0
	var current_speed = animation_tree.get("parameters/Locomotion/SpeedBlend/blend_amount")
	var smooth_speed = lerp(current_speed, target_speed, delta * 8.0)
	animation_tree.set("parameters/Locomotion/SpeedBlend/blend_amount", smooth_speed)

	_drive_crouch(delta)
	_drive_slide()

## The blend position for all three locomotion blend spaces: where he is travelling,
## expressed in his own frame. Forward sits at (0, 1) in every one of them.
##
## Stock RC feeds input space, which is the same thing only while the body is welded to
## camera-back. Facing travel, the body IS the frame: steady state this reads (0, 1) and
## only run_forward plays, and the sideways clips come alive exactly during a pivot, while
## the body still lags the heading. That lean is what keeps a hard 180 from reading as a
## skate, and it is the reason the blend is not simply pinned to forward.
##
## The negated X is not a typo. pilot9's mesh faces its own +Z but its local +X points to
## his LEFT - the 180 degree basis on the `character` node - so travel toward his right is
## -basis.x, and run_right sits at +1. Measured, not derived; test_pilot9_turn_to_face.gd
## pins the sign, because getting it backwards leans him into every turn the wrong way and
## looks like a bad blend rather than a wrong sign.
##
## Local basis rather than global on purpose: only the mesh child rotates, never the
## CharacterBody, so the two agree - and local is readable without the node being in a tree,
## which is what makes this testable headlessly.
func _travel_blend() -> Vector2:
	if not player.face_travel_direction:
		return Vector2(player.input_dir.x, -player.input_dir.y)
	# `direction` and `input_strength` are last frame's when frozen (handle_frozen_movement
	# clears input_dir and nothing else), so without this he keeps running on the spot.
	if player.input_dir == Vector2.ZERO:
		return Vector2.ZERO
	var b: Basis = player.character.transform.basis
	# input_strength, not direction's own length: it is already clamped to 1, so a keyboard
	# diagonal lands on the unit circle where the clips are instead of sqrt(2) past it.
	return Vector2(-player.direction.dot(b.x), player.direction.dot(b.z)) * player.input_strength


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

## Freezes the slide clip on its hold pose, and nothing else. The controller decides when -
## `is_slide_holding` is set the frame `_slide_time` reaches the baked hold point and
## cleared on the `crouch` that ends the hold - and this only mirrors it onto the tree.
##
## Hard 0/1, deliberately unlike the crouch's eased scale right above. The state machine's
## clip clock and the controller's _slide_time are two separate clocks kept in step only by
## both being real time, so anything between 0 and 1 is drift the animation never gets back
## (see _ensure_slide_state in scripts/pilot9_build_scene.gd). Stopping and starting them
## together is exactly what this is allowed to do; running them at different rates is not.
##
## The hold pose is the read here, not a cycle, so there is nothing for an ease to smooth
## anyway - freezing the pose he is in IS the animation.
func _drive_slide() -> void:
	if animation_tree.get(SLIDE_SCALE) == null:
		return   # slide state absent - a pilot9.tscn built before _ensure_slide_state
	# Frozen while holding, AND while the state blends out after a `crouch` ended the slide:
	# is_sliding is already false by then, and letting the clip run would play a slice of the
	# run-out into the cross-fade. The slide -> crouch exit is meant to be pose-to-pose off
	# the held frame - see docs/specs/pilot9-slide-crouch.md. Re-entering `slide` restarts
	# the clip from 0, so a scale left at 0 here never carries into the next slide.
	var hold_pose: bool = player.is_slide_holding or not player.is_sliding
	animation_tree.set(SLIDE_SCALE, 0.0 if hold_pose else 1.0)
