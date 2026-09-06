extends CharacterBody3D

const SPEED = 6.0
const SPRINT_SPEED = 9.0
# The crouch is a gait, not a handicap: she creeps at full sprint pace. Written as SPRINT_SPEED
# rather than 9.0 so retuning the sprint carries the crouch with it, the way SLIDE_SPEED does.
# Note what this costs the thigh screens - BAND_CROUCH is now unreachable, because they read
# speed rather than state and the crouch no longer has a speed of its own.
const CROUCH_SPEED = SPRINT_SPEED
const JUMP_VELOCITY = 12.5
const MAX_JUMPS = 2
# Apex band: while |velocity.y| is inside this, the jump is 'at the top' and hangs.
const APEX_BAND = 1.6
const RISE_GRAVITY_SCALE = 2.6
const HANG_GRAVITY_SCALE = 1.0
const FALL_GRAVITY_SCALE = 1.0
const MAX_FALL_SPEED = 16.0
# How far move_and_slide reaches down to keep her stuck to a ramp or step that drops out from
# under a purely-horizontal velocity. The engine default is 0.1 m - fine at a walk, but a
# single tick at CROUCH_SPEED/SLIDE_SPEED (9 m/s, sprint pace) drops further than that off the
# top of a downgrade, so she goes briefly airborne every frame and the descent reads as a
# stair-step stutter instead of a smooth slope. 0.5 m clears one frame's fall at that speed
# with room to spare. This keeps her *body* on the slope; the model tilt in _physics_process
# is what makes the slope read as one she is walking down rather than skating across level.
const FLOOR_SNAP_LENGTH = 0.5
# How fast the model's pitch chases a change in grade, in radians per second of blend weight.
# The tilt is the visible model alone - the CharacterBody stays a bolt-upright capsule - so
# this is pure show: it sells the slope the snap above is already walking her along. Kept equal
# to ROTATE_SPEED (declared below) so cresting a ramp sweeps the same way a turn does rather
# than snapping.
const MODEL_SLOPE_PITCH_SPEED = 10.0
# A grade shallower than this reads as flat ground and gets no tilt - keeps the model from
# twitching over the sub-degree normal changes a collision mesh throws off on nominally flat
# floor. About 3 degrees.
const MODEL_SLOPE_PITCH_DEADZONE = deg_to_rad(3.0)
const DASH_SPEED = 18.0
const DASH_TIME = 0.3
# Dash-to-dash interval, measured from the press rather than from the end of the dash, so the
# constant means what it says. The backpack's dash screen is a ready light off the back of this:
# lit while it's spendable, dim for the whole lockout.
const DASH_COOLDOWN = 3.0
# The dash leaves the ground along a line this far above horizontal. It drives its own
# horizontal speed flat out, so the vertical leg of that angle is the kick it launches with -
# tan(30) * DASH_SPEED - and normal gravity bends the line over from there.
const DASH_RISE_ANGLE = 30.0
# The slide is the sprint's version of a crouch: C ducks you when you're running and slides
# you when you're sprinting, so each gait has its own low move, and both are held rather than
# timed - you stay down until you ask to get up. It runs at flat sprint speed, nothing gained
# off the top and nothing bled off the end, so it's free to throw into a sprint and it hands
# the body back at full pace. How far it goes is the player's call, not a constant's.
const SLIDE_MIN_SPEED = 5.0
const SLIDE_SPEED = SPRINT_SPEED
# The dive and the get-up each get their own fixed window, with the hold in between them
# lasting as long as the player leaves C alone.
const SLIDE_ENTRY_TIME = 0.3
const SLIDE_RECOVER_TIME = 0.3
# Steering authority while sliding, well under ROTATE_SPEED: enough to carve a line around
# a corner, not enough to turn the slide into a full-speed pivot.
const SLIDE_TURN_SPEED = 4.0
# How fast the speed driving the RUN state chases her real horizontal speed, in m/s per second.
# Smoothed rather than raw so toggling Shift mid-stride winds the cycle up over the 3 m/s
# between SPEED and SPRINT_SPEED - at 20 that is ~0.15 s, fast enough to feel like the gait
# changed and slow enough not to read as a cut.
const ANIM_SPEED_LERP = 20.0
# The speed SET RUN LOOP is authored at, and so the divisor that turns her real speed into the
# RUN state's playback rate: exactly 1.0 at a run, 1.5 at a sprint.
#
# Run and sprint used to be the two ends of a blend space between SET RUN LOOP and SPRINT LOOP.
# The 2026-09-03 SETSUNA.glb export dropped SPRINT LOOP along with every other start/end clip,
# so the gait change is a playback rate on the one cycle now - which is what keeps a sprint from
# reading as a run played at running cadence. Set RUN_MAX_SCALE to 1.0 to pin the rate and let
# the sprint just cover ground faster.
const RUN_CLIP_SPEED = SPEED
const RUN_MAX_SCALE = SPRINT_SPEED / SPEED
# JUMP state's playback rate. The airborne cycle is authored slower than her hops actually last,
# so at 1.0 a short hop showed maybe a third of it and read as a pose rather than a move. Fixed
# rather than driven off airtime: the clip is a loop she hangs in for as long as she is off the
# ground, so there is no duration to fit it to the way DASH fits its clip into DASH_TIME.
const JUMP_CLIP_SCALE = 2.0
# How fast the model's facing chases the heading it is travelling on. Setsuna's heading used to
# click between 15-degree detents rather than sweep; that was scrapped 2026-09-01 - she travels
# along the input outright now, at any angle, and the body turns to follow.
const ROTATE_SPEED = 10.0
const MOUSE_SENSITIVITY = 0.0025
const PITCH_MIN = -1.3
const PITCH_MAX = 1.3

