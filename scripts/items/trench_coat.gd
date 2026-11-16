## pilot9's trench coat: the chain bones, the skinned mesh, the springs that swing the skirt, and
## the on/off switch. Built at runtime by pilot9.gd::_setup_coat(), like the hat holder, so a
## rebuild of pilot9.tscn cannot drop it. See docs/specs/pilot9-trench-coat.md.
##
## The mesh is built once (scripts/items/trench_coat_mesh.gd). What moves each physics tick is 16
## bone rotations: 8 chains of two segments. A segment is a 2D tilt (radians: x his left, y his
## front) in his hips frame, on a damped spring.
extends Node

const _CoatMesh := preload("res://scripts/items/trench_coat_mesh.gd")
const _CoatBody := preload("res://scripts/items/trench_coat_body.gd")
const _CEL := preload("res://resources/pilot_cel_character.tres")

const MESH_NAME := &"Coat"
## What a body piece's cut copy is called: its own name and this.
const CUT_SUFFIX := "CoatCut"
const CHAINS := _CoatMesh.CHAINS
const SIDE_CHAINS := _CoatMesh.SIDE_CHAINS
## A body mesh is an arm piece, and hidden under the coat, when this share of it rides arm bones.
const ARM_SHARE := 0.95
const ARM_BONES := ["Shoulder", "UpperArm", "LowerArm"]
## Per kind (upper segment, lower segment): share of the drag, of the idle sway, of the frequency.
const GAIN := [0.55, 1.0]
const IDLE := [0.4, 1.0]
const FREQ := [1.0, 0.85]
## Per chain down one side (front, side, back, vent): how much of a thigh's swing pushes its
## panel out. The front is open, so a raised thigh mostly comes out through the opening.
const THIGH_PUSH := [0.3, 1.0, 1.0, 0.6]
## The leg clearance (2026-11-12, "the upper leg / hip clips through the coat" running sideways
## or at 45 deg): sample points down each leg, [bone from, bone to, t along it, radius to his
## side, radius to his front/back (m)]. The thigh is ~0.075 m to the side (centre x 0.161 ->
## 0.134, outer 0.215) but ~0.12 front to back; the shin ~0.08 by ~0.09.
const LEG_SAMPLES := [[0, 1, 0.12, 0.075, 0.12], [0, 1, 0.3, 0.075, 0.12], [0, 1, 0.5, 0.075, 0.115],
	[0, 1, 0.7, 0.075, 0.11], [0, 1, 0.88, 0.072, 0.1], [0, 1, 1.0, 0.07, 0.09],
	[1, 2, 0.2, 0.07, 0.09], [1, 2, 0.45, 0.065, 0.085], [1, 2, 0.7, 0.06, 0.08]]
## Which part of his outline each chain's panels cover: degrees off his front, measured on that
## chain's own side (front panel from the opening's edge round to the side, then side, back,
## vent). A leg point outside a chain's wedge leaves that chain alone - a knee going straight
## forward goes out through the open front, not through the front panel.
const CHAIN_WEDGE := [[35.0, 75.0], [50.0, 130.0], [95.0, 165.0], [140.0, 181.0]]
## The most one panel may hang less swung out than its neighbour, degrees (see _blend_neighbours).
const NEIGHBOUR_STEP_DEG := 22.0
## Likewise the most a panel's upper half may hang less swung out than its own lower half.
const HINGE_STEP_DEG := 20.0
## A hips jump past this in one tick is a teleport: the motion history is dropped.
const TELEPORT := 3.0

@export_group("Colours")
@export var leather_color := Color(0.36, 0.22, 0.12):
	set(value):
		leather_color = value
		_recolour()
@export var lining_color := Color(0.16, 0.10, 0.06):
	set(value):
		lining_color = value
		_recolour()

@export_group("Motion")
## The pendulum in a wind: a tail leans back by atan(drag * speed^2). 0.0135 gives ~19 deg at the
## 5 m/s run and ~37 deg at the 7.5 m/s sprint.
@export var drag := 0.0135
## The most the drag can lean a tail, degrees: the dash and the rails sit here.
@export_range(0.0, 85.0, 1.0) var drag_cap_deg := 62.0
## Radial flare per m/s of falling, degrees, and its cap.
@export var flare_deg := 2.0
@export_range(0.0, 60.0, 1.0) var flare_cap_deg := 35.0
## Sideways lean per rad/s of turning, degrees, and its cap.
@export var swirl_deg := 4.0
@export_range(0.0, 45.0, 1.0) var swirl_cap_deg := 22.0
## Kick per m/s^2 of acceleration, degrees (a landing, a dash launch).
@export var kick_deg := 0.25
## How much of world down the coat hangs toward when he tips over (0 = rides his hips).
@export_range(0.0, 1.0, 0.01) var gravity := 0.85
## Spring frequency (Hz) and damping ratio: one small overshoot, settled in about 0.4 s.
@export var freq := 2.2
@export_range(0.05, 2.0, 0.01) var damping := 0.55
## The idle sway at the hem, degrees (1.2 deg is about 1.5 cm), and its period in seconds.
@export var idle_deg := 1.2
@export var idle_period := 3.4

