## pilot9's controller. A copy of addons/real-controller/character.gd
## (fdemir/real-controller, MIT) with four changes, each marked at its site:
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
## 4. He turns to face where he is travelling rather than welding to camera-back, so
##    there is no strafing and no backing up - `face_travel_direction`, in
##    _handle_character_rotation. See docs/specs/pilot9-turn-to-face.md.
##
## Nothing else is ported - see docs/specs/pilot9-real-controller.md ("Stock Real
## Controller feel").
##
## Added on top of RC, which has no crouch at all: the `crouch` toggle (C / controller B)
## and `crouch_speed`. The AnimationTree reads `is_crouching` directly through
## advance_expression, so it is a plain property and not a setter - see
## scripts/pilot9_build_scene.gd::_ensure_crouch_state().
##
## Also changed from stock RC: `sprint` is a toggle, not a hold - see _update_sprint_toggle().
## Letting go of sprint mid-jump should not drop him out of a run, and a jump buffered into a
## slide needs the sprint intent to outlive the button.
##
## Also added: the double jump. `air_jumps` extra jumps while airborne, spent by the same
## `jump` action - see _handle_gravity_and_jump(). The tree has no second-jump clip and no
## fall -> jump transition, so the `air_jumped` signal is what restarts the existing jump
## clip from frame 0; scripts/pilot9_animation.gd is its only listener.
##
## Also added: the slide. Same `crouch` key, claimed instead of the toggle when he is
## sprinting - see _handle_crouch_and_slide() and docs/specs/pilot9-slide.md. Its motion
## is not a speed constant; it is the clip's own forward-distance curve, baked onto
## `slide_motion` by the builder and differentiated here.
##
## Also added: the ledge mantle. Automatic - airborne with a ledge in probe range starts it,
## no button - see _handle_gravity_and_jump() and docs/specs/pilot9-climb.md. Unlike every
## other move here it is POSITION driven: the body is written straight onto a path sampled
## off `climb_motion_y` / `climb_motion_z` with collision off, and move_and_slide() is not
## called for its duration.
##
## Requires a CameraPivot (Node3D) and Camera3D as children, and a character mesh as a child node.
extends CharacterBody3D

## Emitted when a second jump is taken with his feet already off the floor - an air jump. The AnimationTree is already
## in `jump` or `fall` when it happens, and neither re-enters `jump` on its own, so the
## clip is restarted from the listener rather than by a transition condition.
signal air_jumped

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
## Toggled off for the mantle's duration - see _start_climb(). RC never needed a
## reference to its own shape; the climb does, because a body on a scripted path over
## an edge has to stop colliding with the edge.
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

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
@export_range(1.0, 20.0, 0.1) var jump_velocity: float = 6.0
## Extra jumps available while airborne, on top of the one off the floor. 1 is a double
## jump; 0 is stock Real Controller. Each costs the full `jump_velocity`, replacing the
## fall rather than adding to it, so a second jump taken late reads the same as one taken
## early. Refilled on every grounded frame - see _handle_gravity_and_jump().
@export_range(0, 5, 1) var air_jumps: int = 1
@export var can_walk: bool = true
## Speed while crouched. Slower than walk_speed - the crouch clip's own cadence is what
## this is matched against, so changing one without the other makes him skate or moonwalk.
@export_range(0.1, 10.0, 0.1, "or_greater") var crouch_speed: float = 1.6

## Slide Settings
## -----------------------------------------------------------------------------
## The slide is `crouch` pressed at a sprint. Unlike every other move here it has no speed
## of its own: `slide_motion` IS the animation's forward travel, baked out of the clip by
## scripts/pilot9_build_scene.gd, and _apply_slide_velocity() differentiates it. That is
## what keeps his feet with the floor through the run-in and the run-out, which are the
## only two windows of the clip where a mismatch would show. See docs/specs/pilot9-slide.md.

@export_group("Slide")
@export var can_slide: bool = true
## The one dial worth turning. Multiplies distance without touching duration, so 1.5 is a
## longer slide *and* a faster one over the same 1.25 s. 1.0 is the clip as the builder
## trimmed it - see _trim_slide() in scripts/pilot9_build_scene.gd.
##
## The builder never writes this, so a value tuned in the inspector survives a rig swap -
## unlike the three baked properties below, which it overwrites on every sync.
@export_range(0.1, 3.0, 0.05) var slide_scale: float = 1.0
## Kept short deliberately: without it, sprint held and `crouch` tapped re-enters the slide
## on the frame it leaves and he never stands up.
@export_range(0.0, 2.0, 0.05) var slide_cooldown: float = 0.4
## A `crouch` press made while airborne is remembered until he lands and spent the instant
## he does, so a jump into a slide only needs the press somewhere in the air - not on the
## single frame of touchdown. There is no timed window and no rise/fall gate: press `crouch`
## any time before landing. The remembered press becomes a slide only if the slide's normal
## conditions still hold on the landing frame (sprint on, stick pushed, off cooldown);
## otherwise it evaporates without toggling the crouch. `false` turns this off and an air
## press falls straight back to the crouch toggle. See docs/specs/pilot9-jump-slide.md.
@export var can_buffer_slide: bool = true

