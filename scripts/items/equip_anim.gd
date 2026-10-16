## pilot9's draw and holster: he reaches back, grabs the staff, whips it through an arc in the
## plane of his back and spins it once in his hand before settling. Holstering plays the same
## timeline backwards. Built at runtime by pilot9.gd::_setup_equip_anim(), like the item holder
## and the reflect. See docs/specs/pilot9-equip-holster.md.
##
## Procedural - no clip. The arm is the item's own running hold (`hold_rotations`) on a modifier
## of its own, and the staff is placed in world space every rendered frame from where it sits on
## the back, where it sits in the hand and which way the model faces, so a re-export of PILOT9.glb
## or a retuned back_offset cannot leave stale numbers behind.
extends Node

const _ArmPoseModifier := preload("res://scripts/items/arm_pose_modifier.gd")
const _ItemHolder := preload("res://scripts/items/item_holder.gd")
const _ReflectSpin := preload("res://scripts/items/reflect_spin.gd")
const _SPIN_DISC_SHADER := preload("res://shaders/cel/vfx/spin_disc.gdshader")

signal finished(drawn: bool)

@export_group("Timing")
## The arm easing back to the staff, seconds. The staff stays on his back.
@export_range(0.02, 1.0, 0.01) var reach_time: float = 0.10
## Grab to in-plane: the grip slides to his hand and the staff starts to turn.
@export_range(0.02, 1.0, 0.01) var swing_time: float = 0.08
## The fast turn after the swing. Swing and spin are one continuous turn.
@export_range(0.02, 1.0, 0.01) var spin_time: float = 0.133
## The arm handing over to whatever the drawn arm does at this pace.
@export_range(0.02, 1.0, 0.01) var settle_time: float = 0.053

@export_group("Turn")
## Full turns after the swing. Whole turns only: the turn has to end at the in-hand angle.
@export_range(0, 4) var extra_turns: int = 1
## Speed ramp at the grab and into the settle, seconds of the swing + spin.
@export_range(0.0, 0.3, 0.01) var turn_ease_in: float = 0.033
@export_range(0.0, 0.3, 0.01) var turn_ease_out: float = 0.053

## Where the timeline is, 0 (holstered, arm free) to total_time() (drawn, settled).
var t: float = 0.0
## +1 drawing, -1 holstering, 0 idle.
var direction: int = 0
var arm_modifier: SkeletonModifier3D = null

var _pilot: Node = null
var _holder: Node = null
var _skeleton: Skeleton3D = null
var _reflect: Node = null
var _hand_bone := -1
var _back_bone := -1
## The holder's arm weight when a holster started: the settle runs backwards from it.
var _holster_weight := 0.0
## Whether the staff is being placed by this node (anywhere past the grab).
var _placing := false
var _disc: MeshInstance3D = null
var _disc_mat: ShaderMaterial = null


# --- pure helpers, static so tests can check them without a rig ---------------------------

## Whether a press starts an animation. Every gate in one place.
static func can_start(idle: bool, has_item: bool, blocked: bool) -> bool:
	return idle and has_item and not blocked


## The in-plane angle of a staff axis given in the model's own frame: 0 is straight up, and it is
## the `a` of Basis(Vector3.BACK, a) * Vector3.UP. Facing is +Z, so a growing angle tips the top
## toward his right (-X) - seen from behind, clockwise.
static func plane_angle(axis_local: Vector3) -> float:
	return atan2(-axis_local.x, axis_local.y)


## Where the turn ends: the in-hand angle reached by turning counter-clockwise (seen from behind)
## from the back angle - top end down his left side - plus `extra` whole turns more.
static func end_angle(a_back: float, a_hand: float, extra: int) -> float:
	return a_back - fposmod(a_back - a_hand, TAU) - float(extra) * TAU


## How far through the turn `u` seconds into swing + spin is, 0..1, easing in and out.
static func turn_fraction(u: float, duration: float, ease_in_s: float, ease_out_s: float) -> float:
	return _ReflectSpin.spin_angle(u, duration, 1.0, ease_in_s, ease_out_s) / TAU


## The animation arm's weight at timeline time `tt`. Up over the reach, full through the turn, then
## to `settled` - the weight the holder's own arm takes over at - across the settle.
static func arm_weight(tt: float, reach: float, turn: float, settle: float, settled: float) -> float:
	if tt <= reach:
		return smoothstep(0.0, 1.0, tt / maxf(reach, 0.0001))
	if tt <= reach + turn:
		return 1.0
	var s := clampf((tt - reach - turn) / maxf(settle, 0.0001), 0.0, 1.0)
	return lerpf(1.0, settled, smoothstep(0.0, 1.0, s))


# --- wiring --------------------------------------------------------------------------------

