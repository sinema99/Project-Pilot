extends CharacterBody3D

# A hover speeder bike. See docs/specs/speeder1.md.
#
# The body is a yaw-only CharacterBody3D in FLOATING motion mode: it holds its own hover height
# off five ground rays (a spring, no gravity) and only falls when the rays lose the ground. A/D
# steer, W throttles, S brakes then reverses; walls take the speed going into them. Everything
# the eye reads - the tilt to the ground, the bank into a turn, the throttle / brake pitch, the
# parked bob, the landing dip - is on `Tilt`, a top_level visual root placed every drawn frame off
# this body's interpolated transform. The rider is placed the same way, off Tilt's seat.
#
# Getting on and off is EXIA's (docs/specs/mech-stash.md): on foot the shared interaction panel
# offers RIDE / STASH, the wheel picks, F does it; aboard, Tab is the stash and F held 0.6 s gets
# off - only at a crawl. pilot9.gd::begin_ride() / end_ride() is the rider's half.
#
# Frames. The model is speeder1.glb turned a quarter (its nose is the file's -X): in this body
# +Z is the nose, +X the rider's LEFT, +Y up. Every seat / grip / peg point is in that frame.

const PROMPT_SCRIPT := preload("res://scripts/ui/interaction_prompt.gd")
const INTERACT_ACTION := &"interact"
## Inventory.piloted_mech() finds a ridden speeder through this group, for Tab aboard.
const GROUP := &"mech"
const _Fire := preload("res://scripts/speeder_fire.gd")

const PROMPT_RIDE := "RIDE"
const PROMPT_STASH := "STASH"
const PROMPT_OPTIONS := ["RIDE", "STASH"]
const PROMPT_EXIT := "EXIT"
const PROMPT_ANCHOR_HEIGHT := 1.6
const PROMPT_ANCHOR_OFFSET := 1.2

## Shown on the stash screen's portrait box.
@export var display_name := "SPEEDER1"
## The stash's key on the Inventory autoload (one stash per key for the session).
@export var stash_key: StringName = &"speeder1"
const STASH_W := 8
const STASH_H := 6
## TEST CONTENT (docs/specs/speeder1.md, decision 6): so the boxes show on load. Delete when real
## loot exists.
const STASH_TEST_SEED := [
	"res://resources/items/battery.tres",
	"res://resources/items/ration.tres",
]

@export_group("Size")
## The whole bike (docs/specs/speeder1-pass2.md): model, collision, ground rays, camera, bob and dip
## scale with it. The rider points below are in metres AT THIS SCALE (2.0) - retune them if it changes.
@export var size_scale := 2.0

@export_group("Drive")
@export var max_speed := 50.0
## m/s^2 under throttle: 50 / 20 = 2.5 s to top speed.
@export var acceleration := 20.0
## m/s^2 holding S while still rolling forward.
@export var brake := 60.0
@export var reverse_speed := 12.0
@export var reverse_acceleration := 12.0
## m/s^2 lost with no throttle.
@export var coast_drag := 6.0
## Yaw rate, rad/s, standing / at top speed.
@export var turn_rate_slow := 1.9
@export var turn_rate_fast := 1.3

@export_group("Slide")
## Sideways speed bleeds off at this rate (1/s): high = tight (about 0.5 s to recover).
@export var grip_high := 4.0
## The same while sliding.
@export var grip_low := 1.6
## Share of the sideways speed that turns into forward speed as grip takes it back.
@export var grip_conserve := 0.7
## A slide starts above this share of cruise speed with a hard turn, and is full by the second.
@export var slide_from_share := 0.4
@export var slide_full_share := 0.75
@export var slide_ease := 6.0
## The slide lets go slower than it builds (1/s), and barely at all in the air: a drift that
## ends on a hop lands still sliding and grips back over ~0.4 s.
@export var slide_release_ease := 3.0
@export var slide_air_ease := 0.8

@export_group("Power slide")
## Hold Space above this share of top speed: full slide (low grip) and a sharper turn.
@export var drift_min_share := 0.3
@export var drift_yaw_mult := 1.6
## Grip (1/s) at a full power slide: the nose swings round and the path hardly follows (~58 deg).
@export var drift_grip := 1.1

@export_group("Boost")
@export var boost_speed := 80.0
@export var boost_acceleration := 60.0
## Seconds of meter, and seconds to refill it from empty (after the idle).
@export var boost_time := 3.0
@export var boost_refill_time := 6.0
@export var boost_refill_delay := 0.4
## An emptied meter can only start a boost again at this share.
@export var boost_restart := 0.25
## m/s^2 lost above cruise speed once the boost is let go (30 m/s over 2 s).
@export var boost_decay := 15.0

@export_group("Air")
@export var jump_height := 1.5
## Yaw rate in the air on A/D, rad/s. The velocity does not follow the nose.
@export var air_turn_rate := 1.4
@export var air_pitch_max_degrees := 34.0
## The nose levels out over this last height above the ground, metres (x size).
@export var air_level_height := 3.5

@export_group("Crash")
## Into the wall at least this fast (m/s) and more head-on than glancing: a bounce.
@export var bounce_min_speed := 7.0
## Speed into the wall / speed above which a hit is head-on.
@export var glance_share := 0.5
@export var bounce_restitution := 0.3
## Per second, while scraping a wall.
@export var scrape_drag := 0.8

@export_group("Hover")
## Ground to body origin, metres. The hull's underside is 0.07 above the origin.
@export var hover_height := 0.45
@export var hover_stiffness := 70.0
@export var hover_damping := 14.0
## The ground counts as under it out to hover_height + this.
@export var hover_reach := 0.4
@export var gravity_scale := 1.5
## Below this y it goes back to where it was parked.
@export var kill_y := -40.0

@export_group("Look")
@export var bank_max_degrees := 55.0
## The bank is driven by the sideways slip and the stick (weights), summed, clamped to +-1.
@export var bank_slip_weight := 0.8
@export var bank_steer_weight := 0.4
## In the air the bank eases toward level at this rate (1/s), slowly: a hop out of a drift stays leant.
@export var bank_air_ease := 0.8
## The camera rolls with the bike by this share of its bank.
@export var camera_roll_share := 0.18
## Speed (share of max_speed) at which the bank reaches its full share of the steer.
@export var bank_full_speed_share := 0.6
@export var pitch_throttle_degrees := 5.0
@export var pitch_brake_degrees := 6.0
## Visual rates, 1/s.
@export var tilt_ease := 8.0
@export var bank_ease := 4.0
## Parked bob, metres and Hz.
@export var bob_height := 0.02
@export var bob_rate := 0.5
## Landing dip: metres per m/s of fall speed, capped.
@export var land_dip_per_speed := 0.012
@export var land_dip_max := 0.12