## BAKED - written by scripts/pilot9_build_scene.gd::_ensure_slide_motion() from the clip
## itself. Distance travelled as a fraction of the total (Y) against time as a fraction of
## the clip (X), both 0..1. Editing these by hand is wasted work; the next sync rewrites them.
@export var slide_motion: Curve
## BAKED - the slide clip's length in seconds. The state machine plays the clip on its own
## clock and this one runs in _physics_process; they agree only because both are real time,
## which is why there is no TimeScale anywhere near the `slide` state.
@export var slide_duration: float = 0.0
## BAKED - metres the clip's Hips travel forward, the scale `slide_motion` is normalised by.
@export var slide_distance: float = 0.0

## Climb Settings
## -----------------------------------------------------------------------------
## The ledge mantle: automatic when airborne with a ledge in probe range - no button. Two
## raycasts (fired every airborne frame) find the lip, the body is snapped so the clip's
## frame-1 hands meet it, and the whole 1.15 s is then driven by position off the baked
## curves with collision disabled. Not cancellable. See docs/specs/pilot9-climb.md.
##
## Every probe number below is a tunable starting value, not a measurement. The two that
## have to agree with each other are `climb_probe_height` and `climb_band_min`: the forward
## ray has to pass UNDER the lip it is looking for, so the ray height must stay below the
## shallowest ledge the band accepts, or the ray sails over the top of every wall in range.

@export_group("Climb")
@export var can_climb: bool = true
## Height above his feet the forward (wall) ray is cast from. Must be under
## `climb_band_min` - see the note above.
@export_range(0.1, 2.0, 0.05) var climb_probe_height: float = 0.85
## How far past himself the forward ray reaches. Grab range, measured from his centre, so
## it is spending most of itself on the capsule radius (0.34 m).
@export_range(0.1, 2.0, 0.05) var climb_probe_reach: float = 0.6
## The mantle band, in metres of lip height above his feet at the moment he presses `jump`.
## THIS is the whole filter - there is no climbable layer and no tag, so any static
## collider with an up-facing top in the band offers a mantle. Wide enough that the press
## does not have to be frame-perfect; narrow enough that the tall blocks in TrainingV
## (4.2 / 8.6 / 13.3 m) are only ever in band from the top of a double jump.
@export_range(0.2, 3.0, 0.05) var climb_band_min: float = 0.9
@export_range(0.2, 3.0, 0.05) var climb_band_max: float = 1.9
## How far off level the lip may be and still be a floor to land on, in degrees.
@export_range(0.0, 60.0, 1.0) var climb_max_lip_slope: float = 30.0
## Clearance demanded above the spot he would land on. He arrives standing, and planting
## him inside a ceiling is an uglier failure than refusing the mantle.
@export_range(0.5, 3.0, 0.1) var climb_headroom: float = 2.0

## BAKED - written by scripts/pilot9_build_scene.gd::_ensure_climb_motion() off climb_up
## itself. The clip's Hips travel as two normalised curves, time fraction in (0..1),
## distance fraction out. Y overshoots 1.0 near the top - that is the pull over the lip
## before he settles onto it, and clamping it flattens the one thing the arc is for. Z
## goes briefly NEGATIVE at the start - the swing back before the pull.
@export var climb_motion_y: Curve
@export var climb_motion_z: Curve
## BAKED - climb_up's raw (authored) length in seconds. The state machine plays the clip on
## its own clock and _climb_time runs in _physics_process; they agree because BOTH are scaled
## by `climb_speed` off real time - see that dial and docs/specs/pilot9-climb.md.
@export var climb_duration: float = 0.0
## BAKED - how much faster than authored the whole mantle plays (1.5 = one and a half times).
## Applied to both clocks: the clip through the `climb` state's custom timeline (built by
## _ensure_climb_state) and the path through _apply_climb_motion advancing _climb_time by
## delta * climb_speed. Baked rather than a live dial because a value the tree was not built
## against parts the two clocks with nothing in the log.
@export var climb_speed: float = 1.5
## BAKED - metres the body rises over the mantle: the height of the frame-1 hands above the
## ground his feet stand on at the end of the clip. NOT the clip's own Hips travel, which
## is 1.89 m and describes a ledge this pose does not actually reach - see the long note on
## _ensure_climb_motion() in the builder.
@export var climb_rise: float = 0.0
## BAKED - metres the body travels forward over the mantle, front of the wall to standing.
@export var climb_reach: float = 0.0
## BAKED - metres in from the lip his feet land, taken from the clip's own forward Hips
## travel. This is the level-design contract: geometry with a top narrower than this has
## nothing to stand on.
@export var climb_inset: float = 0.0
## BAKED - where climb_up's frame-1 hand contact sits relative to his feet, in his own
## frame. The entry snap places him by subtracting this from the detected lip, which is
## what makes the hands meet the edge every time. Measured off the clip, never guessed.
@export var climb_hand_offset: Vector3 = Vector3.ZERO
## BAKED - where his ground contact sits relative to his feet on the clip's last frame,
## same frame and same job at the other end: the exit snap subtracts it from the landing
## point so his soles finish on the platform rather than through it.
@export var climb_foot_offset: Vector3 = Vector3.ZERO

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
## Speed at which the character mesh rotates to face movement direction. With
## face_travel_direction on this is the pivot dial: it is what a hard 180 costs, and the
## window during which he is still facing the old heading while already moving on the new
## one. Roughly a quarter second at 10.0.
@export_range(0.1, 50.0, 0.1) var rotation_speed: float = 10.0
## Turn the body toward wherever it is travelling instead of welding it to camera-back.
##
## This is the whole strafe seam. `true` (shipping): he always runs forward relative to
## himself, so a forward-only clip - the crouch walk, and whatever follows it - is correct
## in every direction, at the cost of RC's strafing and backing up. `false`: exactly stock
## Real Controller, camera-relative, directional clips and all.
##
## scripts/pilot9_animation.gd branches on this too, and nothing else does. An aim mode or
## a hold-to-strafe modifier is this flag and nothing more.
@export var face_travel_direction: bool = true
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

