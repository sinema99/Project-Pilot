class_name Pilot9Poncho
extends MeshInstance3D

## pilot9's wool poncho: a thick shell over his shoulders and torso, in the scarf's red. See
## docs/specs/pilot9-poncho.md.
##
## A coarse lattice (COLS around, ROWS down: collar, yoke, ridge, then the drape) does the moving.
## The collar row is pinned to UpperChest; every other point is sprung back toward its spot on a tailored rest shell in
## UpperChest's frame. That pull is the stiffness, and it is why the poncho is never a plate and never
## loose cloth. What moves it is the felt acceleration of each point's target (lag, settle, one heavy
## bounce on a landing) and a capped wind from his speed. A smooth, thick mesh is drawn through
## the lattice every frame, so the lattice's corners never show.
##
## It lives under his Skeleton3D at identity, so its vertices are skeleton-space and it is drawn
## wherever the skeleton is drawn, interpolation included. No skin: it is rebuilt from the posed
## skeleton on every skeleton_updated, after every modifier has run.
##
## pilot9.gd builds it (_setup_poncho) and owns the tunables (the "Poncho" export group). They are
## read off `pilot` every frame so they tune live. Without a pilot (the tests) the defaults below stand.

const COLS := 24
const ROWS := 6
## The shoulder ridge: the last row the wind leaves alone. Rows below it are the drape.
const RIDGE_ROW := 2
const N := COLS * ROWS
## Render resolution: subdivisions per lattice span around and down.
const SUB_U := 4
const SUB_V := 4
const RU := COLS * SUB_U
const RV := (ROWS - 1) * SUB_V + 1
## Segments in each rolled edge (hem and collar): a half circle from the outer shell to the inner one.
const ROLL := 4
## Substep size cap, seconds.
const MAX_STEP := 1.0 / 120.0
## A target that moves further than this in one frame is a teleport: start again from rest.
const TELEPORT := 2.0
## Share of the wind that acts up or down. A long fall already floats the hem through inertia;
## the full wind on top lifted it 16 cm.
const VERTICAL_WIND := 0.5
## Low-pass on his body velocity for the wind, seconds.
const WIND_SMOOTH := 0.15
## Rest-pull multiplier per row (row 0, the collar, is pinned outright). The yoke and the ridge
## over the shoulders are held hard; the drape gets slightly softer toward the hem.
const ROW_STIFFNESS := [0.0, 5.0, 4.0, 1.8, 1.25, 1.0]
## How far a segment may stretch past its rest length.
const MAX_STRETCH := 1.06
## Gap kept between the cloth's inner face and a collider, on top of half the thickness.
const CLEARANCE := 0.005
const FALLBACK_COLOR := Color(0.27848125, 0.085499234, 0.11593493, 1)

## -- the shape, bind space (metres; +Z front, +X his left, y up from the floor) ----------------
## Torso measured with tests/_probe_poncho_fit.gd, the shoulder caps with his arms DOWN by
## tests/_probe_poncho_shoulder.gd (the bind pose is a T-pose, whose arms would hold the shoulder
## out as a flat shelf). It hugs him, about 1-1.5 cm off. See the spec's "Shape".

## The collar: a ring just outside the scarf, which sits in the neck hole.
const COLLAR_Y := 1.59
const COLLAR_CENTER_Z := 0.02
const COLLAR_HALF_X := 0.155
const COLLAR_FRONT := 0.16
const COLLAR_BACK := 0.15
## The yoke: halfway out, over the top of the shoulder (y 1.59 at x 0.24, arms down). Front and
## back it is already sloping down the chest.
const YOKE_Y := 1.567
const YOKE_SIDE_Y := 1.607
const YOKE_HALF_X := 0.245
const YOKE_FRONT := 0.182
const YOKE_BACK := 0.16
## The ridge: rolled round the outside of the shoulder cap (which falls from y 1.54 at x 0.28 to
## 1.48 at x 0.30), where the drape starts.
const RIDGE_Y := 1.54
const RIDGE_HALF_X := 0.297
const RIDGE_FRONT := 0.185
const RIDGE_BACK := 0.198
## The hem: below the vest front and back, rising over the shoulder joint at the sides, which is
## what leaves the sides open for his arms.
const HEM_Y := 1.07
const HEM_SIDE_Y := 1.44
const HEM_HALF_X := 0.235
const HEM_SIDE_HALF_X := 0.322
const HEM_FRONT := 0.215
const HEM_BACK := 0.245
## |sin theta| range over which the hem rises from HEM_Y to HEM_SIDE_Y.
const SIDE_FROM := 0.55
const SIDE_TO := 0.95
## Superellipse exponent: 2 is an ellipse, higher squares it off toward his box-shaped torso.
const SQUARENESS := 3.5
## Outward belly on the middle rows, so the drape is a curve and not a straight cone.
const BULGE := 0.008