@export_group("Rider")
## Body-frame points in metres (see the header). The seat point is where his hip joint sits.
@export var seat_point := Vector3(0.0, 1.12, -0.85)
## Parked / crawling (tuck 0) he scoots this far forward on the saddle so the arms keep a bend; it
## eases to nothing as he tucks.
@export var seat_forward_upright := 0.0
@export var grip_left := Vector3(0.50, 1.10, -0.12)
@export var grip_right := Vector3(-0.50, 1.10, -0.12)
@export var peg_left := Vector3(0.60, 0.51, -0.44)
@export var peg_right := Vector3(-0.60, 0.51, -0.44)
## Extra upper-body lean into a full turn, degrees (on top of the bank).
@export var rider_lean_degrees := 10.0
## Extra spine pitch at top speed, degrees.
@export var rider_tuck_degrees := 8.0
## Speed share at which he is fully tucked / below which he sits upright (smoothstep between).
@export var tuck_from_share := 0.15
@export var tuck_full_share := 0.7
@export var tuck_ease := 4.0
## The inside knee drops out this far in a full turn at speed, metres.
@export var knee_out := 0.12
@export var head_turn_max_degrees := 60.0
## His body follows the landing dip at this share (the hips sink 4 cm on a full dip).
@export var rider_dip_share := 0.35
## The coat is kept above this height (body frame) - the seat pan.
@export var coat_plane_height := 0.4

@export_group("Boarding")
## Where he boards from and is put down at, body frame, metres: the ground beside the saddle on
## his left. Always the same spot (the right, then behind, only when the left is blocked).
@export var mount_spot := Vector3(1.8, 0.0, -0.80)
## Walking to the spot (skipped when he is already on it), then the leg swing over the saddle.
@export var mount_walk_time := 0.25
@export var mount_swing_time := 0.55
@export var dismount_swing_time := 0.5
## Hips rise this far over the swing's midpoint; the far foot arcs this high over the saddle.
@export var swing_hip_lift := 0.33
@export var swing_leg_arc := 1.33

@export_group("Exit")
@export var exit_hold_time := 0.6
@export var exit_max_speed := 2.0
const EXIT_CLEAR_RADIUS := 0.4
const EXIT_CLEAR_HEIGHT := 1.8

@export_group("Camera")
@export var camera_distance := 3.6   # at size 1; x size_scale (was 4.5, pulled in 2026-11-12)
@export var camera_distance_fast := 1.0
@export var camera_height := 1.4
@export var camera_pitch_default := -0.22
@export var fov_boost := 10.0
## Boost: the camera drops back this far (x size), widens this many degrees, and shakes this much (m).
@export var boost_pull := 1.2
@export var boost_fov := 18.0
@export var boost_shake := 0.035
## A head-on hit's camera kick, metres at full strength; decays at 5/s.
@export var crash_shake := 0.25
@export var recenter_delay := 1.5
@export var recenter_rate := 2.0
## No recentring below this speed (m/s): parked, the view stays where you put it.
@export var recenter_min_speed := 2.0
## The camera sits behind the NOSE; this share of the way to the travel line is mixed in so a
## sideways drift does not look at a wall.
@export var travel_view_share := 0.25
@export var handover_time := 0.4
@export var mouse_sensitivity := 0.0025
const PITCH_MIN := -1.2
const PITCH_MAX := 0.6

@onready var tilt: Node3D = $Tilt
@onready var model: Node3D = $Tilt/Model
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_pitch_node: Node3D = $CameraPivot/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraPivot/CameraPitch/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/CameraPitch/SpringArm3D/Camera3D
@onready var handover_camera: Camera3D = $HandoverCamera
@onready var interaction_area: Area3D = $InteractionArea
@onready var body_shape: CollisionShape3D = $CollisionShape3D
@onready var area_shape: CollisionShape3D = $InteractionArea/CollisionShape3D

## The hull's collision box at size 1 (centre y, size), the interaction sphere's radius.
const BODY_BOX_SIZE := Vector3(1.0, 0.72, 3.0)
const BODY_BOX_Y := 0.43
const AREA_RADIUS := 2.6
const AREA_Y := 0.5
## The two nozzles, model frame at size 1 (the engines surface of speeder1.glb) and their radius.
const NOZZLES := [Vector3(0.255, 0.315, -1.23), Vector3(-0.255, 0.315, -1.23)]
const NOZZLE_RADIUS := 0.085
## He is this close (flat, metres) to the boarding spot already: no walk.
const MOUNT_ON_SPOT := 0.25

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float

## The rider, or null. Set the moment RIDE is pressed (the mount blend included).
var pilot: Node3D = null
var player_in_range: Node3D = null
var stash: ItemGrid = null
## The cargo boxes mesh: shown while the stash holds anything.
var boxes: MeshInstance3D = null

## Signed speed along the nose, m/s.
var speed := 0.0
## Sideways speed, m/s, + toward the rider's left (the body's +X). Non-zero while sliding.
var lateral := 0.0
var vertical_speed := 0.0
## 0..1 boost meter, and whether a boost is burning now.
var boost_meter := 1.0
var boosting := false
## Tests and probes: Shift held / a Space press, in place of the keys while set.
var boost_override: Variant = null
var jump_override := false
var drift_held := false
var drift_override: Variant = null
var _boost_empty := false
var _boost_idle := 0.0
var _boost_fx := 0.0
var _slide := 0.0
var _drift := 0.0
var _jump_lock := 0.0
var _jump_was := false
var _air_pitch := 0.0
var _air_pitch_target := 0.0
var _yaw_kick := 0.0
var _cam_kick := 0.0
var _scraping := false
var _crash_log: Array = []
var _hit_cooldown := 0.0
## One head-on bounce per this many seconds: a bike pinned on a wall is one hit, not sixty.
const HIT_COOLDOWN := 0.35
var grounded := true
var steer := 0.0
var throttle := 0.0
var stash_hold := false
## < 0 = no hold running.
var exit_hold := -1.0
var mount_left := 0.0
## Counts down while he swings off; he is put down when it reaches 0.
var dismount_left := 0.0
## (steer, throttle) in place of the keyboard while set - tests and probes drive it with this.
var keys_override: Variant = null

var camera_yaw := 0.0
var camera_pitch := -0.22
var _mouse_idle := 0.0

