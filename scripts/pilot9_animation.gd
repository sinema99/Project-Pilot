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
## 4. The slide TimeScale beside the crouch's, which plays the slide clip at the rate the
##    controller reads its distance curve at and freezes it on the hold pose, and the
##    TimeSeek that starts it on the right frame - see _sync_slide_clip(). RC has no slide;
##    docs/specs/pilot9-slide-hold.md, pilot9-slide-rate.md and pilot9-jump-slide.md.
## 5. The rail's grind/sprint blend, eased off `is_rail_sprinting` - see _drive_rail(). RC has
##    no rail; docs/specs/pilot9-rail-grind.md.
## 6. The vault's TimeScale, held at 0 - see _drive_vault(). RC has no vault;
##    docs/specs/pilot9-vault.md.
## 7. The dash's TimeScale, the sprint cycle sped up - see _drive_dash(). RC has no dash;
##    docs/specs/pilot9-dash.md, "The afterimages".
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

## The TimeSeek in the same blend tree, and the name of the state that holds both. Writing a
## clip second here drags the slide clip onto it on the tree's next process; the node resets
## the parameter to -1 itself, so this is a one-shot rather than a value to hold.
const SLIDE_SEEK := "parameters/slide/SlideSeek/seek_request"
const SLIDE_STATE := &"slide"

## The state the double jump restarts. There is no second-jump clip and no fall -> jump
## transition in the tree, so the air jump replays this one - see _on_air_jumped().
const JUMP_STATE := "jump"

## The Blend2 between the rail's two gear clips, built by
## scripts/pilot9_build_scene.gd::_ensure_rail_state() as RAIL_GEAR_NODE. Same silent-rename
## hazard as CROUCH_SCALE: a stale path and he grinds in the grind clip at both gears.
const RAIL_GEAR := "parameters/rail/RailGear/blend_amount"
## Seconds a full gear change of the clip blend takes - the spec's ~0.15 s crossfade.
const RAIL_GEAR_BLEND_TIME := 0.15

## The `vault` state's TimeScale, built by scripts/pilot9_build_scene.gd::_ensure_vault_state()
## as VAULT_SCALE_NODE. Held at 0: the clip is moved only by the seek pilot9.gd writes each
## physics tick (_seek_vault_clip()), never by the tree's own clock. Same silent-rename hazard
## as CROUCH_SCALE - a stale path and the clip runs at authored speed under a body that is not.
const VAULT_SCALE := "parameters/vault/VaultScale/scale"

## The `dash` state's TimeScale, built by scripts/pilot9_build_scene.gd::_ensure_dash_state() as
## DASH_SCALE_NODE. Same silent-rename hazard as CROUCH_SCALE - a stale path and every ghost in
## the trail has the same legs.
const DASH_SCALE := "parameters/dash/DashScale/scale"

@onready var animation_tree: AnimationTree = $"../AnimationTree"
@onready var playback = animation_tree.get("parameters/playback")
@onready var player: CharacterBody3D = $".."

var target_direction: Vector2 = Vector2.ZERO

## Whether the clip has been dragged onto the controller's clock for the slide currently
## running. Re-armed every frame the `slide` state is not the one playing, so a slide the
## state machine enters twice is seeked twice. See _sync_slide_clip().
var _slide_clip_synced: bool = false

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
	_drive_rail(delta)
	_drive_vault()
	_drive_dash()

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
	# Yaw only, not the mesh's whole basis. Since 2026-09-11 the `character` node also carries
	# a slope pitch and roll (pilot9.gd::_align_model_to_slope), and those tip b.x and b.z out
	# of horizontal - the dots below would then shrink by cos(pitch) and ask the blend space
	# for 0.8 of a run on a 35 degree ramp. Identical to the old value on level ground, and
	# rotation.y is still the exact heading because Godot's Euler order is YXZ, applying the
	# yaw outermost. See docs/specs/pilot9-slope-align.md.
	var b := Basis(Vector3.UP, player.character.rotation.y)
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

