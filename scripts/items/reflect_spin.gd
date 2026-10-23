## pilot9's reflect: press the button and the drawn staff spins in front of him for a fixed beat,
## turning back anything in the `reflectable` group that touches it. Built at runtime by
## pilot9.gd::_setup_reflect(), like the item holder. See docs/specs/pilot9-reflect.md.
##
## The arms and the staff are procedural - no clip. The pose is solved from the rig's rest pose
## (both arms straight out, hands meeting in front of the chest) so a re-export of PILOT9.glb
## cannot leave stale numbers behind.
extends Node

const _ArmPoseModifier := preload("res://scripts/items/arm_pose_modifier.gd")
const _SPIN_DISC_SHADER := preload("res://shaders/cel/vfx/spin_disc.gdshader")

## Fired once per reflected projectile. `perfect` is the shooter-bound return; `point` is where
## it touched. Sound will hang off this.
signal reflected(projectile: Node, perfect: bool, point: Vector3)
signal spin_started
signal spin_ended

enum Phase { IDLE, SPIN, RECOVERY }

const GROUP := &"reflectable"
## The reflect layer, as pilot sees it: 3d_physics layer 8.
const ZONE_MASK := 128

const ARM_BONES: PackedStringArray = [
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
]

@export_group("Timing")
## The spin, seconds. Fixed - a press cannot be cancelled.
@export_range(0.2, 2.0, 0.05) var spin_duration: float = 0.6
## Dead time after the spin before the next one may start.
@export_range(0.0, 2.0, 0.05) var recovery_duration: float = 0.4
## Spin seconds during which a hit is a perfect one.
@export_range(0.0, 0.6, 0.01) var perfect_window: float = 0.15

@export_group("Reflect")
## Half-angle of the cone a normal reflect is thrown into, around the camera's aim.
@export_range(0.0, 180.0, 1.0) var random_cone_deg: float = 60.0
## The zone's radius, metres, around the spin centre.
@export_range(0.3, 3.0, 0.05) var zone_radius: float = 1.1

@export_group("Spin")
## Full turns of the staff across the spin.
@export_range(0.5, 8.0, 0.25) var spin_turns: float = 4.0
## Seconds the spin takes to reach full speed, and to leave it.
@export_range(0.0, 0.3, 0.01) var ease_in: float = 0.08
@export_range(0.0, 0.3, 0.01) var ease_out: float = 0.1
## Seconds the arms and staff take to blend between the run and the spin pose.
@export_range(0.0, 0.4, 0.01) var pose_blend: float = 0.1
## How far the hands drop below shoulder height, metres. The reference picture holds it low.
@export_range(0.0, 0.6, 0.01) var hand_drop: float = 0.25
## Metres from the spin centre to each staff tip.
@export_range(0.2, 2.0, 0.05) var tip_distance: float = 0.8
## One-armed sprint spin: how far the staff-hand drops below the shoulder, metres, and how far
## it is held out to the right of the shoulder.
@export_range(0.0, 0.5, 0.01) var sprint_hand_drop: float = 0.1
@export_range(0.0, 0.5, 0.01) var sprint_hand_out: float = 0.05
## Elbow bend of the one-armed spin, degrees. The forearm folds up toward the shoulder line.
@export_range(0.0, 60.0, 1.0) var sprint_elbow_bend: float = 20.0

@export_group("Feedback")
@export_range(1, 64) var spark_count: int = 8
@export_range(1, 64) var perfect_spark_count: int = 28
@export_range(1.0, 20.0, 0.5) var spark_speed: float = 5.0
@export_range(1.0, 30.0, 0.5) var perfect_spark_speed: float = 9.0
## FOV added on a perfect reflect, degrees, easing back over fov_kick_time.
@export_range(0.0, 30.0, 0.5) var fov_kick: float = 8.0
@export_range(0.05, 1.5, 0.05) var fov_kick_time: float = 0.4
## Real seconds the game slows to a crawl on a perfect reflect.
@export_range(0.0, 0.3, 0.01) var hit_stop: float = 0.05
## The spin disc: a flat circle the size of the staff, locked to it, that fades with spin speed.
## Overall opacity at full speed.
@export_range(0.0, 1.0, 0.01) var disc_alpha: float = 0.35
## Brightness of the ring the tips run along, on top of the fill.
@export_range(0.0, 2.0, 0.05) var disc_rim: float = 0.6
## How far behind each tip its smear wedge reaches, degrees.
@export_range(0.0, 180.0, 1.0) var smear_length: float = 120.0