## How far past the wall face the down ray is cast, so it lands on the platform rather than
## on the edge itself - a ray aimed exactly at an edge is a coin toss.
const CLIMB_LIP_PROBE_INSET := 0.4
## Slack on both ends of the down ray, and the foot of the headroom ray, so a lip sitting
## exactly on a band boundary is still found and the headroom ray does not start inside the
## platform it is standing on.
const CLIMB_PROBE_MARGIN := 0.15

var input_dir: Vector2 = Vector2.ZERO
var input_strength: float = 0.0
var direction: Vector3 = Vector3.ZERO
## Sprint is a toggle, not a hold: `sprint` pressed flips this, `walk` pressed clears it.
## Flipped in _update_sprint_toggle() before anything reads it. `is_sprinting` below is this
## AND actually moving AND not crouched; this is the raw intent, and it survives a jump.
var sprint_toggled: bool = false
var is_sprinting: bool = false
var is_walking: bool = false
var is_jumping: bool = false
## Air jumps not yet spent this flight. Refilled to `air_jumps` on every grounded frame,
## so coyote-style leniency is not a thing here: leave the floor and the count is what it
## was on the last frame he touched it.
var _air_jumps_left: int = 0
## Toggled by the `crouch` action, never held. Read every frame by the AnimationTree's
## advance expressions and by _apply_movement.
var is_crouching: bool = false
## True for the length of the slide clip. Read by the AnimationTree's advance expressions
## exactly like is_crouching, so the same warning applies: an expression naming a property
## that does not exist never fires and never complains.
var is_sliding: bool = false

## Seconds into the slide clip. Advanced in _apply_slide_velocity(), at the point the
## distance for this frame is consumed, so the window sampled off `slide_motion` is always
## the frame the motion is applied to.
var _slide_time: float = 0.0
## The heading the slide is travelling on, and the ONE thing his body and his mesh share
## while one is running: _steer_slide() turns it, _apply_slide_velocity() drives the body
## along it, and _handle_character_rotation() writes the mesh straight onto it. Nothing
## else may point him anywhere - two sources for a facing is what skate is made of.
var _slide_direction: Vector3 = Vector3.ZERO
var _slide_cooldown_left: float = 0.0
## A `crouch` press made in the air and not yet spent. Armed by _handle_crouch_and_slide()
## when a press would start a slide but for his feet being off the floor, and consumed on
## the first grounded frame - or dropped there, if the slide cannot start on it. Unlike the
## old timed buffer it does not lapse in the air: press `crouch` any time before landing and
## the slide is waiting for the floor. See docs/specs/pilot9-jump-slide.md.
var _slide_buffered: bool = false

## True for the length of the mantle. Read by the AnimationTree's advance expressions
## exactly like is_sliding, so the same warning applies: an expression naming a property
## that does not exist never fires and never complains. Only ever set by _start_climb(),
## which cannot run unless his feet were already off the floor.
var is_climbing: bool = false

