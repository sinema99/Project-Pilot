extends CharacterBody3D

# EXIA, the first mech. See docs/specs/exia-pilot.md.
#
# Setsuna walks into the interaction box, the prompt offers "F pilot", and F starts the climb:
# she is put on EmbarkPoint (pulled back by the pose's own root motion - see _mount_position),
# off the machine's flank, and player.gd's begin_embark() plays the
# 2 s `embark` clip that carries her up into the cockpit. The mech holds its crouch for the whole
# of it and only then takes her aboard - enter_vehicle() hides her, MECH_launch boots up - which
# is the one rule the climb imposes on everything below: the boot-up waits. See the embark
# section. The view pans out of hers and into the mech's on the frame F is pressed, so the rest
# of the climb is watched from the machine's own camera - see the camera section, and
# docs/specs/mech-camera-handover.md. F again is that whole sequence backwards, and it needs no
# animation of its own: MECH_idle powers the machine down and slides the same canopy open, she
# rides it out, and then `embark` played from its last frame to its first walks her back down
# onto the mark she climbed on from. The pan waits for her feet - the descent is watched from the
# mech's camera, and the view goes back to hers on the last frame of it. See the disembark
# section, and the spec's Disembarking.
#
# The mech has no jump - Space and C are dead while piloting. The export also carries
# MECH_turning_L and MECH_turning_R. The 2026-09-02 re-export animated both - the previous one
# had turning_L as a single keyed frame and no turning_R at all - but they are a foot shuffle on
# the spot rather than a turn: the legs and toes move, no yaw reaches the skeleton, and neither
# covers any ground. The machine is still swung round by the ROTATE_SPEED lerp below, so both
# clips are imported and left unplayed and nothing below refers to them.
# Gravity applies throughout: MECH_launch is a boot-up sequence, not lift, and the mech walks on
# the ground. It is not, however, played on the spot - it steps the mech forward, which is what
# the root motion section at the bottom of this file exists to carry.
#
# The clips chain by pose, which is what drives the whole animation section below:
#
#   MECH_idle ends crouched -> MECH_launch starts crouched, ends standing -> MECH_standing
#
# So MECH_idle is EXIA powering down, not a resting loop. It is played once when nobody is
# aboard and *held* on its last frame, which is how a parked mech stays crouched. MECH_standing
# is the resting pose for a mech with a pilot in it.
#
# Setting off takes exactly as long as MECH_walk_start does. That clip is the mech planting a
# foot and leaning 8.4 m of machine into its first stride, and it is authored on the spot, so
# the ground it should have covered is the ramp: the body accelerates from a standstill to SPEED
# over precisely the clip's own length, and reaches it on the frame the queue hands over to
# MECH_walk. The walk loop therefore only ever plays at one speed, which is the speed its stride
# was authored for. That is why the ramp is derived from the clip rather than dialled in - see
# ramp_rate - and why a re-exported walk start retunes the acceleration on its own.
#
# Stopping is still immediate: see clip_for on why letting go has to win instantly.
#
# The mech travels along its own nose and nowhere else. The input direction is a heading to turn
# towards, never a direction to move in, so a change of direction is a turn the machine has to
# make rather than a drift into the new heading with the model swinging round to catch up.

# 5.0 was the speed the walk was tuned to when EXIA was 5.87 m tall. The 2026-09-01 export made
# it 8.40 m, and a stride 1.43x longer covers 1.43x the ground per cycle, so the speed the loop
# was authored for went up with it. 10.0 read as a skate on the smaller mech; 7.0 is the
# re-tuned number for this one.
const SPEED = 7.0
const ROTATE_SPEED = 10.0
const MOUSE_SENSITIVITY = 0.0025
const PITCH_MIN = -1.3
const PITCH_MAX = 1.3

const ANIM_IDLE := "MECH_idle"
const ANIM_LAUNCH := "MECH_launch"
const ANIM_STANDING := "MECH_standing"
const ANIM_WALK_START := "MECH_walk_start"
const ANIM_WALK := "MECH_walk"

const PROMPT_ENTER := "F pilot"
const PROMPT_EXIT := "F exit"

# The camera handover. See docs/specs/mech-camera-handover.md.
#
# How long the pan from the pilot's view out to the mech's takes. It sits inside the climb, so
# the flight is over long before the boot-up starts, and the rest of the climb is watched from
# the mech's own camera - which is the shot that frames a person scaling an 8.4 m machine.
const HANDOVER_TIME := 0.6
# The pitch every entry starts at, in radians - negative is looking down. EXIA is 8.4 m tall
# with its camera pivot at 7.9 m, so a level camera stares at its shoulders; this tips the
# framing down onto the ground it is about to walk over.
const ENTRY_PITCH := -0.15

# The bone the clips translate the mech with, and the distance below which a clip counts as
# staying put. See the root motion section.
const HIP_BONE := "spine"
const TRAVEL_EPSILON := 0.001

