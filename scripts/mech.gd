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
# Driving it is docs/specs/exia-movement.md: a run (9 m/s) and a sprint (14 m/s), a heavy leg
# jump on Space, a step-turn on the spot, a stop that settles, a breathing idle. Every one of those
# clips is built in code at boot (mech_gait.gd, mech_moves.gd) with solved legs, so a planted foot
# stays planted. The exported MECH_walk / MECH_walk_start / MECH_turning_L / _R are still imported
# and never played. What the mech is doing is one locomotion state, `loco` - see the movement
# section - and each state picks its clip.
# Gravity applies throughout: MECH_launch is a boot-up sequence, not lift, and the mech walks on
# the ground. It is not, however, played on the spot - it steps the mech forward, which is what
# the root motion section at the bottom of this file exists to carry. Off the floor with a pilot
# aboard, gravity is MECH_GRAVITY_SCALE heavier: an 8.4 m machine falls like one.
#
# The exported clips chain by pose:
#
#   MECH_idle ends crouched -> MECH_launch starts crouched, ends standing -> MECH_standing
#
# So MECH_idle is EXIA powering down, not a resting loop. It is played once when nobody is
# aboard and *held* on its last frame, which is how a parked mech stays crouched. MECH_standing
# is the pose the boot-up ends on, and the built MECH_stand_idle starts on exactly that pose.
#
# The mech travels along its own nose and nowhere else. The input direction is a heading to turn
# towards, never a direction to move in, so a change of direction is a turn the machine has to
# make rather than a drift into the new heading with the model swinging round to catch up.

# The run. 7.0 was the old walk's speed; the 2026-10-27 pass made the base gait a heavy jog.
const SPEED = 9.0
# From a standstill to SPEED. Replaces the old walk start, whose clip set the ramp.
const RUN_RAMP_TIME := 0.6
const ROTATE_SPEED = 10.0
# A var, not a const: Settings.mouse_sensitivity scales it at the point of use
# (see _unhandled_input below). The authored 0.0025 stays what it means -
# EXIA's own feel, deliberately a different number from pilot9's 0.005 - and
# is not overwritten by the settings row, only multiplied against.
var MOUSE_SENSITIVITY := 0.0025
const PITCH_MIN = -1.3
const PITCH_MAX = 1.3

const ANIM_IDLE := "MECH_idle"
const ANIM_LAUNCH := "MECH_launch"
const ANIM_STANDING := "MECH_standing"
# Imported, never played since the 2026-10-27 movement pass. Still named so their loop modes are
# pinned the way they always were.
const ANIM_WALK_START := "MECH_walk_start"
const ANIM_WALK := "MECH_walk"
# Built in code at boot. See scripts/mech_gait.gd and scripts/mech_moves.gd.
const ANIM_RUN := "MECH_run"
const ANIM_SPRINT := "MECH_sprint"
const ANIM_STAND_IDLE := "MECH_stand_idle"
const ANIM_TURN_STEP := "MECH_turn_step"
const ANIM_STOP_L := "MECH_stop_L"
const ANIM_STOP_R := "MECH_stop_R"
const ANIM_JUMP_CROUCH := "MECH_jump_crouch"
const ANIM_JUMP_AIR := "MECH_jump_air"
const ANIM_LAND := "MECH_land"

# The sprint. See docs/specs/exia-movement.md and docs/specs/exia-sprint.md.
#
# A tier on top of the run, toggled on the `sprint` action. Both clips are grounded titan runs
# authored for exactly their speed, every planted foot moving back through the mech at that speed.
# Off it the clip plays slower in proportion (gait_rate), so a planted foot keeps pace with the body
# through the ramps and the brakes too.
const SPRINT_SPEED := 14.0
const SPRINT_RAMP_TIME := 0.5
const SPRINT_BRAKE_TIME := 0.25
# Letting go of the keys at a sprint: down to the run speed this fast, then the stop.
const SPRINT_RELEASE_TIME := 0.2
# The crossfade between the run and the sprint, either way. Short, and both clips put the left plant
# at the same phase, so the same foot is down in both.
const SPRINT_BLEND_TIME := 0.15
# A heavy machine on a ~12 m circle at full speed, blended in by speed so the rate does not step on
# the frame the sprint starts.
const ROTATE_SPEED_SPRINT := 4.0
# The slowest each gait clip plays, as a share of its authored rate. The sprint's floor is the run
# speed's share; the run's is what keeps the first step out of a standstill from crawling.
const SPRINT_RATE_MIN := SPEED / SPRINT_SPEED
const RUN_RATE_MIN := 0.4
# Above this horizontal speed the mech plays the sprint clip.
const SPRINT_GAIT_SPEED := SPEED + 0.1
# The bank: a roll of the model about the nose, pivoting at the feet, into the turn.
const BANK_MAX_DEG := 12.0
const BANK_FULL_ACCEL := 16.33   # 14 m/s on a ~12 m circle: 14^2 / 12
const BANK_EASE := 8.0
# The camera on a bound: a damped share of the hip's bounce, a dip and a shake on every footfall.
# The run takes RUN_CAMERA_SHARE of the sprint's dip and bounce, and no shake.
const BOUNCE_SHARE := 0.35
const BOUNCE_SMOOTH := 0.05
const FOOTFALL_DIP := 0.25
const DIP_OMEGA := 26.0
const FOOTFALL_SHAKE_DEG := 0.6
const FOOTFALL_SHAKE_TIME := 0.12
const RUN_CAMERA_SHARE := 0.4
const RUN_DUST_SCALE := 0.6
const SPRINT_FOV_BOOST := 10.0
const FOV_EASE := 8.0

# The locomotion state while a pilot drives. See the movement section and the spec's table.
enum Loco { STAND, TURN, RUN, STOP, CROUCH, AIR, LAND }