var _park := Transform3D.IDENTITY
var _ground_pitch := 0.0
var _ground_roll := 0.0
var _target_ground_pitch := 0.0
var _target_ground_roll := 0.0
var _bank := 0.0
var _pitch := 0.0
var _dip := 0.0
var _dip_velocity := 0.0
var _bob_t := 0.0
var _lean := 0.0
var _speed_share := 0.0

var _mount_from_body := Vector3.ZERO
var _mount_total := 0.0
var _mount_walk := 0.0
## The ground point (body frame) he boards from / is put down at, and the yaw he ends on.
var _spot_local := Vector3.ZERO
var _exit_yaw := 0.0
var _exit_world := Vector3.ZERO
## 0..1, eased up while he gets on or off: the bike's parked bob is held still meanwhile.
var _still := 0.0
var _tuck := 0.0
var fire: Node3D = null
var _mount_from_basis := Basis.IDENTITY

var _handover_left := 0.0
var _handover_from := Transform3D.IDENTITY
var _handover_from_fov := 75.0
var _handover_to: Camera3D = null

var _prompt: Node = null


func _ready() -> void:
	set_meta(&"airframe_snap_lines", 720.0)  # big and fast: a finer vertex-snap grid (AirframeLook)
	add_to_group(GROUP)
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_park = global_transform
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	spring_arm.add_excluded_object(get_rid())
	_apply_size()
	fire = _Fire.new()
	fire.name = &"Fire"
	tilt.add_child(fire)
	fire.setup(size_scale, NOZZLES, NOZZLE_RADIUS)
	_spot_local = mount_spot
	boxes = find_boxes(model)
	var inv := get_node_or_null(^"/root/Inventory")
	if inv != null:
		stash = inv.vehicle_stash(stash_key, STASH_W, STASH_H, STASH_TEST_SEED)
	else:
		stash = ItemGrid.new(STASH_W, STASH_H)
	stash.changed.connect(update_boxes)
	update_boxes()
	camera_yaw = yaw_behind(rotation.y)
	camera_pitch = camera_pitch_default
	_place_visuals(0.0)


## Everything that is the bike's size follows size_scale. The shapes are rebuilt, not resized: the
## scene's sub-resources are shared by every instance.
func _apply_size() -> void:
	model.scale = Vector3.ONE * size_scale
	var box := BoxShape3D.new()
	box.size = BODY_BOX_SIZE * size_scale
	body_shape.shape = box
	body_shape.position = Vector3(0.0, BODY_BOX_Y * size_scale, 0.0)
	var ball := SphereShape3D.new()
	ball.radius = AREA_RADIUS * size_scale
	area_shape.shape = ball
	area_shape.position = Vector3(0.0, AREA_Y * size_scale, 0.0)


## The cargo mesh: the MeshInstance3D wearing the `boxes` material, else one named like Boxes /
## Cube.005. Found by material so a re-export that renames the objects keeps working.
static func find_boxes(root: Node) -> MeshInstance3D:
	if root == null:
		return null
	var fallback: MeshInstance3D = null
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				if mat != null and mat.resource_name.to_lower() == "boxes":
					return mi
		var n := String(mi.name).to_lower()
		if n.contains("box") or n.contains("005"):
			fallback = mi
	return fallback


## The boxes show exactly while the stash holds something.
func update_boxes() -> void:
	if boxes != null and stash != null:
		boxes.visible = not stash.items.is_empty()


# --- getting on and off ---------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if body.has_method(&"begin_ride"):
		player_in_range = body


func _on_body_exited(body: Node3D) -> void:
	if body == player_in_range:
		player_in_range = null


func _bid_prompt() -> void:
	var text := ""
	var options := PackedStringArray()
	var progress := -1.0
	var d := 0.0
	if pilot != null:
		if transition_active() or exit_hold < 0.0:
			return
		text = PROMPT_EXIT
		progress = exit_progress()
	elif player_in_range != null and _can_be_boarded_by(player_in_range):
		text = PROMPT_RIDE
		options = PackedStringArray(PROMPT_OPTIONS)
		d = player_in_range.global_position.distance_to(global_position)
	else:
		return
	if _prompt == null or not is_instance_valid(_prompt):
		_prompt = PROMPT_SCRIPT.acquire(self)
	if _prompt != null:
		_prompt.offer(self, d, INTERACT_ACTION, text, progress, options)


func _can_be_boarded_by(body: Node3D) -> bool:
	return body.get(&"controlled") != false and body.visible and body.is_physics_processing() \
		and body.get(&"riding") == null


## The hold bar's fill, < 0 = no bar.
func exit_progress() -> float:
	return clampf(exit_hold / exit_hold_time, 0.0, 1.0) if exit_hold >= 0.0 else -1.0


## Where the interaction panel floats while the speeder's camera is in use.
func interaction_anchor() -> Dictionary:
	return {"point": global_position + Vector3.UP * PROMPT_ANCHOR_HEIGHT * size_scale, "side": 1.0,
		"offset": PROMPT_ANCHOR_OFFSET * size_scale}


func _unhandled_input(event: InputEvent) -> void:
	if pilot != null and _is_driver_view() and event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity * _settings_sensitivity()
		camera_yaw -= event.relative.x * sens
		camera_pitch = clampf(camera_pitch - event.relative.y * sens, PITCH_MIN, PITCH_MAX)
		_mouse_idle = 0.0
	if not event.is_action_pressed(INTERACT_ACTION) or event.is_echo():
		return
	if pilot == null:
		if player_in_range == null or not _can_be_boarded_by(player_in_range):
			return
		# Something nearer won the panel (a door, EXIA): not this speeder's press.
		if _prompt != null and is_instance_valid(_prompt) and _prompt.current_source != null \
				and _prompt.current_source != self:
			return
		var choice: String = _prompt.selected_option() if _prompt != null and is_instance_valid(_prompt) \
			else PROMPT_RIDE
		if choice == PROMPT_STASH:
			if not _open_stash_from_ground():
				return
		else:
			mount(player_in_range)
	else:
		if transition_active() or stash_hold or exit_hold >= 0.0 or not _is_driver_view():
			return
		exit_hold = 0.0
	get_viewport().set_input_as_handled()


func _settings_sensitivity() -> float:
	var s := get_node_or_null(^"/root/Settings")
	return float(s.mouse_sensitivity) if s != null else 1.0


## The rider is the pilot being played (pilot switching is refused aboard, but stay honest).
func _is_driver_view() -> bool:
	return pilot != null and pilot.get(&"controlled") != false


## Getting on or off is under way: the bike is held dead still and nothing else is accepted.
func transition_active() -> bool:
	return mount_left > 0.0 or dismount_left > 0.0


