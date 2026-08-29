extends CharacterBody3D

const SPEED = 6.0
const SPRINT_SPEED = 9.0
const CROUCH_SPEED = 3.0
const JUMP_VELOCITY = 12.5
const MAX_JUMPS = 2
# Apex band: while |velocity.y| is inside this, the jump is 'at the top' and hangs.
const APEX_BAND = 1.6
const RISE_GRAVITY_SCALE = 2.6
const HANG_GRAVITY_SCALE = 1.0
const FALL_GRAVITY_SCALE = 1.0
const MAX_FALL_SPEED = 16.0
const DASH_SPEED = 18.0
const DASH_TIME = 0.3
const DASH_COOLDOWN = 0.6
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
const SLIDE_ENTRY_TIME = 0.6
const SLIDE_RECOVER_TIME = 0.6
# Steering authority while sliding, well under ROTATE_SPEED: enough to carve a line around
# a corner, not enough to turn the slide into a full-speed pivot.
const SLIDE_TURN_SPEED = 4.0
const LOCOMOTION_BLEND = 0.15
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
var was_crouching := false
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
var sliding := false
var slide_dir := Vector3.ZERO
var slide_time_left := 0.0
var slide_recovering := false
var standing_up := false
var was_standing_up := false

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
	if anim_player.has_animation("SPRINT LOOP"):
		anim_player.get_animation("SPRINT LOOP").loop_mode = Animation.LOOP_LINEAR
	if anim_player.has_animation("IDLE"):
		anim_player.get_animation("IDLE").loop_mode = Animation.LOOP_LINEAR
	if anim_player.has_animation("CROUCH LOOP"):
		anim_player.get_animation("CROUCH LOOP").loop_mode = Animation.LOOP_LINEAR
	if anim_player.has_animation("CROUCH START"):
		anim_player.get_animation("CROUCH START").loop_mode = Animation.LOOP_NONE
	if anim_player.has_animation("RUN START"):
		anim_player.get_animation("RUN START").loop_mode = Animation.LOOP_NONE
	if anim_player.has_animation("JUMP"):
		anim_player.get_animation("JUMP").loop_mode = Animation.LOOP_NONE
	if anim_player.has_animation("DASH"):
		anim_player.get_animation("DASH").loop_mode = Animation.LOOP_NONE
	if anim_player.has_animation("SLIDE START"):
		anim_player.get_animation("SLIDE START").loop_mode = Animation.LOOP_NONE
	if anim_player.has_animation("SLIDE END"):
		anim_player.get_animation("SLIDE END").loop_mode = Animation.LOOP_NONE
	if anim_player.has_animation("CROUCH END"):
		anim_player.get_animation("CROUCH END").loop_mode = Animation.LOOP_NONE

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
func _can_slide(sprinting: bool) -> bool:
	if not sprinting:
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
	standing_up = false
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