# The step-turn: asked to go further than this off the nose from a standstill, the mech steps round
# on the spot first, pivoting about its planted foot, and runs once it is within TURN_DONE_ANGLE.
const TURN_STEP_ANGLE := deg_to_rad(30.0)
const TURN_DONE_ANGLE := deg_to_rad(8.0)
const TURN_STEP_RATE := deg_to_rad(200.0)
# Let go below this and the mech just stands; above it, it plays the stop.
const STOP_MIN_SPEED := 4.5

# The jump. 3 m apex under a heavier gravity: ~1.25 s in the air.
const MECH_GRAVITY_SCALE := 1.6
const JUMP_HEIGHT := 3.0
# Grace after leaving the floor: still counts as grounded for a jump, and is not yet a fall.
const COYOTE := 0.12
const AIR_TURN_SHARE := 0.2
# No second jump in the first moment of a landing.
const LAND_JUMP_LOCK := 0.2
const HEAVY_LANDING := 2.0
const HEAVY_LANDING_KEEP := 0.6
const LIGHT_LANDING := 1.5
const LIGHT_LANDING_RATE := 1.8
const MOVING_LANDING_RATE := 1.5
# Camera: the crouch eases the view down, the push-off kicks the FOV, the landing dips and shakes.
const CROUCH_CAMERA_DROP := 0.4
const JUMP_FOV_KICK := 5.0
const JUMP_FOV_EASE := 4.0
const LAND_DIP := 0.6
const LAND_SHAKE_DEG := 1.2
const LAND_SHAKE_TIME := 0.2

const MechGait := preload("res://scripts/mech_gait.gd")
const MechMoves := preload("res://scripts/mech_moves.gd")
const MechVfx := preload("res://scripts/mech_vfx.gd")

const PROMPT_ENTER := "PILOT"
const PROMPT_EXIT := "EXIT"
# F pressed while it is too fast or off the floor: the exit waits for it to slow down and land.
const PROMPT_EXIT_PENDING := "EXIT..."
# Exiting is allowed at or below this speed, on the floor.
const EXIT_MAX_SPEED := SPEED + 0.1
# The capsule the exit spot has to fit, roughly pilot9's.
const EXIT_CLEAR_RADIUS := 0.45
const EXIT_CLEAR_HEIGHT := 1.9
const EXIT_FLOOR_PROBE := 5.0

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
# Where CameraPivot sits on EXIA, matching its transform in scenes/mech.tscn. The pivot is
# top_level now, so this is what _process() places it from every drawn frame - see _process.
const CAMERA_PIVOT_OFFSET := Vector3(0.0, 7.9, 0.0)

var camera_yaw := 0.0
var camera_pitch := 0.0
var was_moving := false

# The pan in progress, if any: seconds left of it, the view it set off from, and the camera it
# is flying into - the mech's own on the way in, the pilot's on the way out.
var handover_left := 0.0
var _handover_from := Transform3D.IDENTITY
var _handover_from_fov := 75.0
var _handover_to: Camera3D = null

# Metres per second per second from a standstill to the run.
var acceleration := SPEED / RUN_RAMP_TIME

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

# The sprint's state. See docs/specs/exia-sprint.md.
#
# The toggle, with pilot9's rules (see pilot9.gd::_update_sprint_toggle): `sprint` flips it, `walk`
# clears it, a complete stop clears it - on the floor, at rest, no key held, edge-triggered so a
# press made while standing still is kept - and getting out clears it.
var sprint_toggled := false
var _sprint_stop_armed := false
# Set while keys let go above the run speed are bringing it down to the run speed for the stop.
var _braking := false
# The bank, in radians, and the yaw it differentiates.
var bank := 0.0
var _last_yaw := 0.0
var _model_rest := Transform3D.IDENTITY
# The locomotion state and how long it has been in it. See the movement section.
var loco: Loco = Loco.STAND
var _loco_time := 0.0
# Seconds since the floor was last under it; the highest point since it left; the stop's start speed
# and lead clip; the horizontal speed when the stop began.
var _air_time := 0.0
var _air_peak := 0.0
var _stop_clip := ANIM_STOP_L
var _stop_v0 := 0.0
# F was pressed while it could not let the pilot out yet. See _request_exit.
var exit_pending := false
# The clip the locomotion state last started, so a state's clip is started once and then left to run
# - including a one-shot that has finished and is holding its last frame.
var _loco_clip := ""
# How fast the landing clip plays, set when it lands.
var _land_rate := 1.0
# The animation: seconds left of the crossfade the gait clip is blending in over, and which half of
# the cycle the playhead was in (-1 when no gait is the playing clip). A footfall is a playhead
# crossing, and only counts once the clip has its full weight.
var _gait_blend_left := 0.0
var _gait_half := -1
# Each gait clip's hip height track, in metres, and its mean - the camera takes a share of it.
var _hip_tracks: Dictionary = {}
var _hip_means: Dictionary = {}
# The camera's offsets, all zero with CAMERA MOTION off: the smoothed bounce, the dip spring (offset,
# velocity), the shake (seconds since it started, its size and its length) and the crouch's drop.
var _bounce := 0.0
var _dip := 0.0
var _dip_velocity := 0.0
var _shake_age := INF
var _shake_deg := FOOTFALL_SHAKE_DEG
var _shake_time := FOOTFALL_SHAKE_TIME
var _crouch_drop := 0.0
var _sprint_fov_boost := 0.0
var _jump_fov := 0.0
var _vfx: Node3D = null
# The clips built at boot, shared by every mech like the imported clips are.
static var _built_clips: Dictionary = {}

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_pitch_node: Node3D = $CameraPivot/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraPivot/CameraPitch/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/CameraPitch/SpringArm3D/Camera3D
@onready var handover_camera: Camera3D = $HandoverCamera
@onready var model: Node3D = $Model
@onready var anim_player: AnimationPlayer = $Model/AnimationPlayer
@onready var interaction_area: Area3D = $InteractionArea
@onready var exit_point: Marker3D = $ExitPoint
# Where the pilot stands to start her climb. get_node_or_null rather than $: a vehicle without
# one skips the climb and takes her aboard on the spot, which is what F did before the climb
# existed.
@onready var embark_point: Marker3D = get_node_or_null("EmbarkPoint")
# The prompt is a keycap plus a word now, so visibility belongs to the row and
# only the word changes. See docs/specs/ui-shell.md.
@onready var prompt: Control = $UI/Prompt
@onready var prompt_label: Label = $UI/Prompt/Row/Text

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
	_split_travel_out_of_the_clips()
	# The cockpit bone Setsuna rides through the launch. Looked up once: a re-export that drops or
	# renames spine.003 leaves _cockpit_bone at -1, and the canopy carry falls back to hiding her
	# the instant the climb ends.
	var skeletons := anim_player.get_parent().find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0] as Skeleton3D
		_cockpit_bone = _skeleton.find_bone(COCKPIT_BONE)
	_model_rest = model.transform
	_add_built_clips()
	_vfx = MechVfx.new()
	_vfx.name = "MechVfx"
	add_child(_vfx)
	# _process stays on for good: it places the top_level CameraPivot every frame, not just
	# during the handover pan. Switching it off once the pan landed left the camera parked where
	# the boarding ended while EXIA walked away from it.
	# Nobody aboard: power down, and hold the crouch.
	_play_chain(ANIM_IDLE)