## Puts `rider` on: switched off, walked to the spot beside the saddle (skipped when he is on
## it), then swung over the seat; camera handed over. The bike does not move.
func mount(rider: Node3D) -> void:
	if pilot != null or rider == null:
		return
	var watching := get_viewport().get_camera_3d() if is_inside_tree() else null
	pilot = rider
	player_in_range = null
	speed = 0.0
	velocity = Vector3.ZERO
	_mount_from_body = rider.global_position
	var character := rider.get(&"character") as Node3D
	_mount_from_basis = character.global_basis if character != null else Basis.IDENTITY
	rider.begin_ride(self)
	var spot := exit_spot(rider)
	_spot_local = global_transform.affine_inverse() * (spot.position as Vector3)
	var feet: Vector3 = character.global_position if character != null else rider.global_position
	var at: Vector3 = spot.position
	var flat := Vector2(feet.x - at.x, feet.z - at.z).length()
	_mount_walk = mount_walk_time if flat > MOUNT_ON_SPOT else 0.0
	_mount_total = _mount_walk + mount_swing_time
	mount_left = _mount_total
	dismount_left = 0.0
	exit_hold = -1.0
	stash_hold = false
	camera_yaw = yaw_behind(rotation.y)
	camera_pitch = camera_pitch_default
	_mouse_idle = 0.0
	_begin_handover(watching, camera)


## Can the rider get off now: settled on, slow enough, the stash closed.
func can_dismount() -> bool:
	return pilot != null and not transition_active() and absf(speed) <= exit_max_speed and grounded


## One frame of the exit hold. It only fills at a crawl. Returns true when he started getting off.
func step_exit_hold(held: bool, delta: float) -> bool:
	if exit_hold < 0.0:
		return false
	if not held or stash_hold:
		exit_hold = -1.0
		return false
	if absf(speed) <= exit_max_speed and grounded:
		exit_hold += delta
	if exit_hold >= exit_hold_time:
		exit_hold = -1.0
		dismount()
		return true
	return false


## Starts the swing off. The spot is fixed now and the bike held still; he is put down there when
## the swing is done (step_boarding -> _finish_dismount).
func dismount() -> void:
	if pilot == null or dismount_left > 0.0:
		return
	mount_left = 0.0
	exit_hold = -1.0
	stash_hold = false
	speed = 0.0
	velocity = Vector3.ZERO
	var spot := exit_spot(pilot)
	_exit_world = spot.position
	_exit_yaw = spot.yaw
	_spot_local = global_transform.affine_inverse() * _exit_world
	dismount_left = maxf(dismount_swing_time, 0.001)


func _finish_dismount() -> void:
	if pilot == null:
		return
	var rider := pilot
	pilot = null
	dismount_left = 0.0
	var watching := get_viewport().get_camera_3d() if is_inside_tree() else null
	rider.end_ride(_exit_world, _exit_yaw)
	_begin_handover(watching, get_viewport().get_camera_3d() if is_inside_tree() else null)


## Counts the boarding clocks down (drawn frames). Returns true on the frame he steps off.
func step_boarding(delta: float) -> bool:
	if mount_left > 0.0:
		mount_left = maxf(mount_left - delta, 0.0)
	if dismount_left > 0.0:
		dismount_left = maxf(dismount_left - delta, 0.0)
		if dismount_left <= 0.0:
			_finish_dismount()
			return true
	return false


## Walk and swing progress, each 0..1: (0, 0) the moment he is pressed, (1, 1) seated. Dismounting
## runs the swing backwards from (1, 1) to (1, 0).
func boarding_progress() -> Vector2:
	if dismount_left > 0.0:
		return Vector2(1.0, clampf(dismount_left / maxf(dismount_swing_time, 0.001), 0.0, 1.0))
	if mount_left > 0.0:
		var elapsed := _mount_total - mount_left
		var walk := 1.0 if _mount_walk <= 0.0 else clampf(elapsed / _mount_walk, 0.0, 1.0)
		var swing := clampf((elapsed - _mount_walk) / maxf(mount_swing_time, 0.001), 0.0, 1.0)
		return Vector2(walk, swing)
	return Vector2.ONE


## Where he is put down: the fixed spot on his left, else the right, else behind, else the left
## anyway. Returns {position, yaw}; he faces along the nose. `ignore` is the rider (his own
## capsule must not block the spot he is standing on).
func exit_spot(ignore: Node3D = null) -> Dictionary:
	var sides := [mount_spot, Vector3(-mount_spot.x, 0.0, mount_spot.z), Vector3(0.0, 0.0, -2.2 * size_scale)]
	var fallback := {position = global_transform * (sides[0] as Vector3), yaw = rotation.y}
	if not is_inside_tree():
		return fallback
	var space := get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = EXIT_CLEAR_RADIUS
	capsule.height = EXIT_CLEAR_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	var skip: Array[RID] = [get_rid()]
	if ignore is CollisionObject3D:
		skip.append((ignore as CollisionObject3D).get_rid())
	q.exclude = skip
	for local: Vector3 in sides:
		var at := global_transform * local
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 4.0)
		ray.exclude = skip
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		var ground: Vector3 = hit.position
		q.transform = Transform3D(Basis.IDENTITY, ground + Vector3.UP * (EXIT_CLEAR_HEIGHT * 0.5 + 0.05))
		if not space.intersect_shape(q, 1).is_empty():
			continue
		return {position = ground, yaw = rotation.y}
	return fallback


# --- the stash ------------------------------------------------------------------------------

## Tab aboard (Inventory.piloted_mech() -> this): settled on, not on the way off.
func can_open_stash() -> bool:
	return pilot != null and not transition_active() and exit_hold < 0.0


## The stash screen opened (or closed) over a ridden speeder: no drive input while it is up.
func set_stash_hold(on: bool) -> void:
	stash_hold = on
	if on:
		exit_hold = -1.0


func _open_stash_from_ground() -> bool:
	if player_in_range == null or not player_in_range.has_method(&"can_open_inventory") \
			or not player_in_range.can_open_inventory():
		return false
	var inv := get_node_or_null(^"/root/Inventory")
	return inv != null and inv.open_stash(self)


# --- driving --------------------------------------------------------------------------------

## Keys -> (steer, throttle): D = +1 steer (right), W = +1 throttle, S = -1.
static func read_keys() -> Vector2:
	var k := Vector2.ZERO
	if Input.is_key_pressed(KEY_D):
		k.x += 1.0
	if Input.is_key_pressed(KEY_A):
		k.x -= 1.0
	if Input.is_key_pressed(KEY_W):
		k.y += 1.0
	if Input.is_key_pressed(KEY_S):
		k.y -= 1.0
	return k