## The colliders, bind space: [bone, centre, half extents, rounding, fits the rest]. A rounded box;
## zero half extents is a sphere, zero x/z is a capsule. Everything below the collar collides.
## The upper-arm capsules lie along his T-posed arms in bind space, so the rest shell is NOT fitted
## out of them (that would bring the shelf back); they only act live, lifting the shoulder edge
## over a raised arm instead of letting the deltoid poke through.
const COLLIDERS := [
	[&"UpperChest", Vector3(0.0, 1.30, 0.0), Vector3(0.20, 0.17, 0.18), 0.03, true],
	[&"Chest", Vector3(0.0, 1.07, -0.15), Vector3(0.13, 0.15, 0.06), 0.025, true],
	[&"Hips", Vector3(0.0, 1.0, 0.0), Vector3(0.19, 0.06, 0.10), 0.03, true],
	[&"LeftUpperLeg", Vector3(0.10, 0.78, 0.02), Vector3(0.0, 0.20, 0.0), 0.10, true],
	[&"RightUpperLeg", Vector3(-0.10, 0.78, 0.02), Vector3(0.0, 0.20, 0.0), 0.10, true],
	[&"LeftUpperArm", Vector3(0.243, 1.48, 0.0), Vector3.ZERO, 0.063, true],
	[&"RightUpperArm", Vector3(-0.243, 1.48, 0.0), Vector3.ZERO, 0.063, true],
	[&"LeftUpperArm", Vector3(0.41, 1.50, -0.005), Vector3(0.14, 0.0, 0.0), 0.08, false],
	[&"RightUpperArm", Vector3(-0.41, 1.50, -0.005), Vector3(0.14, 0.0, 0.0), 0.08, false],
]
const FRAME_BONE := &"UpperChest"

## -- tunables (pilot9's "Poncho" group overwrites these every frame) --------------------------
var stiffness := 2.2
var damping := 0.55
var bend := 0.3
var max_accel := 20.0
var max_jolt := 1.0
var wind_full_speed := 20.0
var wind_max_lift := 18.0
var thickness := 0.008

## The pilot whose "Poncho" exports this reads. Untyped - the pilot has no class_name.
var pilot: Node = null
var body_skeleton: Skeleton3D = null

## Rest lattice, bind space, fitted out of the colliders.
var rest := PackedVector3Array()
## Per point: rest length of the segment up to the row above, and the wind lever (distance to the
## ridge point of its column; zero on and above the ridge).
var _rest_len := PackedFloat32Array()
var _lever := PackedFloat32Array()
## Per point, world space: offset from target, its velocity, the target velocity felt so far, the
## felt acceleration this frame, and last frame's target.
var _d := PackedVector3Array()
var _dv := PackedVector3Array()
var _v_felt := PackedVector3Array()
var _acc := PackedVector3Array()
var _t_prev := PackedVector3Array()
var _origin_prev := Vector3.ZERO
var _body_velocity := Vector3.ZERO
var _fresh := true
## World positions of the lattice after the last step.
var world := PackedVector3Array()

## Collider bones, binds and this frame's world transforms (bind space -> world).
var _collider_bones := PackedInt32Array()
var _binds: Dictionary = {}
var collider_xforms: Array[Transform3D] = []
var _frame_bone := -1
var _last_frame := -1

var _surface_material: Material = null
var _buffers: Array[ArrayMesh] = []
var _front := 0
var _indices := PackedInt32Array()
var _uvs := PackedVector2Array()