# Builds every clip in docs/specs/exia-movement.md from the imported rig and adds them to the
# player's library. Built every boot rather than baked, so a re-export of Mech_V1.glb cannot strand a
# stale clip. A rig without the bones the build drives gets none of them - it can still be boarded and
# driven, the state machine simply finds no clip to play.
func _add_built_clips() -> void:
	if _skeleton == null or not anim_player.has_animation(ANIM_STANDING):
		return
	if _built_clips.is_empty():
		if _skeleton.find_bone("toe.L.001") < 0 or _skeleton.find_bone("thigh.L") < 0:
			return
		_built_clips = MechMoves.build_all(_skeleton, anim_player.get_animation(ANIM_STANDING))
	var library := anim_player.get_animation_library("")
	if library == null:
		return
	for clip_name in _built_clips:
		if not library.has_animation(clip_name):
			library.add_animation(clip_name, _built_clips[clip_name])
	for clip_name in [ANIM_RUN, ANIM_SPRINT]:
		var clip: Animation = _built_clips[clip_name]
		var track := bone_track(clip, HIP_BONE)
		if track < 0:
			continue
		var total := 0.0
		var keys := clip.track_get_key_count(track)
		for key in keys - 1:
			total += (clip.track_get_key_value(track, key) as Vector3).y
		_hip_tracks[clip_name] = track
		_hip_means[clip_name] = total / maxf(keys - 1, 1)
	hold_built_bones(anim_player, _built_clips[ANIM_SPRINT], _skeleton, _built_clips.keys())

# The built clips key bones the exported clips never touch - `toe.L.001`, the left sole plate, has no
# track in any of them (the right one does). An AnimationPlayer leaves an unkeyed bone wherever the
# last clip put it, so after a run the left plate stayed at the run's last angle under every later
# clip. This gives each exported clip a one-key track holding MECH_standing's value (the bone rest
# where standing has no track, which is what the built clips start from) for every bone `template`
# keys and it does not. Idempotent: the clips are shared between instances, and a clip that already
# has the track keeps it.
static func hold_built_bones(player: AnimationPlayer, template: Animation, skeleton: Skeleton3D,
		built: Array) -> void:
	if template == null or not player.has_animation(ANIM_STANDING):
		return
	var base := MechGait.locals_at(skeleton, player.get_animation(ANIM_STANDING), 0.0)
	for clip_name in player.get_animation_list():
		if built.has(clip_name):
			continue
		var clip := player.get_animation(clip_name)
		for track in template.get_track_count():
			var path := template.track_get_path(track)
			var type := template.track_get_type(track)
			if clip.find_track(path, type) >= 0:
				continue
			var b := skeleton.find_bone(String(path.get_concatenated_subnames()))
			if b < 0:
				continue
			var held := clip.add_track(type)
			clip.track_set_path(held, path)
			match type:
				Animation.TYPE_ROTATION_3D:
					clip.rotation_track_insert_key(held, 0.0, base[b].basis.get_rotation_quaternion())
				Animation.TYPE_POSITION_3D:
					clip.position_track_insert_key(held, 0.0, base[b].origin)
				Animation.TYPE_SCALE_3D:
					clip.scale_track_insert_key(held, 0.0, base[b].basis.get_scale())

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
		prompt.visible = false
	elif pilot != null:
		prompt_label.text = PROMPT_EXIT_PENDING if exit_pending else PROMPT_EXIT
		prompt.visible = true
	elif player_in_range != null:
		prompt_label.text = PROMPT_ENTER
		prompt.visible = true
	else:
		prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if pilot != null and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := MOUSE_SENSITIVITY * Settings.mouse_sensitivity
		camera_yaw -= event.relative.x * sensitivity
		camera_pitch = clamp(camera_pitch - event.relative.y * sensitivity, PITCH_MIN, PITCH_MAX)

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
			_request_exit()
		else:
			return
		# scripts/interact_button.gd reads an `interact` action that also binds F, so one press
		# could otherwise open a door AND board the mech. Consumed only on the presses this
		# actually acted on - consuming unconditionally would make a parked mech eat F for the
		# whole scene. Which of the two wins is scene-tree order; see the Known Gaps in
		# docs/specs/button-door.md.
		get_viewport().set_input_as_handled()

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

# F while driving. On the floor and no faster than the run, the pilot gets out now. Otherwise the
# exit waits: the sprint is dropped so the mech brakes down, the prompt says it is waiting, and the
# physics step lets the pilot out the moment it is down and slow enough. F again calls it off.
func _request_exit() -> void:
	if exit_pending:
		exit_pending = false
	elif can_exit_now(is_on_floor(), Vector2(velocity.x, velocity.z).length(), loco):
		_exit_mech()
		return
	else:
		exit_pending = true
		sprint_toggled = false
	_update_prompt()