@export_group("Limits")
## How far a panel may swing in toward his legs, degrees, upper and lower segment.
@export var inward_deg := 4.0
@export var inward_lower_deg := 10.0
## How much of a shin's swing pushes the lower panels out, and the most it can, degrees.
@export_range(0.0, 1.0, 0.01) var shin_push := 0.6
@export var shin_push_cap_deg := 30.0
## Hard cap on any segment's tilt off his hips, degrees.
@export_range(10.0, 170.0, 1.0) var cap_deg := 110.0
## Clearance kept between a chain point and the floor or a wall, metres.
@export var plane_margin := 0.035
## Swing the panels out round his real legs (see LEG_SAMPLES). Off = only the THIGH_PUSH estimate.
@export var leg_clearance := true
## Gap kept between a panel and the outside of his leg, metres, and the most the leg clearance
## may swing a panel out, degrees.
@export var leg_margin := 0.02
## 40 deg is plenty for a sideways stride; past that it was fanning a panel flat along the floor.
@export_range(0.0, 110.0, 1.0) var leg_clear_cap_deg := 40.0
## The lower panels' outward pool while he crouches, degrees.
@export var crouch_pool_deg := 9.0

@export_group("Wind")
## The Ichi storm's push on the coat while he tredges, as a wind speed in m/s (the storm's own
## 28 m/s would pin it flat).
@export var wind_speed := 6.5
## How much of that the gusts add on top, at a full gust.
@export var wind_gust := 0.8

var is_on := false
var pilot: Node = null
var skeleton: Skeleton3D = null
var mesh_instance: MeshInstance3D = null
## His arm pieces: hidden while the coat is on.
var arm_meshes: Array[MeshInstance3D] = []
## His trunk pieces the coat covers: hidden while the coat is on, like the arms...
var covered_meshes: Array[MeshInstance3D] = []
## ...and what is worn in their place: copies with everything under the coat cut away (the front
## strip the open coat shows is all that is left). Shown only while the coat is on. A piece the
## coat covers whole (his shoulder balls) has no copy.
var cut_meshes: Array[MeshInstance3D] = []
## The belly bones [left waist, left mid, right waist, right mid] and their line (see trench_coat_mesh.gd BELLY_BONE): rest
## points in model space, the chest point's bones + weights.
var belly_bones := PackedInt32Array()
var _belly_line: Array = []
var upper_bones := PackedInt32Array()
var lower_bones := PackedInt32Array()
## Extra planes for the next ticks, each [world point, world normal]. Tests and probes use this.
var extra_planes: Array = []
## A world velocity to feel in place of his own (m/s), or null. Tests and probes use this to
## stream the coat on a pilot who is standing still.
var velocity_override: Variant = null
## Microseconds the last tick took.
var last_tick_usec := 0

var _hips := -1
var _legs := PackedInt32Array()
## Per chain: rest-pose pivot relative to the hips, outward direction, which leg (0 left, 1 right).
var _pivot := PackedVector3Array()
var _out := PackedVector2Array()
var _leg := PackedInt32Array()
## Per segment (8 uppers then 8 lowers): rest vector to its far end, tilt, tilt rate, sway phase.
var _rest_vec := PackedVector3Array()
var _d := PackedVector2Array()
var _w := PackedVector2Array()
var _phase := PackedFloat32Array()
## Rest tilts of his thighs and shins, in the hips frame.
var _leg_rest := PackedVector2Array()
var _clock := 0.0
var _seeded := false
var _p := Vector3.ZERO
var _v := Vector3.ZERO
var _a := Vector3.ZERO
var _yaw := 0.0
var _yaw_rate := 0.0
var _leather: ShaderMaterial = null
var _lining: ShaderMaterial = null
var _leather_base: StandardMaterial3D = null
var _lining_base: StandardMaterial3D = null