# The climb into a mech, and the one clip in her set that is not locomotion: a scripted 2.0 s
# move that carries her from a standing pose on the ground to a seated one in EXIA's cockpit.
# The whole climb is authored travel, so where she is standing when it starts is the whole of
# the wiring - the vehicle picks that spot. See docs/specs/exia-pilot.md.
const ANIM_EMBARK := "SET embark"

# The walk-off-a-ledge cycle. Named because its loop mode is set apart from the others in
# _ready() - it is the one clip in her set that ping-pongs. See there for why.
const ANIM_FALL := "SET Falling"

# The pitch her camera is put back to when she is handed out of a mech - level, which is where
# it sits at the start of the game. The ejection ends on her ordinary framing rather than on a
# special one, and never on whatever the mech's camera was left pointing at.
# See docs/specs/mech-camera-handover.md.
const EXIT_PITCH = 0.0

# Her measured height, so the collider is the model rather than a round number. The 2026-09-03
# rebuild of assets/setsuna.glb dropped her from 1.8787 m to 1.6725 m (top of the head box at
# y 1.7902 through the metarig's 0.9343115 scale), and the old 1.8 left the capsule standing
# ~13 cm proud of her. Re-measure this after a rebuild that changes her silhouette; a re-export
# that only touches animation cannot move it.
#
# CROUCH_HEIGHT is NOT derived from it - it is a gameplay number, what gap she can duck under,
# and it stays where it was tuned.
const STAND_HEIGHT = 1.6725
const CROUCH_HEIGHT = 1.0
# How fast the debug keys move the placeholder meters, in fraction per second.
const DEBUG_METER_RATE = 0.6
const CROUCH_LERP_SPEED = 8.0
const RUN_MODEL_LIFT = 0.08

# --- The crouch lean ---
# All three crouch clips are static *poses*, not cycles - nothing in any of them moves over its
# own second. SET CROUCH LOOP is the upright crouch; SET CROUCH LOOP LEFT and RIGHT are the same
# crouch leaning to one side. So the CROUCH state is a blend space with the three of them on a
# -1..+1 axis, and the axis is her *turn*: any direction held with her facing where she is going
# is the neutral crouch, and she banks into a corner for as long as she is coming round.
#
# What drives it is the angle between where she is pointing and where the input says to go -
# her heading lag. `rotation.y` chases that direction at ROTATE_SPEED, so the lag *is* the turn:
# it is ROTATE_SPEED x bigger the harder she is cornering, it holds while a mouse swing keeps
# pulling the target round, and it falls to zero the moment she lines up with it. Reading the
# lag rather than the per-frame yaw delta keeps this out of the movement block and off the
# frame rate.
#
# The heading lag, in radians, that leans her all the way over. 15 degrees is about a 90 deg/s
# corner held; tapping a new direction out of a straight line overshoots it and saturates, which
# is the "hold W, press D" bank the lean exists for. Lower it for a twitchier lean.
const CROUCH_LEAN_ANGLE = deg_to_rad(15.0)
# How fast the axis eases between the three poses, in axis units per second. The blend position
# is a parameter rather than a transition, so this is the one hand-off in the crouch the state
# machine cannot fade for us - without it the poses would pop. It has to outrun the corner it is
# leaning into: a tapped turn is over in about 0.3 s, so anything under ~5 arrives after she has
# already straightened up and the bank never shows.
const CROUCH_LEAN_SPEED = 8.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
var camera_yaw := 0.0
var camera_pitch := 0.0
var current_height := STAND_HEIGHT
var jumping := false
var crouching := false
var crouch_was_pressed := false
var sprinting := false
var sprint_was_pressed := false
var jumps_used := 0
var jump_queued := false
var dash_time_left := 0.0
var dash_cooldown_left := 0.0
var dash_dir := Vector3.ZERO
var dash_queued := false
# Placeholders, and honestly so. The backpack's health and stamina screens need something to
# read, and nothing in the game damages the player or costs him a sprint yet - sprint is an
# uncosted toggle. These are plain 0..1 floats moved by the debug keys below, so the screens are
# wired to real variables from the start and landing the real systems changes nothing at the
# screen end. See docs/specs/setsuna-screens.md.
var health := 1.0
var stamina := 1.0
var sliding := false
var slide_dir := Vector3.ZERO
var slide_time_left := 0.0
var slide_recovering := false
# Her horizontal speed, chased toward the real one at ANIM_SPEED_LERP and fed to the RUN state's
# TimeScale. Smoothed rather than raw so the cycle winds up and down instead of snapping the
# frame the Shift toggle flips.
var _anim_speed := 0.0
# The CROUCH blend space's axis, -1 (leaning left) .. +1 (leaning right), 0 being the upright
# crouch. Chased toward the turn she is in rather than written outright, so the three held poses
# cross-fade into each other instead of popping.
var _crouch_lean := 0.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_pitch_node: Node3D = $CameraPivot/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraPivot/CameraPitch/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/CameraPitch/SpringArm3D/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var player_model: Node3D = $PlayerModel
@onready var anim_player: AnimationPlayer = $PlayerModel/AnimationPlayer
# Her locomotion state machine (resources/setsuna_locomotion_tree.tres). Every transition
# between the locomotion clips is an object in there with its own crossfade, which is the whole
# point: nothing in this script can stomp a blend halfway through any more. This script only
# feeds it - condition bools each frame, and travel() for the two discrete moves.
# See docs/specs/setsuna-animation-tree.md.
#
# The one thing it does not own is `embark`, which is played forwards, backwards and seeked to
# arbitrary frames by the vehicle handover; the tree is switched off for that whole sequence and
# the raw anim_player calls below run unchanged.
@onready var anim_tree: AnimationTree = $PlayerModel/AnimationTree
@onready var _sm: AnimationNodeStateMachinePlayback = anim_tree["parameters/playback"]