func _init() -> void:
	name = "Poncho"
	_build_rest()
	_build_topology()
	_buffers = [ArrayMesh.new(), ArrayMesh.new()]
	# Rebuilt every frame and drawn wherever the skeleton is: never let a stale box cull it.
	custom_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, 3.0, 3.0))
	_surface_material = StandardMaterial3D.new()
	_surface_material.resource_name = "scarf"
	(_surface_material as StandardMaterial3D).albedo_color = FALLBACK_COLOR

## Ties it to his skeleton and draws it at rest, now: ApplyCelPilot9 walks his meshes right after
## pilot9's _ready() and has to find a surface wearing the scarf slot.
func setup(skel: Skeleton3D) -> void:
	body_skeleton = skel
	_find_scarf_material()
	_frame_bone = skel.find_bone(FRAME_BONE)
	_collider_bones.clear()
	for c: Array in COLLIDERS:
		_collider_bones.append(skel.find_bone(c[0]))
	_collect_binds()
	_fresh = true
	_update_from_skeleton(0.0)
	skel.skeleton_updated.connect(_on_skeleton_updated)

## The scarf slot's own material from his body, so the cel applier derives the very same
## material for both (it keys on slot name + colour).
func _find_scarf_material() -> void:
	for child in body_skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi == self or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m != null and m.resource_name.strip_edges() == "scarf":
				_surface_material = m
				return

## Bind poses (mesh space -> bone space) by bone, from whichever skin carries them.
func _collect_binds() -> void:
	_binds.clear()
	for child in body_skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.skin == null:
			continue
		for b in mi.skin.get_bind_count():
			var bone := mi.skin.get_bind_bone(b)
			if bone < 0:
				bone = body_skeleton.find_bone(mi.skin.get_bind_name(b))
			if bone >= 0 and not _binds.has(bone):
				_binds[bone] = mi.skin.get_bind_pose(b)

func _bind(bone: int) -> Transform3D:
	if _binds.has(bone):
		return _binds[bone]
	# No skin binds it: fall back to the inverse of the bone's rest, which is what a bind is.
	return body_skeleton.get_bone_global_rest(bone).affine_inverse() if bone >= 0 else Transform3D.IDENTITY

## Bind space -> world for `bone`, this frame (interpolated, the way he is drawn).
func _bone_xform(bone: int) -> Transform3D:
	if bone < 0:
		return body_skeleton.get_global_transform_interpolated()
	return body_skeleton.get_global_transform_interpolated() * body_skeleton.get_bone_global_pose(bone) \
		* _bind(bone)

## -- per frame ------------------------------------------------------------------------------

func _on_skeleton_updated() -> void:
	# Once per drawn frame, however many times the skeleton reports.
	var frame := Engine.get_process_frames()
	if frame == _last_frame:
		return
	_last_frame = frame
	_update_from_skeleton(get_process_delta_time())

func _update_from_skeleton(dt: float) -> void:
	if body_skeleton == null:
		return
	var on := _enabled()
	visible = on
	if not on:
		_fresh = true
		return
	_pull_tunables()
	var frame := _bone_xform(_frame_bone)
	var targets := PackedVector3Array()
	targets.resize(N)
	for i in N:
		targets[i] = frame * rest[i]
	collider_xforms.clear()
	for k in _collider_bones.size():
		collider_xforms.append(_bone_xform(_collider_bones[k]))
	step(minf(dt, 0.05), targets, frame.origin)
	_rebuild_mesh(body_skeleton.get_global_transform_interpolated().affine_inverse())

func _enabled() -> bool:
	var settings: Node = Engine.get_main_loop().root.get_node_or_null(^"/root/Settings") \
		if Engine.get_main_loop() is SceneTree else null
	return settings == null or settings.poncho

func _pull_tunables() -> void:
	if pilot == null:
		return
	stiffness = pilot.poncho_stiffness
	damping = pilot.poncho_damping
	bend = pilot.poncho_bend
	max_accel = pilot.poncho_max_accel
	max_jolt = pilot.poncho_max_jolt
	wind_full_speed = pilot.poncho_wind_full_speed
	wind_max_lift = pilot.poncho_wind_max_lift
	thickness = pilot.poncho_thickness