func setup(pilot: Node, holder: Node, skeleton: Skeleton3D, reflect: Node) -> void:
	_pilot = pilot
	_holder = holder
	_skeleton = skeleton
	_reflect = reflect
	if _skeleton == null:
		return
	_hand_bone = _skeleton.find_bone(_ItemHolder.HAND_BONE)
	_back_bone = _skeleton.find_bone(_ItemHolder.BACK_BONE)
	if _hand_bone < 0 or _back_bone < 0:
		push_error("equip_anim: the rig lacks %s or %s - R will snap instead" \
			% [_ItemHolder.HAND_BONE, _ItemHolder.BACK_BONE])
		return
	arm_modifier = _ArmPoseModifier.new()
	arm_modifier.name = &"EquipPoseModifier"
	arm_modifier.blend_time = 0.0
	# Added after the holder's and the reflect's modifiers, so this one has the last word.
	_skeleton.add_child(arm_modifier)
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_build_disc()


func total_time() -> float:
	return reach_time + swing_time + spin_time + settle_time


func turn_time() -> float:
	return swing_time + spin_time


func is_playing() -> bool:
	return direction != 0


func ready_to_play() -> bool:
	return arm_modifier != null


func _blocked_by_state() -> bool:
	return _pilot.is_climbing or _pilot.is_vaulting or _pilot.is_wall_running \
		or _pilot.is_wall_climbing


## The press. Draws if holstered, holsters if drawn. Ignored while one is already playing, in a
## mantle, vault or wall-run, and with no item. Returns whether it started.
func toggle() -> bool:
	if not ready_to_play() or _holder == null:
		return false
	if not can_start(direction == 0, _holder.item_instance != null, _blocked_by_state()):
		return false
	if _holder.is_drawn:
		# A spin needs the staff in his hands: holstering ends it on the spot.
		if _reflect != null:
			_reflect.cancel()
		_holster_weight = _holder.arm_modifier.influence if _holder.arm_modifier != null else 0.0
		_holder.set_drawn(false)
		# The holder's arm hands over to this one at the same weight, so the arm does not move.
		if _holder.arm_modifier != null:
			_holder.arm_modifier.influence = 0.0
		direction = -1
		t = total_time()
	else:
		direction = 1
		t = 0.0
	_apply()
	return true


## Jumps to the end of whatever is playing: an equip lands in his hand, drawn; a holster on his back.
func finish_now() -> void:
	if direction == 0:
		return
	_end(direction > 0)


func _end(drawn: bool) -> void:
	var settled := _settled_weight()
	direction = 0
	t = total_time() if drawn else 0.0
	arm_modifier.target = 0.0
	arm_modifier.influence = 0.0
	_release_item()
	if _holder.item_instance == null:
		return
	if drawn:
		_holder.set_drawn(true)
		if _holder.arm_modifier != null:
			_holder.arm_modifier.influence = settled
	else:
		_holder.set_drawn(false)
	_disc.visible = false
	finished.emit(drawn)


func _release_item() -> void:
	_placing = false
	if _holder != null and _holder.item_instance != null and _holder.held_item != null:
		_holder.item_instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
		_holder.item_instance.transform = _holder.held_item.hand_offset if _holder.is_drawn \
			else _holder.held_item.back_offset


## The weight the holder's arm takes over at: live on a draw, frozen at the press on a holster.
func _settled_weight() -> float:
	if direction < 0:
		return _holster_weight
	return _holder.drawn_arm_target()


# --- per frame -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if direction == 0:
		return
	if _holder == null or _holder.item_instance == null:
		direction = 0
		arm_modifier.target = 0.0
		arm_modifier.influence = 0.0
		_placing = false
		_disc.visible = false
		return
	if _blocked_by_state():
		finish_now()
		return
	t += delta * direction
	if direction > 0 and t >= total_time():
		_end(true)
		return
	if direction < 0 and t <= 0.0:
		_end(false)
		return
	_apply()


## Sets the arm for this frame and places the staff.
func _apply() -> void:
	arm_modifier.pose = _ItemHolder.pose_from_rotations(_holder.held_item.hold_rotations, _skeleton)
	arm_modifier.target = arm_weight(t, reach_time, turn_time(), settle_time, _settled_weight())
	arm_modifier.influence = arm_modifier.target
	_pose_staff()


## Right after the rig has taken this frame's pose, so the staff is set from the hand and chest as
## they really are, not as last frame's were.
func _on_skeleton_updated() -> void:
	if direction != 0:
		_pose_staff()


func _skel_xf() -> Transform3D:
	return _skeleton.get_global_transform_interpolated()


## Where the staff sits in his hand this frame, world space.
func hand_transform() -> Transform3D:
	return _skel_xf() * _skeleton.get_bone_global_pose(_hand_bone) * _holder.held_item.hand_offset


## Where the staff sits on his back this frame, world space.
func back_transform() -> Transform3D:
	return _skel_xf() * _skeleton.get_bone_global_pose(_back_bone) * _holder.held_item.back_offset