# EXIA's canopy, and the one bone MECH_launch slides shut as it boots up. A child of spine.002 up
# in the chest, so the root-motion split never touches it and its world transform carries the
# mech's forward travel for free. Setsuna rides it through the launch - see the embark section.
const COCKPIT_BONE := "spine.003"

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
var pilot: Node3D = null
var player_in_range: Node3D = null
# Seconds left of the pilot's climb up the outside of the machine, and the third state this
# script has: `pilot` is already set while it runs, but EXIA is not hers to drive yet and the
# boot-up has not started. 0.0 the rest of the time. See the embark section.
var embark_left := 0.0
# Seconds left of the canopy close, and the fourth state: the climb is over and MECH_launch is
# booting up, but Setsuna is still on screen, held on `embark`'s last frame and carried by the
# cockpit bone as it seals. 0.0 the rest of the time - and 0.0 outright when the export has no
# spine.003 or no MECH_launch, which boards her the instant the climb ends the way it used to.
var seal_left := 0.0
# The two the way out is made of, and the mirror of the two above: seconds left of the canopy
# *opening* - MECH_idle powering the mech down with her still aboard, riding the cockpit back
# open - and then seconds left of the descent, `embark` running backwards down the machine.
# `pilot` is still set through both: she is not handed back until her feet are on the ground.
# 0.0 the rest of the time, and 0.0 for the whole of an exit that falls back to the cut.
var unseal_left := 0.0
var disembark_left := 0.0
# The cockpit bone's world transform and the pilot's root transform at the frame MECH_launch
# starts. seat_follow replays the bone's motion since then onto her root. See _board.
var _cockpit_board := Transform3D.IDENTITY
var _pilot_board := Transform3D.IDENTITY
# The mech's skeleton and the index of COCKPIT_BONE in it, both looked up once in _ready. The
# index is -1 when the export has no spine.003, which is the switch that skips the canopy carry.
var _skeleton: Skeleton3D = null
var _cockpit_bone := -1
var camera_yaw := 0.0
var camera_pitch := 0.0
var was_moving := false

# The pan in progress, if any: seconds left of it, the view it set off from, and the camera it
# is flying into - the mech's own on the way in, the pilot's on the way out.
var handover_left := 0.0
var _handover_from := Transform3D.IDENTITY
var _handover_from_fov := 75.0
var _handover_to: Camera3D = null

# Metres per second per second, filled in from MECH_walk_start's length in _ready. The fallback
# is a one-second ramp, which is what that clip currently is.
var acceleration := SPEED

# Clip name -> the travel curve split out of it, and where that curve was last sampled. Only the
# clips that actually travel get an entry.
var travel_curves: Dictionary = {}
var _travel_clip := ""
var _travel_last := Vector3.ZERO

# How far the pose currently on screen has been displaced from where its clip authored it, in
# metres, in the mech's own space. This is the ground the body has been given instead of the
# skeleton, and it is *held* when a one-shot ends: the parked mech's crouch is MECH_idle's last
# frame, so it is still standing 2.17 m behind where the export drew it. Zero while a clip that
# does not travel is playing, because those poses are the anchor. See _mount_position, which is
# the only thing that reads it - root motion itself works in differences and does not care.
var pose_travel := Vector3.ZERO

# Metres of ground per unit of bone travel - see travel_scale_for. Filled in from the imported
# rig in _ready; 1.0 until then, which is what an unscaled armature works out to anyway.
var travel_scale := 1.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_pitch_node: Node3D = $CameraPivot/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraPivot/CameraPitch/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/CameraPitch/SpringArm3D/Camera3D
@onready var handover_camera: Camera3D = $HandoverCamera
@onready var anim_player: AnimationPlayer = $Model/AnimationPlayer
@onready var interaction_area: Area3D = $InteractionArea
@onready var exit_point: Marker3D = $ExitPoint
# Where the pilot stands to start her climb. get_node_or_null rather than $: a vehicle without
# one skips the climb and takes her aboard on the spot, which is what F did before the climb
# existed.
@onready var embark_point: Marker3D = get_node_or_null("EmbarkPoint")
@onready var prompt_label: Label = $UI/PromptLabel

func _ready() -> void:
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	spring_arm.add_excluded_object(get_rid())
	# The loop modes come from the import (MECH_walk off its .loop suffix, MECH_standing from
	# _subresources), but a re-export that drops one would fail silently, so state the intent
	# here as well.
	#
	# The one-shots are meant to be held: when a non-looping clip ends the mixer stops writing
	# and the skeleton keeps its last frame, which is what makes a powered-down mech stay
	# crouched. MECH_standing loops only so that current_animation keeps naming it for the state
	# machine - it is a single held pose, so a loop and a hold look the same.
	for looping in [ANIM_WALK, ANIM_STANDING]:
		if anim_player.has_animation(looping):
			anim_player.get_animation(looping).loop_mode = Animation.LOOP_LINEAR
	for one_shot in [ANIM_IDLE, ANIM_LAUNCH, ANIM_WALK_START]:
		if anim_player.has_animation(one_shot):
			anim_player.get_animation(one_shot).loop_mode = Animation.LOOP_NONE
	if anim_player.has_animation(ANIM_WALK_START):
		acceleration = ramp_rate(anim_player.get_animation(ANIM_WALK_START).length)
	_split_travel_out_of_the_clips()
	# The cockpit bone Setsuna rides through the launch. Looked up once: a re-export that drops or
	# renames spine.003 leaves _cockpit_bone at -1, and the canopy carry falls back to hiding her
	# the instant the climb ends.
	var skeletons := anim_player.get_parent().find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0] as Skeleton3D
		_cockpit_bone = _skeleton.find_bone(COCKPIT_BONE)
	# _process exists only to fly the handover camera; it is switched on for the pan and off
	# again at the end of it.
	set_process(false)
	# Nobody aboard: power down, and hold the crouch.
	_play_chain(ANIM_IDLE)