## One frame of the lattice. `targets` are the rest points placed on him now (world), `origin` his
## frame's origin (for the wind). Collides against `collider_xforms` (empty = no colliders).
@warning_ignore("integer_division")
func step(dt: float, targets: PackedVector3Array, origin: Vector3) -> void:
	if _fresh or dt <= 0.0 or _teleported(targets):
		_reset(targets, origin)
		return
	# What each point FEELS of its target's motion: the jolt beyond max_jolt is never felt, and
	# the rest arrives no faster than max_accel. Keeps a 10 m/s landing a bounce, not a whip.
	for i in N:
		var v_t := (targets[i] - _t_prev[i]) / dt
		var diff := v_t - _v_felt[i]
		var over := diff.length()
		if over > max_jolt:
			_v_felt[i] += diff * (1.0 - max_jolt / over)
			diff = v_t - _v_felt[i]
		var cap := max_accel * dt
		if diff.length() > cap:
			diff = diff.normalized() * cap
		_acc[i] = diff / dt
		_v_felt[i] += diff
	var v_body := (origin - _origin_prev) / dt
	_body_velocity = _body_velocity.lerp(v_body, 1.0 - exp(-dt / WIND_SMOOTH))
	var wind := wind_offset_dir(_body_velocity, wind_full_speed, wind_max_lift)
	var k0 := pow(TAU * stiffness, 2.0)
	var n := maxi(ceili(dt / MAX_STEP), 1)
	var h := dt / float(n)
	for _s in n:
		for i in range(COLS, N):
			var k: float = k0 * ROW_STIFFNESS[i / COLS]
			var c := 2.0 * damping * sqrt(k)
			var w := wind * _lever[i]
			var a := -k * (_d[i] - w) - c * _dv[i] - _acc[i]
			_dv[i] += a * h
			_d[i] += _dv[i] * h
		_smooth()
	for i in N:
		world[i] = targets[i] + _d[i]
	_hold_lengths()
	_collide()
	for i in N:
		_d[i] = world[i] - targets[i]
		_t_prev[i] = targets[i]
	_origin_prev = origin

func _teleported(targets: PackedVector3Array) -> bool:
	if _t_prev.size() != N:
		return true
	for i in N:
		if targets[i].distance_squared_to(_t_prev[i]) > TELEPORT * TELEPORT:
			return true
	return false

func _reset(targets: PackedVector3Array, origin: Vector3) -> void:
	_d.resize(N)
	_dv.resize(N)
	_v_felt.resize(N)
	_acc.resize(N)
	_d.fill(Vector3.ZERO)
	_dv.fill(Vector3.ZERO)
	_v_felt.fill(Vector3.ZERO)
	_acc.fill(Vector3.ZERO)
	_t_prev = targets.duplicate()
	world = targets.duplicate()
	_origin_prev = origin
	_body_velocity = Vector3.ZERO
	_fresh = false

## The wind's hem offset per metre of lever: along the airflow (against his velocity), its angle
## growing with speed up to `max_lift_deg` at `full_speed`, flat after.
static func wind_offset_dir(velocity: Vector3, full_speed: float, max_lift_deg: float) -> Vector3:
	var speed := velocity.length()
	if speed < 0.001 or full_speed <= 0.0:
		return Vector3.ZERO
	var strength := clampf(speed / full_speed, 0.0, 1.0)
	var flow := -velocity / speed * deg_to_rad(max_lift_deg) * strength
	flow.y *= VERTICAL_WIND
	return flow

## Thick wool: every free point's offset eases toward its neighbours' mean, so the deformation
## stays one smooth piece and cannot kink between columns.
func _smooth() -> void:
	if bend <= 0.0:
		return
	var src := _d.duplicate()
	for r in range(1, ROWS):
		for c in COLS:
			var i := r * COLS + c
			var sum := src[r * COLS + (c + 1) % COLS] + src[r * COLS + (c + COLS - 1) % COLS] \
				+ src[i - COLS]
			var count := 3.0
			if r < ROWS - 1:
				sum += src[i + COLS]
				count += 1.0
			_d[i] = src[i].lerp(sum / count, bend)