## Seconds into climb_up. Advanced in _apply_climb_motion(), which is also the only thing
## that ends the mantle on time.
var _climb_time: float = 0.0
## The heading the mantle runs on: straight at the wall, taken from the forward ray's hit
## normal at the entry snap and never turned afterwards. The slide's _slide_direction
## discipline applies - while is_climbing this is the only thing pointing him anywhere.
var _climb_facing: Vector3 = Vector3.ZERO
## Where the entry snap put him, and the origin every sampled offset is added to.
var _climb_start_position: Vector3 = Vector3.ZERO
## Where he is hard-snapped on the exit frame: feet on the lip, climb_inset in along
## _climb_facing. Computed at entry from the same detected lip, so a frame of curve drift
## cannot leave him half in the floor.
var _climb_end_position: Vector3 = Vector3.ZERO
## The metres the curves are scaled by for THIS mantle, measured off the detected lip
## rather than taken from the bake. They come out equal to climb_rise / climb_reach while
## the entry snap is lip-relative; deriving them anyway is what keeps his feet on the
## platform if that ever stops being true.
var _climb_detected_rise: float = 0.0
var _climb_detected_reach: float = 0.0
## A `jump` pressed during the mantle. The mantle is not cancellable, so the press is held
## and spent on the first frame after the exit snap - the same courtesy the land-and-slide
## buffer gives. Dropped, not spent, if `frozen` ends the mantle.
var _climb_jump_buffered: bool = false

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
	_update_sprint_toggle()
	# Freezing mid-mantle ends it rather than pausing it, for the reason the slide ends
	# itself: nothing advances _climb_time while frozen, and he would be left hanging in
	# the air with his collision shape switched off. Landing him on top is the safe stop.
	if frozen and is_climbing:
		_end_climb(false)
	_handle_crouch_and_slide(delta)
	_handle_gravity_and_jump(delta)
	_handle_camera_transition(delta)
	_handle_controller_camera(delta)

	# A mantle owns his position outright. move_and_slide() is deliberately NOT called
	# these frames - his collision shape is off and he is being written along a path over
	# an edge, so a velocity step would only fight the curve.
	if is_climbing:
		_apply_climb_motion(delta)
		return

	if frozen:
		handle_frozen_movement()
		move_and_slide()
		return

	_handle_movement_input()
	# Before the rotation, and outside its THIRD_PERSON gate: the heading is what steers the
	# body, so it has to turn even in a camera mode where nothing is drawing the mesh.
	if is_sliding:
		_steer_slide(delta)
	if camera_mode == CameraMode.THIRD_PERSON:
		_handle_character_rotation(delta)
	# A slide owns his velocity outright: the curve says how fast, the steered heading says
	# where, and the stick reaches it only through that heading.
	if is_sliding:
		_apply_slide_velocity(delta)
	else:
		_apply_movement()
	move_and_slide()

func handle_frozen_movement() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	input_dir = Vector2.ZERO
	is_sprinting = false
	is_walking = false

## Sprint toggles rather than being held: `sprint` (Shift / right trigger) flips it, `walk`
## (Alt) clears it. A toggle means letting go of the button mid-jump does not silently drop
## him out of a run - the intent carries through the air, so a jump buffered into a slide
## still reads the sprint it started with, and the player is not punished for an accidental
## release. Called before _handle_crouch_and_slide() so the slide checks see this frame's
## value. Frozen the press is ignored: handle_frozen_movement() forces the effective
## is_sprinting false anyway, and the toggle should come back untouched after a pause.
func _update_sprint_toggle() -> void:
	if frozen:
		return
	if Input.is_action_just_pressed("sprint"):
		sprint_toggled = not sprint_toggled
	elif Input.is_action_just_pressed("walk"):
		sprint_toggled = false

## The `crouch` press, and the one place it is spent. Pressed at a sprint it starts a slide;
## pressed at any other time it toggles the crouch. Never both - a single decision point is
## what keeps a slide from also leaving him crouched when it ends.
##
## Read here rather than in _input so it lands on the same frame as every other movement
## input; the AnimationTree samples is_crouching and is_sliding after this.
func _handle_crouch_and_slide(delta: float) -> void:
	_slide_cooldown_left = maxf(_slide_cooldown_left - delta, 0.0)

	if frozen:
		# Freezing mid-slide has to end it, not pause it: nothing advances _slide_time
		# while frozen, so the clip would play on against a clock that stopped. A queued
		# air press goes with it - a stale slide firing on the frame he unfreezes is not
		# what was asked for.
		_end_slide()
		_slide_buffered = false
		return

	# The mantle holds the whole body for its length, and `crouch` means nothing during
	# one. Returning here rather than earlier keeps the cooldown ticking, so a slide
	# cancelled into a mantle still waits out its full delay after he stands up.
	if is_climbing:
		return

	if is_sliding:
		if not is_on_floor():
			_end_slide()          # off a ledge mid-slide; `fall` takes it from here
		elif _slide_time >= slide_duration:
			_end_slide()
		return                    # the slide holds the crouch key for its whole length

	# A `crouch` press made in the air (see _should_buffer_slide) waits here for the ground.
	# Spent BEFORE the just-pressed check below, so one press is never read twice - and a
	# landing where the slide cannot start (sprint toggled off, stick centred, still on
	# cooldown) just drops the press rather than falling through to a crouch.
	if _slide_buffered and is_on_floor():
		_slide_buffered = false
		var buffered := _travel_direction(Input.get_vector("left", "right", "forward", "backward"))
		if _can_start_slide(buffered):
			_start_slide(buffered)
		return

	if not Input.is_action_just_pressed("crouch"):
		return

	# Fresh rather than last frame's `direction`: _handle_movement_input has not run yet
	# this frame, and this is the last look at the stick before _can_start_slide() decides -
	# a frame of lag in it is a frame of lag on the whole slide.
	var heading := _travel_direction(Input.get_vector("left", "right", "forward", "backward"))
	if _can_start_slide(heading):
		_start_slide(heading)
	elif _should_buffer_slide():
		# Sprinting into a slide, feet not yet on the floor - the one thing _can_start_slide()
		# failed on. Remember the press and spend it the instant he lands.
		_slide_buffered = true
	else:
		is_crouching = not is_crouching