## Mesh -> whether it is an arm piece. The weights are read once per mesh, not once per pilot.
static var _arm_cache := {}
## Mesh -> trench_coat_body.gd's cut() of it ([] = the coat covers none of it).
static var _cut_cache := {}


func setup(owner_pilot: Node, skel: Skeleton3D) -> void:
	pilot = owner_pilot
	if skel == null:
		push_error("trench_coat: no skeleton - pilot9 will not be able to wear the coat")
		return
	skeleton = skel
	_hips = skel.find_bone("Hips")
	if _hips < 0:
		push_error("trench_coat: skeleton has no Hips bone")
		return
	_find_arm_meshes()
	_cut_body()
	_add_bones()
	_build_mesh()
	set_on(true)


func toggle() -> void:
	set_on(not is_on)


func set_on(on: bool) -> void:
	is_on = on
	if mesh_instance != null:
		mesh_instance.visible = on
	for mi in arm_meshes + covered_meshes:
		if is_instance_valid(mi):
			mi.visible = not on
	for mi in cut_meshes:
		if is_instance_valid(mi):
			mi.visible = on
	if on:
		reset()


## Drops the motion: the coat hangs still where the limits let it.
func reset() -> void:
	_seeded = false
	for k in _d.size():
		_d[k] = Vector2.ZERO
		_w[k] = Vector2.ZERO
	if skeleton != null and not upper_bones.is_empty():
		_write_pose()


func _physics_process(delta: float) -> void:
	if not is_on or skeleton == null or pilot == null or not (pilot as Node3D).visible:
		return
	if _asleep():
		return
	var t0 := Time.get_ticks_usec()
	tick(delta)
	last_tick_usec = Time.get_ticks_usec() - t0


## A pilot nobody is playing, standing still with the coat settled, costs nothing.
func _asleep() -> bool:
	if not _seeded or not pilot.get(&"frozen") or velocity_override != null:
		return false
	if (pilot as CharacterBody3D).velocity.length_squared() > 0.0025:
		return false
	for k in _w.size():
		if _w[k].length_squared() > 0.0004:
			return false
	return true


# -- building ---------------------------------------------------------------------------------

func _find_arm_meshes() -> void:
	arm_meshes.clear()
	for child in skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or mi.skin == null or mi.name == MESH_NAME:
			continue
		if not _arm_cache.has(mi.mesh):
			_arm_cache[mi.mesh] = arm_share(mi.mesh as ArrayMesh, mi.skin) >= ARM_SHARE
		if _arm_cache[mi.mesh]:
			arm_meshes.append(mi)


## The share of `mesh`'s vertices whose heaviest bone is a shoulder, upper arm or lower arm.
static func arm_share(mesh: ArrayMesh, skin: Skin) -> float:
	return _CoatBody.bone_share(mesh, skin, ARM_BONES)


## Finds the trunk pieces the coat covers and builds what is worn in their place: a sibling
## MeshInstance3D per piece, wearing the piece's cut copy and its materials. Siblings and not a
## mesh swap, because the hat and AIRFRAME both swap `mesh` on his own pieces already; a new
## body piece is picked up by every look, the ghosts and the rim light like any other.
func _cut_body() -> void:
	covered_meshes.clear()
	cut_meshes.clear()
	for child in skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or mi.skin == null or mi.name == MESH_NAME \
				or arm_meshes.has(mi) or String(mi.name).ends_with(CUT_SUFFIX):
			continue
		if not _cut_cache.has(mi.mesh):
			_cut_cache[mi.mesh] = _CoatBody.cut(mi.mesh as ArrayMesh, mi.skin, skeleton)
		var result: Array = _cut_cache[mi.mesh]
		if result.is_empty():
			continue
		covered_meshes.append(mi)
		if int(result[1]) == 0:
			continue
		var copy := MeshInstance3D.new()
		copy.name = String(mi.name) + CUT_SUFFIX
		copy.mesh = result[0]
		copy.skin = mi.skin
		copy.transform = mi.transform
		copy.layers = mi.layers
		copy.cast_shadow = mi.cast_shadow
		copy.material_override = mi.material_override
		copy.material_overlay = mi.material_overlay
		for s in mini(mi.mesh.get_surface_count(), copy.mesh.get_surface_count()):
			copy.set_surface_override_material(s, mi.get_surface_override_material(s))
		copy.visible = false
		cut_meshes.append(copy)
	# Added after the walk: the skeleton's children are not changed under it.
	for copy in cut_meshes:
		skeleton.add_child(copy)
		copy.skeleton = NodePath("..")