## No segment down a column stretches past MAX_STRETCH of its rest length.
func _hold_lengths() -> void:
	for r in range(1, ROWS):
		for c in COLS:
			var i := r * COLS + c
			var up := world[i - COLS]
			var seg := world[i] - up
			var length := seg.length()
			var limit := _rest_len[i] * MAX_STRETCH
			if length > limit:
				world[i] = up + seg / length * limit

## Pushes everything below the collar out of every collider, and kills the offset velocity
## heading into it.
func _collide() -> void:
	if collider_xforms.is_empty():
		return
	var gap := thickness * 0.5 + CLEARANCE
	for i in range(COLS, N):
		for k in collider_xforms.size():
			var xf: Transform3D = collider_xforms[k]
			var spec: Array = COLLIDERS[k]
			var local := xf.affine_inverse() * world[i]
			var push := push_out(local, spec[1], spec[2], spec[3], gap)
			if push == Vector3.ZERO:
				continue
			var normal := (xf.basis * push).normalized()
			world[i] = xf * (local + push)
			var into := _dv[i].dot(normal)
			if into < 0.0:
				_dv[i] -= normal * into

## How far to move `p` (collider space) so it is at least `gap` outside a box of `half` extents
## around `center` rounded by `radius`. Zero when it already is.
static func push_out(p: Vector3, center: Vector3, half: Vector3, radius: float, gap: float) -> Vector3:
	var q := p - center
	var a := q.abs() - half
	var outside := a.max(Vector3.ZERO)
	var inside := minf(maxf(a.x, maxf(a.y, a.z)), 0.0)
	var dist := outside.length() + inside - radius
	if dist >= gap:
		return Vector3.ZERO
	var dir: Vector3
	if outside.length() > 0.00001:
		dir = (outside * q.sign()).normalized()
	else:
		# Deep inside: out through the nearest face.
		if a.x >= a.y and a.x >= a.z:
			dir = Vector3(signf(q.x) if q.x != 0.0 else 1.0, 0.0, 0.0)
		elif a.y >= a.z:
			dir = Vector3(0.0, signf(q.y) if q.y != 0.0 else 1.0, 0.0)
		else:
			dir = Vector3(0.0, 0.0, signf(q.z) if q.z != 0.0 else 1.0)
	return dir * (gap - dist)

## Offsets from rest this frame (world), for the tests.
func offsets() -> PackedVector3Array:
	return _d

## -- the rest shell --------------------------------------------------------------------------

## Point on a squared-off ellipse at `theta` (0 = front, +90 deg = his left): x/z offsets.
static func superellipse(theta: float, half_x: float, front: float, back: float) -> Vector2:
	var s := sin(theta)
	var c := cos(theta)
	var b := front if c >= 0.0 else back
	var denom := pow(absf(s) / half_x, SQUARENESS) + pow(absf(c) / b, SQUARENESS)
	var r := 1.0 / pow(denom, 1.0 / SQUARENESS)
	return Vector2(s * r, c * r)

## How far toward a side column `theta` is: 0 front/back, 1 at the arm opening.
static func side_amount(theta: float) -> float:
	return smoothstep(SIDE_FROM, SIDE_TO, absf(sin(theta)))

## The rest lattice before it is fitted to the colliders, bind space.
static func rest_shell() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(N)
	for c in COLS:
		var theta := TAU * float(c) / float(COLS)
		var side := side_amount(theta)
		var collar := superellipse(theta, COLLAR_HALF_X, COLLAR_FRONT, COLLAR_BACK)
		var yoke := superellipse(theta, YOKE_HALF_X, YOKE_FRONT, YOKE_BACK)
		var ridge := superellipse(theta, RIDGE_HALF_X, RIDGE_FRONT, RIDGE_BACK)
		var hem := superellipse(theta, lerpf(HEM_HALF_X, HEM_SIDE_HALF_X, side), HEM_FRONT, HEM_BACK)
		var hem_y := lerpf(HEM_Y, HEM_SIDE_Y, side)
		out[c] = Vector3(collar.x, COLLAR_Y, collar.y + COLLAR_CENTER_Z)
		out[COLS + c] = Vector3(yoke.x, lerpf(YOKE_Y, YOKE_SIDE_Y, side), yoke.y)
		out[RIDGE_ROW * COLS + c] = Vector3(ridge.x, RIDGE_Y, ridge.y)
		for r in range(RIDGE_ROW + 1, ROWS):
			var u := float(r - RIDGE_ROW) / float(ROWS - 1 - RIDGE_ROW)
			var xz := ridge.lerp(hem, u)
			xz += xz.normalized() * BULGE * sin(PI * u)
			out[r * COLS + c] = Vector3(xz.x, lerpf(RIDGE_Y, hem_y, u), xz.y)
	return out