## Sprinting, moving, on the ground. The clip opens at 8 m/s with his feet planted, so
## anything slower than a sprint would start it with a lurch.
func _can_start_slide(heading: Vector3) -> bool:
	return can_slide \
		and slide_motion != null \
		and slide_duration > 0.0 \
		and _slide_cooldown_left <= 0.0 \
		and is_on_floor() \
		and heading != Vector3.ZERO \
		and sprint_toggled \
		and not Input.is_action_pressed("walk")

## The airborne half of _can_start_slide(): every slide condition except the one a jump makes
## briefly false - his feet on the floor. A `crouch` press that meets these is a slide the
## player is asking for while still in the air, so it is remembered rather than spent as a
## crouch toggle, and stays remembered until he lands. No rise/fall gate and no timer: press
## `crouch` any time before touchdown. Sprint being a toggle is what makes this safe - the
## press means "slide" because the sprint it needs cannot have been let go by accident. See
## docs/specs/pilot9-jump-slide.md.
func _should_buffer_slide() -> bool:
	return can_slide \
		and can_buffer_slide \
		and slide_motion != null \
		and slide_duration > 0.0 \
		and _slide_cooldown_left <= 0.0 \
		and not is_on_floor() \
		and sprint_toggled \
		and not Input.is_action_pressed("walk") \
		and Input.get_vector("left", "right", "forward", "backward") != Vector2.ZERO


func _start_slide(heading: Vector3) -> void:
	is_sliding = true
	_slide_time = 0.0
	# Where he is visibly pointing, not where the stick is pushing. Entering mid-turn the two
	# differ, and since the mesh is about to be welded to this heading, taking the stick's
	# would snap his body round on the entry frame. The stick is only the fallback for first
	# person, where nothing has been driving character.rotation.
	_slide_direction = _facing() if camera_mode == CameraMode.THIRD_PERSON else heading
	# The clip's tail stands him up and runs him out, so ending in a crouch would fight the
	# pose he is visibly in - even trimmed, he is upright and running by the cut.
	is_crouching = false

## Turns the slide. The player steers one exactly as he steers a run - same stick, same
## rotation_speed, same lerp - which is the whole of the change: a slide that cannot be
## aimed is a 1.25 s commitment the player makes blind, and every miss reads as the controls
## having been taken away rather than as a bad call.
##
## Deliberately a lerp on the HEADING rather than on the mesh. _handle_character_rotation()
## then writes the mesh onto the result instead of chasing it with a second lerp: one lerp
## end to end, so a slide turns at the speed a run turns at and not at half of it, and the
## body can never be pointing somewhere the mesh is not.
##
## Stick released, the heading holds - a slide with no input carries straight on, which is
## also what keeps the run-out from swinging when the player lets go early.
func _steer_slide(delta: float) -> void:
	if input_dir == Vector2.ZERO or direction == Vector3.ZERO:
		return
	var turned := lerp_angle(
		atan2(_slide_direction.x, _slide_direction.z),
		atan2(direction.x, direction.z),
		rotation_speed * delta)
	_slide_direction = Vector3(sin(turned), 0.0, cos(turned))

## The world direction the mesh is facing. The inverse of the rotation target computed in
## _handle_character_rotation(), and correct for the same reason: the 180 degree basis that
## turns pilot9 the right way round lives on the `character` node's own transform, so its
## rotation.y and a travel direction are already in the same frame.
func _facing() -> Vector3:
	return Vector3(sin(character.rotation.y), 0.0, cos(character.rotation.y))

## Also the cooldown's only writer - a slide cancelled by a jump has to wait out the same
## delay as one that ran to the end, or landing straight back into another is free.
func _end_slide() -> void:
	if not is_sliding:
		return
	is_sliding = false
	_slide_time = 0.0
	_slide_cooldown_left = slide_cooldown