# Whether a pilot can be let out right now: on the floor, not mid-jump, no faster than the run.
static func can_exit_now(on_floor: bool, h_speed: float, state: Loco) -> bool:
	return on_floor and h_speed <= EXIT_MAX_SPEED and state != Loco.CROUCH and state != Loco.AIR

func _exit_mech() -> void:
	exit_pending = false
	sprint_toggled = false
	_braking = false
	_gait_half = -1
	loco = Loco.STAND
	_loco_time = 0.0
	_crouch_drop = 0.0
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
	var spot := exit_spot()
	former_pilot.exit_vehicle(spot.position, spot.yaw)
	_begin_handover(watching, get_viewport().get_camera_3d())
	_update_prompt()

# Where the cut puts the pilot: ExitPoint (behind the mech) if it is clear, else the same distance
# to the left, the right, then the front. Clear means a pilot-sized capsule there touches nothing
# but this mech, and there is floor under it within EXIT_FLOOR_PROBE - the spot is dropped onto
# that floor. Returns {position, yaw}, the yaw facing the mech. Nothing clear: ExitPoint, as before.
func exit_spot() -> Dictionary:
	var behind: Vector3 = exit_point.position
	var fallback := {position = exit_point.global_position, yaw = rotation.y}
	if not is_inside_tree():
		return fallback
	var space := get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = EXIT_CLEAR_RADIUS
	capsule.height = EXIT_CLEAR_HEIGHT
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = capsule
	shape_query.exclude = [get_rid()]
	for turn in [0.0, PI * 0.5, -PI * 0.5, PI]:
		var local := Basis(Vector3.UP, turn) * behind
		var at := global_transform * local
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0,
			at + Vector3.DOWN * EXIT_FLOOR_PROBE)
		ray.exclude = [get_rid()]
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		var ground: Vector3 = hit.position
		shape_query.transform = Transform3D(Basis.IDENTITY,
			ground + Vector3.UP * (EXIT_CLEAR_HEIGHT * 0.5 + 0.05))
		if not space.intersect_shape(shape_query, 1).is_empty():
			continue
		var to_mech := global_position - ground
		return {position = ground, yaw = atan2(to_mech.x, to_mech.z)}
	return fallback

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
	camera_pivot.rotation.y = camera_yaw
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

## Places the camera rig every drawn frame, then runs the handover pan if one is in flight.
##
## The placement is here rather than in _physics_process because physics interpolation is on
## project-wide (see project.godot). EXIA steps at the physics tick and is drawn at an
## interpolated position between ticks; a camera parented to it would either interpolate too -
## quantising mouse look to the tick and lagging it a frame - or inherit the raw stepped
## position and judder through every turn. So CameraPivot is top_level with interpolation OFF
## (scenes/mech.tscn) and gets its position from EXIA's *interpolated* transform while its
## rotation comes straight off the mouse. Same split as player.gd::_process and pilot9.gd's.
##
## _aim_camera() still writes the same yaw and pitch in the physics step; that write is what the
## movement block reads back off the pivot basis, so both stay.
func _process(delta: float) -> void:
	_step_bound_camera(delta)
	camera_pivot.global_position = (get_global_transform_interpolated() * CAMERA_PIVOT_OFFSET
		+ Vector3(0.0, _bounce + _dip + _crouch_drop, 0.0))
	camera_pivot.rotation.y = camera_yaw
	var shake := shake_offset(_shake_age, _shake_deg, _shake_time) if Settings.camera_motion 		else Vector2.ZERO
	camera_pitch_node.rotation.x = camera_pitch + shake.x
	camera_pitch_node.rotation.z = shake.y
	# Read live rather than captured, the same reason pilot9's base_fov is a property: FOV is a
	# comfort setting, and one that silently stops applying the moment you board is the bug the
	# sensitivity rows were built to avoid. Nothing authored is lost - mech.tscn never set `fov`,
	# so EXIA was sitting on Godot's default 75 rather than a framing decision.
	#
	# Before the handover block below, so a pan reading _handover_to.fov gets this frame's value.
	camera.fov = Settings.fov + _sprint_fov_boost + _jump_fov

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
	_handover_to.current = true

# Drops the pan where it stands, without choosing what to show instead.
func _cancel_handover() -> void:
	handover_left = 0.0

# --- animation ------------------------------------------------------------

# The clip for a mech nobody is driving: parked, being climbed, or sealing / unsealing. Returns ""
# to leave the playhead where it is.
#
# Standing still means two different things here: with a pilot aboard (the canopy closing) it is the
# boot-up running on into MECH_standing, and parked it is the held last frame of MECH_idle. `current`
# is "" once a one-shot has ended, so a parked mech reads as "nothing playing" - and that is precisely
# the state to leave alone, because the skeleton is still holding the crouch. The two scripted
# transitions, MECH_launch and MECH_idle, always play out.
static func parked_clip(piloted: bool, current: String) -> String:
	if current == ANIM_LAUNCH or current == ANIM_IDLE:
		return ""
	if piloted:
		return "" if current == ANIM_STANDING else ANIM_STANDING
	# Parked, and the power-down has already ended: the crouch is held, so play nothing.
	return "" if current == "" else ANIM_IDLE

# The clip each locomotion state plays. The run gives way to the sprint above SPRINT_GAIT_SPEED.
static func loco_clip(state: Loco, h_speed: float, stop_clip: String) -> String:
	match state:
		Loco.TURN:
			return ANIM_TURN_STEP
		Loco.RUN:
			return ANIM_SPRINT if h_speed > SPRINT_GAIT_SPEED else ANIM_RUN
		Loco.STOP:
			return stop_clip
		Loco.CROUCH:
			return ANIM_JUMP_CROUCH
		Loco.AIR:
			return ANIM_JUMP_AIR
		Loco.LAND:
			return ANIM_LAND
	return ANIM_STAND_IDLE

static func is_gait(clip: String) -> bool:
	return clip == ANIM_RUN or clip == ANIM_SPRINT