var phase: Phase = Phase.IDLE
## Seconds into the current phase.
var elapsed: float = 0.0
## The staff's current spin angle, radians, while it is spinning.
var angle: float = 0.0

var zone: Area3D = null
var _zone_shape: SphereShape3D = null
var pose_modifier: SkeletonModifier3D = null

var _pilot: Node = null
var _holder: Node = null
var _skeleton: Skeleton3D = null
var _vfx: Node = null
var _hit_this_spin: Array = []
var _rng := RandomNumberGenerator.new()

## Spin geometry in skeleton rest space, solved once in setup().
var _centre_in_chest := Vector3.ZERO
var _chest_bone := -1
var _overriding := false

## The spin is one-armed: the right arm holds the staff out in front of him and the left keeps
## running. (The two-armed pose below is kept but no longer chosen.) The arm is re-aimed every frame because the sprint lean tilts the chest.
var _one_arm := false
var _one_arm_centre := Vector3.ZERO
var _two_arm_pose: Dictionary = {}
var _one_arm_pose: Dictionary = {}
var _arm_len := 0.0
var _hold_bones: Dictionary = {}
var _hand_bone := -1
## True until the first skeleton update of a one-armed spin has read the real fist.
var _hand_centre_stale := true

var _disc: MeshInstance3D = null
var _disc_mat: ShaderMaterial = null


# --- pure helpers, static so tests can check them without a rig ---------------------------

## Whether a press starts a spin. Every gate in one place.
static func can_start(idle: bool, has_item: bool, drawn: bool, frozen: bool, blocked: bool) -> bool:
	return idle and has_item and drawn and not frozen and not blocked


## A hit `elapsed` seconds into the spin is perfect inside the window.
static func is_perfect(elapsed_s: float, window: float) -> bool:
	return elapsed_s <= window