# --- pilot handshake ------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	# Only things that can actually be a pilot arm the prompt.
	if body.has_method("enter_vehicle"):
		player_in_range = body
		_update_prompt()

func _on_body_exited(body: Node3D) -> void:
	if body == player_in_range:
		player_in_range = null
		_update_prompt()

func _update_prompt() -> void:
	# Nothing to press while she is climbing in or being sealed into the cockpit, and nothing
	# while she is being let back out again - F is dead for the whole of both sequences - so the
	# prompt goes away rather than offering an exit from a mech she is not settled into yet, or
	# an entry into one she is halfway down the side of.
	if embark_left > 0.0 or seal_left > 0.0 or unseal_left > 0.0 or disembark_left > 0.0:
		prompt_label.visible = false
	elif pilot != null:
		prompt_label.text = PROMPT_EXIT
		prompt_label.visible = true
	elif player_in_range != null:
		prompt_label.text = PROMPT_ENTER
		prompt_label.visible = true
	else:
		prompt_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if pilot != null and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * MOUSE_SENSITIVITY
		camera_pitch = clamp(camera_pitch - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)

	# Setsuna's own _unhandled_input is switched off while she is piloting, so F cannot be
	# claimed by both scripts on the same press.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		# The climb and the canopy close own her body for their whole length, and so do the
		# canopy open and the descent: there is nothing to get out of yet, and nothing to climb
		# into twice.
		if embark_left > 0.0 or seal_left > 0.0 or unseal_left > 0.0 or disembark_left > 0.0:
			return
		if pilot == null and player_in_range != null:
			_enter_mech()
		elif pilot != null:
			_exit_mech()

func _enter_mech() -> void:
	pilot = player_in_range
	# Read before anything else is written: the pan sets off from whatever is on screen this
	# instant, which is the pilot's own camera. Taken off the viewport rather than out of the
	# pilot so the mech needs to know nothing about how a pilot's camera rig is put together.
	var watching := get_viewport().get_camera_3d()
	# Climbing in always puts the camera behind the machine, however the pilot walked up to it,
	# and at the same pitch every time. camera_yaw is only ever written by mouse motion
	# otherwise, so without this the shot is whatever the last piloting session was left on -
	# and on the first entry it is 0.0, a compass bearing with nothing to do with the mech.
	camera_yaw = yaw_behind(rotation.y)
	camera_pitch = ENTRY_PITCH
	_aim_camera()
	# The climb, if this pilot and this mech both have one. She is put on the mount mark and her
	# own clip carries her up the machine from there; _board() is what happens at the top of it.
	# A pilot with no embark clip, or a mech with no mark, is taken aboard on the spot - which is
	# what F did before the climb existed, and is still what it does for either of them.
	embark_left = 0.0
	if embark_point != null and pilot.has_method("begin_embark"):
		embark_left = maxf(pilot.begin_embark(_mount_position(),
			embark_point.global_rotation.y), 0.0)
	if embark_left <= 0.0:
		_board()
	_update_prompt()
	_begin_handover(watching, camera)

# Where the pilot stands to start her climb: EmbarkPoint, pulled back by however far the pose the
# mech is holding has been displaced from where its clip authored it.
#
# Root motion is what makes that necessary, and the two features have to know about each other.
# Her climb was authored against EXIA crouched at the end of its power-down, and in the export
# that crouch sits 2.17 m along the mech's nose, because MECH_idle walks the machine forward as it
# powers down. mech.gd takes exactly that travel out of the skeleton and gives it to the body
# instead - see the root motion section - so on screen the crouch stands 2.17 m *behind* where the
# climb expects to find it. Mounting straight off the mark put her on the front of the chest with
# the open canopy behind her; subtracting the same displacement puts her in the cockpit.
#
# Taken from the curve rather than written down as a constant, so a re-exported power-down that
# travels a different distance retunes this on its own - and so does climbing into a mech caught
# part way through one.
func _mount_position() -> Vector3:
	return embark_point.global_position - global_transform.basis * pose_travel

# The pilot has reached the cockpit: the climb ends on the last frame of her clip, and MECH_launch
# starts on the next. Booting the machine up and taking her out of the world are no longer one
# moment - MECH_launch slides the canopy shut first, and she stays on screen riding it. See the
# embark section and _physics_process's sealing branch.
#
# was_moving is cleared so the first movement key after climbing in still reads as a standing
# start.
func _board() -> void:
	embark_left = 0.0
	was_moving = false
	# Boot-up out of the crouch MECH_idle left it in, then hold the standing pose behind it.
	_play_chain(ANIM_LAUNCH, ANIM_STANDING)
	# She is not hidden yet. MECH_launch slides the canopy (spine.003) shut over its own length,
	# and she rides it there, held on embark's last frame. Record where the cockpit bone and her
	# root sit now; seat_follow replays the bone's motion onto her root until the launch ends.
	#
	# A mech with no spine.003 or no launch clip - or a pilot with no ride() to be carried by -
	# has nothing to put on screen for the beat, so enter_vehicle() takes that pilot aboard here
	# the way F did before the canopy close existed. The seal beat exists to be *seen*; a pilot
	# hidden on the frame F was pressed (pilot9) is not eligible for it, and calling ride() on
	# one that does not have it is a live crash. See docs/specs/pilot9-mech-mount.md.
	seal_left = 0.0
	if _cockpit_bone >= 0 and anim_player.has_animation(ANIM_LAUNCH) and pilot.has_method("ride"):
		seal_left = anim_player.get_animation(ANIM_LAUNCH).length
	if seal_left > 0.0:
		_cockpit_board = _cockpit_world()
		_pilot_board = pilot.global_transform
	else:
		pilot.enter_vehicle(self)

