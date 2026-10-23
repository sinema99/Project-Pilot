## pilot9's draw and holster: he puts his right arm out a little, the staff forms in his hand out
## of thin air - growing from his grip to both ends behind two cyan edges - and the arm carries it
## into the hold. Holstering plays the same timeline backwards. Built at runtime by
## pilot9.gd::_setup_equip_anim(), like the item holder and the reflect. See
## docs/specs/pilot9-staff-materialize.md.
##
## Procedural - no clip. The arm-out pose is worked out once from the rig's rest pose and three
## angles, so a re-export of PILOT9.glb cannot leave stale numbers behind. The staff never leaves
## the hand socket: holstered it is hidden, and the sweep is a scale along its own length.
extends Node

const _ArmPoseModifier := preload("res://scripts/items/arm_pose_modifier.gd")
const _ItemHolder := preload("res://scripts/items/item_holder.gd")
const _EDGE_SHADER := preload("res://shaders/cel/vfx/materialize_edge.gdshader")

signal finished(drawn: bool)

@export_group("Timing")
## The arm lifting out, seconds. Nothing in his hand yet.
@export_range(0.02, 1.0, 0.01) var out_time: float = 0.15
## The staff forming, grip to both ends, with the arm held out.
@export_range(0.02, 1.0, 0.01) var sweep_time: float = 0.20
## The arm carrying the staff into whatever the drawn arm does at this pace.
@export_range(0.02, 1.0, 0.01) var back_time: float = 0.15

@export_group("Arm out")
## Off his body to the side, degrees (0 hangs straight down).
@export_range(0.0, 90.0, 1.0) var arm_out_angle: float = 35.0
## Then tipped toward his front, degrees.
@export_range(0.0, 90.0, 1.0) var arm_forward_angle: float = 20.0
## The forearm bent further forward than the upper arm, degrees.
@export_range(0.0, 90.0, 1.0) var elbow_bend: float = 25.0
## The wrist's flick, fingers up, at the start of the sweep. Degrees at its peak.
@export_range(0.0, 60.0, 1.0) var flick_angle: float = 25.0
## How long the flick lasts from the start of the sweep, seconds.
@export_range(0.02, 0.5, 0.01) var flick_time: float = 0.12

@export_group("Edge")
@export var edge_color: Color = Color(0.35, 0.95, 1.0)
## Above 1 so it blooms like his rim light.
@export_range(0.0, 8.0, 0.1) var edge_energy: float = 2.5
## Band length along the staff, metres.
@export_range(0.002, 0.1, 0.001) var edge_thickness: float = 0.015
## Band radius over the staff's own.
@export_range(1.0, 3.0, 0.05) var edge_radius_scale: float = 1.35
## The last part of the sweep the edges fade out over, as a fraction of it.
@export_range(0.0, 1.0, 0.05) var edge_fade: float = 0.3

## Where the timeline is, 0 (holstered, arm free) to total_time() (drawn, settled).
var t: float = 0.0
## +1 drawing, -1 holstering, 0 idle.
var direction: int = 0
var arm_modifier: SkeletonModifier3D = null

var _pilot: Node = null
var _holder: Node = null
var _skeleton: Skeleton3D = null
var _reflect: Node = null
## bone index -> Quaternion: the arm out, palm down.
var _out_pose: Dictionary = {}
## The hand's rotation at the top of the flick.
var _flick_hand := Quaternion.IDENTITY
var _hand_bone := -1
## The holder's arm weight when a holster started: the arm back runs backwards from it.
var _holster_weight := 0.0
## The staff's extent in its own frame, read when an animation starts.
var _half_length := 0.8
var _radius := 0.025
var _edges: Array[MeshInstance3D] = []
var _edge_mat: ShaderMaterial = null


# --- pure helpers, static so tests can check them without a rig ---------------------------

## Whether a press starts an animation. Every gate in one place.
static func can_start(idle: bool, has_item: bool, blocked: bool) -> bool:
	return idle and has_item and not blocked


## How much of the staff has formed at timeline time `tt`, 0..1. Fast out of the grip, easing
## into full length.
static func sweep_fraction(tt: float, out: float, sweep: float) -> float:
	var x := clampf((tt - out) / maxf(sweep, 0.0001), 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)


## The animation arm's weight at timeline time `tt`. Up over the arm out, full through the sweep,
## then to `settled` - the weight the holder's own arm takes over at - across the arm back.
static func arm_weight(tt: float, out: float, sweep: float, back: float, settled: float) -> float:
	if tt <= out:
		return smoothstep(0.0, 1.0, tt / maxf(out, 0.0001))
	return lerpf(1.0, settled, back_fraction(tt, out, sweep, back))