# The crossfade into `to` from `from`. The stop and the landing end exactly on the standing pose and
# the idle starts on it, so those joins are near-cuts; the boot-up's MECH_standing fades into the
# idle slowly. See the spec's blend table.
static func blend_for(from: String, to: String) -> float:
	if is_gait(to):
		if is_gait(from):
			return SPRINT_BLEND_TIME
		if from == ANIM_STOP_L or from == ANIM_STOP_R:
			return 0.15
		return 0.2
	match to:
		ANIM_STAND_IDLE:
			if from == ANIM_STOP_L or from == ANIM_STOP_R or from == ANIM_LAND:
				return 0.1
			if from == ANIM_STANDING:
				return 0.3
			return 0.2
		ANIM_TURN_STEP:
			return 0.2
		ANIM_STOP_L, ANIM_STOP_R:
			return 0.15
		ANIM_JUMP_CROUCH:
			return 0.1
		ANIM_JUMP_AIR:
			return 0.08 if from == ANIM_JUMP_CROUCH else 0.25
		ANIM_LAND:
			return 0.05
	return 0.0

# The mech's nose, as a unit vector on the ground plane.
#
# This is the inverse of the atan2(x, z) the turn aims with, and has to stay that way: a sin/cos
# swap here would point the mech's travel across its own facing and put the slide back, mirrored.
# See test_the_nose_matches_the_heading_the_mech_turns_towards.
static func facing_for(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))

# Starts `clip` now and hands over to `next` when it ends. The queue is cleared first: an
# interrupted chain (launch cut short by a movement key) would otherwise leave its follow-up
# sitting in the queue to fire one clip too late.
func _play_chain(clip: String, next: String = "", blend: float = 0.0) -> void:
	if not anim_player.has_animation(clip):
		return
	anim_player.clear_queue()
	anim_player.play(clip, blend)
	if next != "" and anim_player.has_animation(next):
		anim_player.queue(next)

# Parked, being climbed, or sealing / unsealing: the exported chain.
func _drive_parked(piloted: bool) -> void:
	_loco_clip = ""
	anim_player.speed_scale = 1.0
	var clip := parked_clip(piloted, anim_player.current_animation)
	if clip != "":
		_play_chain(clip)

# Starts the clip `loco` wants if it is not already the one running, and keeps the gaits' rate
# matched to the speed.
func _drive_loco_animation(h_speed: float) -> void:
	var current := anim_player.current_animation
	# The boot-up plays out unless the pilot asks for something; standing still is not asking.
	if loco == Loco.STAND and current == ANIM_LAUNCH:
		anim_player.speed_scale = 1.0
		return
	var want := loco_clip(loco, h_speed, _stop_clip)
	if not anim_player.has_animation(want):
		return
	var from: String = current if current != "" else _loco_clip
	if want != _loco_clip or (current == ANIM_STANDING and want == ANIM_STAND_IDLE):
		var blend := blend_for(from, want)
		var phase := -1.0
		if is_gait(want) and is_gait(current):
			# Both gaits put the left plant at u = 0: carry the phase across, the same foot stays down.
			phase = fposmod(anim_player.current_animation_position
				/ anim_player.get_animation(current).length, 1.0)
		elif is_gait(want) and not is_gait(from):
			# Setting off: the left foot reaching for its plant - the lean into the first step.
			phase = 0.75
		_play_chain(want, "", blend)
		if phase >= 0.0:
			anim_player.seek(phase * anim_player.get_animation(want).length, false)
		_loco_clip = want
		if is_gait(want):
			_gait_blend_left = blend
			_gait_half = -1
	match want:
		ANIM_RUN, ANIM_SPRINT:
			anim_player.speed_scale = gait_rate(want, h_speed)
		ANIM_LAND:
			anim_player.speed_scale = _land_rate
		_:
			anim_player.speed_scale = 1.0

# --- the gaits -------------------------------------------------------------
#
# See docs/specs/exia-movement.md. Everything the gaits decide is a pure function up here so the
# tests can pin it without driving a tree.

# The turn rate at `speed`: ROTATE_SPEED at the run, ROTATE_SPEED_SPRINT at a full sprint, blended
# by speed in between so it does not step on the frame the sprint starts.
static func turn_rate(speed: float) -> float:
	return lerpf(ROTATE_SPEED, ROTATE_SPEED_SPRINT,
		clampf((speed - SPEED) / (SPRINT_SPEED - SPEED), 0.0, 1.0))

# The speed to head for and how fast to head for it, as (target, rate), while a key is held.
#
# Sprinting from a standstill is the run ramp and then the sprint ramp, so the sprint ramp only
# begins once the run speed is reached. Dropping the sprint eases back to the run in the brake time.
static func speed_target(sprinting: bool, speed: float, run_rate: float) -> Vector2:
	if sprinting:
		if speed < SPEED - 0.01:
			return Vector2(SPEED, run_rate)
		return Vector2(SPRINT_SPEED, (SPRINT_SPEED - SPEED) / SPRINT_RAMP_TIME)
	if speed > SPEED:
		return Vector2(SPEED, (SPRINT_SPEED - SPEED) / SPRINT_BRAKE_TIME)
	return Vector2(SPEED, run_rate)

# How fast a gait clip plays at `speed`: in proportion to it, so a planted foot moves back through
# the mech at exactly the body's speed through the ramps and the brakes. Floored per gait.
static func gait_rate(clip: String, speed: float) -> float:
	if clip == ANIM_SPRINT:
		return clampf(speed / SPRINT_SPEED, SPRINT_RATE_MIN, 1.0)
	return clampf(speed / SPEED, RUN_RATE_MIN, 1.0)

# The sprint clip's rate. Kept for the sprint tests' sake.
static func sprint_rate(speed: float) -> float:
	return gait_rate(ANIM_SPRINT, speed)

# Metres per second per second of the brake from a sprint down to the run when the keys are let go.
static func release_rate() -> float:
	return (SPRINT_SPEED - SPEED) / SPRINT_RELEASE_TIME