# Every clip is set up behind a has_animation() guard, and that is load-bearing rather than
# defensive: scripts/setsuna_import.gd drops the unfinished clips out of the export, so the
# guards here and through _physics_process are what make a half-finished animation set play
# as a smaller move list instead of a broken one.
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_snap_length = FLOOR_SNAP_LENGTH
	# Don't let the camera's spring arm collide with our own body.
	spring_arm.add_excluded_object(get_rid())
	# The clips a state can sit in indefinitely: the three she rests in on the ground, and the
	# two she hangs in off it. SET JUMP LOOP is a whole airborne cycle rather than a one-shot
	# flip now - there is no wind-up or landing clip left for it to sit between.
	#
	# The crouch poses are static, so their loop mode never actually shows; it is set with the
	# rest so the blend space's `sync` has three clips of one mind about their playhead.
	for clip: String in ["SET IDLE", "SET RUN LOOP", "SET CROUCH LOOP", "SET CROUCH LOOP LEFT",
			"SET CROUCH LOOP RIGHT", "SET JUMP LOOP"]:
		if anim_player.has_animation(clip):
			anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	# SET Falling is the exception, and it is faked rather than fixed. Its first and last frames
	# are ~29 degrees apart across the legs and arms, so LOOP_LINEAR snaps back to the start once
	# a second on a long drop. Ping-pong plays it forwards and then straight back down again, so
	# the only join is the clip against its own mirror - the pose either end is identical by
	# construction and there is nothing left to pop. The real fix is matching the two poses in
	# Blender; until then the drop reads as a 2.0 s cycle instead of a 1.0 s one with a hitch.
	if anim_player.has_animation(ANIM_FALL):
		anim_player.get_animation(ANIM_FALL).loop_mode = Animation.LOOP_PINGPONG
	# The airborne cycle runs at JUMP_CLIP_SCALE for the whole game. Written once here rather
	# than per frame in _physics_process, the way RUN's and DASH's rates are: nothing about it
	# changes with what she is doing.
	anim_tree["parameters/JUMP/TimeScale/scale"] = JUMP_CLIP_SCALE
	# The two one-shots. SET DASH is squeezed into DASH_TIME and has to stop on its last frame;
	# SET embark is *held* on its last frame, which is her sitting in the cockpit - looping it
	# would drop her back down the machine and climb it again while the mech boots up.
	for clip: String in ["SET DASH", ANIM_EMBARK]:
		if anim_player.has_animation(clip):
			anim_player.get_animation(clip).loop_mode = Animation.LOOP_NONE

# How long the climb into a vehicle takes, or 0.0 when the export has no clip for it - which is
# the vehicle's signal to take her aboard on the spot instead, the way F worked before the climb
# existed. `embark` is dropped at import unless it is listed in scripts/setsuna_import.gd's
# allow-list, so this goes to 0.0 by exactly the same switch every other clip of hers has.
func embark_length() -> float:
	if not anim_player.has_animation(ANIM_EMBARK):
		return 0.0
	return anim_player.get_animation(ANIM_EMBARK).length

# Starts the climb. The vehicle picks where it starts from - EXIA's EmbarkPoint, off its flank -
# because the clip is authored travel from that exact spot: her body does not move for the whole
# 2 s, the bones do, so being put down a metre out means climbing into thin air beside the mech.
#
# She is frozen here rather than at the end: the climb is a cutscene of her own body, and it
# would fight live input the whole way up. Returns the length so the vehicle can wait it out.
func begin_embark(mount_position: Vector3, mount_yaw: float) -> float:
	# The locomotion tree is switched off for the whole climb-ride-descent sequence. `embark` is
	# played forwards, backwards and seeked to arbitrary frames from here, and an AnimationTree
	# owns the skeleton too hard to allow any of that. exit_vehicle() switches it back on.
	anim_tree.active = false
	global_position = mount_position
	rotation.y = mount_yaw
	# Her camera keeps looking the way it was looking. It is only carried along for the first
	# fraction of the climb - the vehicle pans out of it - but the pan sets off from this shot,
	# and without this the snap onto the mark would swing it by however far she was turned.
	camera_pivot.rotation.y = camera_yaw - rotation.y
	_hand_over_controls()
	# The run lift and the slope tilt are both left on by a freeze mid-stride, and the climb is
	# neither a run nor on a slope.
	player_model.position.y = 0.0
	player_model.rotation.x = 0.0
	if anim_player.has_animation(ANIM_EMBARK):
		anim_player.play(ANIM_EMBARK)
		# play() resumes a clip that is already current; the climb always starts at the top.
		anim_player.seek(0.0, true)
	return embark_length()