func _physics_process(delta: float) -> void:
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
			crouching = false
			standing_up = true
			if anim_player.has_animation("CROUCH END"):
				anim_player.play("CROUCH END")
				anim_player.seek(0.0, true)
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

	# Landing from an air jump is deliberately uneventful - you keep your speed and your
	# control, and the locomotion clip picks the body straight back up. There used to be a
	# CROUCH START touchdown with a freeze behind it; the pose looked good and the stop
	# killed every line of movement it landed in.
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
		if anim_player.has_animation("JUMP"):
			anim_player.play("JUMP")
	elif jump_queued and jumps_used < MAX_JUMPS and dash_time_left <= 0.0:
		# Air jump: a fresh press only, and the vertical velocity is reset rather than added
		# to, so the second hop is the same height whether you're rising or already falling.
		velocity.y = JUMP_VELOCITY
		jumping = true
		jumps_used += 1
		_cancel_slide()
		if anim_player.has_animation("JUMP"):
			# play() resumes a clip that's already current, so seek back to force the restart.
			anim_player.play("JUMP")
			anim_player.seek(0.0, true)
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
		dash_cooldown_left = DASH_TIME + DASH_COOLDOWN
		rotation.y = atan2(dash_dir.x, dash_dir.z)
		# Kicked, not held: the dash owns the horizontal speed for its whole window but only
		# sets the vertical once, so the launch leaves at DASH_RISE_ANGLE and gravity arcs it
		# over from there instead of holding a straight ramp.
		velocity.y = DASH_SPEED * tan(deg_to_rad(DASH_RISE_ANGLE))
		jumping = false
		# The dash wins over the crouch and the slide; the collider lerps back up from here.
		crouching = false
		_cancel_slide()
		if anim_player.has_animation("DASH"):
			# Speed-scale the clip so it lands exactly with the end of the dash window.
			var dash_anim_len := anim_player.get_animation("DASH").length
			anim_player.play("DASH", -1, dash_anim_len / DASH_TIME)
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
	# CROUCH END holds the body until something else claims it, or until the one-shot ends
	# and clears current_animation. Running out of the crouch cancels it - the locomotion
	# clip below is the better read.
	if standing_up and (moving or is_crouching or jumping or dashing or sliding
			or not is_on_floor() or anim_player.current_animation != "CROUCH END"):
		standing_up = false
	# Sprint swaps the locomotion loop; toggling Shift mid-stride cross-fades between the two.
	var loop_clip := "SPRINT LOOP" if (is_sprinting and anim_player.has_animation("SPRINT LOOP")) else "RUN LOOP"
	if not dashing and not jumping and not sliding:
		if is_crouching and anim_player.has_animation("CROUCH LOOP"):
			if not was_crouching:
				anim_player.play("CROUCH START")
				anim_player.queue("CROUCH LOOP")
			elif anim_player.current_animation != "CROUCH START" and anim_player.current_animation != "CROUCH LOOP":
				anim_player.play("CROUCH LOOP", LOCOMOTION_BLEND)
			# CROUCH LOOP is a crouch-walk cycle, not a static pose, so it has to be stopped
			# when the player stops creeping. CROUCH START is left alone either way, so the
			# settle-down always finishes.
			if moving:
				if not anim_player.is_playing():
					anim_player.play()
			elif anim_player.current_animation == "CROUCH LOOP" and anim_player.is_playing():
				# Freeze on the clip's first frame, which poses one leg out in front. Stopping
				# wherever the playhead happened to be can catch the passing frame, where both
				# legs are in line and nobody actually stands like that.
				anim_player.seek(0.0, true)
				anim_player.pause()
		elif moving and not was_moving:
			anim_player.play("RUN START")
			anim_player.queue(loop_clip)
		elif moving and anim_player.current_animation != "RUN START":
			if anim_player.current_animation != loop_clip:
				anim_player.play(loop_clip, LOCOMOTION_BLEND)
		elif not moving and is_on_floor() and not standing_up:
			if was_standing_up:
				# The stand-up ends deep in the crouch pose, so cross-fade up to the standing
				# one instead of snapping. A finished one-shot leaves its final pose as the
				# blend source, which is exactly what we want to rise out of.
				anim_player.play("IDLE", LOCOMOTION_BLEND)
			else:
				anim_player.play("IDLE")
	# Falling without jumping (walked off a ledge) has no clip - holds the current pose.
	was_moving = moving and not dashing
	was_crouching = is_crouching
	was_standing_up = standing_up
	var is_running := moving and not dashing and not is_crouching and not sliding

	move_and_slide()

	camera_pivot.rotation.y = camera_yaw - rotation.y
	camera_pitch_node.rotation.x = camera_pitch

	# The CROUCH clips animate the mesh down themselves, so the root stays put while crouching.
	# Lift slightly while running since the RUN animation's foot-down pose sits lower than IDLE and clips the ground.
	player_model.position.y = RUN_MODEL_LIFT if is_running else 0.0