# The launch speed for a JUMP_HEIGHT apex under the mech's gravity.
static func jump_velocity(g: float) -> float:
	return sqrt(2.0 * g * MECH_GRAVITY_SCALE * JUMP_HEIGHT)

# The roll the model leans to, in radians. Into the turn: the lateral acceleration is speed times
# the yaw rate, a left turn has a positive yaw rate, and a left lean is a negative roll about the
# nose. Full lean at 14 m/s on a ~12 m circle.
static func bank_target(speed: float, yaw_rate: float) -> float:
	return -clampf(speed * yaw_rate / BANK_FULL_ACCEL, -1.0, 1.0) * deg_to_rad(BANK_MAX_DEG)

# pilot9's rules for the toggle, with the inputs passed in so a test can drive it without a tree.
# The stop is checked above the press so a press landing on the frame of a stop wins - that is the
# standing-still-then-pressing case.
func _update_sprint_toggle(on_floor: bool, input_held: bool, h_speed: float,
		sprint_pressed: bool, walk_pressed: bool) -> void:
	if not (on_floor and not input_held and h_speed < 0.1):
		_sprint_stop_armed = true
	elif _sprint_stop_armed:
		_sprint_stop_armed = false
		sprint_toggled = false
	if sprint_pressed:
		sprint_toggled = not sprint_toggled
	elif walk_pressed:
		sprint_toggled = false

# Eases the bank towards the lean the turn wants, and writes it onto the Model on top of its
# authored transform - which carries the yaw compensation, so the roll composes with it and never
# replaces it. The pivot is the mech's origin, which is its feet. The collider never tilts.
func _update_bank(delta: float, driving: bool, h_speed: float) -> void:
	var target := 0.0
	if driving and is_on_floor() and delta > 0.0:
		target = bank_target(h_speed, wrapf(rotation.y - _last_yaw, -PI, PI) / delta)
	_last_yaw = rotation.y
	bank = lerpf(bank, target, 1.0 - exp(-BANK_EASE * delta))
	if absf(bank) < 0.00001:
		bank = 0.0
		model.transform = _model_rest
	else:
		model.transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), bank), Vector3.ZERO) \
			* _model_rest

# A footfall is a gait's playhead crossing 0 (left) or half its length (right) - read off the phase
# rather than a method track, so the clips stay pure pose data. Only counts once the clip has its
# full weight, not mid-crossfade.
func _track_footfalls(delta: float) -> void:
	var current := anim_player.current_animation
	if not is_gait(current):
		_gait_half = -1
		return
	_gait_blend_left = maxf(_gait_blend_left - delta, 0.0)
	var length := anim_player.get_animation(current).length
	var half := int(floorf(anim_player.current_animation_position / length * 2.0)) % 2
	if _gait_half != -1 and half != _gait_half and _gait_blend_left <= 0.0:
		_on_footfall(half, current)
	_gait_half = half

# One planted foot. The camera takes a dip (and, sprinting, a shake) - CAMERA MOTION - and the floor
# a ring of dust - MOVEMENT EFFECTS. `half` is 0 for the left foot, 1 for the right. The run takes
# RUN_CAMERA_SHARE of the sprint's dip and smaller dust.
func _on_footfall(half: int, clip: String = ANIM_SPRINT) -> void:
	var sprinting := clip == ANIM_SPRINT
	if Settings.camera_motion:
		_dip = -FOOTFALL_DIP * (1.0 if sprinting else RUN_CAMERA_SHARE)
		_dip_velocity = 0.0
		if sprinting:
			_start_shake(FOOTFALL_SHAKE_DEG, FOOTFALL_SHAKE_TIME)
	if Settings.movement_effects and _vfx != null:
		_vfx.footfall(_planted_ball(half), 1.0 if sprinting else RUN_DUST_SCALE)

# Hit the floor from the air, `fall` metres below the highest point. The biggest dip of the set and a
# shake, both scaled with the fall; a dust ring under each foot; a heavy landing bleeds speed.
func _on_land(fall: float, moving: bool) -> void:
	var k := clampf(fall / JUMP_HEIGHT, 0.5, 2.0)
	if Settings.camera_motion:
		_dip = -LAND_DIP * k
		_dip_velocity = 0.0
		_start_shake(LAND_SHAKE_DEG * k, LAND_SHAKE_TIME)
	if Settings.movement_effects and _vfx != null:
		_vfx.footfall(_planted_ball(0))
		_vfx.footfall(_planted_ball(1))
	if fall >= HEAVY_LANDING:
		velocity.x *= HEAVY_LANDING_KEEP
		velocity.z *= HEAVY_LANDING_KEEP
	_land_rate = land_rate(fall, moving)

# How fast the landing clip plays: quick for a short drop, quicker with a key held.
static func land_rate(fall: float, moving: bool) -> float:
	if fall < LIGHT_LANDING:
		return LIGHT_LANDING_RATE
	return MOVING_LANDING_RATE if moving else 1.0

func _start_shake(deg: float, time: float) -> void:
	_shake_age = 0.0
	_shake_deg = deg
	_shake_time = time

# Where a foot's ball is on the floor, in the world. `half` is 0 for the left foot, 1 for the right.
func _planted_ball(half: int) -> Vector3:
	var at := _ball_world(".L" if half == 0 else ".R")
	return Vector3(at.x, global_position.y, at.z)

func _ball_world(side: String) -> Vector3:
	var bone := _skeleton.find_bone("toe" + side + ".001") if _skeleton != null else -1
	if bone < 0:
		return global_position
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(bone)).origin

# One exact step of a critically damped spring - closed form, so the dip's shape does not depend on
# the frame rate. Returns (offset, velocity). Same spring as pilot9's landing dip.
static func dip_step(x: float, v: float, omega: float, dt: float) -> Vector2:
	var decay := exp(-omega * dt)
	var c := v + omega * x
	return Vector2((x + c * dt) * decay, (v - omega * c * dt) * decay)