# The cockpit bone's transform in world space: skeleton pose composed with the skeleton node's
# own transform, so the Model's counter-rotation and the mech's root-motion travel are both in
# it. Only called while _cockpit_bone >= 0.
func _cockpit_world() -> Transform3D:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_cockpit_bone)

# Where the pilot's root goes this frame to ride the cockpit bone. Her root at board time,
# expressed once in the bone's frame, replayed against the bone's live transform - a rigid
# attach. With `now == board` it returns `pilot_board` unchanged, so she does not jump on the
# first frame; a translation of the bone translates her one for one, and a rotation carries her
# round it with the offset preserved.
static func seat_follow(cockpit_now: Transform3D, cockpit_board: Transform3D,
		pilot_board: Transform3D) -> Transform3D:
	return cockpit_now * (cockpit_board.affine_inverse() * pilot_board)

# --- the way out ----------------------------------------------------------
#
# The entry backwards, and no new animation anywhere in it. See the spec's Disembarking section.
#
#   F pressed ──> MECH_idle powers EXIA down and slides the canopy open; she is on screen again,
#                 held on embark's last frame, riding the cockpit out (unseal_left)
#             ──> MECH_idle ends ──> `embark` plays from its last frame to its first, carrying
#                                    her down onto the mount mark (disembark_left)
#             ──> clip ends ──> _hand_back(): her body is hers again and the camera pans into
#                               her view

func _exit_mech() -> void:
	# Whatever it was doing when she let go of the controls, it powers down and stays crouched.
	was_moving = false
	# F is dead through the canopy close, so this only fires here if something else calls it - but
	# a stale countdown would drive her ride() against a mech that is powering down, so drop it.
	seal_left = 0.0
	_play_chain(ANIM_IDLE)
	if _can_climb_down():
		# The power-down is the canopy opening, so she comes out on it before she climbs down:
		# `pilot` stays set, the machine is nobody's to drive, and the camera stays on the mech's
		# own until the descent has landed.
		unseal_left = anim_player.get_animation(ANIM_IDLE).length
		pilot.begin_unseal()
		_update_prompt()
		return
	# The cut, which is what F did before the descent existed and is still the fallback for a
	# vehicle or a pilot missing any piece of it. She is put out of the *back* of the machine
	# (see ExitPoint) facing it, so the mech she has just climbed out of is what the camera is
	# looking at, and exit_vehicle() puts her own camera behind her and makes it current.
	var former_pilot := pilot
	pilot = null
	# Whatever is on screen this instant - the mech's camera, or the handover camera itself if
	# the pan in never finished and this is a pilot getting straight back out again.
	var watching := get_viewport().get_camera_3d()
	former_pilot.exit_vehicle(exit_point.global_position, rotation.y)
	_begin_handover(watching, get_viewport().get_camera_3d())
	_update_prompt()

# Whether this pilot can be let out the way she came in. It needs every piece the climb needed -
# the mark, the clip, and the cockpit bone to ride out on - plus both scripted clips: MECH_idle
# because it is the canopy opening, and MECH_launch because starting it is what recorded the
# seated offset the ride out is replayed from. Any one of them missing and F falls back to the
# cut at ExitPoint, which is not an error path - it is the placeholder, still working.
func _can_climb_down() -> bool:
	if embark_point == null or _cockpit_bone < 0:
		return false
	if not anim_player.has_animation(ANIM_IDLE) or not anim_player.has_animation(ANIM_LAUNCH):
		return false
	if not pilot.has_method("begin_unseal") or not pilot.has_method("begin_disembark"):
		return false
	return pilot.has_method("embark_length") and pilot.embark_length() > 0.0

# The canopy is open and she is sitting in it: start the walk down. _mount_position() is read
# here rather than remembered from the way in, so the descent lands on the mark relative to
# wherever the machine has since walked - and by now MECH_idle has ended, so the pose it is
# holding carries exactly the travel the mark is corrected for, the same as the parked mech she
# climbed into. That also puts the mark where the canopy ride has just left her, so the snap onto
# it in begin_disembark is not one that shows.
func _begin_descent() -> void:
	unseal_left = 0.0
	disembark_left = maxf(pilot.begin_disembark(_mount_position(),
		embark_point.global_rotation.y), 0.0)
	if disembark_left <= 0.0:
		_hand_back()

# Her feet are down. The descent has ended on `embark`'s first frame, standing on the mount mark
# facing the machine, so she is handed back exactly where she is rather than teleported to
# ExitPoint: walking her round to the back of the mech after she has climbed down the front of it
# is the one thing the descent cannot survive. exit_vehicle() puts her camera behind her and
# makes it current, and the pan flies the view into it - the entry's flight, the other way.
func _hand_back() -> void:
	var former_pilot := pilot
	pilot = null
	disembark_left = 0.0
	var watching := get_viewport().get_camera_3d()
	former_pilot.exit_vehicle(former_pilot.global_position, former_pilot.rotation.y)
	_begin_handover(watching, get_viewport().get_camera_3d())
	_update_prompt()