# She is aboard: the vehicle is driving now, and she is not on screen. Called at the end of the
# canopy close, or outright when there is no climb to play.
func enter_vehicle(_vehicle: Node3D) -> void:
	visible = false
	_hand_over_controls()

# Carried by EXIA's closing cockpit. Between the end of the climb and the moment MECH_launch
# seals the canopy she is still on screen, held on `embark`'s last frame, and the mech drives her
# whole frozen rig from the cockpit bone each physics frame by handing the seated transform here.
# Her body is already out of the simulation - `_hand_over_controls` ran when the climb began - so
# this is a plain transform write. `enter_vehicle()` hides her once the canopy is shut.
func ride(seat_transform: Transform3D) -> void:
	global_transform = seat_transform

# The canopy opening, and the seal run the other way: EXIA is powering down, sliding its cockpit
# back open, and she comes out on it - on screen again, still frozen, still holding `embark`'s
# last frame, with the mech driving her whole rig from the cockpit bone through ride() exactly as
# it did on the way in. begin_disembark() takes her from there down the machine.
#
# The seated pose is normally still on her skeleton from the climb - `embark` is LOOP_NONE and
# nothing of hers has played since - but it is seeked to rather than assumed, so a pilot who was
# boarded some other way still comes out of the cockpit sitting in it.
func begin_unseal() -> void:
	anim_tree.active = false
	visible = true
	_hand_over_controls()
	if anim_player.has_animation(ANIM_EMBARK):
		anim_player.play(ANIM_EMBARK)
		anim_player.seek(embark_length(), true)

# The climb out, which is the climb in played backwards. EXIA has powered down and opened its
# canopy around her, and the same 2 s of `embark`, run from its last frame to its first, carries
# her out of the cockpit and back down onto the mark she climbed on from. Nothing was animated
# for it - see the spec's Disembarking section.
#
# She is put on the mark first for the same reason begin_embark does it: the clip is authored
# travel, so the whole descent is drawn relative to wherever her body is standing, and the
# vehicle is the thing that knows where that is. The transform is rebuilt from scratch rather
# than positioned, because ride() has just been writing the cockpit bone's basis onto her.
#
# Returns the length so the vehicle can wait it out, the same as the climb.
func begin_disembark(mount_position: Vector3, mount_yaw: float) -> float:
	anim_tree.active = false
	global_transform = Transform3D(Basis.IDENTITY, mount_position)
	rotation.y = mount_yaw
	visible = true
	_hand_over_controls()
	# The run lift and slope tilt belong to a stride, and nothing has cleared them since she
	# climbed in.
	player_model.position.y = 0.0
	player_model.rotation.x = 0.0
	if anim_player.has_animation(ANIM_EMBARK):
		anim_player.play_backwards(ANIM_EMBARK)
		# `embark` is already the assigned clip - she has been holding its last frame since the
		# climb - and play() resumes an assigned clip rather than restarting it, so the descent
		# says where it starts outright. The mirror of begin_embark's seek to 0.
		anim_player.seek(embark_length(), true)
	return embark_length()

# Stops her being a body anyone is driving. Shared by the climb and by the moment the vehicle
# takes her aboard - the difference between those two is only whether she is still on screen,
# which is why the visibility is not in here.
func _hand_over_controls() -> void:
	velocity = Vector3.ZERO
	collision_shape.disabled = true
	set_physics_process(false)
	set_process_unhandled_input(false)

# Hands her body back at `exit_position`, pointed along `facing_yaw`. The vehicle picks both:
# EXIA puts her out of the back of itself facing the machine, so what she is looking at when
# she lands is the mech she just climbed out of.
#
# The camera is placed behind her rather than left where it was. Her camera_yaw is still holding
# the heading she walked up to the mech on, and the mech has been orbiting its own camera since;
# either one is an arbitrary angle by the time she is handed back, and dropping her looking at
# her own back is exactly the bug the entry angle fixed on the way in.
func exit_vehicle(exit_position: Vector3, facing_yaw: float) -> void:
	# ride() drove her entire transform off EXIA's cockpit bone through the canopy close, and that
	# bone carries the armature scale that sizes the mech (see mech.gd's root-motion note) along
	# with the seated pose's backward tilt. Setting position and yaw alone would leave that scale
	# and tilt sitting on her basis - she would climb out oversized and leaning back. Rebuild the
	# transform from scratch so she is upright at unit scale however ride() left her.
	global_transform = Transform3D(Basis.IDENTITY, exit_position)
	rotation.y = facing_yaw
	camera_yaw = yaw_behind(facing_yaw)
	camera_pitch = EXIT_PITCH
	camera_pivot.rotation.y = camera_yaw - rotation.y
	camera_pitch_node.rotation.x = camera_pitch
	velocity = Vector3.ZERO
	visible = true
	collision_shape.disabled = false
	# Her body is hers again, so the locomotion tree takes the skeleton back. It restarts at
	# IDLE, which is where a pilot who has just climbed down a mech should be.
	anim_tree.active = true
	_anim_speed = 0.0
	set_physics_process(true)
	set_process_unhandled_input(true)
	camera.current = true