## The chain bones. Their global rest bases are identity (Hips' is), so a pose is a rotation in
## his hips frame about the bone's head.
func _add_bones() -> void:
	var points := _CoatMesh.chain_points()
	var hips_rest := skeleton.get_bone_global_rest(_hips)
	for c in CHAINS:
		var side := 1.0 if c < SIDE_CHAINS else -1.0
		var rows: Array = points[c % SIDE_CHAINS]
		var pivot := Vector3(rows[0].x * side, rows[0].y, rows[0].z)
		var knee := Vector3(rows[1].x * side, rows[1].y, rows[1].z)
		var up := _add_bone(_CoatMesh.upper_bone_name(c), _hips, hips_rest.affine_inverse() * pivot)
		var lo := _add_bone(_CoatMesh.lower_bone_name(c), up, knee - pivot)
		upper_bones.append(up)
		lower_bones.append(lo)
		_pivot.append(hips_rest.affine_inverse() * pivot)
		_out.append(Vector2(pivot.x, pivot.z).normalized())
		_leg.append(0 if c < SIDE_CHAINS else 1)
		_rest_vec.append(knee - pivot)
	for c in CHAINS:
		var side := 1.0 if c < SIDE_CHAINS else -1.0
		var rows: Array = points[c % SIDE_CHAINS]
		_rest_vec.append(Vector3((rows[2].x - rows[1].x) * side, rows[2].y - rows[1].y, rows[2].z - rows[1].z))
	_d.resize(CHAINS * 2)
	_w.resize(CHAINS * 2)
	for k in CHAINS * 2:
		var c := k % CHAINS
		# The sway runs round the coat; the lower segments ride it a little behind.
		_phase.append(atan2(_out[c].x, _out[c].y) + (0.7 if k >= CHAINS else 0.0))
	# The belly bones go on before the mesh is built, so its weights can name them.
	_belly_line = _CoatMesh.belly_line(skeleton)
	belly_bones.clear()
	for side in 2:
		for k in _CoatMesh.BELLY_BONES.size():
			var edge: Vector3 = _belly_line[0][k]
			var at := Vector3(edge.x * (1.0 if side == 0 else -1.0), edge.y, edge.z)
			var n: String = (_CoatMesh.BELLY_BONES if side == 0 else _CoatMesh.BELLY_BONES_R)[k]
			belly_bones.append(_add_bone(n, _hips, hips_rest.affine_inverse() * at))
	for n: String in ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]:
		_legs.append(skeleton.find_bone(n))
	for leg in 2:
		for part in 2:
			var a := skeleton.get_bone_global_rest(_legs[leg * 3 + part]).origin
			var b := skeleton.get_bone_global_rest(_legs[leg * 3 + part + 1]).origin
			_leg_rest.append(tilt_of((b - a).normalized()))


func _add_bone(bone_name: String, parent: int, at: Vector3) -> int:
	var existing := skeleton.find_bone(bone_name)
	if existing >= 0:
		return existing
	var b := skeleton.get_bone_count()
	skeleton.add_bone(bone_name)
	skeleton.set_bone_parent(b, parent)
	skeleton.set_bone_rest(b, Transform3D(Basis.IDENTITY, at))
	skeleton.reset_bone_pose(b)
	return b


func _build_mesh() -> void:
	# What AIRFRAME and Jetpack read the colour from; the cel overrides are what RETRO twins.
	_leather_base = StandardMaterial3D.new()
	_leather_base.resource_name = "coat_leather"
	_lining_base = StandardMaterial3D.new()
	_lining_base.resource_name = "coat_lining"
	_leather = _CEL.duplicate() as ShaderMaterial
	_lining = _CEL.duplicate() as ShaderMaterial
	# No ink on the inside: the leather's line already runs round every open edge.
	_lining.next_pass = null
	_recolour()
	var skin := Skin.new()
	for b in skeleton.get_bone_count():
		skin.add_named_bind(skeleton.get_bone_name(b), skeleton.get_bone_global_rest(b).affine_inverse())
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = MESH_NAME
	mesh_instance.mesh = _CoatMesh.build(skeleton, _leather_base, _lining_base)
	mesh_instance.skin = skin
	mesh_instance.set_surface_override_material(_CoatMesh.LEATHER, _leather)
	mesh_instance.set_surface_override_material(_CoatMesh.LINING, _lining)
	# The rest-pose bounds don't hold a streaming skirt or a raised arm.
	mesh_instance.extra_cull_margin = 1.5
	skeleton.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")