## Runs the slide clip at the controller's own rate, and freezes it on the hold pose. The
## controller decides both - `is_slide_holding` is set the frame `_slide_time` reaches the
## baked hold point and cleared on the `crouch` that ends the hold - and this only mirrors
## them onto the tree.
##
## Hard `slide_time_scale`-or-0, deliberately unlike the crouch's eased scale right above.
## The state machine's clip clock and the controller's _slide_time are two separate clocks
## kept in step only by running at the SAME rate, and `slide_time_scale` is that rate on both
## sides: _apply_slide_velocity() advances its clock by delta * it (see _ensure_slide_state in
## scripts/pilot9_build_scene.gd, and docs/specs/pilot9-slide-rate.md). Stopping and starting
## them together is exactly what this is allowed to do, and so is running them both at that
## one rate; running them at rates that differ - or at a rate that varies, like the crouch's -
## is drift the animation never gets back.
##
## The hold pose is the read here, not a cycle, so there is nothing for an ease to smooth
## anyway - freezing the pose he is in IS the animation.
func _drive_slide() -> void:
	if animation_tree.get(SLIDE_SCALE) == null:
		return   # slide state absent - a pilot9.tscn built before _ensure_slide_state
	_sync_slide_clip()
	# Frozen while holding, AND while the state blends out after the slide has ended:
	# is_sliding is already false by then, and letting the clip run would advance it under a
	# cross-fade nothing is driving. On the ordinary exit that parks it on the last frame of
	# the run-out - a standing pose - for the 0.2 s blend into Locomotion, which is what
	# makes `slide -> Locomotion` standing-to-standing. See docs/specs/pilot9-slide-stand.md.
	# Re-entering `slide` restarts the clip from 0, so a scale left at 0 here never carries
	# into the next slide.
	var hold_pose: bool = player.is_slide_holding or not player.is_sliding
	animation_tree.set(SLIDE_SCALE, 0.0 if hold_pose else player.slide_time_scale)

## Drags the slide clip onto `_slide_time` the frame the `slide` state starts playing, and
## is the whole reason the hold freezes on the pose it was baked for.
##
## The two clocks run at one rate (see above) but they do not START together. The controller
## starts its own the frame the slide starts; the state machine starts the clip whenever it
## reaches the state, which is a frame later at best - and far worse coming out of a jump,
## because a fade in progress blocks every transition in the machine until it finishes.
## A buffered slide landing into a 0.2 s fade toward `jump_land` opens the clip a fifth of a
## second late, and at slide_time_scale 2.0 that is 24 frames of clip: the controller hits
## `slide_hold_time` and writes a scale of 0 while the clip is still down at frame 10 or 15,
## and pilot9 holds a pose out of the middle of his entry for the rest of the slide.
## The transition guard in _ensure_slide_state() closes that particular hole; this closes
## every other one, by making the clip's start position something the tree does not get to
## decide.
##
## One seek per entry rather than a correction every frame, deliberately. Once seeked the two
## clocks agree and running at the same rate keeps them agreeing, so there is nothing left to
## correct - and a seek issued every frame would step the clip at the rate this runs at
## instead of letting it play, which is the stutter the whole TimeScale arrangement exists to
## avoid.
##
## Seeking to `_slide_time` is right even when the state opens after the hold has begun:
## the controller freezes that clock at `slide_hold_time`, so a very late entry lands
## straight on the hold pose rather than on the frame it would have reached.
func _sync_slide_clip() -> void:
	if playback == null or animation_tree.get(SLIDE_SEEK) == null:
		return   # a pilot9.tscn built before the TimeSeek - the clip runs unseeked, as it did
	if not (player.is_sliding and playback.get_current_node() == SLIDE_STATE):
		_slide_clip_synced = false
		return
	if _slide_clip_synced:
		return
	_slide_clip_synced = true
	animation_tree.set(SLIDE_SEEK, player.slide_clip_time())

## Crossfades the `rail` state's two clips toward the gear the controller is in. Linear over
## RAIL_GEAR_BLEND_TIME rather than exponential, so a gear change reads as a crossfade that
## finishes instead of one that only ever approaches. Written whether or not the state is playing, so a
## catch already sprinting opens on the sprint clip rather than fading into it.
func _drive_rail(delta: float) -> void:
	var current: Variant = animation_tree.get(RAIL_GEAR)
	if current == null:
		return   # rail state absent - a pilot9.tscn built before _ensure_rail_state
	var target := 1.0 if player.is_rail_sprinting else 0.0
	if not player.is_rail_grinding:
		target = 1.0 if player.sprint_toggled else 0.0
	animation_tree.set(RAIL_GEAR, move_toward(float(current), target,
		delta / RAIL_GEAR_BLEND_TIME))

## Pins the vault clip's own clock at a standstill. pilot9.gd seeks it onto the controller's vault
## time every physics tick, because each vault runs at its own rate (entry speed) with its own
## run-up (distance to the wall) and no fixed timeline could stay under the body. Held while the
## state blends out too, so the fade into Locomotion starts from the touchdown pose.
func _drive_vault() -> void:
	if animation_tree.get(VAULT_SCALE) == null:
		return   # vault state absent - a pilot9.tscn built before _ensure_vault_state
	animation_tree.set(VAULT_SCALE, 0.0)

## The forced sprint cycle's rate for the dash. Written every frame, so the Inspector tunes it live.
func _drive_dash() -> void:
	if animation_tree.get(DASH_SCALE) == null:
		return   # dash state absent - a pilot9.tscn built before _ensure_dash_state
	animation_tree.set(DASH_SCALE, player.dash_anim_speed)