## The new signed speed after `dt` of `throttle_in` (W +1, S -1, none 0). `boosting` is full thrust
## up to boost_speed whatever the throttle; above cruise speed without it the excess bleeds off at
## boost_decay (so a boost lets go over about 2 s).
func step_speed(v: float, throttle_in: float, dt: float, boosting_now := false) -> float:
	if boosting_now and v >= 0.0:
		return move_toward(v, boost_speed, boost_acceleration * dt)
	if throttle_in > 0.0:
		if v < 0.0:
			return minf(v + brake * dt, 0.0)
		return minf(v + acceleration * dt, max_speed) if v < max_speed else move_toward(v, max_speed, boost_decay * dt)
	if throttle_in < 0.0:
		if v > 0.0:
			return maxf(v - brake * dt, 0.0)
		return maxf(v - reverse_acceleration * dt, -reverse_speed)
	if v > max_speed:
		return move_toward(v, max_speed, boost_decay * dt)
	return move_toward(v, 0.0, coast_drag * dt)


## 0..1: how hard the turn pushes the bike into a slide (a hard steer above 60% of cruise speed).
func slide_target(steer_in: float, v: float) -> float:
	var share := clampf(absf(v) / maxf(max_speed, 0.01), 0.0, 1.0)
	return smoothstep(slide_from_share, slide_full_share, share) * absf(steer_in) if v > 0.0 else 0.0


## Sideways grip, 1/s, for a (eased) slide amount.
func grip_rate(slide_amount: float, drift_amount := 0.0) -> float:
	var g := lerpf(grip_high, grip_low, clampf(slide_amount, 0.0, 1.0))
	return lerpf(g, minf(drift_grip, g), clampf(drift_amount, 0.0, 1.0))


## One tick of the sideways bleed. `f` forward, `l` sideways: returns the new (f, l). Most of what
## grip takes from the sideways speed goes into forward speed.
func apply_grip(f: float, l: float, slide_amount: float, dt: float, drift_amount := 0.0) -> Vector2:
	var l2 := l * exp(-grip_rate(slide_amount, drift_amount) * dt)
	# Grip turns the velocity toward the nose: at conserve 1 it is a pure rotation (the speed is
	# unchanged), below 1 some is lost. It never adds speed.
	var mag := sqrt(f * f + l * l)
	var f_full := sqrt(maxf(mag * mag - l2 * l2, 0.0))
	var f2 := lerpf(absf(f), f_full, grip_conserve)
	return Vector2(f2 if f >= 0.0 else -f2, l2)


## Boost meter: returns {meter, empty, boosting, idle} after `dt`. Pure; the physics step stores it.
func boost_step(meter: float, empty: bool, idle: float, want: bool, dt: float) -> Dictionary:
	if empty and meter >= boost_restart:
		empty = false
	var on := want and not empty and meter > 0.0
	if on:
		meter = maxf(meter - dt / maxf(boost_time, 0.001), 0.0)
		idle = 0.0
		if meter <= 0.0:
			empty = true
			on = false
	else:
		idle += dt
		if idle >= boost_refill_delay:
			meter = minf(meter + dt / maxf(boost_refill_time, 0.001), 1.0)
	return {meter = meter, empty = empty, boosting = on, idle = idle}


## Yaw rate (rad/s, + = left) for a steer (+1 = right) at signed speed `v`. Reversing flips it.
func yaw_rate(steer_in: float, v: float) -> float:
	var share := clampf(absf(v) / maxf(max_speed, 0.01), 0.0, 1.0)
	var rate := lerpf(turn_rate_slow, turn_rate_fast, share)
	return -steer_in * rate * (-1.0 if v < -0.5 else 1.0)


## The bank (radians, + = top toward his right) for a steer at speed `v`.
## `lat` is the sideways speed (+ toward his left): a drift leans the bike the way it slides, and
## holds the lean for as long as the slide lasts.
func bank_unit(steer_in: float, v: float, lat := 0.0) -> float:
	var share := clampf(absf(v) / maxf(max_speed * bank_full_speed_share, 0.01), 0.0, 1.0)
	var slip := clampf(lat / maxf(absf(v) * 0.75, 4.0), -1.0, 1.0) if v > 0.0 else 0.0
	return clampf(bank_steer_weight * steer_in * share + bank_slip_weight * slip, -1.0, 1.0)


func bank_target(steer_in: float, v: float, lat := 0.0) -> float:
	return deg_to_rad(bank_max_degrees) * bank_unit(steer_in, v, lat)