# --- the camera -----------------------------------------------------------
#
# See docs/specs/mech-camera-handover.md.
#
# The orbit is stored as a world yaw and a pitch and written onto the rig rather than read back
# off it: the pivot hangs off the body, so the mech turning underneath it would otherwise drag
# the camera round with it.

# The world yaw that puts the camera directly behind a mech facing `mech_yaw`.
#
# The camera looks along its pivot's -Z and the mech's nose is its +Z (see facing_for), so
# "behind" is half a turn round from the body's own yaw. Getting this wrong by a quarter turn
# leaves the camera on the mech's flank on entry, with W walking it across the screen - so the
# two are asserted against each other in the tests.
static func yaw_behind(mech_yaw: float) -> float:
	return wrapf(mech_yaw + PI, -PI, PI)

# Eases the pan: 0 at the start, 1 at the end, and flat at both ends so the camera leaves and
# arrives with no velocity. A linear pan jolts at exactly the two moments the player is watching
# for the join.
static func handover_ease(elapsed: float, duration: float) -> float:
	if duration <= 0.0:
		return 1.0
	var t := clampf(elapsed / duration, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _aim_camera() -> void:
	camera_pivot.rotation.y = camera_yaw - rotation.y
	camera_pitch_node.rotation.x = camera_pitch

# Starts a pan from `watching` to `destination`, which is the mech's own camera on the way in
# and the pilot's on the way out. `watching` is read before anything else is written, so passing
# the handover camera itself - a pan interrupted by a second press of F - takes the flight over
# from wherever it had got to rather than snapping back to its start.
#
# Nothing to fly from, or nowhere to fly to, means there is no pan to make: the destination
# takes the picture outright.
func _begin_handover(watching: Camera3D, destination: Camera3D) -> void:
	if destination == null:
		return
	if watching == null:
		destination.current = true
		return
	_handover_from = watching.global_transform
	_handover_from_fov = watching.fov
	_handover_to = destination
	handover_left = HANDOVER_TIME
	handover_camera.global_transform = _handover_from
	handover_camera.fov = _handover_from_fov
	# The pan is a flight into the destination's shot, so that camera owns the clip planes.
	handover_camera.near = destination.near
	handover_camera.far = destination.far
	handover_camera.current = true
	set_process(true)

func _process(delta: float) -> void:
	if handover_left <= 0.0:
		return
	if not is_instance_valid(_handover_to):
		# Nowhere left to fly to. Drop the pan rather than leaving the viewport on a camera
		# nobody is driving.
		_cancel_handover()
		return
	handover_left = maxf(handover_left - delta, 0.0)
	var t := handover_ease(HANDOVER_TIME - handover_left, HANDOVER_TIME)
	# The destination is re-read every frame rather than captured when F was pressed. On the way
	# in EXIA is booting up and MECH_launch walks it 1.66 m forward under root motion, and the
	# pilot may already be steering with the mouse; on the way out Setsuna has her body back and
	# can walk off mid-pan. A destination fixed up front would be stale by the time the pan
	# reached it, and the handover would end on the very jump this exists to remove. Chasing the
	# live transform makes the last frame of the pan and the first frame of the camera it hands
	# over to the same picture.
	handover_camera.global_transform = _handover_from.interpolate_with(_handover_to.global_transform, t)
	handover_camera.fov = lerpf(_handover_from_fov, _handover_to.fov, t)
	if handover_left <= 0.0:
		_finish_handover()

# The pan has landed, so hand the viewport over. Making the destination current clears the
# handover camera by itself, which is what keeps the viewport from being left without a camera
# for a frame.
func _finish_handover() -> void:
	handover_left = 0.0
	set_process(false)
	_handover_to.current = true

# Drops the pan where it stands, without choosing what to show instead.
func _cancel_handover() -> void:
	handover_left = 0.0
	set_process(false)

# --- animation ------------------------------------------------------------

# Picks the clip to start this frame, or "" to leave the playhead where it is.
#
# Returning "" rather than re-issuing the clip already playing is what stops MECH_walk
# restarting every frame, and what lets the one-shot MECH_walk_start run to its end with
# MECH_walk queued behind it.
#
# Standing still means two different things: with a pilot aboard it is MECH_standing, and parked
# it is the held last frame of MECH_idle. `current` is "" once a one-shot has ended, so a parked
# mech reads as "nothing playing" - and that is precisely the state to leave alone, because the
# skeleton is still holding the crouch.
#
# Releasing every movement key cuts straight back to standing, including part-way through the
# start clip: a mech that has to finish spooling up before it will stop is worse to drive than
# one whose start gets interrupted. The two scripted transitions, MECH_launch and MECH_idle, are
# the exception - nobody is waiting on them, so they play out.
static func clip_for(piloted: bool, moving: bool, was_moving_last_frame: bool,
		current: String) -> String:
	if moving:
		if not was_moving_last_frame:
			return ANIM_WALK_START
		# Mid-spool-up, or already walking - either way the queue has it in hand. Anything else
		# means the chain was interrupted, so pick the loop back up.
		if current == ANIM_WALK_START or current == ANIM_WALK:
			return ""
		return ANIM_WALK
	if current == ANIM_LAUNCH or current == ANIM_IDLE:
		return ""
	if piloted:
		return "" if current == ANIM_STANDING else ANIM_STANDING
	# Parked, and the power-down has already ended: the crouch is held, so play nothing.
	return "" if current == "" else ANIM_IDLE

# The acceleration that spends the whole of MECH_walk_start getting from a standstill to SPEED.
#
# Tying the two together is what keeps MECH_walk at one constant speed: the ramp ends on the
# frame the start clip does, so the walk loop is only ever entered at SPEED and never plays at a
# speed its stride was not authored for. A re-exported start clip of a different length retunes
# the ramp to match it.
# The mech's nose, as a unit vector on the ground plane.
#
# This is the inverse of the atan2(x, z) the turn above aims with, and has to stay that way: a
# sin/cos swap here would point the mech's travel across its own facing and put the slide back,
# mirrored. See test_the_nose_matches_the_heading_the_mech_turns_towards.
static func facing_for(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))