@warning_ignore("integer_division")
func _build_rest() -> void:
	rest = rest_shell()
	# Fit it out of the body at bind, so the rest shape never fights the colliders. Not out of the
	# T-posed arm capsules (see COLLIDERS).
	var gap := thickness * 0.5 + CLEARANCE
	for _pass in 3:
		for i in range(COLS, N):
			for spec: Array in COLLIDERS:
				if spec[4]:
					rest[i] += push_out(rest[i], spec[1], spec[2], spec[3], gap)
	_rest_len.resize(N)
	_lever.resize(N)
	for i in N:
		var r := i / COLS
		var c := i % COLS
		_rest_len[i] = 0.0 if r == 0 else rest[i].distance_to(rest[i - COLS])
		_lever[i] = 0.0 if r <= RIDGE_ROW else rest[i].distance_to(rest[RIDGE_ROW * COLS + c])
	world = rest.duplicate()

## -- the drawn mesh --------------------------------------------------------------------------
##
## Layout (each ring RU + 1 vertices, the last a UV seam copy of the first):
##   outer shell rows 0..RV-1, inner shell rows 0..RV-1,
##   hem roll ROLL-1 rings (outer -> inner), collar roll ROLL-1 rings (outer -> inner).

const RING := RU + 1

func _ring_offset(block: int) -> int:
	return block * RING

func _build_topology() -> void:
	_indices = PackedInt32Array()
	_uvs = PackedVector2Array()
	# Blocks of rings: outer RV, inner RV, hem roll, collar roll.
	var outer := 0
	var inner := RV
	var hem_roll := 2 * RV
	var collar_roll := 2 * RV + (ROLL - 1)
	var rings := 2 * RV + 2 * (ROLL - 1)
	_uvs.resize(rings * RING)
	for j in RV:
		for i in RING:
			var uv := Vector2(float(i) / RU, float(j) / (RV - 1))
			_uvs[(outer + j) * RING + i] = uv
			_uvs[(inner + j) * RING + i] = uv
	for k in ROLL - 1:
		for i in RING:
			_uvs[(hem_roll + k) * RING + i] = Vector2(float(i) / RU, 1.0 + 0.02 * (k + 1))
			_uvs[(collar_roll + k) * RING + i] = Vector2(float(i) / RU, -0.02 * (k + 1))
	# Godot front faces wind clockwise. Outer, seen from outside with u to the right and v down:
	# (a, b, c) top-left, top-right, bottom-right.
	for j in RV - 1:
		_strip(outer + j, outer + j + 1, false)
		_strip(inner + j, inner + j + 1, true)
	# The hem roll carries on past the outer shell's bottom row, so it winds like the outer.
	var chain := [outer + RV - 1]
	for k in ROLL - 1:
		chain.append(hem_roll + k)
	chain.append(inner + RV - 1)
	for k in chain.size() - 1:
		_strip(chain[k], chain[k + 1], false)
	# The collar roll runs the other way up the outer shell, so it winds like the inner.
	chain = [outer]
	for k in ROLL - 1:
		chain.append(collar_roll + k)
	chain.append(inner)
	for k in chain.size() - 1:
		_strip(chain[k], chain[k + 1], true)

func _strip(ring_a: int, ring_b: int, flip: bool) -> void:
	for i in RU:
		var a := ring_a * RING + i
		var b := a + 1
		var d := ring_b * RING + i
		var c := d + 1
		if flip:
			_indices.append_array(PackedInt32Array([a, c, b, a, d, c]))
		else:
			_indices.append_array(PackedInt32Array([a, b, c, a, c, d]))