func _physics_process(delta: float) -> void:
	if pilot != null and not transition_active():
		step_exit_hold(Input.is_action_pressed(INTERACT_ACTION), delta)
	_bid_prompt()

	var driving := pilot != null and not transition_active() and not stash_hold and _is_driver_view()
	var keys := Vector2.ZERO
	if driving:
		keys = keys_override if keys_override is Vector2 else read_keys()
	# The exit hold is a stop: no drive while F is down.
	if exit_hold >= 0.0:
		keys = Vector2.ZERO
	steer = keys.x
	throttle = keys.y
	# Getting on or off: the bike is dead still (the hover spring still holds its height).
	var holding := transition_active()

	var boost_want := false
	var jump_want := false
	if driving and exit_hold < 0.0:
		# No boost on the keys any more (only a test override). Shift = jump, Space = power slide.
		boost_want = bool(boost_override) if boost_override != null else false
		var jump_down := Input.is_action_pressed(&"sprint")
		jump_want = jump_override or (jump_down and not _jump_was)
		_jump_was = jump_down
		drift_held = drift_override if drift_override != null else Input.is_action_pressed(&"jump")
	else:
		_jump_was = true
		drift_held = false
	jump_override = false
	var st := boost_step(boost_meter, _boost_empty, _boost_idle, boost_want and driving, delta)
	boost_meter = st.meter
	_boost_empty = st.empty
	_boost_idle = st.idle
	boosting = st.boosting

	var ground := _sample_ground()
	var was_grounded := grounded
	grounded = not ground.is_empty() and global_position.y - float(ground.height) <= hover_height + hover_reach
	if _jump_lock > 0.0:
		_jump_lock -= delta
		grounded = false
	if jump_want and grounded and not holding:
		vertical_speed = sqrt(2.0 * gravity * gravity_scale * jump_height)
		_jump_lock = 0.25
		grounded = false
	# World-space ground speed from the last slide: the model keeps it, the nose only steers it.
	var vh := Vector3(velocity.x, 0.0, velocity.z)
	if holding:
		vh = Vector3.ZERO
	var old_nose := _flat(global_basis.z)
	var old_side := _flat(global_basis.x)
	var f := vh.dot(old_nose)
	var l := vh.dot(old_side)
	if grounded:
		var target_y: float = float(ground.height) + hover_height
		var a := hover_stiffness * (target_y - global_position.y) - hover_damping * vertical_speed
		vertical_speed += a * delta
		if global_position.y < target_y - 0.25:
			# Never sink into a step: pop up onto it.
			vertical_speed = maxf(vertical_speed, (target_y - 0.25 - global_position.y) / delta)
		_target_ground_pitch = float(ground.pitch)
		_target_ground_roll = float(ground.roll)
		_air_pitch_target = 0.0
		if not was_grounded:
			_on_land(-vertical_speed)
		if holding:
			f = 0.0
			l = 0.0
		else:
			f = step_speed(f, throttle, delta, boosting)
			var yaw_mult := drift_yaw_mult if (drift_held and f > max_speed * drift_min_share) else 1.0
			rotation.y = wrapf(rotation.y + yaw_rate(steer, f) * yaw_mult * delta + _take_yaw_kick(delta), -PI, PI)
		var slide_goal := slide_target(steer, f)
		if drift_held and f > max_speed * drift_min_share:
			slide_goal = 1.0
		_slide = move_toward(_slide, slide_goal, (slide_ease if slide_goal > _slide else slide_release_ease) * delta)
		var drift_goal := 1.0 if (drift_held and f > max_speed * drift_min_share) else 0.0
		_drift = move_toward(_drift, drift_goal, slide_ease * delta)
		# The old velocity, in the turned nose's frame, then grip pulls it round to the nose.
		var world_v := old_nose * f + old_side * l
		var nose := _flat(global_basis.z)
		var side := _flat(global_basis.x)
		var fl := apply_grip(world_v.dot(nose), world_v.dot(side), _slide, delta, _drift)
		vh = nose * fl.x + side * fl.y
	else:
		vertical_speed -= gravity * gravity_scale * delta
		_target_ground_pitch = move_toward(_target_ground_pitch, 0.0, delta)
		_target_ground_roll = move_toward(_target_ground_roll, 0.0, delta)
		_slide = move_toward(_slide, 0.0, slide_air_ease * delta)
		_drift = move_toward(_drift, 0.0, slide_air_ease * delta)
		if not holding:
			# A little yaw in the air; the velocity keeps going where it was going.
			rotation.y = wrapf(rotation.y - steer * air_turn_rate * delta + _take_yaw_kick(delta), -PI, PI)
			if boosting:
				var nose_a := _flat(global_basis.z)
				var along := vh.dot(nose_a)
				if along < boost_speed:
					vh += nose_a * minf(boost_acceleration * delta, boost_speed - along)
		var above := 99.0
		if not ground.is_empty():
			above = global_position.y - float(ground.height)
		var arc := atan2(vertical_speed, maxf(vh.length(), 3.0))
		var cap := deg_to_rad(air_pitch_max_degrees)
		_air_pitch_target = -clampf(arc, -cap, cap) * smoothstep(0.6, air_level_height * size_scale, above)
	velocity = vh + Vector3.UP * vertical_speed
	var pre_h := vh
	move_and_slide()
	_handle_hits(pre_h, delta)
	var nose_now := _flat(global_basis.z)
	var side_now := _flat(global_basis.x)
	speed = velocity.dot(nose_now)
	lateral = velocity.dot(side_now)
	vertical_speed = velocity.y
	_speed_share = clampf(absf(speed) / maxf(max_speed, 0.01), 0.0, 1.0)

	if global_position.y < kill_y:
		respawn()

	# The coat feels the bike's speed, and lies on the seat instead of hanging through the hull.
	var coat: Object = pilot.get(&"coat") if pilot != null else null
	if coat != null and "velocity_override" in coat:
		coat.velocity_override = velocity
		var tx := global_transform * tilt_local()
		coat.extra_planes = [[tx * Vector3(0.0, coat_plane_height, 0.0), tx.basis.y.normalized()]]


static func _flat(v: Vector3) -> Vector3:
	var h := Vector3(v.x, 0.0, v.z)
	return h.normalized() if h.length_squared() > 0.0001 else Vector3.BACK


## The part of a wall-hit nose swing handed out this tick (it eases out, 10/s), radians.
func _take_yaw_kick(delta: float) -> float:
	var d := _yaw_kick * (1.0 - exp(-10.0 * delta))
	_yaw_kick -= d
	return d


## Walls, after move_and_slide(). `pre_h` is the ground velocity it was given. Godot already slid it
## along the wall, so a glancing hit keeps its speed along it (a scrape, a little drag); a head-on
## hit (>= bounce_min_speed into the wall and more than glance_share of the speed) is bounced back
## off it, the nose swings toward the wall's tangent and the camera kicks.
func _handle_hits(pre_h: Vector3, delta: float) -> void:
	_scraping = false
	_hit_cooldown = maxf(_hit_cooldown - delta, 0.0)
	var pre_len := pre_h.length()
	if pre_len < 0.5:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if n.y > 0.5:
			continue
		var nh := Vector3(n.x, 0.0, n.z)
		if nh.length() < 0.3:
			continue
		nh = nh.normalized()
		var into := -pre_h.dot(nh)
		if into <= 0.0:
			continue
		var share := into / pre_len
		if into >= bounce_min_speed and share > glance_share and _hit_cooldown <= 0.0:
			_hit_cooldown = HIT_COOLDOWN
			velocity.x += nh.x * into * bounce_restitution
			velocity.z += nh.z * into * bounce_restitution
			var tangent := nh.cross(Vector3.UP)
			var nose := _flat(global_basis.z)
			if tangent.dot(nose) < 0.0:
				tangent = -tangent
			_yaw_kick += nose.signed_angle_to(tangent, Vector3.UP) * clampf(share * 1.2, 0.0, 1.0) * 0.5
			_cam_kick = maxf(_cam_kick, clampf(into / max_speed, 0.0, 1.0))
			_crash_log.append(into)
		elif share <= glance_share:
			_scraping = true
			velocity.x *= 1.0 - scrape_drag * delta
			velocity.z *= 1.0 - scrape_drag * delta


## Back to where it was parked, stopped. A rider comes with it.
func respawn() -> void:
	global_transform = _park
	speed = 0.0
	lateral = 0.0
	vertical_speed = 0.0
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func _on_land(fall_speed: float) -> void:
	if fall_speed > 2.0:
		var k := size_scale
		_dip_velocity -= minf(fall_speed * land_dip_per_speed * 8.0 * k, land_dip_max * 8.0 * k)