static func ramp_rate(walk_start_length: float) -> float:
	# No clip, or a zero-length one: set off at once rather than never.
	if walk_start_length <= 0.0:
		return SPEED
	return SPEED / walk_start_length

# Starts `clip` now and hands over to `next` when it ends. The queue is cleared first: an
# interrupted chain (launch cut short by a movement key) would otherwise leave its follow-up
# sitting in the queue to fire after the walk start, one clip too late.
func _play_chain(clip: String, next: String = "") -> void:
	if not anim_player.has_animation(clip):
		return
	anim_player.clear_queue()
	anim_player.play(clip)
	if next != "" and anim_player.has_animation(next):
		anim_player.queue(next)

func _drive_animation(piloted: bool, moving: bool) -> void:
	var clip := clip_for(piloted, moving, was_moving, anim_player.current_animation)
	was_moving = moving
	if clip == "":
		return
	_play_chain(clip, ANIM_WALK if clip == ANIM_WALK_START else "")

# --- movement -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	# The climb. EXIA is claimed but not yet driven, so it holds its crouch through the parked
	# branch below exactly as if nobody had pressed anything, and the boot-up waits for her.
	# The countdown is read before it is spent, so the frame she lands still takes that branch:
	# _board() has just started MECH_launch, and clip_for leaves a launch alone either way.
	var climbing := embark_left > 0.0
	if climbing:
		# Mouse look stays live while she climbs. The pan lands on the mech's camera a third of
		# the way up, and a dead camera for the rest of the climb reads as a freeze.
		_aim_camera()
		embark_left = maxf(embark_left - delta, 0.0)
		if embark_left <= 0.0:
			_board()
			_update_prompt()

	# The descent, and the last beat of the handback: EXIA has powered down and let her out, and
	# she is walking herself down the outside of the machine on `embark` played backwards. The
	# mech is nobody's to drive - it holds the crouch through the parked branch below exactly as
	# it does for the climb up - but she is not hers yet either, which is what `pilot` staying set
	# through the countdown says.
	var climbing_down := disembark_left > 0.0
	if climbing_down:
		# Mouse look stays live for the descent, the same as for the climb.
		_aim_camera()
		disembark_left = maxf(disembark_left - delta, 0.0)
		if disembark_left <= 0.0:
			_hand_back()

	if pilot == null or climbing or climbing_down:
		velocity.x = move_toward(velocity.x, 0, SPEED * delta)
		velocity.z = move_toward(velocity.z, 0, SPEED * delta)
		_drive_animation(false, false)
		move_and_slide()
		# The power-down walks the mech forward as well; parked is not the same as anchored.
		_apply_root_motion()
		return

	# The canopy close. She is aboard but not driving yet: MECH_launch is sliding the cockpit
	# (spine.003) shut, and she rides it, held on embark's last frame. Movement input is dead for
	# the beat - friction and gravity only, and MECH_launch is left to play through to the queued
	# MECH_standing. Root motion runs before she is pinned to the bone, so the ~1.66 m the launch
	# walks the body forward is already in the cockpit's world transform when seat_follow reads it.
	if seal_left > 0.0:
		velocity.x = move_toward(velocity.x, 0, SPEED * delta)
		velocity.z = move_toward(velocity.z, 0, SPEED * delta)
		_drive_animation(true, false)
		move_and_slide()
		_apply_root_motion()
		pilot.ride(seat_follow(_cockpit_world(), _cockpit_board, _pilot_board))
		_aim_camera()
		seal_left = maxf(seal_left - delta, 0.0)
		if seal_left <= 0.0:
			# Canopy shut. Take her out of the world; the boot-up finishes without her.
			pilot.enter_vehicle(self)
			_update_prompt()
		return

	# The canopy opening, which is the seal run the other way. She has let go of the controls and
	# MECH_idle is powering EXIA down and sliding the cockpit (spine.003) back open; she is on
	# screen again, held on embark's last frame, and rides the bone out on the offset the launch
	# recorded. Movement input is dead for the beat - friction and gravity only - and the root
	# motion runs before she is pinned to the bone, so the 2.17 m the power-down walks the body
	# forward is already in the cockpit's world transform when seat_follow reads it, exactly as
	# it is on the way in.
	if unseal_left > 0.0:
		velocity.x = move_toward(velocity.x, 0, SPEED * delta)
		velocity.z = move_toward(velocity.z, 0, SPEED * delta)
		_drive_animation(false, false)
		move_and_slide()
		_apply_root_motion()
		pilot.ride(seat_follow(_cockpit_world(), _cockpit_board, _pilot_board))
		_aim_camera()
		unseal_left = maxf(unseal_left - delta, 0.0)
		if unseal_left <= 0.0:
			# Cockpit open. She climbs down it.
			_begin_descent()
		return

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

	var cam_basis := camera_pivot.global_transform.basis
	var direction := cam_basis * Vector3(input_dir.x, 0, input_dir.y)

	var wants_to_move := direction.length() > 0.01

	# The mech is allowed to turn through the standing start - it plants the foot facing where it
	# is about to go, rather than stepping off and then swinging round. Setsuna turns the same way
	# now that her 15-degree heading detents are gone, just at her own ROTATE_SPEED.
	if wants_to_move:
		direction = direction.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), ROTATE_SPEED * delta)

		# Only the *speed* is ramped; the heading is taken from the mech's nose outright, so the
		# velocity is exactly along the facing on every frame and the mech cannot slide.
		#
		# Ramping the two axes towards the input direction instead is what used to slide it: the
		# body turns at ROTATE_SPEED and the velocity chased the heading at its own rate, so
		# through every turn the mech was pointing one way and travelling another. Feeding the
		# nose back in also means a turn costs no speed and needs no separate steering term - the
		# velocity vector is simply carried round by the rotation above.
		#
		# The magnitude is read back off the velocity rather than kept in a field so that a
		# collision counts: move_and_slide() bleeds speed off against a wall, and the mech then
		# ramps back up out of whatever it was left with.
		var speed := Vector2(velocity.x, velocity.z).length()
		speed = move_toward(speed, SPEED, acceleration * delta)
		var facing := facing_for(rotation.y)
		velocity.x = facing.x * speed
		velocity.z = facing.z * speed
	else:
		# Stopping stays instant - SPEED is a whole second's worth of ramp per frame - because
		# releasing the keys has to win now. A mech that coasts is a mech that walks off ledges.
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	# Held on the ground, so the walk doesn't kick in for a frame while falling onto terrain.
	_drive_animation(true, is_on_floor() and wants_to_move)

	move_and_slide()
	_apply_root_motion()

	_aim_camera()