func _recolour() -> void:
	if _leather == null:
		return
	_leather_base.albedo_color = leather_color
	_lining_base.albedo_color = lining_color
	_leather.set_shader_parameter(&"color", leather_color)
	_lining.set_shader_parameter(&"color", lining_color)


# -- the springs ------------------------------------------------------------------------------

## One step. Runs in _physics_process; tests and probes may call it themselves.
func tick(delta: float) -> void:
	if delta <= 0.0 or upper_bones.is_empty():
		return
	_clock += delta
	var hips_pose := skeleton.get_bone_global_pose(_hips)
	var frame := hips_pose.basis.orthonormalized()
	var to_model := Transform3D(frame, hips_pose.origin)
	var world := skeleton.global_transform
	var world_basis := world.basis.orthonormalized() * frame
	var from_world := world_basis.transposed()
	var p := world * hips_pose.origin
	var fwd := world_basis.z
	var yaw := atan2(fwd.x, fwd.z)
	if not _seeded or p.distance_to(_p) > TELEPORT:
		_seeded = true
		_p = p
		_v = Vector3.ZERO
		_a = Vector3.ZERO
		_yaw = yaw
		_yaw_rate = 0.0
	var v_prev := _v
	_v = _v.lerp((p - _p) / delta, 1.0 - exp(-delta / 0.04))
	_a = _a.lerp((_v - v_prev) / delta, 1.0 - exp(-delta / 0.06))
	_p = p
	if velocity_override != null:
		_v = velocity_override
		_a = Vector3.ZERO
	_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _yaw, -PI, PI) / delta, 1.0 - exp(-delta / 0.08))
	_yaw = yaw

	# The air he moves through, in his hips frame.
	var v := from_world * (_v - _wind())
	var a := from_world * _a
	var flat := Vector2(v.x, v.z)
	var speed := flat.length()
	var push := Vector2.ZERO
	if speed > 0.01:
		push = -flat / speed * minf(atan(drag * speed * speed), deg_to_rad(drag_cap_deg))
	push -= Vector2(a.x, a.z) * deg_to_rad(kick_deg)
	var flare := clampf(-v.y * deg_to_rad(flare_deg), -deg_to_rad(6.0), deg_to_rad(flare_cap_deg))
	var swirl := clampf(-_yaw_rate * deg_to_rad(swirl_deg), -deg_to_rad(swirl_cap_deg), deg_to_rad(swirl_cap_deg))
	var hang := tilt_of(from_world * Vector3.DOWN) * gravity
	var pool := deg_to_rad(crouch_pool_deg) if pilot.get(&"is_crouching") else 0.0

	# His legs, as tilts off their rest: [left thigh, left shin, right thigh, right shin].
	var leg_tilt := PackedVector2Array()
	for leg in 2:
		for part in 2:
			var from := skeleton.get_bone_global_pose(_legs[leg * 3 + part]).origin
			var to := skeleton.get_bone_global_pose(_legs[leg * 3 + part + 1]).origin
			leg_tilt.append(tilt_of(frame.transposed() * (to - from).normalized()) - _leg_rest[leg * 2 + part])

	# Not in a crouch or a slide: his thighs are near level there, and no hinged panel can clear
	# them without lying flat on the floor (the crouch pool shapes the coat there instead).
	var legs := []
	if leg_clearance and not pilot.get(&"is_crouching") and not pilot.get(&"is_sliding"):
		legs = _leg_points(frame, hips_pose.origin)
	var planes := _planes(world.affine_inverse())
	var cap := deg_to_rad(cap_deg)
	var idle := deg_to_rad(idle_deg)
	var ph := TAU * _clock / maxf(idle_period, 0.1)
	var steps := maxi(1, ceili(delta * 120.0))
	var h := delta / float(steps)
	var shin_cap := deg_to_rad(shin_push_cap_deg)
	for c in CHAINS:
		var out := _out[c]
		var side := Vector2(out.y, -out.x)
		var joint := Vector3.ZERO
		for kind in 2:
			var k := kind * CHAINS + c
			var rest := hang + (push + out * flare + side * swirl) * float(GAIN[kind])
			rest += (out * sin(ph + _phase[k]) + side * 0.4 * sin(ph * 1.6 + _phase[k] * 1.7)) \
				* idle * float(IDLE[kind])
			if kind == 1:
				rest += out * pool
			var om := TAU * freq * float(FREQ[kind])
			var d := _d[k]
			var w := _w[k]
			for s in steps:
				w += ((rest - d) * om * om - w * 2.0 * damping * om) * h
				d += w * h
			# His body: a panel comes in toward him only a little, and a leg swinging out takes
			# the panel with it.
			var limit: float
			if kind == 0:
				limit = maxf(leg_tilt[_leg[c] * 2].dot(out), 0.0) * float(THIGH_PUSH[c % SIDE_CHAINS]) 					- deg_to_rad(inward_deg)
			else:
				limit = minf(maxf(leg_tilt[_leg[c] * 2 + 1].dot(out), 0.0) * shin_push, shin_cap) \
					- deg_to_rad(inward_lower_deg)
			var r := d.dot(out)
			if r < limit:
				d += out * (limit - r)
				w -= out * minf(w.dot(out), 0.0)
			# His legs as they really are: the panel swings out until it clears every leg point
			# under it in its wedge. The limit above only anticipates; this is the hard floor.
			var from_point: Vector3 = to_model * _pivot[c] if kind == 0 else joint
			var o3 := frame * Vector3(out.x, 0.0, out.y)
			var lift := _leg_clearance(c, from_point, frame * (tilt_quat(d) * _rest_vec[k]), o3,
				frame * Vector3.DOWN, legs)
			if lift > 0.0:
				d += out * lift
				w -= out * minf(w.dot(out), 0.0)
			if d.length() > cap:
				var n := d.normalized()
				d = n * cap
				w -= n * maxf(w.dot(n), 0.0)
			# The floor and the walls, on this segment's far end.
			var from: Vector3 = to_model * _pivot[c] if kind == 0 else joint
			var q := tilt_quat(d)
			var vec: Vector3 = frame * (q * _rest_vec[k])
			if not planes.is_empty():
				var fixed := _clear(from, vec, planes, frame * Vector3(out.x, 0.0, out.y))
				if not fixed.is_equal_approx(vec):
					var turn := Quaternion((frame.transposed() * vec).normalized(), (frame.transposed() * fixed).normalized())
					d = tilt_of(turn * q * Vector3.DOWN)
					w *= 0.4
					vec = fixed
			joint = from + vec
			_d[k] = d
			_w[k] = w
	_blend_neighbours()
	_write_pose()