## Where the staff would sit in his hand this frame with the arm fully in the hold pose, whatever
## the arm is really doing - the turn's end angle comes from this, so it holds still while the
## arm blends in and out at the reach and the settle.
func hold_transform() -> Transform3D:
	var pose: Dictionary = arm_modifier.pose
	var chain: Array[int] = []
	var i := _hand_bone
	while i >= 0 and pose.has(i):
		chain.push_front(i)
		i = _skeleton.get_bone_parent(i)
	var xf := _skeleton.get_bone_global_pose(i) if i >= 0 else Transform3D.IDENTITY
	for b in chain:
		xf = xf * Transform3D(Basis(pose[b] as Quaternion), _skeleton.get_bone_pose_position(b))
	return _skel_xf() * xf * _holder.held_item.hand_offset


## The model's frame, the one the back plane is measured in.
func _model_basis() -> Basis:
	var model: Node3D = _pilot.character
	return model.get_global_transform_interpolated().basis.orthonormalized()


## The staff's world transform at timeline time `tt`.
func staff_transform(tt: float) -> Transform3D:
	var back := back_transform()
	if tt <= reach_time:
		return back
	var hand := hand_transform()
	var model := _model_basis()
	var inv := model.inverse()
	var scale := hand.basis.get_scale()
	var a_back := plane_angle(inv * back.basis.y)
	var hold := hold_transform()
	var a_hand := plane_angle(inv * hold.basis.y)
	var a_end := end_angle(a_back, a_hand, extra_turns)
	var u := tt - reach_time
	var turn := turn_time()
	var f := turn_fraction(minf(u, turn), turn, turn_ease_in, turn_ease_out)
	var plane := model * Basis(Vector3.BACK, lerpf(a_back, a_end, f))
	# The grab: the grip slides from the back placement to his hand, and the back's tilt out of
	# the plane flattens away, both over the swing - so neither end of it pops.
	var g := smoothstep(0.0, 1.0, clampf(u / maxf(swing_time, 0.0001), 0.0, 1.0))
	var back_n := back.basis.orthonormalized()
	var tilt := Quaternion((back_n * (model * Basis(Vector3.BACK, a_back)).inverse()).orthonormalized())
	# The hold trails the staff mostly along his facing, out of the back plane, so the spinning
	# plane tilts over to it while the spin slows - the mirror of the grab.
	var h := smoothstep(0.0, 1.0, clampf((u - swing_time) / maxf(spin_time, 0.0001), 0.0, 1.0))
	var tilt_end := Quaternion(model * Basis(Vector3.BACK, a_hand) * Vector3.UP,
		hold.basis.y.normalized())
	var basis := Basis(tilt.slerp(Quaternion.IDENTITY, g) * Quaternion.IDENTITY.slerp(tilt_end, h)) * plane
	var xf := Transform3D(basis.scaled_local(scale), back.origin.lerp(hand.origin, g))
	if u <= turn:
		return xf
	var s := smoothstep(0.0, 1.0, clampf((u - turn) / maxf(settle_time, 0.0001), 0.0, 1.0))
	return xf.interpolate_with(hand, s)


func _pose_staff() -> void:
	var item: Node3D = _holder.item_instance
	if item == null or _holder.held_item == null:
		return
	if t <= reach_time:
		# Still on his back: the holder's own placement, in the back socket.
		if _placing:
			_release_item()
		_draw_disc()
		return
	if not _placing:
		_placing = true
		# Placed in world space every rendered frame, so the engine's interpolation of it (which
		# only knows the ticks) would fight that.
		item.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	item.global_transform = staff_transform(t)
	_draw_disc()


# --- the spin disc ------------------------------------------------------------------------------

func _build_disc() -> void:
	_disc = MeshInstance3D.new()
	_disc.name = &"EquipSpinDisc"
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


## The reflect's disc, on this turn: same look (its settings), opacity from the turn's speed.
func _draw_disc() -> void:
	if _disc == null:
		return
	var speed := 0.0
	var u := t - reach_time
	if _placing and Settings.movement_effects and u >= 0.0 and u <= turn_time():
		speed = _ReflectSpin.spin_speed_fraction(u, turn_time(), turn_ease_in, turn_ease_out)
	_disc.visible = speed > 0.0
	if not _disc.visible:
		return
	var staff: Transform3D = _holder.item_instance.global_transform
	var r: Node = _reflect
	var tip: float = r.tip_distance if r != null else 0.8
	# The shader smears behind a tip turning toward local -X (the reflect's way). A draw turns the
	# other way, so its disc is mirrored across the staff; a holster runs it backwards, unmirrored.
	var mirror := -1.0 if direction > 0 else 1.0
	_disc.global_transform = Transform3D(
		staff.basis.orthonormalized() * Basis.from_scale(Vector3(mirror * tip, tip, tip)), staff.origin)
	_disc_mat.set_shader_parameter(&"fade", speed)
	_disc_mat.set_shader_parameter(&"disc_alpha", r.disc_alpha if r != null else 0.35)
	_disc_mat.set_shader_parameter(&"rim", r.disc_rim if r != null else 0.6)
	_disc_mat.set_shader_parameter(&"smear_length", deg_to_rad(r.smear_length if r != null else 120.0))