# The shake's (pitch, roll) in radians, `age` seconds into a shake of `deg` lasting `time`: random,
# fading to nothing.
static func shake_offset(age: float, deg: float = FOOTFALL_SHAKE_DEG,
		time: float = FOOTFALL_SHAKE_TIME) -> Vector2:
	if age >= time:
		return Vector2.ZERO
	var fade := 1.0 - age / time
	return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * deg_to_rad(deg) * fade

# The widening the sprint adds to the field of view, in degrees.
static func fov_boost_target(h_speed: float) -> float:
	return SPRINT_FOV_BOOST if h_speed > SPRINT_GAIT_SPEED else 0.0

# The camera's offsets and the FOV boosts, advanced one drawn frame. The bounce is a damped share of
# the playing gait's hip height once it has its full weight; the dip and the shake are kicked by
# footfalls and landings; the crouch eases the view down while the jump loads. All zero with CAMERA
# MOTION off. The FOV is not gated by it - pilot9's sprint FOV is not either.
func _step_bound_camera(delta: float) -> void:
	if Settings.camera_motion:
		var target := 0.0
		var current := anim_player.current_animation
		if is_gait(current) and _gait_blend_left <= 0.0 and _hip_tracks.has(current):
			var clip := anim_player.get_animation(current)
			var hip := (clip.position_track_interpolate(_hip_tracks[current],
				anim_player.current_animation_position) as Vector3).y
			var share := BOUNCE_SHARE * (1.0 if current == ANIM_SPRINT else RUN_CAMERA_SHARE)
			target = share * (hip - _hip_means[current]) * travel_scale
		_bounce = lerpf(_bounce, target, 1.0 - exp(-delta / BOUNCE_SMOOTH))
		var spring := dip_step(_dip, _dip_velocity, DIP_OMEGA, delta)
		_dip = spring.x
		_dip_velocity = spring.y
		_shake_age += delta
		var drop := -CROUCH_CAMERA_DROP if loco == Loco.CROUCH and pilot != null else 0.0
		_crouch_drop = lerpf(_crouch_drop, drop, 1.0 - exp(-12.0 * delta))
	else:
		_bounce = 0.0
		_dip = 0.0
		_dip_velocity = 0.0
		_shake_age = INF
		_crouch_drop = 0.0
	var boost := fov_boost_target(Vector2(velocity.x, velocity.z).length()) if pilot != null else 0.0
	_sprint_fov_boost = lerpf(_sprint_fov_boost, boost, 1.0 - exp(-FOV_EASE * delta))
	_jump_fov = lerpf(_jump_fov, 0.0, 1.0 - exp(-JUMP_FOV_EASE * delta))

# --- movement -------------------------------------------------------------
#
# While a pilot drives, what the mech is doing is `loco`, one of Loco. next_loco() is the whole
# transition table (docs/specs/exia-movement.md, "The locomotion state") as a pure function of what
# this frame reads; _physics_process does the entry actions, moves the body the way the state says,
# and _drive_loco_animation() plays the state's clip.

# The state after `state`, given this frame's reading `r`:
#   on_floor, air_time, rising (bool / seconds / bool), wants_move (a key held), heading_off
#   (radians between the nose and where the keys point), h_speed, jump (pressed this frame),
#   time (seconds in `state`), clip_done (the state's one-shot has ended).
static func next_loco(state: Loco, r: Dictionary) -> Loco:
	var grounded: bool = r.on_floor or r.air_time <= COYOTE
	var can_jump: bool = grounded and state != Loco.CROUCH and state != Loco.AIR \
		and not (state == Loco.LAND and r.time < LAND_JUMP_LOCK)
	if r.jump and can_jump:
		return Loco.CROUCH
	if state == Loco.CROUCH:
		return Loco.AIR if r.time >= MechMoves.CROUCH_TIME else Loco.CROUCH
	if state == Loco.AIR:
		return Loco.LAND if r.on_floor and not r.rising and r.time > 0.05 else Loco.AIR
	if not grounded:
		return Loco.AIR
	match state:
		Loco.STAND:
			if r.wants_move:
				return Loco.TURN if r.heading_off > TURN_STEP_ANGLE else Loco.RUN
		Loco.TURN:
			if not r.wants_move:
				return Loco.STAND
			if r.heading_off < TURN_DONE_ANGLE:
				return Loco.RUN
		Loco.RUN:
			if r.wants_move or r.h_speed > EXIT_MAX_SPEED:
				return Loco.RUN
			return Loco.STOP if r.h_speed > STOP_MIN_SPEED else Loco.STAND
		Loco.STOP:
			if r.wants_move:
				return Loco.RUN
			if r.clip_done:
				return Loco.STAND
		Loco.LAND:
			if r.clip_done:
				return Loco.RUN if r.wants_move else Loco.STAND
	return state

func _physics_process(delta: float) -> void:
	var driving := pilot != null and embark_left <= 0.0 and disembark_left <= 0.0 \
		and seal_left <= 0.0 and unseal_left <= 0.0
	if not is_on_floor():
		velocity.y -= gravity * (MECH_GRAVITY_SCALE if driving else 1.0) * delta

	# The climb. EXIA is claimed but not yet driven, so it holds its crouch through the parked
	# branch below exactly as if nobody had pressed anything, and the boot-up waits for her.
	# The countdown is read before it is spent, so the frame she lands still takes that branch:
	# _board() has just started MECH_launch, and parked_clip leaves a launch alone either way.
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
		sprint_toggled = false
		_braking = false
		loco = Loco.STAND
		_update_bank(delta, false, 0.0)
		_drive_parked(false)
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
		_drive_parked(true)
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
		_drive_parked(false)
		move_and_slide()
		_apply_root_motion()
		pilot.ride(seat_follow(_cockpit_world(), _cockpit_board, _pilot_board))
		_aim_camera()
		unseal_left = maxf(unseal_left - delta, 0.0)
		if unseal_left <= 0.0:
			# Cockpit open. She climbs down it.
			_begin_descent()
		return

	_drive(delta)