## Handles gravity application, the jump, the air jump and the mantle trigger.
##
## The mantle is automatic: every airborne frame the ledge probe runs, and a qualifying lip
## in range starts it with no input. Checked BEFORE the jump-press handling so a `jump`
## pressed on the frame a mantle begins is buffered for the exit (by the is_climbing branch
## next frame) rather than spent as an air jump.
func _handle_gravity_and_jump(delta: float) -> void:
	if is_climbing:
		# Not cancellable - collision is off and he is on a scripted path over an edge, so
		# there is no safe point to release him. The press is held for the exit instead.
		if not frozen and Input.is_action_just_pressed("jump"):
			_climb_jump_buffered = true
		return

	if not is_on_floor():
		velocity += get_gravity() * delta
		is_jumping = velocity.y > 0
	else:
		is_jumping = false
		_air_jumps_left = air_jumps

	# Spent here, ahead of everything else. The exit snap teleported him onto the ledge
	# without a move_and_slide(), so is_on_floor() is still false on this frame and the
	# press would otherwise fall through to the air-jump branch and be charged for.
	if _climb_jump_buffered:
		_climb_jump_buffered = false
		if not frozen:
			velocity.y = jump_velocity
			is_jumping = true
			return

	# The mantle is automatic - no press. Probe every airborne frame and let a qualifying
	# ledge start it. Ahead of the jump handling so a `jump` on the entry frame is buffered
	# for the exit by the is_climbing branch above next frame, not spent as an air jump. The
	# entry snap has already placed him, faced him and zeroed his velocity.
	if not frozen and not is_on_floor() and _try_start_climb():
		return

	if frozen or not Input.is_action_just_pressed("jump"):
		return

	if is_on_floor():
		# Jumping stands him up rather than being swallowed by the crouch. There is no
		# crouch-jump clip, and a dead jump key reads as broken input.
		is_crouching = false
		# Same argument for the slide, and it is the only way out of one early. Without
		# it the slide is a 1.25 second cutscene the player cannot leave.
		_end_slide()
		velocity.y = jump_velocity
		is_jumping = true
	elif _air_jumps_left > 0:
		# The double jump. velocity.y is assigned, not added: rising, a second jump that
		# stacked would send him twice as high off a mistimed double-tap, and falling fast
		# an added one would barely register. Replacing it makes the second jump the same
		# jump wherever in the arc it is taken.
		_air_jumps_left -= 1
		velocity.y = jump_velocity
		is_jumping = true
		air_jumped.emit()

## Processes movement input and calculates movement direction relative to camera.
func _handle_movement_input() -> void:
	input_dir = Input.get_vector("left", "right", "forward", "backward")
	input_strength = minf(input_dir.length(), 1.0)
	direction = _travel_direction(input_dir)

## The world direction a stick/WASD vector means, given where the camera is pointing.
## Lifted out of _handle_movement_input so the slide can ask the same question on the frame
## it starts, before that function has run - see _handle_crouch_and_slide().
func _travel_direction(dir: Vector2) -> Vector3:
	var camera_basis := Transform3D(Basis(Vector3.UP, camera_pivot.rotation.y), Vector3.ZERO).basis
	return (camera_basis * Vector3(dir.x, 0, dir.y)).normalized()

## Rotates the character mesh smoothly toward the direction it should face.
##
## Deviation 3 from stock RC: the lerp is gated on movement input. Stock welds the
## body to camera-back every frame, so orbiting just dragged pilot9 around with
## the camera and his face was unreachable. Standing still he now holds his world
## facing and the camera orbits freely around him.
##
## Deviation 4: what he turns toward. Stock aims at camera-back, which is what makes
## strafing and backing up read against the camera - and what left the one forward-only
## crouch clip playing over sideways motion. Aiming at the travel direction instead means
## he is always walking forward relative to himself, so that clip is correct everywhere.
##
## atan2(direction.x, direction.z) is a generalisation of the stock target rather than a
## replacement for it: `direction` is already camera-relative out of _handle_movement_input,
## so for straight-forward input the two expressions evaluate to the same angle. Measured at
## three camera yaws before this was written, and tests/test_pilot9_turn_to_face.gd holds it.
## That equality is also why the 180 degree basis baked into the `character` node needs no
## correction here.
##
## Deviation 5, the slide: the mesh is welded to `_slide_direction`, not lerped toward it.
## _steer_slide() has already done the smoothing on that heading this frame, at this same
## rotation_speed; lerping again here would only halve the turn rate and open a gap between
## where he points and where he travels. It also ignores the input gate - the heading holds
## itself when the stick is centred, so there is nothing to fall back to.
func _handle_character_rotation(delta: float) -> void:
	if camera_mode == CameraMode.FIRST_PERSON:
		return
	var target: float
	if is_climbing:
		# Welded, like the slide's - and for a stronger reason: the entry snap placed his
		# hands on the lip along this heading, so anything that turned him would slide the
		# grab off the edge it was measured against.
		character.rotation.y = atan2(_climb_facing.x, _climb_facing.z)
		return
	elif is_sliding:
		character.rotation.y = atan2(_slide_direction.x, _slide_direction.z)
		return
	elif input_dir == Vector2.ZERO:
		return
	else:
		target = atan2(direction.x, direction.z) if face_travel_direction \
			else camera_pivot.rotation.y + PI
	character.rotation.y = lerp_angle(character.rotation.y, target, rotation_speed * delta)

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
	is_sprinting = sprint_toggled and is_moving and not Input.is_action_pressed("walk") and not is_crouching
	is_walking = Input.is_action_pressed("walk") and is_moving and not sprint_toggled and can_walk and not is_crouching
	
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