## How far through the arm back `tt` is, 0..1, eased.
static func back_fraction(tt: float, out: float, sweep: float, back: float) -> float:
	return smoothstep(0.0, 1.0, clampf((tt - out - sweep) / maxf(back, 0.0001), 0.0, 1.0))


## How far the arm's shape has gone from arm-out to the hold, given the arm back's fraction `s`.
## Always 1 at s = 1, so the handover to the holder's arm cannot pop. With little drawn weight to
## hand over to (idle), it lingers on arm-out, so the arm drops rather than passing through the hold.
static func shape_fraction(s: float, settled: float) -> float:
	return lerpf(s * s * s, s, clampf(settled, 0.0, 1.0))


## The wrist flick, 0..1..0 over `flick` seconds from the start of the sweep.
static func flick_amount(tt: float, out: float, flick: float) -> float:
	var u := (tt - out) / maxf(flick, 0.0001)
	if u <= 0.0 or u >= 1.0:
		return 0.0
	return sin(u * PI)


## The upper arm's direction in skeleton space (facing +Z, his right -X, up +Y): straight down,
## out to his right by `out_deg`, then toward his front by `fwd_deg`.
static func upper_arm_dir(out_deg: float, fwd_deg: float) -> Vector3:
	var o := deg_to_rad(out_deg)
	var v := Vector3(-sin(o), -cos(o), 0.0)
	return (Basis(Vector3.RIGHT, -deg_to_rad(fwd_deg)) * v).normalized()


## The forearm: the upper arm's direction bent `bend_deg` further toward his front.
static func forearm_dir(upper: Vector3, bend_deg: float) -> Vector3:
	var axis := upper.cross(Vector3.BACK)
	if axis.length_squared() < 0.000001:
		return upper
	return (Basis(axis.normalized(), deg_to_rad(bend_deg)) * upper).normalized()


# --- wiring --------------------------------------------------------------------------------

func setup(pilot: Node, holder: Node, skeleton: Skeleton3D, reflect: Node) -> void:
	_pilot = pilot
	_holder = holder
	_skeleton = skeleton
	_reflect = reflect
	if _skeleton == null:
		return
	_hand_bone = _skeleton.find_bone(_ItemHolder.HAND_BONE)
	if not _build_out_pose():
		push_error("equip_anim: the rig lacks the right arm chain - R will snap instead")
		return
	arm_modifier = _ArmPoseModifier.new()
	arm_modifier.name = &"EquipPoseModifier"
	arm_modifier.blend_time = 0.0
	# Added after the holder's and the reflect's modifiers, so this one has the last word.
	_skeleton.add_child(arm_modifier)
	_build_edges()


## Works out the arm-out pose from the rig's rest: each bone keeps its rest twist and is turned,
## by the shortest arc, to point where the angles say. Bones point down their local +Y.
func _build_out_pose() -> bool:
	var names := _ItemHolder.ARM_BONES
	var idx: Array[int] = []
	for n in names:
		var i := _skeleton.find_bone(n)
		if i < 0:
			return false
		idx.append(i)
	var shoulder := idx[0]
	var upper := idx[1]
	var lower := idx[2]
	var hand := idx[3]
	var parent := _skeleton.get_bone_parent(shoulder)
	var g_parent := _skeleton.get_bone_global_rest(parent).basis if parent >= 0 else Basis.IDENTITY
	var g_shoulder := g_parent * _skeleton.get_bone_rest(shoulder).basis
	var d_upper := upper_arm_dir(arm_out_angle, arm_forward_angle)
	var d_fore := forearm_dir(d_upper, elbow_bend)
	var g_upper := _aim(g_shoulder * _skeleton.get_bone_rest(upper).basis, d_upper)
	var g_lower := _aim(g_upper * _skeleton.get_bone_rest(lower).basis, d_fore)
	var g_hand := _aim(g_lower * _skeleton.get_bone_rest(hand).basis, d_fore)
	# Palm down: turn the hand about the fingers until the palm's normal (+Z) is as near straight
	# down as it can get.
	var fingers := g_hand.y.normalized()
	var want := Vector3.DOWN - fingers * fingers.dot(Vector3.DOWN)
	var have := g_hand.z - fingers * fingers.dot(g_hand.z)
	if want.length_squared() > 0.000001 and have.length_squared() > 0.000001:
		g_hand = Basis(Quaternion(have.normalized(), want.normalized())) * g_hand
	var flick_axis := fingers.cross(Vector3.UP)
	var g_flick := g_hand
	if flick_axis.length_squared() > 0.000001:
		g_flick = Basis(flick_axis.normalized(), deg_to_rad(flick_angle)) * g_hand
	_out_pose = {
		shoulder: _skeleton.get_bone_rest(shoulder).basis.get_rotation_quaternion(),
		upper: _local(g_shoulder, g_upper),
		lower: _local(g_upper, g_lower),
		hand: _local(g_lower, g_hand),
	}
	_flick_hand = _local(g_lower, g_flick)
	return true