# --- root motion ----------------------------------------------------------

# The clips travel, and until this section existed the body did not.
#
# MECH_idle steps the mech 1.257 bone units forward as it powers down and MECH_launch a further
# 0.963 as it stands back up, so by the last frame of the boot-up the mech is 2.219457 ahead of
# where MECH_standing holds it. The travel is authored as a translation of the whole armature:
# every unparented bone in the export - the hip, the upper torso, both hands, both feet -
# carries the same +Z drift, and each one lands exactly 2.219457 ahead of its own MECH_standing
# value. Nothing moved the CharacterBody3D while that happened, so the moment MECH_standing took
# over it yanked the mech the whole way back.
#
# Those are bone units rather than metres, and the two stopped being the same thing in the
# 2026-09-01 export: it scales the armature node by 1.7268 to reach the bigger mech, so the
# 2.219457 the skeleton travels is 3.83 m of ground. travel_scale carries that conversion, and a
# re-export at a different size retunes it on its own.
#
# So the travel is taken out of the skeleton when the mech loads and replayed on the body
# instead, which is what root motion means:
#
#   - every unparented bone's position track gets the hip's horizontal drift subtracted from it,
#     which leaves the clips playing on the spot and makes MECH_launch's last frame identical to
#     MECH_standing's pose. There is nothing left to snap back from.
#   - the drift is kept as a curve and fed to the body each physics frame, so the mech - mesh,
#     collider and camera together - covers exactly the ground the animation covered.
#
# The render is unchanged: the mech still sweeps forward through the boot-up, and its feet still
# stay planted while it does, because a foot that holds still in the world has to travel
# backwards through a body that is moving forwards - which is precisely what subtracting the
# drift from the toe tracks leaves behind. What changes is that the hitbox goes with it.
#
# Measuring travel from MECH_standing's pose rather than from each clip's own first frame is
# what makes the chain add up: MECH_launch opens 1.26 m ahead, where MECH_idle left the mech,
# and that carried-over 1.26 m has to come out of the skeleton too or it snaps back at the end
# of the launch just the same.

# Animation -> the travel curve split out of it, or null for a clip that stays put. The clips
# belong to the imported GLB and are shared by every instance of mech.tscn, so the split is done
# once per resource: a second mech reads the curve out of here instead of re-deriving it from
# tracks the first one already flattened.
static var _split_clips: Dictionary = {}

# The index of `bone`'s position track in `clip`, or -1. Track paths are node-plus-subname
# ("metarig_001/Skeleton3D:spine"), and only the subname is stable across a re-export.
static func bone_track(clip: Animation, bone: String) -> int:
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		if String(clip.track_get_path(track).get_concatenated_subnames()) == bone:
			return track
	return -1

# The bones with no parent - the ones the export translates together when the mech travels.
static func root_bone_names(skeleton: Skeleton3D) -> PackedStringArray:
	var names: PackedStringArray = []
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_parent(bone) == -1:
			names.append(skeleton.get_bone_name(bone))
	return names