## Five rays: centre, nose, tail, left, right. Returns {height, pitch, roll} (radians, the
## ground's tilt in this body's frame), or {} with nothing under the centre or the nose.
func _sample_ground() -> Dictionary:
	if not is_inside_tree():
		return {}
	var space := get_world_3d().direct_space_state
	var reach := hover_height + hover_reach + 1.5
	var heights := {}
	for key: String in ["c", "f", "b", "l", "r"]:
		var local: Vector3 = {"c": Vector3.ZERO, "f": Vector3(0, 0, 1.3), "b": Vector3(0, 0, -1.3),
			"l": Vector3(0.45, 0, 0), "r": Vector3(-0.45, 0, 0)}[key] * size_scale
		var from := global_transform * (local + Vector3.UP * 1.0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (1.0 + reach))
		var ex: Array[RID] = [get_rid()]
		if pilot is CollisionObject3D:
			ex.append((pilot as CollisionObject3D).get_rid())
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			heights[key] = (hit.position as Vector3).y
	if not heights.has("c") and not heights.has("f"):
		return {}
	var h: float = maxf(heights.get("c", -INF), heights.get("f", -INF))
	var pitch := 0.0
	if heights.has("f") and heights.has("b"):
		pitch = -atan2(float(heights.f) - float(heights.b), 2.6 * size_scale)
	var roll := 0.0
	if heights.has("l") and heights.has("r"):
			roll = atan2(float(heights.l) - float(heights.r), 0.9 * size_scale)
	return {height = h, pitch = clampf(pitch, -0.6, 0.6), roll = clampf(roll, -0.6, 0.6)}


# --- the look, the rider, the camera (every drawn frame) ------------------------------------

func _process(delta: float) -> void:
	_step_visuals(delta)
	step_boarding(delta)
	_place_visuals(delta)
	_place_camera(delta)
	_step_handover(delta)
	_drive_fire()


func _step_visuals(delta: float) -> void:
	_ground_pitch = lerpf(_ground_pitch, _target_ground_pitch, 1.0 - exp(-tilt_ease * delta))
	_ground_roll = lerpf(_ground_roll, _target_ground_roll, 1.0 - exp(-tilt_ease * delta))
	_bank = lerpf(_bank, bank_target(steer, speed, lateral) if grounded else 0.0,
		1.0 - exp(-(bank_ease if grounded else bank_air_ease) * delta))
	var pitch_to := 0.0
	if grounded and throttle > 0.0 and speed >= 0.0 and speed < max_speed - 0.1:
		pitch_to = -deg_to_rad(pitch_throttle_degrees)
	elif grounded and throttle < 0.0 and speed > 0.5:
		pitch_to = deg_to_rad(pitch_brake_degrees)
	_pitch = lerpf(_pitch, pitch_to, 1.0 - exp(-4.0 * delta))
	_air_pitch = lerpf(_air_pitch, _air_pitch_target, 1.0 - exp(-6.0 * delta))
	_boost_fx = lerpf(_boost_fx, 1.0 if boosting else 0.0, 1.0 - exp(-(5.0 if boosting else 2.0) * delta))
	_cam_kick *= exp(-5.0 * delta)
	# The dip: a critically damped spring back to 0.
	var omega := 14.0
	_dip_velocity += (-omega * omega * _dip - 2.0 * omega * _dip_velocity) * delta
	_dip += _dip_velocity * delta
	var dip_max := land_dip_max * size_scale
	_dip = clampf(_dip, -dip_max, dip_max)
	_bob_t += delta
	_lean = lerpf(_lean, clampf(_bank / maxf(deg_to_rad(bank_max_degrees), 0.01), -1.0, 1.0),
		1.0 - exp(-bank_ease * delta))
	_still = lerpf(_still, 1.0 if transition_active() else 0.0, 1.0 - exp(-8.0 * delta))
	# Upright at a crawl, tucked at speed; upright again while he gets on or off.
	var tuck_to := 0.0
	if pilot != null and not transition_active():
		tuck_to = smoothstep(tuck_from_share, tuck_full_share, _speed_share)
	_tuck = lerpf(_tuck, tuck_to, 1.0 - exp(-tuck_ease * delta))
	if pilot != null:
		_mouse_idle += delta


## Tilt's transform in this body's frame: ground tilt, then the throttle pitch and the bank, the
## parked bob and the dip. The bob is held still while he gets on or off.
func tilt_local() -> Transform3D:
	var bob := sin(_bob_t * TAU * bob_rate) * bob_height * size_scale * (1.0 - _speed_share) * (1.0 - _still)
	var b := Basis(Vector3.RIGHT, _ground_pitch + _pitch + _air_pitch) * Basis(Vector3.BACK, _ground_roll + _bank)
	return Transform3D(b, Vector3(0.0, bob + _dip, 0.0))


func _place_visuals(_delta: float) -> void:
	var body_xf := get_global_transform_interpolated() if is_inside_tree() else global_transform
	var tilt_xf := body_xf * tilt_local()
	tilt.global_transform = tilt_xf
	if pilot != null:
		_place_rider(tilt_xf)