## A direction uniformly inside a cone of `half_angle_deg` around `axis`.
static func random_cone_direction(axis: Vector3, half_angle_deg: float,
		rng: RandomNumberGenerator) -> Vector3:
	var a := axis.normalized()
	if a == Vector3.ZERO:
		return Vector3.FORWARD
	var cos_max := cos(deg_to_rad(clampf(half_angle_deg, 0.0, 180.0)))
	var cos_t := rng.randf_range(cos_max, 1.0)
	var sin_t := sqrt(maxf(1.0 - cos_t * cos_t, 0.0))
	var phi := rng.randf() * TAU
	var helper := Vector3.UP if absf(a.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var u := a.cross(helper).normalized()
	var v := a.cross(u)
	return (a * cos_t + (u * cos(phi) + v * sin(phi)) * sin_t).normalized()


## The staff's angle `t` seconds into a spin of `duration` that turns it `turns` times: speed
## ramps up over ease_in, holds, ramps down over ease_out, so it starts and ends at rest and the
## last angle is exactly turns * TAU.
static func spin_angle(t: float, duration: float, turns: float, ease_in_s: float,
		ease_out_s: float) -> float:
	var total := turns * TAU
	if duration <= 0.0:
		return total
	t = clampf(t, 0.0, duration)
	var ei := minf(ease_in_s, duration * 0.5)
	var eo := minf(ease_out_s, duration * 0.5)
	# Peak speed such that the area under the trapezoid is `total`.
	var peak := total / maxf(duration - 0.5 * ei - 0.5 * eo, 0.0001)
	if t < ei:
		return peak * t * t / (2.0 * ei)
	var at_ei := peak * ei * 0.5
	var flat_end := duration - eo
	if t <= flat_end:
		return at_ei + peak * (t - ei)
	var at_flat := at_ei + peak * (flat_end - ei)
	var r := t - flat_end
	return at_flat + peak * r - peak * r * r / (2.0 * eo)


## spin_angle()'s speed at `t` as a fraction of its peak: 0 -> 1 over the ease-in, 1 through the
## flat, 1 -> 0 over the ease-out. 0 outside the spin.
static func spin_speed_fraction(t: float, duration: float, ease_in_s: float,
		ease_out_s: float) -> float:
	if t < 0.0 or t > duration or duration <= 0.0:
		return 0.0
	var ei := minf(ease_in_s, duration * 0.5)
	var eo := minf(ease_out_s, duration * 0.5)
	if ei > 0.0 and t < ei:
		return t / ei
	if eo > 0.0 and t > duration - eo:
		return (duration - t) / eo
	return 1.0


## The two arms' hold for the spin, bone index -> rotation. Straight arms from each shoulder at
## the point P a reach in front of the chest and `drop` below shoulder height where the hands
## meet. Returns {pose, centre_in_chest}: the pose dictionary and P in the chest bone's rest frame.
static func solve_reach(skel: Skeleton3D, drop: float) -> Dictionary:
	var out := {"pose": {}, "centre_in_chest": Vector3.ZERO, "ok": false}
	if skel == null:
		return out
	var ids := {}
	for n in ARM_BONES:
		ids[n] = skel.find_bone(n)
	var chest := skel.find_bone(&"UpperChest")
	if chest < 0 or ids["RightUpperArm"] < 0 or ids["LeftUpperArm"] < 0 \
			or ids["RightLowerArm"] < 0 or ids["LeftLowerArm"] < 0 \
			or ids["RightHand"] < 0 or ids["LeftHand"] < 0:
		return out
	var rest := func(i: int) -> Transform3D: return skel.get_bone_global_rest(i)
	var r_sh: Vector3 = rest.call(ids["RightUpperArm"]).origin
	var l_sh: Vector3 = rest.call(ids["LeftUpperArm"]).origin
	var arm_len: float = (rest.call(ids["RightLowerArm"]).origin - r_sh).length() \
		+ (rest.call(ids["RightHand"]).origin - rest.call(ids["RightLowerArm"]).origin).length()
	var mid := (r_sh + l_sh) * 0.5
	var half_w := (r_sh - l_sh).length() * 0.5
	var chest_rest: Transform3D = rest.call(chest)
	var front := chest_rest.basis.z
	front.y = 0.0
	front = front.normalized() if front.length() > 0.001 else Vector3.BACK
	var reach := sqrt(maxf(arm_len * arm_len - half_w * half_w - drop * drop, 0.01))
	var centre := mid + front * reach + Vector3.DOWN * drop
	var pose := {}
	for side in ["Right", "Left"]:
		var upper: int = ids[side + "UpperArm"]
		var lower: int = ids[side + "LowerArm"]
		var shoulder: Vector3 = rest.call(upper).origin
		var d0: Vector3 = (rest.call(lower).origin - shoulder).normalized()
		var d1: Vector3 = (centre - shoulder).normalized()
		var arc := Quaternion(d0, d1)
		var parent := skel.get_bone_parent(upper)
		var gp: Basis = rest.call(parent).basis if parent >= 0 else Basis.IDENTITY
		var lr: Basis = skel.get_bone_rest(upper).basis
		# A bone pose is the bone's whole local rotation (rest is only where it starts), so the
		# result is the rest rotation turned by `arc` in skeleton space: gp^-1 * arc * gp * lr.
		var local_new := gp.inverse() * Basis(arc) * gp * lr
		pose[upper] = local_new.get_rotation_quaternion()
		# Held at rest: straight arm, flat hand, shoulder where the rig put it.
		for held in [lower, ids[side + "Hand"], skel.find_bone(side + "Shoulder")]:
			if held >= 0:
				pose[held] = skel.get_bone_rest(held).basis.get_rotation_quaternion()
	out["pose"] = pose
	out["centre_in_chest"] = chest_rest.affine_inverse() * centre
	out["ok"] = true
	return out


# --- wiring --------------------------------------------------------------------------------

func setup(pilot: Node, holder: Node, skeleton: Skeleton3D, vfx: Node) -> void:
	_pilot = pilot
	_holder = holder
	_skeleton = skeleton
	_vfx = vfx
	_rng.randomize()
	zone = Area3D.new()
	zone.name = &"ReflectZone"
	zone.collision_layer = 0
	zone.collision_mask = ZONE_MASK
	zone.monitoring = false
	zone.monitorable = false
	var shape := CollisionShape3D.new()
	_zone_shape = SphereShape3D.new()
	_zone_shape.radius = zone_radius
	shape.shape = _zone_shape
	zone.add_child(shape)
	add_child(zone)
	zone.top_level = true
	if _skeleton == null:
		return
	_chest_bone = _skeleton.find_bone(&"UpperChest")
	var solved := solve_reach(_skeleton, hand_drop)
	if not solved["ok"]:
		push_error("reflect_spin: the rig lacks the arm bones the spin needs - it will not run")
		return
	_centre_in_chest = solved["centre_in_chest"]
	_two_arm_pose = solved["pose"]
	_setup_one_arm()
	pose_modifier = _ArmPoseModifier.new()
	pose_modifier.name = &"SpinPoseModifier"
	pose_modifier.pose = solved["pose"]
	pose_modifier.blend_time = pose_blend
	# After the holder's own modifier, so this one has the last word on the arms.
	_skeleton.add_child(pose_modifier)
	_build_disc()


## The rendered (physics-interpolated) transforms. Plain global_transform is the last physics
## tick's, which steps at 60 Hz while the frame it is drawn in does not - every jitter in the
## streak was that difference.
func _skel_xf() -> Transform3D:
	return _skeleton.get_global_transform_interpolated()


func _pilot_pos() -> Vector3:
	return _pilot.get_global_transform_interpolated().origin


## The spin angle for this rendered frame, not the last physics tick: the tick's angle advances
## in 60 Hz jumps, which stepped both the staff and the streak.
func _refresh_angle() -> void:
	if phase != Phase.SPIN:
		return
	# What is drawn is between the last two ticks, `fraction` of the way from the older to the newer.
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	var t := elapsed - tick + Engine.get_physics_interpolation_fraction() * tick
	angle = spin_angle(clampf(t, 0.0, spin_duration), spin_duration, spin_turns, ease_in, ease_out)


func _setup_one_arm() -> void:
	var upper := _skeleton.find_bone(&"RightUpperArm")
	var lower := _skeleton.find_bone(&"RightLowerArm")
	var hand := _skeleton.find_bone(&"RightHand")
	_hand_bone = hand
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_hold_bones = {"upper": upper, "lower": lower, "parent": _skeleton.get_bone_parent(upper)}
	_arm_len = _skeleton.get_bone_rest(lower).origin.length() 		+ _skeleton.get_bone_rest(hand).origin.length()
	for n in ["RightShoulder", "RightLowerArm", "RightHand"]:
		var i := _skeleton.find_bone(n)
		if i >= 0:
			_one_arm_pose[i] = _skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
	_one_arm_pose[upper] = _skeleton.get_bone_rest(upper).basis.get_rotation_quaternion()


## Aims the right arm straight out in front of him, level with the world rather than the leaning
## chest, and records where the fist ends up. Runs every frame of a one-armed spin.
func _update_one_arm() -> void:
	var upper: int = _hold_bones["upper"]
	var parent: int = _hold_bones["parent"]
	var skel_basis := _skel_xf().basis
	var scale_f := skel_basis.get_scale().x
	var inv := skel_basis.orthonormalized().inverse()
	var gp := Basis.IDENTITY
	var shoulder := Vector3.ZERO
	if parent >= 0:
		var pt := _skeleton.get_bone_global_pose(parent)
		gp = pt.basis.orthonormalized()
		shoulder = (pt * (_skeleton.get_bone_rest(upper).origin))
	else:
		shoulder = _skeleton.get_bone_rest(upper).origin
	var model: Node3D = _pilot.character
	var facing := model.get_global_transform_interpolated().basis.z
	facing.y = 0.0
	facing = facing.normalized() if facing.length() > 0.001 else Vector3.FORWARD
	var right := Vector3.UP.cross(facing).normalized()
	var want_world := facing * (_arm_len * scale_f) + Vector3.DOWN * sprint_hand_drop 		+ right * sprint_hand_out
	var d1 := (inv * want_world).normalized()
	var lower: int = _hold_bones["lower"]
	var lr := _skeleton.get_bone_rest(upper).basis
	var d0 := (gp * (lr * _skeleton.get_bone_rest(lower).origin.normalized())).normalized()
	var arc := Quaternion(d0, d1)
	var upper_local := gp.inverse() * Basis(arc) * gp * lr
	_one_arm_pose[upper] = upper_local.get_rotation_quaternion()
	# The elbow folds the forearm up (the way a real elbow bends), about the axis d1 x up.
	var upper_len := _skeleton.get_bone_rest(lower).origin.length()
	var fore_len := _arm_len - upper_len
	var fdir := d1
	var bend := deg_to_rad(sprint_elbow_bend)
	var axis := d1.cross(Vector3.UP)
	if bend > 0.0 and axis.length() > 0.01:
		axis = axis.normalized()
		var rot := Basis(axis, bend)
		var lower_gp := gp * upper_local
		_one_arm_pose[lower] = (lower_gp.inverse() * rot * lower_gp 			* _skeleton.get_bone_rest(lower).basis).get_rotation_quaternion()
		fdir = rot * d1
	else:
		_one_arm_pose[lower] = _skeleton.get_bone_rest(lower).basis.get_rotation_quaternion()
	if _hand_centre_stale:
		_one_arm_centre = _skel_xf() * (shoulder + d1 * upper_len + fdir * fore_len)


## Right after the rig has taken this frame's pose, so the staff is set from the fist as it really
## is, not as last frame's arm or the aim maths say it is. Only the one-armed spin follows the
## hand; the two-armed one is a fixed meeting point.
func _on_skeleton_updated() -> void:
	if not (_one_arm and _overriding and _holder != null and _holder.item_instance != null 			and _holder.held_item != null):
		return
	var grip: Vector3 = _holder.held_item.hand_offset.origin
	_one_arm_centre = _skel_xf() * (_skeleton.get_bone_global_pose(_hand_bone) * grip)
	_hand_centre_stale = false
	_refresh_angle()
	_pose_staff()


func ready_to_spin() -> bool:
	return pose_modifier != null


func is_spinning() -> bool:
	return phase == Phase.SPIN


func _build_disc() -> void:
	_disc = MeshInstance3D.new()
	_disc.name = &"SpinDisc"
	_disc.top_level = true
	_disc.visible = false
	_disc.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 2.0
	_disc.mesh = quad
	_disc_mat = ShaderMaterial.new()
	_disc_mat.shader = _SPIN_DISC_SHADER
	_disc.material_override = _disc_mat
	add_child(_disc)


## The press. Does nothing if any gate is shut. Returns whether a spin started.
func try_start() -> bool:
	if not ready_to_spin() or _holder == null:
		return false
	var blocked := _blocked_by_state()
	var frozen: bool = _pilot.frozen
	if not can_start(phase == Phase.IDLE, _holder.item_instance != null, _holder.is_drawn,
			frozen, blocked):
		return false
	phase = Phase.SPIN
	elapsed = 0.0
	angle = 0.0
	_hit_this_spin.clear()
	# Always the one-armed spin, standing too (2026-10-12): the two-armed one held it at his hip.
	_one_arm = true
	_hand_centre_stale = true
	if _one_arm:
		_update_one_arm()
		pose_modifier.pose = _one_arm_pose
	else:
		pose_modifier.pose = _two_arm_pose
	pose_modifier.blend_time = pose_blend
	_zone_shape.radius = zone_radius
	zone.monitoring = true
	_overriding = true
	# The staff is placed in world space every rendered frame, so the engine's own physics
	# interpolation of it (which only knows the ticks) would fight that.
	if _holder.item_instance != null:
		_holder.item_instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	spin_started.emit()
	return true


## The states whose animations need his hands. Rail grind, wall-run, wall climb, mantle and vault.
func _blocked_by_state() -> bool:
	return _pilot.is_climbing or _pilot.is_vaulting or _pilot.is_wall_running \
		or _pilot.is_wall_climbing \
		or _pilot.is_rail_grinding or _pilot.is_rail_switching


## Ends everything at once - used when the staff is holstered mid-spin.
func cancel() -> void:
	if phase == Phase.IDLE:
		return
	_finish_spin()
	phase = Phase.IDLE
	elapsed = 0.0
	_release_item()


func _finish_spin() -> void:
	zone.monitoring = false
	if pose_modifier != null:
		pose_modifier.target = 0.0
	spin_ended.emit()


func _release_item() -> void:
	_overriding = false
	if _holder != null and _holder.item_instance != null:
		_holder.item_instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	if _holder != null and _holder.item_instance != null and _holder.held_item != null:
		_holder.item_instance.transform = _holder.held_item.hand_offset


# --- per frame -------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if phase == Phase.IDLE or _holder == null:
		return
	if not _holder.is_drawn or _holder.item_instance == null:
		cancel()
		return
	elapsed += delta
	if phase == Phase.SPIN:
		if _one_arm:
			_update_one_arm()
		angle = spin_angle(elapsed, spin_duration, spin_turns, ease_in, ease_out)
		pose_modifier.target = 1.0
		zone.global_position = spin_centre()
		_reflect_overlaps()
		if elapsed >= spin_duration:
			angle = spin_turns * TAU
			_finish_spin()
			phase = Phase.RECOVERY
			elapsed = 0.0
	elif elapsed >= recovery_duration:
		phase = Phase.IDLE
		elapsed = 0.0


func _process(_delta: float) -> void:
	_refresh_angle()
	if _one_arm and phase == Phase.SPIN:
		_update_one_arm()
	if _overriding and _holder != null and _holder.item_instance != null:
		_pose_staff()
	_draw_disc()


## Where the staff spins: a reach in front of the chest, carried by the chest as it leans.
func spin_centre() -> Vector3:
	if _one_arm:
		return _one_arm_centre
	if _skeleton == null or _chest_bone < 0:
		return _pilot_pos() + Vector3.UP * 1.2
	var chest_pose := _skeleton.get_bone_global_pose(_chest_bone)
	return _skel_xf() * (chest_pose * _centre_in_chest)


## The staff's basis at spin angle `a`: it starts standing upright and turns about the way he
## faces, so the circle it draws is the one in the reference picture.
func spin_basis(a: float) -> Basis:
	var model: Node3D = _pilot.character
	var facing := model.get_global_transform_interpolated().basis.z.normalized()
	return Basis(facing, a) * Basis.looking_at(-facing, Vector3.UP)


func _pose_staff() -> void:
	var item: Node3D = _holder.item_instance
	var w := 1.0
	if pose_modifier != null:
		w = smoothstep(0.0, 1.0, pose_modifier.influence)
	var spin := Transform3D(spin_basis(angle), spin_centre())
	if w >= 0.999:
		item.global_transform = spin
	else:
		var hand: Transform3D = _holder.hand_socket.get_global_transform_interpolated() * _holder.held_item.hand_offset
		item.global_transform = hand.interpolate_with(spin, w)
	# The blend-out is done once the arms are back and the spin is over.
	if phase != Phase.SPIN and pose_modifier != null and pose_modifier.influence <= 0.001:
		_release_item()


func _reflect_overlaps() -> void:
	var found: Array = []
	found.append_array(zone.get_overlapping_areas())
	found.append_array(zone.get_overlapping_bodies())
	for node in found:
		if node in _hit_this_spin or not node.is_in_group(GROUP) or not node.has_method(&"reflect"):
			continue
		if node.get("reflected") == true:
			continue
		_hit_this_spin.append(node)
		var perfect := is_perfect(elapsed, perfect_window)
		var point: Vector3 = node.global_position
		node.reflect(reflect_direction(perfect, point, node.get("shooter")), perfect)
		_feedback(point, perfect)
		reflected.emit(node, perfect, point)


## Where a hit goes: back at the shooter if perfect (and it still exists), else a random throw
## inside the cone around the camera's aim.
func reflect_direction(perfect: bool, from: Vector3, shooter: Variant) -> Vector3:
	if perfect and shooter is Node3D and is_instance_valid(shooter):
		var to: Vector3 = (shooter as Node3D).global_position + Vector3.UP * 1.0 - from
		if to.length() > 0.01:
			return to.normalized()
	var cam: Camera3D = _pilot.camera_3d
	var aim: Vector3 = -cam.global_basis.z if cam != null else _pilot.character.global_basis.z
	return random_cone_direction(aim, random_cone_deg, _rng)


func _feedback(point: Vector3, perfect: bool) -> void:
	if perfect:
		if Settings.camera_motion:
			_pilot.kick_fov(fov_kick, fov_kick_time)
			_hit_stop()
	if _vfx != null and Settings.movement_effects:
		var aim: Vector3 = -_pilot.camera_3d.global_basis.z if _pilot.camera_3d != null else Vector3.FORWARD
		_vfx.reflect_burst(point, aim,
			perfect_spark_count if perfect else spark_count,
			perfect_spark_speed if perfect else spark_speed)


func _hit_stop() -> void:
	if hit_stop <= 0.0 or Engine.time_scale != 1.0 or not is_inside_tree():
		return
	Engine.time_scale = 0.05
	# ignore_time_scale: the timer counts real seconds, or it would never end.
	get_tree().create_timer(hit_stop, true, false, true).timeout.connect(
		func(): Engine.time_scale = 1.0)


# --- the spin disc ------------------------------------------------------------------------------

## Placed on the staff itself every rendered frame - its centre, its plane, its angle - so the two
## can never drift apart. Opacity follows the spin's speed, so it is gone while the staff is slow.
func _draw_disc() -> void:
	if _disc == null:
		return
	var speed := 0.0
	if phase == Phase.SPIN and Settings.movement_effects and _overriding 			and _holder != null and _holder.item_instance != null:
		var tick := 1.0 / float(Engine.physics_ticks_per_second)
		var t := elapsed - tick + Engine.get_physics_interpolation_fraction() * tick
		speed = spin_speed_fraction(clampf(t, 0.0, spin_duration), spin_duration, ease_in, ease_out)
	_disc.visible = speed > 0.0
	if not _disc.visible:
		return
	var staff: Transform3D = _holder.item_instance.global_transform
	_disc.global_transform = Transform3D(staff.basis.orthonormalized().scaled(Vector3.ONE * tip_distance),
		staff.origin)
	_disc_mat.set_shader_parameter(&"fade", speed)
	_disc_mat.set_shader_parameter(&"disc_alpha", disc_alpha)
	_disc_mat.set_shader_parameter(&"rim", disc_rim)
	_disc_mat.set_shader_parameter(&"smear_length", deg_to_rad(smear_length))