## Drives the slide from the clip's own forward-travel curve instead of a speed constant.
##
## `slide_motion` is distance-so-far against time, both normalised 0..1. The speed for this
## frame is the distance across the frame's window divided by the frame - i.e. the curve
## differentiated, sampled exactly where the motion is about to be applied. Feet and floor
## therefore agree wherever the clip has planted feet, which is the run-in at ~8 m/s and the
## run-out at ~5, without either number appearing anywhere in this file.
##
## is_sprinting and is_walking are deliberately left holding whatever _apply_movement last
## set: nothing reads them while the `slide` state owns the tree, and leaving them alone is
## what lets a slide that ends with sprint still toggled on hand straight back to a sprint
## rather than fading up from a run.
func _apply_slide_velocity(delta: float) -> void:
	if delta <= 0.0 or slide_motion == null or slide_duration <= 0.0:
		return
	var from := _slide_time / slide_duration
	var to := minf(_slide_time + delta, slide_duration) / slide_duration
	var travelled := (slide_motion.sample(to) - slide_motion.sample(from)) * slide_distance * slide_scale
	var speed_now := travelled / delta
	velocity.x = _slide_direction.x * speed_now
	velocity.z = _slide_direction.z * speed_now
	_slide_time += delta

## -- the ledge mantle ---------------------------------------------------------
##
## Detection, entry snap, path playback, exit. See docs/specs/pilot9-climb.md. Three things
## are worth knowing before reading them:
##
## 1. The rays are fired every airborne frame - the mantle is automatic, so there is no
##    press to hang the probe off. Three raycasts a frame while off the floor; cheap, and
##    the guard in _handle_gravity_and_jump() keeps it from running on grounded frames.
## 2. The geometry is measured off the CLIP, not off the ledge. climb_hand_offset and
##    climb_foot_offset are where his hands and his soles sit relative to his own origin on
##    the first and last frames; both snaps subtract them from the detected lip, so the two
##    moments that actually touch the world are exact by construction.
## 3. Nothing here calls move_and_slide(). global_position is written directly with the
##    collision shape switched off, which is the only way a body gets over an edge it is
##    standing against.

## Is this hit a ledge? In the band, and flat enough to stand on. Pure maths, deliberately
## kept out of the raycasting so it can be tested without a physics world - it is the ONLY
## filter the mantle has (no climbable layer, no tag), which makes it worth testing.
##
## `height` is metres of lip above his feet; `normal` is the surface normal at the hit.
func _qualifies_as_ledge(height: float, normal: Vector3) -> bool:
	if height < climb_band_min or height > climb_band_max:
		return false
	return normal.normalized().dot(Vector3.UP) > cos(deg_to_rad(climb_max_lip_slope))

## Turns three raycast results into a mantle, or into nothing. Split out of _probe_ledge()
## for the reason the predicate above is: this is the whole decision, and the rays are the
## only part of it that needs a world.
##
## `forward` must have hit a wall, `down` must have hit a lip that qualifies, and
## `headroom` must have hit NOTHING - anything over the spot he would land on refuses the
## mantle, because he arrives standing and planting him inside a ceiling is an ugly failure.
##
## The lip handed back is the wall face at the top surface's height, not the down ray's own
## hit point: that ray is cast deliberately inside the platform (see CLIMB_LIP_PROBE_INSET)
## and his hands belong on the edge, not 0.4 m in from it.
func _evaluate_ledge(feet_y: float, forward: Dictionary, down: Dictionary,
		headroom: Dictionary) -> Dictionary:
	if forward.is_empty() or down.is_empty() or not headroom.is_empty():
		return {}
	var lip_y: float = (down["position"] as Vector3).y
	if not _qualifies_as_ledge(lip_y - feet_y, down["normal"]):
		return {}
	var face: Vector3 = forward["position"]
	return {
		"lip": Vector3(face.x, lip_y, face.z),
		"wall_normal": forward["normal"],
	}

## Fires the three rays and hands them to _evaluate_ledge(). Returns {} when there is no
## mantle here, which is every airborne frame away from a wall.
func _probe_ledge() -> Dictionary:
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}
	var feet := global_position
	# Third person: the mesh yaw, which _handle_character_rotation() has been turning toward
	# travel every airborne frame - grab the wall he is flying at. First person: nothing
	# drives the mesh (that function early-returns), so character.rotation.y is stale and the
	# probe would fire at a fixed world heading. Aim it where the camera looks instead, the
	# way every other first-person heading in this controller is taken.
	var facing := _facing() if camera_mode == CameraMode.THIRD_PERSON \
		else -Vector3(sin(camera_pivot.rotation.y), 0.0, cos(camera_pivot.rotation.y))
	var self_rid := get_rid()

	# 1. The wall. Cast below the shallowest lip the band accepts - see climb_probe_height -
	#    so it meets the face rather than sailing over the top of it.
	var eye := feet + Vector3.UP * climb_probe_height
	var forward_q := PhysicsRayQueryParameters3D.create(eye, eye + facing * climb_probe_reach)
	forward_q.exclude = [self_rid]
	var forward := space.intersect_ray(forward_q)
	if forward.is_empty():
		return {}

	# 2. The lip, found from above and a little inside the platform. The ray spans the band
	#    and no more, so a hit is nearly always qualified already and _qualifies_as_ledge()
	#    is confirming rather than filtering.
	var inside: Vector3 = (forward["position"] as Vector3) + facing * CLIMB_LIP_PROBE_INSET
	var top := Vector3(inside.x, feet.y + climb_band_max + CLIMB_PROBE_MARGIN, inside.z)
	var span := (climb_band_max - climb_band_min) + 2.0 * CLIMB_PROBE_MARGIN
	var down_q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * span)
	down_q.exclude = [self_rid]
	var down := space.intersect_ray(down_q)
	if down.is_empty():
		return {}

	# 3. Headroom over the spot he would end up standing on.
	var face_pos: Vector3 = forward["position"]
	var landing := Vector3(face_pos.x, (down["position"] as Vector3).y, face_pos.z) \
		+ facing * climb_inset
	var head_q := PhysicsRayQueryParameters3D.create(
		landing + Vector3.UP * CLIMB_PROBE_MARGIN, landing + Vector3.UP * climb_headroom)
	head_q.exclude = [self_rid]
	var headroom := space.intersect_ray(head_q)

	return _evaluate_ledge(feet.y, forward, down, headroom)