## A neighbouring panel may not hang more than NEIGHBOUR_STEP_DEG less swung out than the one beside
## it (the pair share an edge): a back panel the leg clearance throws out 50 deg while its neighbours
## hang at 15 tore into a flap in a sideways run. The lesser one is lifted outward, never the
## greater one pulled in, so no leg is un-cleared.
func _blend_neighbours() -> void:
	var step := deg_to_rad(NEIGHBOUR_STEP_DEG)
	# The same for a panel's own hinge: a lower half thrown out round a swinging shin pulls its
	# upper half along instead of folding sharply at the knee row.
	for c in CHAINS:
		_lift_to(c, CHAINS + c, deg_to_rad(HINGE_STEP_DEG))
	for kind in 2:
		var base := kind * CHAINS
		# Two sweeps so a spike spreads along the side, then the vent halves meet.
		for sweep in 2:
			for side in 2:
				var first := side * SIDE_CHAINS
				for i in SIDE_CHAINS - 1:
					_lift_to(base + first + i, base + first + i + 1, step)
				for i in range(SIDE_CHAINS - 1, 0, -1):
					_lift_to(base + first + i, base + first + i - 1, step)
			_lift_to(base + SIDE_CHAINS - 1, base + CHAINS - 1, step)
			_lift_to(base + CHAINS - 1, base + SIDE_CHAINS - 1, step)


## Pulls segment `low` toward segment `high` until their tilts are within `step` of each other (as
## vectors, so a panel thrown sideways while its neighbour trails back is caught too). Only a
## segment that hangs less swung out than `high` is moved.
func _lift_to(low: int, high: int, step: float) -> void:
	var diff := _d[high] - _d[low]
	var gap := diff.length()
	if gap <= step or _d[high].length() <= _d[low].length():
		return
	_d[low] += diff / gap * (gap - step)