# The world yaw that puts the camera behind a body facing `body_yaw`: half a turn round, since
# the model's nose is its +Z and the camera looks along its pivot's -Z. mech.gd carries the same
# function for the same reason - the two rigs are built the same way, and this is the one line
# where that convention is written down.
static func yaw_behind(body_yaw: float) -> float:
	return wrapf(body_yaw + PI, -PI, PI)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * MOUSE_SENSITIVITY
		camera_pitch = clamp(camera_pitch - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		jump_queued = true
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_CTRL:
		dash_queued = true

# The jump arc is deliberately not a uniform parabola. Heavy gravity on the way up turns the
# launch into a fast pop that bleeds its speed quickly, so the push-off reads as an explosive
# shove rather than a lazy lob. Inside the apex band gravity mostly lets go and the player
# floats. The descent keeps that same light gravity, so the drop falls at the hang's pace
# instead of accelerating into a slam.
func _gravity_scale() -> float:
	if velocity.y > APEX_BAND:
		return RISE_GRAVITY_SCALE
	if velocity.y < -APEX_BAND:
		return FALL_GRAVITY_SCALE
	return HANG_GRAVITY_SCALE

# Moves the CROUCH blend axis one frame toward the turn she is in, and returns where it lands:
# -1 (leaning left) .. +1 (leaning right), 0 the upright crouch.
#
# `lag` is the signed heading lag in radians - how far the input direction is round from where
# she is pointing, which is the same thing as how hard she is turning. Its sign is the yaw's, so
# it is *positive going left*: her nose is local +Z, so her right is local -X, and swinging the
# forward vector that way is a decreasing rotation.y. Hence the negation - the axis is signed the
# other way round, +1 being the right-hand pose.
#
# Split out of _physics_process so it can be tested: the crouch is three held poses and this
# function, so an axis that silently never leaves 0 looks exactly like a lean that was never
# wired, and a sign error looks exactly like two poses exported the wrong way round.
func _step_crouch_lean(lag: float, delta: float) -> float:
	var target := clampf(-lag / CROUCH_LEAN_ANGLE, -1.0, 1.0)
	_crouch_lean = move_toward(_crouch_lean, target, CROUCH_LEAN_SPEED * delta)
	return _crouch_lean

# The pitch to put on the model so it lies along the grade she is standing on, in radians:
# positive is nose-down (heading downhill), negative is nose-up (climbing). Zero on flat
# ground, on a grade shallower than the deadzone, or when `facing` runs straight across the
# slope with no up or down to it.
#
# `facing` is her world forward (+Z nose, so transform.basis.z); `floor_normal` is what
# get_floor_normal() hands back. Dropping `facing`'s component along the normal leaves the
# part of it that lies in the slope plane, and how far that dips below level - its y - is the
# sine of the grade she is walking. rotation.x is nose-down for positive angles and +Z tipped
# below horizontal (negative y) is the downhill case, hence the negation.
#
# Split out and static for the same reason _step_crouch_lean is: it is pure trig with a sign
# convention that is easy to get backwards, and a flipped sign here looks exactly like a model
# that leans back going downhill.
static func _slope_pitch(facing: Vector3, floor_normal: Vector3) -> float:
	var along_slope := facing - floor_normal * facing.dot(floor_normal)
	if along_slope.length() < 0.001:
		return 0.0
	var pitch := asin(clampf(-along_slope.normalized().y, -1.0, 1.0))
	return 0.0 if absf(pitch) < MODEL_SLOPE_PITCH_DEADZONE else pitch

# Hands the jump to the tree, which owns the rest of it: JUMP is the whole airborne cycle and it
# loops there until one of the landing conditions comes true. Shared by the grounded and the
# air jump. The wind-up and landing clips it used to sit between are gone from the export - the
# crossfades on the way in and out do that job now.
#
# travel() rather than a condition bool, so there is no one-frame race between setting a flag
# and the tree happening to look at it. Every other state has an explicit travel-only transition
# into JUMP; the air jump is a no-op on the animation because she is already in it, so the
# double jump re-pops her height without re-popping the flip.
func _start_jump_anim() -> void:
	_sm.travel("JUMP")

# --- Slide ---
# SLIDE START is the dive and SLIDE END the get-up, and the gap between them is the slide:
# a finished one-shot leaves its last frame on the body, so the dive simply stays held until
# the player taps C for the get-up or jumps out. That hold is why the animation is two clips
# and not one.
#
# Squeezes a clip into a fixed window the way the DASH clip is squeezed into DASH_TIME, so
# retiming it in Blender changes how the move looks and never how long it takes.
func _clip_scale(clip: String, window: float) -> float:
	if window <= 0.0 or not anim_player.has_animation(clip):
		return 1.0
	return anim_player.get_animation(clip).length / window

# Crouch only becomes a slide at a sprint, with real speed to spend and nothing else already
# owning the body. Anything short of that is a plain crouch instead.
func _can_slide(at_sprint: bool) -> bool:
	if not at_sprint:
		return false
	if not is_on_floor() or jumping or dash_time_left > 0.0:
		return false
	if not anim_player.has_animation("SLIDE START"):
		return false
	return Vector3(velocity.x, 0.0, velocity.z).length() >= SLIDE_MIN_SPEED

func _start_slide() -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	slide_dir = flat.normalized() if flat.length() > 0.01 else transform.basis.z
	slide_time_left = SLIDE_ENTRY_TIME
	slide_recovering = false
	sliding = true
	crouching = false
	rotation.y = atan2(slide_dir.x, slide_dir.z)
	anim_player.play("SLIDE START", -1, _clip_scale("SLIDE START", SLIDE_ENTRY_TIME))
	anim_player.seek(0.0, true)

# The get-up, and the only thing that ends a slide on its own terms - jumping and dashing
# take the body away instead. Asking for it twice does nothing; the first one already won.
func _finish_slide() -> void:
	if slide_recovering:
		return
	if not anim_player.has_animation("SLIDE END"):
		_cancel_slide()
		return
	slide_recovering = true
	slide_time_left = SLIDE_RECOVER_TIME
	anim_player.play("SLIDE END", -1, _clip_scale("SLIDE END", SLIDE_RECOVER_TIME))
	anim_player.seek(0.0, true)

# Hands the horizontal velocity back to normal movement, leaving whatever speed is on it.
func _cancel_slide() -> void:
	sliding = false
	slide_recovering = false
	slide_time_left = 0.0

# Held rather than tapped, so a meter can be dragged to any value and watched on Setsuna's back
# while it moves. 1/2 drain and fill health, 3/4 do the same for stamina - the number row is clear
# of everything the movement keys use. Goes away with the real systems.
func _debug_meters(delta: float) -> void:
	var step := DEBUG_METER_RATE * delta
	if Input.is_key_pressed(KEY_1):
		health = clampf(health - step, 0.0, 1.0)
	if Input.is_key_pressed(KEY_2):
		health = clampf(health + step, 0.0, 1.0)
	if Input.is_key_pressed(KEY_3):
		stamina = clampf(stamina - step, 0.0, 1.0)
	if Input.is_key_pressed(KEY_4):
		stamina = clampf(stamina + step, 0.0, 1.0)

func _physics_process(delta: float) -> void:
	_debug_meters(delta)

	if not is_on_floor():
		velocity.y -= gravity * _gravity_scale() * delta
		velocity.y = max(velocity.y, -MAX_FALL_SPEED)

	# Sprint is a toggle like the crouch, and it's resolved before the crouch toggle because
	# it decides what C even means: sprinting it's a slide, running it's a duck. The two
	# gaits are exclusive, so picking one drops the other and the pairs stay clean.
	var sprint_pressed := Input.is_key_pressed(KEY_SHIFT)
	if sprint_pressed and not sprint_was_pressed:
		sprinting = not sprinting
		if sprinting:
			crouching = false
	sprint_was_pressed = sprint_pressed
	# Crouch is a toggle: tap C to duck, tap again to stand. Read as an edge off the same
	# polling the rest of the movement keys use, so nothing depends on the event reaching
	# _unhandled_input. What the tap means depends on what the body is already doing - at a
	# sprint it's a slide, mid-slide it's the bail-out, crouched it's the stand-up.
	var crouch_pressed := Input.is_key_pressed(KEY_C)
	if crouch_pressed and not crouch_was_pressed:
		if sliding:
			# Tapping C again is how you stand back up, and until it comes the slide holds.
			# It also cuts a dive short, which is the one thing that shortens a slide.
			_finish_slide()
		elif crouching:
			# Standing up is a crossfade out of the CROUCH state, not a clip: the get-up went
			# with the rest of the start/end animations in the 2026-09-03 export.
			crouching = false
		elif _can_slide(sprinting):
			_start_slide()
		else:
			# Too slow to slide, so it's a duck - and ducking is the other half of dropping
			# out of a sprint, which is what makes C usable without reaching for Shift first.
			crouching = true
			sprinting = false
	crouch_was_pressed = crouch_pressed
	# The dash and a grounded jump both stand you up and then run as normal - crouch never
	# blocks them. Held crouch had a natural moment to leave the pose (letting go of C) and
	# a toggle doesn't, so these inputs are that moment instead. Sprint used to be on this
	# list too, but a toggle can't be: left on, it would cancel every crouch on every frame.
	# It clears the crouch from its own press instead. The dash does the same from inside
	# its own block, where the cooldown is cleared and we know the dash is really firing.
	if crouching and is_on_floor() and (jump_queued or Input.is_key_pressed(KEY_SPACE)):
		crouching = false
	var is_crouching := crouching
	var is_sprinting := sprinting
	# A slide ducks the collider the same way a crouch does, without being a crouch.
	var target_height := CROUCH_HEIGHT if (is_crouching or sliding) else STAND_HEIGHT
	current_height = move_toward(current_height, target_height, CROUCH_LERP_SPEED * delta)
	collision_shape.shape.height = current_height
	collision_shape.position.y = current_height / 2.0
	mesh_instance.mesh.height = current_height
	mesh_instance.position.y = current_height / 2.0
	# The camera stays at standing eye height in every state - crouching shrinks the collider
	# and the mesh, but dropping the view with it makes the camera feel like it's bobbing.
	camera_pivot.position.y = STAND_HEIGHT

	# Landing is deliberately uneventful for gameplay - you keep your speed and your control.
	# There is no landing clip at all since the 2026-09-03 export: touchdown is a crossfade out
	# of JUMP into whatever she is doing on the ground, and it locks nothing. There used to be a
	# CROUCH START touchdown with a freeze behind it; the pose looked good and the stop killed
	# every line of movement it landed in.
	#
	# Jump budget. Leaving the ground without jumping (walked off a ledge) spends the
	# grounded jump, so a ledge drop still only grants the one air jump.
	if is_on_floor() and velocity.y <= 0.0:
		jumps_used = 0
	elif not is_on_floor() and jumps_used == 0:
		jumps_used = 1

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor() and not is_crouching and dash_time_left <= 0.0:
		velocity.y = JUMP_VELOCITY
		jumping = true
		jumps_used = 1
		# Jumping is the other way out of a slide.
		_cancel_slide()
		_start_jump_anim()
	elif jump_queued and jumps_used < MAX_JUMPS and dash_time_left <= 0.0:
		# Air jump: a fresh press only, and the vertical velocity is reset rather than added
		# to, so the second hop is the same height whether you're rising or already falling.
		velocity.y = JUMP_VELOCITY
		jumping = true
		jumps_used += 1
		_cancel_slide()
		_start_jump_anim()
	jump_queued = false

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

	# Crouch only slows you down on the ground. Airborne it's just a pose - ducking
	# mid-jump shouldn't brake the arc, and the toggle can still be tapped in the air
	# to land already crouched.
	var speed := SPRINT_SPEED if is_sprinting else SPEED
	if is_crouching and is_on_floor():
		speed = CROUCH_SPEED
	var cam_basis := camera_pivot.global_transform.basis
	var direction := cam_basis * Vector3(input_dir.x, 0, input_dir.y)

	# --- Dash ---
	# A short burst along the movement input (or straight ahead when standing still).
	# While it runs it owns the horizontal velocity - gravity still applies.
	dash_cooldown_left = max(dash_cooldown_left - delta, 0.0)
	if dash_queued and dash_time_left <= 0.0 and dash_cooldown_left <= 0.0:
		dash_dir = direction.normalized() if direction.length() > 0.01 else transform.basis.z
		dash_dir.y = 0.0
		dash_dir = dash_dir.normalized()
		dash_time_left = DASH_TIME
		dash_cooldown_left = DASH_COOLDOWN
		rotation.y = atan2(dash_dir.x, dash_dir.z)
		# Kicked, not held: the dash owns the horizontal speed for its whole window but only
		# sets the vertical once, so the launch leaves at DASH_RISE_ANGLE and gravity arcs it
		# over from there instead of holding a straight ramp.
		velocity.y = DASH_SPEED * tan(deg_to_rad(DASH_RISE_ANGLE))
		jumping = false
		# The dash wins over the crouch and the slide; the collider lerps back up from here.
		crouching = false
		_cancel_slide()
		if anim_player.has_animation("SET DASH"):
			# Speed-scale the clip so it lands exactly with the end of the dash window. It is the
			# DASH state's TimeScale rather than a play() argument now, and it has to be written
			# before the travel so the state starts at the right rate on its first frame.
			var dash_anim_len := anim_player.get_animation("SET DASH").length
			anim_tree["parameters/DASH/TimeScale/scale"] = dash_anim_len / DASH_TIME
		_sm.travel("DASH")
	dash_queued = false

	var dashing := dash_time_left > 0.0
	if dashing:
		dash_time_left -= delta
		velocity.x = dash_dir.x * DASH_SPEED
		velocity.z = dash_dir.z * DASH_SPEED
	elif sliding:
		# The slide owns the horizontal velocity for its whole window - steering is dead,
		# and the speed only ever goes down from the entry boost.
		# Locked to sprint speed the whole way down, so the slide is a wash on pace and
		# hands the body back at full speed instead of something you accelerate out of.
		# The input still steers: it can't change how fast the slide goes, only where, so
		# a carved line is worth more than a straight one without ever being free.
		slide_time_left = max(slide_time_left - delta, 0.0)
		if direction.length() > 0.01:
			var slide_yaw := atan2(slide_dir.x, slide_dir.z)
			slide_yaw = lerp_angle(slide_yaw, atan2(direction.x, direction.z), SLIDE_TURN_SPEED * delta)
			slide_dir = Vector3(sin(slide_yaw), 0.0, cos(slide_yaw))
			rotation.y = slide_yaw
		velocity.x = slide_dir.x * SLIDE_SPEED
		velocity.z = slide_dir.z * SLIDE_SPEED
		# The clock only bounds the two clips. Run out of it without a get-up started and
		# the slide is in its hold, where it sits until the player asks to leave.
		if slide_recovering and slide_time_left <= 0.0:
			_cancel_slide()
	elif direction.length() > 0.01:
		# Travel goes exactly along the input at whatever angle it comes in at, and the model's
		# facing sweeps round after it. Nothing quantises the heading any more.
		direction = direction.normalized()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), ROTATE_SPEED * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	# Touchdown ends the jump as a piece of gameplay state - the collider, the slide test and the
	# dash all read `jumping`. The landing *animation* is not decided here: the ground conditions
	# below come true on the same frame and carry JUMP straight into IDLE, RUN or CROUCH over
	# their own crossfade, which is why landing still costs no speed and no control.
	if jumping and is_on_floor() and velocity.y <= 0.0:
		jumping = false

	move_and_slide()

	# --- Animation ---
	# All of it, and all of it declarative: four condition bools, the run cycle's rate and the
	# crouch stride's blend position. Which clip plays, and how it gets there from the last one,
	# is the state machine's business - see docs/specs/setsuna-animation-tree.md.
	#
	# Setsuna's export carries no start or end clips as of 2026-09-03, so every hand-off between
	# these states is a crossfade authored on the transition rather than an animation. That is
	# what the xfade_time on each row of the tree's table is for, and it is the only thing
	# standing between two clips now.
	#
	# Fed after move_and_slide() rather than before it, because is_on_floor() only tells the truth
	# about *this* frame afterwards. Set beforehand, the frame she jumps still reports on_floor
	# and the ground conditions would pull her straight back out of JUMP before it drew a frame.
	# The tree ticks in its own _physics_process, which Godot runs after this node's, so writing
	# them here still lands them in the same physics step.

	# Every condition off three facts: on the floor, holding a direction, holding the crouch.
	# The four of them are mutually exclusive and cover every case by construction, which is
	# what keeps the "one live exit per state" invariant true without any of the pre-ANDed
	# polarity pairs the old table needed: a transition can only AND its conditions, never
	# negate one, so the negations are baked into the four bools instead.
	var grounded := is_on_floor()
	var pressing := direction.length() > 0.01
	var moving := grounded and pressing and not is_crouching
	var stopped := grounded and not pressing and not is_crouching
	anim_tree["parameters/conditions/moving"] = moving
	anim_tree["parameters/conditions/not_moving"] = stopped
	# One condition for the whole crouch, standing or walking: the CROUCH state covers both, and
	# which of them she is doing is the blend position below rather than a second state.
	anim_tree["parameters/conditions/crouching"] = grounded and is_crouching
	anim_tree["parameters/conditions/off_floor"] = not grounded

	var flat_speed := Vector2(velocity.x, velocity.z).length()
	_anim_speed = move_toward(_anim_speed, flat_speed, ANIM_SPEED_LERP * delta)
	# The run cycle's playback rate. Never below 1.0: the clip is authored at RUN_CLIP_SPEED and
	# slowing it down under that would only show up on the two ends of a stop, where the
	# crossfade owns the body anyway.
	anim_tree["parameters/RUN/TimeScale/scale"] = clampf(_anim_speed / RUN_CLIP_SPEED, 1.0, RUN_MAX_SCALE)

	# The crouch lean: she banks into whatever corner she is coming round, and crouches upright
	# once she is pointing where she is going. The turn is measured as her heading lag - the
	# angle from her facing to the direction the input is asking for - which is zero on a
	# straight line however fast she is moving, and which the movement block above is already
	# closing at ROTATE_SPEED. Standing still there is no direction to lag behind, so no lean.
	#
	# Written every frame rather than only while crouching, so the axis has already eased to the
	# turn she is actually in by the time the CROUCH state fades in again.
	var heading_lag := angle_difference(rotation.y, atan2(direction.x, direction.z)) if pressing else 0.0
	anim_tree["parameters/CROUCH/blend_position"] = _step_crouch_lean(heading_lag, delta)

	camera_pivot.rotation.y = camera_yaw - rotation.y
	camera_pitch_node.rotation.x = camera_pitch

	# The CROUCH clips animate the mesh down themselves, so the root stays put while crouching.
	# Lift slightly while running since the RUN animation's foot-down pose sits lower than IDLE and clips the ground.
	var is_running := moving and not dashing and not is_crouching and not sliding
	player_model.position.y = RUN_MODEL_LIFT if is_running else 0.0

	# Tip the model along the grade so a ramp reads as one she is walking up or down rather than
	# skating across on the level. Only the model moves - the capsule that does the colliding
	# stays vertical - and it eases toward the target rather than snapping, so cresting a ramp
	# sweeps like a turn. Released to level the moment she leaves the ground: an airborne body
	# has no grade to lie along, and get_floor_normal() is stale once is_on_floor() goes false.
	var pitch_target := _slope_pitch(global_transform.basis.z, get_floor_normal()) if is_on_floor() else 0.0
	player_model.rotation.x = lerp_angle(player_model.rotation.x, pitch_target, MODEL_SLOPE_PITCH_SPEED * delta)