# Rewrites `clip` so it plays on the spot, and returns the horizontal travel it removed as a
# one-track Animation to sample with position_track_interpolate(). Returns null - and leaves the
# clip alone - when there was no travel to take out.
#
# `anchor` is the hip's resting position, the one MECH_standing holds. Only x and z are taken:
# the hip's vertical drop is the crouch itself, and a mech that cannot fall through its own
# floor has nowhere to put it.
static func split_travel(clip: Animation, roots: PackedStringArray, anchor: Vector3) -> Animation:
	var hip := bone_track(clip, HIP_BONE)
	if hip < 0:
		return null

	var curve := Animation.new()
	curve.length = clip.length
	var out := curve.add_track(Animation.TYPE_POSITION_3D)
	curve.track_set_path(out, clip.track_get_path(hip))
	curve.track_set_interpolation_type(out, clip.track_get_interpolation_type(hip))
	var travels := false
	for key in clip.track_get_key_count(hip):
		var pos: Vector3 = clip.track_get_key_value(hip, key)
		var travel := Vector3(pos.x - anchor.x, 0.0, pos.z - anchor.z)
		travels = travels or travel.length() > TRAVEL_EPSILON
		curve.position_track_insert_key(out, clip.track_get_key_time(hip, key), travel)
	if not travels:
		return null

	# The other root bones are keyed on their own times, so the curve is sampled at each key
	# rather than paired up key-for-key. The clips are keyed at the import's 30 fps and the
	# travel is linear between keys, so this is exact at both ends and within a millimetre in
	# between.
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		if not roots.has(String(clip.track_get_path(track).get_concatenated_subnames())):
			continue
		for key in clip.track_get_key_count(track):
			var time := clip.track_get_key_time(track, key)
			var pos: Vector3 = clip.track_get_key_value(track, key)
			clip.track_set_key_value(track, key, pos - curve.position_track_interpolate(out, time))
	return curve

# Metres of ground per unit of bone travel: whatever scale sits between the mech's own transform
# and its skeleton's. The clips key bone positions in the armature's space, and the export puts a
# 1.7268 scale on the armature node to size the mech, so a bone that travels one unit walks the
# machine 1.7268 m. Taken as a ratio rather than read off the skeleton outright so that scaling
# the whole mech - the CharacterBody3D and the model together - leaves it at 1.0.
static func travel_scale_for(body: Transform3D, skeleton: Transform3D) -> float:
	return (body.affine_inverse() * skeleton).basis.get_scale().y

func _split_travel_out_of_the_clips() -> void:
	var skeletons := anim_player.get_parent().find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty() or not anim_player.has_animation(ANIM_STANDING):
		return
	travel_scale = travel_scale_for(global_transform, (skeletons[0] as Skeleton3D).global_transform)
	var standing := anim_player.get_animation(ANIM_STANDING)
	var hip := bone_track(standing, HIP_BONE)
	if hip < 0:
		return

	# MECH_standing is a single held pose, so its first key is the resting position outright.
	var anchor: Vector3 = standing.track_get_key_value(hip, 0)
	var roots := root_bone_names(skeletons[0] as Skeleton3D)
	for clip_name in [ANIM_IDLE, ANIM_LAUNCH, ANIM_STANDING, ANIM_WALK_START, ANIM_WALK]:
		if not anim_player.has_animation(clip_name):
			continue
		var clip := anim_player.get_animation(clip_name)
		if not _split_clips.has(clip):
			_split_clips[clip] = split_travel(clip, roots, anchor)
		if _split_clips[clip] != null:
			travel_curves[clip_name] = _split_clips[clip]

# How far `clip` has travelled from the resting pose by time `at`, in metres, in the mech's own
# space. The curve is in bone units, so travel_scale converts it to the ground the feet cover.
# `at` is clamped, so INF asks for the clip's last frame - which is the pose a finished one-shot
# leaves on the skeleton.
func _travel_of(clip: String, at: float) -> Vector3:
	var curve: Animation = travel_curves.get(clip)
	if curve == null:
		return Vector3.ZERO
	return curve.position_track_interpolate(0, minf(at, curve.length)) * travel_scale

func _travel_now() -> Vector3:
	return _travel_of(anim_player.current_animation, anim_player.current_animation_position)

# The ground the animation covered since the last physics frame.
#
# A clip change contributes nothing: the new clip starts wherever it starts - MECH_launch opens
# 2.17 m along - and the body has already been walked there by the clip before it. Reading the
# difference across that boundary would double the last one back on itself.
func _root_motion_step() -> Vector3:
	var travel := _travel_now()
	if anim_player.current_animation != _travel_clip:
		# The clip changed. Nothing playing means a one-shot ended and the skeleton is holding
		# its last frame, so the displacement stays on screen: pose_travel takes the curve's
		# *end* rather than wherever the playhead happened to be sampled on the final frame.
		# Anything else has taken the skeleton over, and its own travel is the displacement now.
		pose_travel = (_travel_of(_travel_clip, INF) if anim_player.current_animation == ""
			else travel)
		_travel_clip = anim_player.current_animation
		_travel_last = travel
		return Vector3.ZERO
	# Only while something is actually playing. A held pose keeps the displacement it was left
	# with, and _travel_now() reads zero for a mech with no clip running - which is exactly the
	# state a parked mech is in when someone climbs into it.
	if _travel_clip != "":
		pose_travel = travel
	var step := travel - _travel_last
	_travel_last = travel
	return step

# Moved rather than teleported, so a mech booting up with its nose against a wall stays behind
# the wall. move_and_slide() has already run and set is_on_floor(); this is horizontal, so it
# does not disturb either.
func _apply_root_motion() -> void:
	var step := _root_motion_step()
	if step != Vector3.ZERO:
		move_and_collide(global_transform.basis * step)