## Airborne, with a ledge in range. Called every airborne frame now that the mantle is
## automatic; returns false for every other case so the frame falls through to the normal
## jump handling - see _handle_gravity_and_jump().
func _try_start_climb() -> bool:
	if not can_climb or is_climbing or is_on_floor():
		return false
	if climb_motion_y == null or climb_motion_z == null or climb_duration <= 0.0 or climb_speed <= 0.0:
		return false
	var ledge := _probe_ledge()
	if ledge.is_empty():
		return false
	_start_climb(ledge["lip"], ledge["wall_normal"])
	return true

## The entry snap. Instant, never blended: a one or two frame blend here reads as a slide
## toward the wall, and the whole point of snapping is that the hands meet the edge every
## time rather than nearly every time.
func _start_climb(lip: Vector3, wall_normal: Vector3) -> void:
	is_climbing = true
	_climb_time = 0.0
	_climb_jump_buffered = false
	# The mantle ends him standing, and it cannot be entered out of a slide anyway. Clearing
	# both is what stops the exit handing back into a pose he is visibly not in. The buffered
	# air-crouch goes too, for the reason `frozen` drops it: a stale slide firing on the frame
	# the mantle hands back is not what was asked for.
	is_crouching = false
	_slide_buffered = false
	_end_slide()

	# Face the wall: the heading opposite its normal, flattened to the ground plane. A normal
	# with no horizontal part is not a wall to face, so hold the heading he arrived on.
	var into_wall := Vector3(-wall_normal.x, 0.0, -wall_normal.z)
	_climb_facing = into_wall.normalized() if into_wall.length() > 0.001 else _facing()
	character.rotation.y = atan2(_climb_facing.x, _climb_facing.z)

	# His own frame, so the two baked offsets can be applied exactly as they were measured.
	# Built from the yaw rather than read off the node, so this is correct before anything
	# has re-evaluated the mesh transform.
	var body := Basis(Vector3.UP, character.rotation.y)
	_climb_start_position = lip - body * climb_hand_offset
	_climb_end_position = lip + _climb_facing * climb_inset - body * climb_foot_offset
	global_position = _climb_start_position

	# Measured off the detected lip rather than lifted out of the bake - see the note on
	# _climb_detected_rise. The forward half is projected onto the heading because the
	# curves drive two axes; the few centimetres of lateral between his hands on the lip and
	# his feet on the top are left for the exit snap to absorb.
	var span := _climb_end_position - _climb_start_position
	_climb_detected_rise = span.y
	_climb_detected_reach = _climb_facing.dot(span)

	# Deferred because this runs inside physics processing, where the shape is in use.
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	velocity = Vector3.ZERO

## Writes the body along the baked path. Position driven, not velocity driven - a mantle is
## not physics, and every frame of it is a place rather than a speed.
func _apply_climb_motion(delta: float) -> void:
	if climb_motion_y == null or climb_motion_z == null or climb_duration <= 0.0 or climb_speed <= 0.0:
		_end_climb(true)
		return
	# delta * climb_speed, not delta: the `climb` state's custom timeline compresses the clip
	# by the same climb_speed, so the two clocks stay locked while the whole mantle plays fast.
	_climb_time += delta * climb_speed
	if _climb_time >= climb_duration:
		_end_climb(true)
		return
	var u := _climb_time / climb_duration
	var offset := Vector3.UP * (climb_motion_y.sample(u) * _climb_detected_rise) \
		+ _climb_facing * (climb_motion_z.sample(u) * _climb_detected_reach)
	global_position = _climb_start_position + offset
	velocity = Vector3.ZERO

## Ends the mantle, on time or on `frozen`. Both endings do the same three things - hard
## snap to the endpoint, put the collision shape back, stop him dead - because the state
## being left is the same either way: a body with no collision shape somewhere over an edge.
##
## `completed` is false only when `frozen` cut it short, and then the buffered jump goes
## with it: a stale mantle-jump firing on the frame he unfreezes is not what was asked for.
func _end_climb(completed: bool) -> void:
	if not is_climbing:
		return
	is_climbing = false
	_climb_time = 0.0
	global_position = _climb_end_position
	velocity = Vector3.ZERO
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	if not completed:
		_climb_jump_buffered = false

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