static func _aim(b: Basis, dir: Vector3) -> Basis:
	return Basis(Quaternion(b.y.normalized(), dir.normalized())) * b


static func _local(parent_global: Basis, global: Basis) -> Quaternion:
	return (parent_global.orthonormalized().inverse() * global.orthonormalized()).get_rotation_quaternion()


func total_time() -> float:
	return out_time + sweep_time + back_time


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
	_measure_item()
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
	# Scaled from _process every rendered frame: the engine's tick interpolation would fight it.
	_holder.item_instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_apply()
	return true


## Jumps to the end of whatever is playing: a draw lands fully formed and drawn, a holster gone.
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
	_show_edges(false)
	if _holder.item_instance == null:
		return
	_holder.item_instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	# set_drawn() puts the staff back at hand_offset, full length, shown or hidden.
	_holder.set_drawn(drawn)
	if drawn and _holder.arm_modifier != null:
		_holder.arm_modifier.influence = settled
	finished.emit(drawn)


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
		_show_edges(false)
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


## Sets the arm for this frame and grows the staff.
func _apply() -> void:
	var settled := _settled_weight()
	var s := back_fraction(t, out_time, sweep_time, back_time)
	var f := shape_fraction(s, settled)
	var hold: Dictionary = _ItemHolder.pose_from_rotations(_holder.held_item.hold_rotations, _skeleton)
	var flick := flick_amount(t, out_time, flick_time)
	var pose := {}
	for bone in _out_pose:
		var q: Quaternion = _out_pose[bone]
		if bone == _hand_bone:
			q = q.slerp(_flick_hand, flick)
		pose[bone] = q.slerp(hold[bone], f) if hold.has(bone) else q
	arm_modifier.pose = pose
	arm_modifier.target = arm_weight(t, out_time, sweep_time, back_time, settled)
	arm_modifier.influence = arm_modifier.target
	_grow_staff(sweep_fraction(t, out_time, sweep_time))


## The staff at `amount` of its length, centred on the grip, with an edge band on each end.
func _grow_staff(amount: float) -> void:
	var item: Node3D = _holder.item_instance
	var offset: Transform3D = _holder.held_item.hand_offset
	item.visible = amount > 0.0
	item.transform = offset * Transform3D(Basis.from_scale(Vector3(1.0, maxf(amount, 0.001), 1.0)))
	var fade := clampf((1.0 - amount) / maxf(edge_fade, 0.0001), 0.0, 1.0)
	_show_edges(amount > 0.0 and fade > 0.0)
	if not _edges[0].visible:
		return
	var reach := _half_length * amount
	_edges[0].transform = offset * Transform3D(Basis.IDENTITY, Vector3(0.0, reach, 0.0))
	_edges[1].transform = offset * Transform3D(Basis.IDENTITY, Vector3(0.0, -reach, 0.0))
	_edge_mat.set_shader_parameter(&"fade", fade)


# --- the edges ---------------------------------------------------------------------------------

func _build_edges() -> void:
	_edge_mat = ShaderMaterial.new()
	_edge_mat.shader = _EDGE_SHADER
	for i in 2:
		var edge := MeshInstance3D.new()
		edge.name = &"MaterializeEdge%d" % i
		edge.visible = false
		edge.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		edge.mesh = CylinderMesh.new()
		edge.material_override = _edge_mat
		if _holder != null and _holder.hand_socket != null:
			_holder.hand_socket.add_child(edge)
		else:
			add_child(edge)
		_edges.append(edge)


func _show_edges(on: bool) -> void:
	for e in _edges:
		e.visible = on


## Reads the staff's length and girth from its meshes (in its own frame), and sizes the bands.
func _measure_item() -> void:
	var item: Node3D = _holder.item_instance
	var box := AABB()
	var first := true
	for node in item.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := (item.global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb() \
			if item.is_inside_tree() else mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if not first:
		_half_length = maxf(absf(box.position.y), absf(box.end.y))
		_radius = maxf(box.size.x, box.size.z) * 0.5
	_edge_mat.set_shader_parameter(&"edge_color", Vector3(edge_color.r, edge_color.g, edge_color.b))
	_edge_mat.set_shader_parameter(&"energy", edge_energy)
	for e in _edges:
		var c := e.mesh as CylinderMesh
		c.top_radius = _radius * edge_radius_scale
		c.bottom_radius = _radius * edge_radius_scale
		c.height = edge_thickness
		c.radial_segments = 16
		c.rings = 1