# One physics frame of a pilot driving: read the keys, advance `loco`, move the body the way the
# state says, play its clip.
func _drive(delta: float) -> void:
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
	direction.y = 0.0
	var wants_to_move := direction.length() > 0.01
	var heading := atan2(direction.x, direction.z) if wants_to_move else rotation.y

	var on_floor := is_on_floor()
	_air_time = 0.0 if on_floor else _air_time + delta
	var h_speed := Vector2(velocity.x, velocity.z).length()
	_update_sprint_toggle(on_floor, input_dir != Vector2.ZERO, h_speed,
		Input.is_action_just_pressed("sprint"), Input.is_action_just_pressed("walk"))

	var before := loco
	loco = next_loco(loco, {
		on_floor = on_floor,
		air_time = _air_time,
		rising = velocity.y > 0.0,
		wants_move = wants_to_move,
		heading_off = absf(wrapf(heading - rotation.y, -PI, PI)),
		h_speed = h_speed,
		jump = Input.is_action_just_pressed("jump"),
		time = _loco_time,
		clip_done = anim_player.current_animation == "",
	})
	if loco != before:
		_enter_loco(before, wants_to_move, h_speed)
	else:
		_loco_time += delta

	match loco:
		Loco.STAND:
			# Stopping from a standstill or a crawl is instant - releasing the keys has to win now. A
			# mech that coasts is a mech that walks off ledges.
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)
		Loco.TURN:
			velocity.x = 0.0
			velocity.z = 0.0
			_step_turn(heading, delta)
		Loco.RUN, Loco.LAND:
			if wants_to_move:
				_run_toward(heading, h_speed, delta, 1.0)
			elif loco == Loco.RUN:
				# Let go above the run speed: down to it, along the way it was travelling, then the stop.
				var along := Vector2(velocity.x, velocity.z).normalized()
				var speed := move_toward(h_speed, SPEED, release_rate() * delta)
				velocity.x = along.x * speed
				velocity.z = along.y * speed
			else:
				velocity.x = move_toward(velocity.x, 0, SPEED)
				velocity.z = move_toward(velocity.z, 0, SPEED)
		Loco.STOP:
			# The stop clip's own brake, so its locked foot holds.
			var along := Vector2(velocity.x, velocity.z).normalized()
			if along == Vector2.ZERO:
				var f := facing_for(rotation.y)
				along = Vector2(f.x, f.z)
			var speed := MechMoves.stop_speed(_loco_time, _stop_v0)
			velocity.x = along.x * speed
			velocity.z = along.y * speed
		Loco.AIR:
			# Committed: the speed it left with. A held key swings the nose round slowly, and the
			# velocity follows it.
			_air_peak = maxf(_air_peak, global_position.y)
			if wants_to_move:
				rotation.y = lerp_angle(rotation.y, heading, turn_rate(h_speed) * AIR_TURN_SHARE * delta)
				var facing := facing_for(rotation.y)
				velocity.x = facing.x * h_speed
				velocity.z = facing.z * h_speed
		# CROUCH: the speed it had, no turning.

	_update_bank(delta, loco == Loco.RUN, h_speed)
	var speed_now := Vector2(velocity.x, velocity.z).length()
	_drive_loco_animation(speed_now)
	_track_footfalls(delta)

	move_and_slide()
	_apply_root_motion()

	_aim_camera()

	if exit_pending and can_exit_now(is_on_floor(), Vector2(velocity.x, velocity.z).length(), loco):
		_exit_mech()

# The entry actions of a state change. `before` is the state left.
func _enter_loco(before: Loco, wants_to_move: bool, h_speed: float) -> void:
	_loco_time = 0.0
	match loco:
		Loco.AIR:
			_air_peak = global_position.y
			if before == Loco.CROUCH and is_on_floor():
				# The push-off.
				velocity.y = jump_velocity(gravity)
				_jump_fov = JUMP_FOV_KICK
		Loco.LAND:
			_on_land(_air_peak - global_position.y, wants_to_move)
		Loco.STOP:
			_stop_v0 = h_speed
			var u := 0.0
			if is_gait(anim_player.current_animation):
				u = anim_player.current_animation_position \
					/ anim_player.get_animation(anim_player.current_animation).length
			_stop_clip = ANIM_STOP_L if MechMoves.stop_lead(u) == ".L" else ANIM_STOP_R
	_braking = loco == Loco.RUN and not wants_to_move

# The body ramps its speed along the nose while the nose turns toward `heading`.
#
# Only the *speed* is ramped; the heading is taken from the mech's nose outright, so the velocity is
# exactly along the facing on every frame and the mech cannot slide. The magnitude is read back off
# the velocity rather than kept in a field so that a collision counts: move_and_slide() bleeds speed
# off against a wall, and the mech then ramps back up out of whatever it was left with.
func _run_toward(heading: float, h_speed: float, delta: float, turn_share: float) -> void:
	_braking = false
	rotation.y = lerp_angle(rotation.y, heading, turn_rate(h_speed) * turn_share * delta)
	var step := speed_target(sprint_toggled, h_speed, acceleration)
	var speed := move_toward(h_speed, step.x, step.y * delta)
	var facing := facing_for(rotation.y)
	velocity.x = facing.x * speed
	velocity.z = facing.z * speed

# One frame of the step-turn: yaw toward `heading` at TURN_STEP_RATE, about the planted foot's ball,
# so that foot stays where it is on the floor and the stepping one carries the turn.
func _step_turn(heading: float, delta: float) -> void:
	var step := clampf(wrapf(heading - rotation.y, -PI, PI), -TURN_STEP_RATE * delta, TURN_STEP_RATE * delta)
	var u := 0.0
	if anim_player.current_animation == ANIM_TURN_STEP:
		u = anim_player.current_animation_position / MechMoves.TURN_LENGTH
	var pivot := _ball_world(MechMoves.turn_pivot(u))
	pivot.y = global_position.y
	var moved := pivot + Basis(Vector3.UP, step) * (global_position - pivot)
	rotation.y = wrapf(rotation.y + step, -PI, PI)
	move_and_collide(moved - global_position)

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