## Puts the rider's hip joint on the seat (or on its way: the walk to the spot, the swing over the
## saddle) facing the nose, and feeds his pose layer.
func _place_rider(tilt_xf: Transform3D) -> void:
	var character := pilot.get(&"character") as Node3D
	var pose := pilot.get(&"ride_pose") as SkeletonModifier3D
	if character == null:
		return
	var skel := pose.get_skeleton() if pose != null else null
	# His hip joint at rest, in the character's own frame (the pose layer turns the hips about
	# that joint, never moves it).
	var hips_in_char := Vector3(0.0, 0.85, -0.04)
	if skel != null:
		var hips := skel.find_bone(&"Hips")
		if hips >= 0:
			hips_in_char = _skel_in_character(character, skel) * skel.get_bone_global_rest(hips).origin
	var prog := boarding_progress()
	var walk := smoothstep(0.0, 1.0, prog.x)
	var sw := smoothstep(0.0, 1.0, prog.y)
	var seat_q := tilt_xf.basis.get_rotation_quaternion()
	var char_scale := Basis.from_scale(character.global_basis.get_scale())
	var want_basis := Basis(seat_q) * char_scale
	var seat := tilt_xf * (seat_point + Vector3(0.0, 0.0, seat_forward_upright * (1.0 - _tuck)) + Vector3.UP * _dip * (rider_dip_share - 1.0))
	# Standing on the spot, upright; the hips rise over the swing's middle and settle on the seat.
	var stand := tilt_xf * _spot_local + want_basis * hips_in_char
	var hip := stand.lerp(seat, sw) + tilt_xf.basis.y * (swing_hip_lift * sin(PI * sw))
	var char_origin := hip - want_basis * hips_in_char
	var rot := _mount_from_basis.orthonormalized().get_rotation_quaternion().slerp(seat_q, walk)
	# The body is never rotated: the character's local offset is a plain translation off it.
	pilot.global_position = _mount_from_body.lerp(char_origin - character.position, walk)
	character.global_basis = Basis(rot) * char_scale
	if pose == null:
		return
	var blend := smoothstep(0.0, 1.0, clampf(prog.y / 0.4, 0.0, 1.0))
	pose.influence = blend
	# Feet: from the ground at the spot to the pegs. The far foot goes over the saddle.
	var far_is_right := _spot_local.x >= 0.0
	var arc := swing_leg_arc * sin(PI * sw)
	var near_arc := 0.15 * sin(PI * sw)
	var inside_left := maxf(-_lean, 0.0) * _tuck * knee_out
	var inside_right := maxf(_lean, 0.0) * _tuck * knee_out
	var ride_l := peg_left + Vector3(inside_left, 0.0, 0.0)
	var ride_r := peg_right - Vector3(inside_right, 0.0, 0.0)
	var stand_l := _spot_local + Vector3(0.12, 0.05, 0.0)
	var stand_r := _spot_local + Vector3(-0.12, 0.05, 0.0)
	var foot_l := stand_l.lerp(ride_l, sw) + Vector3.UP * (near_arc if far_is_right else arc)
	var foot_r := stand_r.lerp(ride_r, sw) + Vector3.UP * (arc if far_is_right else near_arc)
	pose.grip_left = tilt_xf * grip_left
	pose.grip_right = tilt_xf * grip_right
	pose.peg_left = tilt_xf * foot_l
	pose.peg_right = tilt_xf * foot_r
	pose.lean_degrees = rider_lean_degrees * _lean
	pose.tuck_share = _tuck
	pose.tuck_degrees = rider_tuck_degrees * _speed_share * _tuck
	var look := wrapf(camera_yaw + PI - rotation.y, -PI, PI)
	pose.head_yaw = clampf(look, -deg_to_rad(head_turn_max_degrees), deg_to_rad(head_turn_max_degrees))
	pose.has_targets = true


static func _skel_in_character(character: Node3D, skel: Skeleton3D) -> Transform3D:
	return character.global_transform.affine_inverse() * skel.global_transform


func _place_camera(delta: float) -> void:
	if pilot != null and _mouse_idle > recenter_delay and absf(speed) > recenter_min_speed:
		var behind := yaw_behind(view_heading())
		camera_yaw = camera_yaw + wrapf(behind - camera_yaw, -PI, PI) * (1.0 - exp(-recenter_rate * delta))
		camera_pitch = lerpf(camera_pitch, camera_pitch_default, 1.0 - exp(-recenter_rate * delta))
	var body_xf := get_global_transform_interpolated() if is_inside_tree() else global_transform
	camera_pivot.global_position = body_xf.origin + Vector3.UP * camera_height * size_scale
	camera_pivot.rotation = Vector3(0.0, camera_yaw, 0.0)
	camera_pitch_node.rotation = Vector3(camera_pitch, 0.0, 0.0)
	spring_arm.spring_length = (camera_distance + camera_distance_fast * _speed_share + boost_pull * _boost_fx) * size_scale
	var s := get_node_or_null(^"/root/Settings")
	camera.rotation.z = -_bank * camera_roll_share
	camera.fov = (float(s.fov) if s != null else 75.0) + fov_boost * _speed_share + boost_fov * _boost_fx
	var shake := boost_shake * _boost_fx + crash_shake * _cam_kick
	camera.h_offset = randf_range(-1.0, 1.0) * shake if shake > 0.0005 else 0.0
	camera.v_offset = randf_range(-1.0, 1.0) * shake if shake > 0.0005 else 0.0


## The yaw the camera heads for: the NOSE, with `travel_view_share` of the way to the direction the
## bike is travelling mixed in once it moves forward (a drift shows the bike swinging across the
## screen without the view pointing at a wall).
func view_heading() -> float:
	var vh := Vector2(velocity.x, velocity.z)
	var share := smoothstep(3.0, 9.0, vh.length()) if speed > 0.0 else 0.0
	return lerp_angle(rotation.y, atan2(vh.x, vh.y), share * travel_view_share) if share > 0.0 else rotation.y


## The thrusters: lit by what the bike is doing, gated by the MOVEMENT EFFECTS setting.
func _drive_fire() -> void:
	if fire == null:
		return
	var s := get_node_or_null(^"/root/Settings")
	var on: bool = s == null or bool(s.movement_effects)
	var lv: Vector2 = _Fire.levels(pilot != null, throttle, speed, _speed_share, steer, _boost_fx)
	fire.drive(lv.x, lv.y, on, _boost_fx)


## The world yaw that puts the camera behind a speeder facing `yaw` (it looks along its -Z).
static func yaw_behind(yaw: float) -> float:
	return wrapf(yaw + PI, -PI, PI)


func _begin_handover(watching: Camera3D, destination: Camera3D) -> void:
	if destination == null:
		return
	if watching == null or handover_time <= 0.0:
		destination.current = true
		return
	_handover_from = watching.global_transform
	_handover_from_fov = watching.fov
	_handover_to = destination
	_handover_left = handover_time
	handover_camera.global_transform = _handover_from
	handover_camera.fov = _handover_from_fov
	handover_camera.near = destination.near
	handover_camera.far = destination.far
	handover_camera.current = true


func _step_handover(delta: float) -> void:
	if _handover_left <= 0.0:
		# Pilot switched back to while aboard: the bike's view, not his.
		if pilot != null and _is_driver_view() and is_inside_tree() \
				and get_viewport().get_camera_3d() != camera:
			camera.current = true
		return
	if not is_instance_valid(_handover_to):
		_handover_left = 0.0
		return
	_handover_left = maxf(_handover_left - delta, 0.0)
	var t := clampf(1.0 - _handover_left / handover_time, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	handover_camera.global_transform = _handover_from.interpolate_with(_handover_to.global_transform, t)
	handover_camera.fov = lerpf(_handover_from_fov, _handover_to.fov, t)
	if _handover_left <= 0.0:
		_handover_to.current = true