## His leg sample points this tick, model space: per point [position, [side radius, front/back
## radius], wedge side (1 his left, -1 his right, 0 on the centre line), degrees off his front].
func _leg_points(frame: Basis, hips_origin: Vector3) -> Array:
	var out := []
	var to_hips := frame.transposed()
	for leg in 2:
		var joints := []
		for part in 3:
			joints.append(skeleton.get_bone_global_pose(_legs[leg * 3 + part]).origin)
		for sample: Array in LEG_SAMPLES:
			var q: Vector3 = (joints[sample[0]] as Vector3).lerp(joints[sample[1]], float(sample[2]))
			var h := to_hips * (q - hips_origin)
			var side := 0.0 if absf(h.x) < 0.03 else signf(h.x)
			out.append([q, Vector2(sample[3], sample[4]), side, rad_to_deg(atan2(absf(h.x), h.z))])
	return out


## How far (radians, along `o3`) a segment from `from` along `vec` must swing out to clear the leg
## points in chain `chain`'s wedge, or 0. `o3` / `down` are his outward and down, model space.
func _leg_clearance(chain: int, from: Vector3, vec: Vector3, o3: Vector3, down: Vector3, legs: Array) -> float:
	var side := 1.0 if chain < SIDE_CHAINS else -1.0
	var wedge: Array = CHAIN_WEDGE[chain % SIDE_CHAINS]
	var span := vec.dot(down)
	if span < 0.05:
		return 0.0
	var now := atan2(vec.dot(o3), span)
	var need := -INF
	for point: Array in legs:
		if float(point[2]) == -side:
			continue
		var ang: float = point[3]
		if ang < float(wedge[0]) or ang > float(wedge[1]):
			continue
		var rel: Vector3 = (point[0] as Vector3) - from
		var depth := rel.dot(down)
		# Only what is beside this segment: not above its top, not past its far end.
		if depth < 0.03 or depth > span + 0.04:
			continue
		# The leg's radius in this panel's outward direction (an ellipse: thin to the side, deep
		# to the front and back).
		var axes: Vector2 = point[1]
		var a := deg_to_rad(float(point[3]))
		var radius := Vector2(axes.x * sin(a), axes.y * cos(a)).length()
		need = maxf(need, atan2(rel.dot(o3) + radius + leg_margin, depth))
	if need == -INF:
		return 0.0
	return clampf(need - now, 0.0, deg_to_rad(leg_clear_cap_deg))


func _write_pose() -> void:
	for c in CHAINS:
		var up := tilt_quat(_d[c])
		skeleton.set_bone_pose_rotation(upper_bones[c], up)
		skeleton.set_bone_pose_rotation(lower_bones[c], up.inverse() * tilt_quat(_d[CHAINS + c]))
	_write_belly()


## Moves each belly bone so its row's front edge (waist, mid) sits on the straight line from the posed
## chest row's front edge down to the hip row's (on his pelvis). Never into him: the push along
## his hips' forward axis is kept >= 0, so a backward chest lean leaves the waist on his pelvis.
func _write_belly() -> void:
	if belly_bones.is_empty() or _belly_line.is_empty():
		return
	var hips_pose := skeleton.get_bone_global_pose(_hips)
	var hips_rest := skeleton.get_bone_global_rest(_hips)
	var hips_move := hips_pose * hips_rest.affine_inverse()
	var rows: Array = _belly_line[0]
	var h_rest: Vector3 = _belly_line[1]
	var c_rest: Vector3 = _belly_line[2]
	var cb: Array = _belly_line[3]
	var cw: Array = _belly_line[4]
	var inv := hips_pose.basis.orthonormalized().inverse()
	for side in 2:
		var m := Vector3(-1.0 if side == 1 else 1.0, 1.0, 1.0)
		var h := hips_move * (h_rest * m)
		var c := Vector3.ZERO
		var total := 0.0
		for k in cb.size():
			var b: int = cb[k]
			if side == 1:
				b = _mirror_bone(b)
			c += float(cw[k]) * (skeleton.get_bone_global_pose(b) * skeleton.get_bone_global_rest(b).affine_inverse() * (c_rest * m))
			total += float(cw[k])
		c /= total
		for k in rows.size():
			var w_rest: Vector3 = rows[k]
			var t := (w_rest.y - h_rest.y) / (c_rest.y - h_rest.y)
			var local := inv * (h.lerp(c, t) - hips_move * (w_rest * m))
			local.z = maxf(local.z, 0.0)
			var b := belly_bones[side * rows.size() + k]
			skeleton.set_bone_pose_position(b, skeleton.get_bone_rest(b).origin + local)


func _mirror_bone(b: int) -> int:
	var n := skeleton.get_bone_name(b)
	if n.begins_with("Left"):
		return skeleton.find_bone("Right" + n.substr(4))
	if n.begins_with("Right"):
		return skeleton.find_bone("Left" + n.substr(5))
	return b