## Catmull-Rom weights for one segment at t.
static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 \
		+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)

## The smooth surface through the lattice `pts` (any space): RU x RV points, row-major by ring.
@warning_ignore("integer_division")
static func surface(pts: PackedVector3Array) -> PackedVector3Array:
	# Down each column first, with mirrored end points.
	var cols: Array[PackedVector3Array] = []
	for c in COLS:
		var col := PackedVector3Array()
		col.resize(RV)
		for j in RV:
			var r := mini(j / SUB_V, ROWS - 2)
			var t := float(j - r * SUB_V) / SUB_V
			var p1 := pts[r * COLS + c]
			var p2 := pts[(r + 1) * COLS + c]
			var p0 := pts[(r - 1) * COLS + c] if r > 0 else 2.0 * p1 - p2
			var p3 := pts[(r + 2) * COLS + c] if r + 2 < ROWS else 2.0 * p2 - p1
			col[j] = _cr(p0, p1, p2, p3, t)
		cols.append(col)
	# Then around each ring, periodic.
	var out := PackedVector3Array()
	out.resize(RU * RV)
	for j in RV:
		for c in COLS:
			var p0 := cols[(c + COLS - 1) % COLS][j]
			var p1 := cols[c][j]
			var p2 := cols[(c + 1) % COLS][j]
			var p3 := cols[(c + 2) % COLS][j]
			for s in SUB_U:
				out[j * RU + c * SUB_U + s] = _cr(p0, p1, p2, p3, float(s) / SUB_U)
	return out

func _rebuild_mesh(to_local: Transform3D) -> void:
	var local := PackedVector3Array()
	local.resize(N)
	for i in N:
		local[i] = to_local * world[i]
	var p := surface(local)
	var h := thickness * 0.5
	var rings := 2 * RV + 2 * (ROLL - 1)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(rings * RING)
	norms.resize(rings * RING)
	var hem_roll := 2 * RV
	var collar_roll := hem_roll + ROLL - 1
	for j in RV:
		var jd := mini(j + 1, RV - 1)
		var ju := maxi(j - 1, 0)
		for i in RU:
			var here := p[j * RU + i]
			var du := p[j * RU + (i + 1) % RU] - p[j * RU + (i + RU - 1) % RU]
			var dv := p[jd * RU + i] - p[ju * RU + i]
			var n := dv.cross(du).normalized()
			_put(verts, norms, j, i, here + n * h, n)
			_put(verts, norms, RV + j, i, here - n * h, -n)
			if j == RV - 1 or j == 0:
				# The rolled edge: a half circle from the outer face to the inner one, bulging
				# along the surface past the edge.
				var e := dv.normalized() if j == RV - 1 else -dv.normalized()
				var block := hem_roll if j == RV - 1 else collar_roll
				for k in ROLL - 1:
					var phi := PI * float(k + 1) / ROLL
					var rn := n * cos(phi) + e * sin(phi)
					_put(verts, norms, block + k, i, here + rn * h, rn)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	# Double-buffered: the buffer being filled is never the one assigned, so the MeshInstance's
	# surface override (the cel material) is carried across the swap rather than dropped by a
	# clear_surfaces() on the live mesh.
	var back := 1 - _front
	var m := _buffers[back]
	m.clear_surfaces()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, _surface_material)
	mesh = m
	_front = back

static func _put(verts: PackedVector3Array, norms: PackedVector3Array, ring: int, i: int,
		v: Vector3, n: Vector3) -> void:
	verts[ring * RING + i] = v
	norms[ring * RING + i] = n
	if i == 0:
		verts[ring * RING + RU] = v
		norms[ring * RING + RU] = n

## For the dash afterimages: the mesh as it is this frame, kept. The live buffer is handed over and
## replaced, so the ghost's copy never changes under it. See scripts/pilot9_afterimage.gd.
func frozen_mesh() -> Mesh:
	var m := mesh
	if m == null:
		return null
	_buffers[_front] = ArrayMesh.new()
	return m