## `vec` from `from` (model space), turned the least it takes to keep its far end `plane_margin`
## clear of every plane. `fallback` is the way to go if it points straight into one.
func _clear(from: Vector3, vec: Vector3, planes: Array, fallback: Vector3) -> Vector3:
	var length := vec.length()
	if length < 1e-5:
		return vec
	var u := vec / length
	for plane: Array in planes:
		var point: Vector3 = plane[0]
		var n: Vector3 = plane[1]
		var height := n.dot(from - point)
		if height + length * n.dot(u) >= plane_margin:
			continue
		var c := clampf((plane_margin - height) / length, -1.0, 1.0)
		var t := u - n * u.dot(n)
		if t.length_squared() < 1e-8:
			t = fallback - n * fallback.dot(n)
		if t.length_squared() < 1e-8:
			continue
		u = n * c + t.normalized() * sqrt(1.0 - c * c)
	return u * length


## What the coat must stay clear of, in model space: the floor under him, the wall he is running
## along, climbing, or pulling himself up. All from what the controller already knows.
func _planes(to_model: Transform3D) -> Array:
	var out := []
	var body := pilot as CharacterBody3D
	if body != null and body.is_on_floor():
		out.append([to_model * body.global_position, (to_model.basis * body.get_floor_normal()).normalized()])
	if pilot.get(&"is_wall_running"):
		out.append([to_model * pilot._wall_point, (to_model.basis * pilot._wall_normal).normalized()])
	if pilot.get(&"is_wall_climbing"):
		out.append([to_model * pilot._wall_climb_point, (to_model.basis * pilot._wall_climb_normal).normalized()])
	if pilot.get(&"is_climbing"):
		# The face under the lip he is pulling himself over, while his feet are still below it.
		var facing: Vector3 = pilot._climb_facing
		var top: Vector3 = pilot._climb_end_position
		if facing.length_squared() > 0.5 and body.global_position.y < top.y - 0.3:
			out.append([to_model * (top - facing * pilot.climb_inset), (to_model.basis * -facing).normalized()])
	for plane: Array in extra_planes:
		out.append([to_model * (plane[0] as Vector3), (to_model.basis * (plane[1] as Vector3)).normalized()])
	return out


## The Ichi storm's wind on the coat while he tredges, world space.
func _wind() -> Vector3:
	if not pilot.get(&"is_tredging"):
		return Vector3.ZERO
	var tredge: Node = pilot.get(&"tredge")
	if tredge == null:
		return Vector3.ZERO
	var storm: Node = tredge.storm()
	if storm == null:
		return Vector3.ZERO
	var dir: Vector2 = storm.wind_direction
	if dir.length_squared() < 1e-6:
		return Vector3.ZERO
	dir = dir.normalized()
	return Vector3(dir.x, 0.0, dir.y) * wind_speed * (1.0 + wind_gust * float(tredge.gust))


# -- pure, so tests can pin them --------------------------------------------------------------

## The tilt that swings a hanging segment onto unit direction `u`: its length is the angle off
## straight down, its direction where the tip goes (x his left, y his front).
static func tilt_of(u: Vector3) -> Vector2:
	var s := sqrt(u.x * u.x + u.z * u.z)
	if s < 1e-6:
		return Vector2.ZERO
	return Vector2(u.x, u.z) / s * acos(clampf(-u.y, -1.0, 1.0))


## The rotation for a tilt: about a level axis, no twist.
static func tilt_quat(d: Vector2) -> Quaternion:
	var l := d.length()
	if l < 1e-7:
		return Quaternion.IDENTITY
	return Quaternion(Vector3(-d.y, 0.0, d.x) / l, l)


## Where a segment of `chain` ends up, world space: [waist pivot, knee joint, hem tip].
func chain_world(chain: int) -> Array:
	var hips_pose := skeleton.get_bone_global_pose(_hips)
	var frame := hips_pose.basis.orthonormalized()
	var pivot: Vector3 = Transform3D(frame, hips_pose.origin) * _pivot[chain]
	var joint := pivot + frame * (tilt_quat(_d[chain]) * _rest_vec[chain])
	var tip := joint + frame * (tilt_quat(_d[CHAINS + chain]) * _rest_vec[CHAINS + chain])
	var world := skeleton.global_transform
	return [world * pivot, world * joint, world * tip]


## A segment's tilt, degrees (segment = chain for the upper, CHAINS + chain for the lower).
func tilt_deg(segment: int) -> Vector2:
	return _d[segment] * (180.0 / PI)
