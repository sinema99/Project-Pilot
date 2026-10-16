extends RefCounted

# EXIA's sprint: a grounded titan run, built in code. See docs/specs/exia-sprint.md ("Redo").
#
# The clip plays on the spot and the body supplies the 14 m/s, so the one hard constraint is that
# a planted foot moves backward through the mech at exactly SPRINT_SPEED. Keying legs by hand
# cannot hit that, so the legs are SOLVED: every key places the sole plate (on the floor path
# during contact, on an authored arc in flight) and a two-bone solve fits thigh and shin to it.
# Everything else - pelvis, spine, arms - is authored as angles about the mech's axes.
#
# The foot, measured off the rig: `foot` + `toe` are one near-vertical stilt (ankle to ball,
# ~1.67 m) and `toe.*.001` is a flat sole plate (~0.86 m) running forward from the ball. A step
# lands on the plate's back edge with the tip up, slaps flat under the weight, then pivots up onto
# the plate's tip for the push-off. "Ball" below is the plate's back edge, the toe.*.001 head.
#
# Authored in MECH space (nose +Z, left +X, up +Y, metres) and converted per bone, so the armature's
# +90 degree yaw and 1.7268 scale are absorbed here and a re-export that fixes them needs no change.
# The base pose is MECH_standing, not the bone rest: the rig's rest is not its bind pose.
#
# The numbers are the 2026-10-12 grill's, retuned 2026-10-13 (14 m/s, 8 degree lean, 1.0 s cycle):
# grouped by bone and named for the pose they set.

const CLIP := "MECH_sprint"
const LENGTH := 1.0             # one cycle, two steps: 2 steps a second, 7 m each
const FPS := 30
const SPRINT_SPEED := 14.0
const CONTACT_TIME := 0.35      # each foot's time on the floor: a 4.9 m floor path
const CONTACT_FRACTION := CONTACT_TIME / LENGTH

# --- hips ---------------------------------------------------------------------
# Heights of the thigh heads' midpoint above the floor. Lowest a beat after each plant (the knee
# soaking up the landing), highest in the short moment both feet are up.
const HIP_LOW := 3.90
const HIP_HIGH := 4.10
const HIP_LOW_AT := 0.07        # seconds after the plant
const HIP_SWAY := 0.15          # sideways over the planted foot
const HIP_SWAY_PEAK := 0.2      # of the cycle: a little after mid-stance, the mass arriving late

# --- pelvis and spine ---------------------------------------------------------
const LEAN_DEG := 8.0           # forward lean at `spine`: mostly upright, the weight over the hips
const LEAN_BOB_DEG := 1.0       # deeper at the low point, less at the high
const HIP_YAW_DEG := 6.0        # toward the reaching leg
const HIP_ROLL_DEG := 4.0       # the free side dropping through the low point
const HIP_ROLL_PEAK := 0.1      # of the cycle
const CHEST_COUNTER_DEG := 8.0  # spine.001 twists against the hips
const CHEST_LAG := 0.05         # seconds behind the hips
const CANOPY_CANCEL := 0.7      # spine.003 undoes this share of the lean and twist below it

# --- legs ---------------------------------------------------------------------
const STRIDE_FRONT := 1.85      # ball lands this far ahead of the hip; the floor path runs 4.9 m back from it
const PLATE_LAND_DEG := 12.0    # sole plate tip up as it lands on its back edge
const PLATE_FLAT_BY := 0.2      # of the stance: slapped flat under the weight
const PIVOT_FROM := 0.55        # of the stance: the heel lifts, pivoting on the plate's tip
const PLATE_PUSH_DEG := -35.0   # tip down, heel up, as it leaves the floor
const STILT_LAND_DEG := 12.0    # ankle behind the ball: continuing the reaching leg's line
const STILT_LOAD_DEG := -6.0    # ankle forward over the ball: loaded, the low point
const STILT_LOAD_AT := 0.3      # of the stance
const STILT_PUSH_DEG := -22.0   # ankle well forward: the stilt in line with the driving leg
const STILT_KICK_DEG := -25.0   # extra fold early in the swing: the heel coming up behind
const SWING_LIFT := 0.8         # heel height the swing adds on top of the toe-off height (~1.0 m peak)
const SWING_LIFT_SHAPE := 1.15  # > 1: lifts slowly, peaks late, comes down firmly
const SWING_START_SLOPE := -8.0 # ball z velocity per swing unit leaving the floor: carries on back a little
const SWING_END_SLOPE := -2.0   # and arriving: no visible paw-back, the farthest point is the landing
const SWING_WARP := 0.35        # slow out of the push-off, fast through the passing pose

# --- arms ---------------------------------------------------------------------
# Each arm's forward peak is exactly the opposite foot's plant, held through the low contact pose
# and quick through the middle - the legs' rhythm, not a sine.
const ARM_FWD_DEG := 30.0
const ARM_BACK_DEG := -25.0
const ELBOW_FWD_DEG := 95.0     # absolute bend between upper arm and forearm
const ELBOW_BACK_DEG := 80.0
const ADDUCT_FWD_DEG := 12.0    # forward fist in toward the chest's centreline
const ABDUCT_BACK_DEG := 8.0    # back fist out past the hip
const HAND_CURL_DEG := 10.0
const ARM_HOLD := 2.0           # tanh sharpness: higher flattens the swing's ends into longer holds
const FOREARM_LAG_FRAMES := 1.0 # the forearm behind the upper arm: follow-through
const JOLT_SHOULDER_DEG := 2.5  # each plant's impact up through the frame: shoulders drop
const JOLT_ELBOW_DEG := 4.0     # and the forearms sag
const JOLT_TIME := 0.04         # seconds to the jolt's peak; settled by ~0.15 s

# Bones the build drives. Everything else holds its MECH_standing value.
const DRIVEN := ["spine", "spine.001", "spine.003", "shoulder.L", "shoulder.R", "upper_arm.L",
	"upper_arm.R", "forearm.L", "forearm.R", "hand.L", "hand.R", "thigh.L", "shin.L", "foot.L",
	"toe.L", "toe.L.001", "thigh.R", "shin.R", "foot.R", "toe.R", "toe.R.001"]

# --- the sampler: a clip's pose with no scene tree ------------------------------

## `skeleton`'s transform into the mech's own space: every node between it and the CharacterBody3D
## that carries the model. Local transforms only, so it needs no tree.
static func space_of(skeleton: Skeleton3D) -> Transform3D:
	var c := Transform3D.IDENTITY
	var n: Node = skeleton
	while n != null and not (n is CharacterBody3D):
		if n is Node3D:
			c = (n as Node3D).transform * c
		n = n.get_parent()
	return c

static func _subname(clip: Animation, track: int) -> String:
	return String(clip.track_get_path(track).get_concatenated_subnames())

## Every bone's local transform at time `t` of `clip` (rest where the clip has no track), in the
## skeleton's own units.
static func locals_at(skeleton: Skeleton3D, clip: Animation, t: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var pos: Dictionary = {}
	var rot: Dictionary = {}
	for track in clip.get_track_count():
		match clip.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				pos[_subname(clip, track)] = clip.position_track_interpolate(track, t)
			Animation.TYPE_ROTATION_3D:
				rot[_subname(clip, track)] = clip.rotation_track_interpolate(track, t)
	for b in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(b)
		var name := skeleton.get_bone_name(b)
		var q: Quaternion = rot.get(name, rest.basis.get_rotation_quaternion())
		out.append(Transform3D(Basis(q), pos.get(name, rest.origin)))
	return out

## Every bone's global transform in MECH space, metres, rotation orthonormal.
static func mech_pose(skeleton: Skeleton3D, locals: Array[Transform3D]) -> Array[Transform3D]:
	var c := space_of(skeleton)
	var rs := c.basis.orthonormalized()
	var gs: Array[Transform3D] = []
	var out: Array[Transform3D] = []
	for b in skeleton.get_bone_count():
		var p := skeleton.get_bone_parent(b)
		gs.append(locals[b] if p < 0 else gs[p] * locals[b])
		out.append(Transform3D(rs * gs[b].basis.orthonormalized(), c * gs[b].origin))
	return out

static func pose_at(skeleton: Skeleton3D, clip: Animation, t: float) -> Array[Transform3D]:
	return mech_pose(skeleton, locals_at(skeleton, clip, t))

## The time in `clip` at which the left ball of foot is lowest, which is its left contact. Used to
## phase-match the walk and the sprint across a crossfade.
static func left_contact_time(skeleton: Skeleton3D, clip: Animation) -> float:
	var ball := skeleton.find_bone("toe.L.001")
	if ball < 0 or clip.length <= 0.0:
		return 0.0
	var best_t := 0.0
	var best_y := INF
	var steps := int(round(clip.length * FPS))
	for i in steps:
		var t := float(i) / FPS
		var y: float = pose_at(skeleton, clip, t)[ball].origin.y
		if y < best_y:
			best_y = y
			best_t = t
	return best_t

# --- curves -----------------------------------------------------------------------

static func _smooth(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func _hermite(p0: float, m0: float, p1: float, m1: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return ((2.0 * t3 - 3.0 * t2 + 1.0) * p0 + (t3 - 2.0 * t2 + t) * m0
		+ (-2.0 * t3 + 3.0 * t2) * p1 + (t3 - t2) * m1)

## The thigh heads' midpoint height above the floor at cycle phase `u`. Repeats every step: lowest
## HIP_LOW_AT after each plant, highest half way through the flight, a half cosine between.
static func hip_height(u: float) -> float:
	var half := LENGTH * 0.5
	var high_at := CONTACT_TIME + (half - CONTACT_TIME) * 0.5
	var s := fposmod(u * LENGTH, half)
	if s < HIP_LOW_AT:
		s += half
	var amp := HIP_HIGH - HIP_LOW
	if s < high_at:
		return HIP_LOW + amp * 0.5 * (1.0 - cos(PI * (s - HIP_LOW_AT) / (high_at - HIP_LOW_AT)))
	return HIP_HIGH - amp * 0.5 * (1.0 - cos(PI * (s - high_at) / (half + HIP_LOW_AT - high_at)))

## The hips' sideways shift over the planted foot at phase `u`, metres, + = the left (+X).
static func hip_sway(u: float) -> float:
	return HIP_SWAY * cos(TAU * (u - HIP_SWAY_PEAK))

## The right arm's swing at phase `u`: +1 forward at the left foot's plant, -1 back at the right's.
## The left arm is its negative. A tanh flattens the ends into holds and speeds up the middle.
static func arm_swing(u: float) -> float:
	return tanh(ARM_HOLD * cos(TAU * u)) / tanh(ARM_HOLD)

## The latest plant's impact travelling up the frame at phase `u`, 0..1: peaks JOLT_TIME after
## each plant, settled by about 0.15 s.
static func jolt(u: float) -> float:
	var t := fposmod(u * LENGTH, LENGTH * 0.5) / JOLT_TIME
	return t * exp(1.0 - t)

## The ball (the sole plate's back edge) when the plate's floor contact is at `flat_z` - where the
## ball would be with the plate flat. Tip up, the plate rocks on its back edge, which stays down;
## heel up, it pivots on its tip, which stays down, and the ball rises. Returns (z, height).
static func _ball_on_floor(flat_z: float, plate_deg: float, plate_len: float) -> Vector2:
	if plate_deg >= 0.0:
		return Vector2(flat_z, 0.0)
	var a := deg_to_rad(plate_deg)
	return Vector2(flat_z + plate_len - plate_len * cos(a), -plate_len * sin(a))

## One foot at cycle phase `p` (0 = its plant): the ball's z relative to the hip anchor and height
## above the floor, the sole plate's pitch (degrees, + = tip up), the stilt's lean (degrees, + =
## ankle behind the ball) and whether it is on the floor. `plate_len` is the plate's length in the
## side view.
static func leg_state(p: float, plate_len: float) -> Dictionary:
	p = fposmod(p, 1.0)
	if p < CONTACT_FRACTION:
		var w := p / CONTACT_FRACTION
		# Planted: the floor contact moves back through the mech at exactly the body's speed.
		var flat_z := STRIDE_FRONT - SPRINT_SPEED * p * LENGTH
		var plate := 0.0
		if w < PLATE_FLAT_BY:
			plate = lerpf(PLATE_LAND_DEG, 0.0, _smooth(w / PLATE_FLAT_BY))
		elif w > PIVOT_FROM:
			var k := (w - PIVOT_FROM) / (1.0 - PIVOT_FROM)
			plate = PLATE_PUSH_DEG * k * k
		var stilt := (lerpf(STILT_LAND_DEG, STILT_LOAD_DEG, _smooth(w / STILT_LOAD_AT))
			if w < STILT_LOAD_AT
			else lerpf(STILT_LOAD_DEG, STILT_PUSH_DEG, _smooth((w - STILT_LOAD_AT) / (1.0 - STILT_LOAD_AT))))
		var b := _ball_on_floor(flat_z, plate, plate_len)
		return {z = b.x, h = b.y, plate = plate, stilt = stilt, planted = true}
	# The swing, from the toe-off pose to the next plant. Warped so it leaves slowly, as if lifting
	# a load, and whips through the passing pose; the lift peaks late and comes down firmly.
	var q := (p - CONTACT_FRACTION) / (1.0 - CONTACT_FRACTION)
	var start := _ball_on_floor(STRIDE_FRONT - SPRINT_SPEED * CONTACT_TIME, PLATE_PUSH_DEG, plate_len)
	var x := q - SWING_WARP * sin(PI * q) / PI
	var kick := 6.75 * q * (1.0 - q) * (1.0 - q)   # peaks at 1 a third of the way through
	return {
		z = _hermite(start.x, SWING_START_SLOPE, STRIDE_FRONT, SWING_END_SLOPE, x),
		h = start.y * (1.0 - _smooth(q)) + SWING_LIFT * sin(PI * pow(q, SWING_LIFT_SHAPE)),
		plate = lerpf(PLATE_PUSH_DEG, PLATE_LAND_DEG, _smooth(q / 0.85)),
		stilt = lerpf(STILT_PUSH_DEG, STILT_LAND_DEG, _smooth(q)) + STILT_KICK_DEG * kick,
		planted = false,
	}

static func _rx(deg: float) -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(deg))

static func _ry(deg: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(deg))

static func _rz(deg: float) -> Basis:
	return Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(deg))

# --- the build --------------------------------------------------------------------

## Builds MECH_sprint on `skeleton` from `standing`'s pose. 31 keys per track at 30 fps (30
## frames), the last equal to the first. Public pieces of the solve are in `solve_pose` so a test can read it.
static func build(skeleton: Skeleton3D, standing: Animation) -> Animation:
	var clip := Animation.new()
	clip.length = LENGTH
	clip.loop_mode = Animation.LOOP_LINEAR
	clip.step = 1.0 / FPS

	var base_locals := locals_at(skeleton, standing, 0.0)
	var ctx := _context(skeleton, base_locals)

	# Track paths come off the standing clip so they match the AnimationPlayer's root.
	var prefix := ""
	for track in standing.get_track_count():
		prefix = String(standing.track_get_path(track)).get_slice(":", 0)
		break

	var bones := skeleton.get_bone_count()
	var rot_tracks: Array[int] = []
	var pos_tracks: Dictionary = {}    # bone -> track, only for bones standing keys a position on
	var scale_tracks: Dictionary = {}
	for b in bones:
		var name := skeleton.get_bone_name(b)
		var path := NodePath("%s:%s" % [prefix, name])
		var rt := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(rt, path)
		rot_tracks.append(rt)
		var has_pos := false
		var has_scale := false
		for track in standing.get_track_count():
			if _subname(standing, track) != name:
				continue
			if standing.track_get_type(track) == Animation.TYPE_POSITION_3D:
				has_pos = true
			elif standing.track_get_type(track) == Animation.TYPE_SCALE_3D:
				has_scale = true
		if has_pos or name == "spine":
			var pt := clip.add_track(Animation.TYPE_POSITION_3D)
			clip.track_set_path(pt, path)
			pos_tracks[b] = pt
		if has_scale:
			var st := clip.add_track(Animation.TYPE_SCALE_3D)
			clip.track_set_path(st, path)
			scale_tracks[b] = st

	var base_scales: Dictionary = {}
	for track in standing.get_track_count():
		if standing.track_get_type(track) == Animation.TYPE_SCALE_3D:
			base_scales[_subname(standing, track)] = standing.scale_track_interpolate(track, 0.0)

	var frames := int(round(LENGTH * FPS))
	for k in frames + 1:
		var u := float(k % frames) / frames
		var t := float(k) / FPS
		var pose := solve_pose(ctx, u)
		for b in bones:
			clip.rotation_track_insert_key(rot_tracks[b], t, pose.rot[b])
			if pos_tracks.has(b):
				clip.position_track_insert_key(pos_tracks[b], t,
					pose.spine_pos if b == ctx.spine else base_locals[b].origin)
			if scale_tracks.has(b):
				clip.scale_track_insert_key(scale_tracks[b], t,
					base_scales.get(skeleton.get_bone_name(b), Vector3.ONE))
	return clip

## The standing pose in mech space and each bone's rigid local offset from its parent.
class _Context extends RefCounted:
	var skeleton: Skeleton3D
	var rs: Basis
	var k: float
	var base_locals: Array[Transform3D]
	var g0: Array[Transform3D]      # standing, mech space, metres
	var parent: Array[int] = []
	var l0b: Array[Basis] = []      # standing local rotation (mech-space frames)
	var l0o: Array[Vector3] = []    # standing local offset, in the parent's frame, metres
	var spine := -1
	var floor_y := 0.0
	var hip_z := 0.0
	var idx: Dictionary = {}

## What the build needs from the skeleton, worked out once.
static func _context(sk: Skeleton3D, locals: Array[Transform3D]) -> _Context:
	var ctx := _Context.new()
	ctx.skeleton = sk
	ctx.base_locals = locals
	var c := space_of(sk)
	ctx.rs = c.basis.orthonormalized()
	ctx.k = c.basis.get_scale().y
	ctx.g0 = mech_pose(sk, locals)
	for b in sk.get_bone_count():
		ctx.idx[sk.get_bone_name(b)] = b
		var p := sk.get_bone_parent(b)
		ctx.parent.append(p)
		if p < 0:
			ctx.l0b.append(ctx.g0[b].basis)
			ctx.l0o.append(ctx.g0[b].origin)
		else:
			ctx.l0b.append(ctx.g0[p].basis.inverse() * ctx.g0[b].basis)
			ctx.l0o.append(ctx.g0[p].basis.inverse() * (ctx.g0[b].origin - ctx.g0[p].origin))
	ctx.spine = ctx.idx["spine"]
	ctx.floor_y = minf(ctx.g0[ctx.idx["toe.L.001"]].origin.y, ctx.g0[ctx.idx["toe.R.001"]].origin.y)
	ctx.hip_z = (ctx.g0[ctx.idx["thigh.L"]].origin.z + ctx.g0[ctx.idx["thigh.R"]].origin.z) * 0.5
	return ctx

## The sole plate, ball to tip, standing, in mech space. The tip is where the unparented
## `toe.*.002` IK leftover sits; without it, the plate bone's own axis at the measured 0.86 m.
static func plate_vector(ctx: _Context, side: String) -> Vector3:
	var tip: int = ctx.idx["toe" + side + ".001"]
	if ctx.idx.has("toe" + side + ".002"):
		var v: Vector3 = ctx.g0[ctx.idx["toe" + side + ".002"]].origin - ctx.g0[tip].origin
		if v.length() > 0.1:
			return v
	return ctx.g0[tip].basis.y.normalized() * 0.86

## One pose of the cycle at `u` in [0, 1): the local rotation of every bone (skeleton space) and
## the spine's position track value. Also stashes each leg's ball and plate tip targets (mech
## space) so a test can check them against what the clip really plays.
static func solve_pose(ctx: _Context, u: float) -> Dictionary:
	var n := ctx.skeleton.get_bone_count()
	var idx := ctx.idx
	var ng: Array[Basis] = []
	var no: Array[Vector3] = []
	ng.resize(n)
	no.resize(n)

	# --- hips: pitch, yaw, roll, sway, and the height the spine's position track has to supply -
	var h := hip_height(u)
	var target_hip := h + ctx.floor_y
	var bob := clampf(((HIP_LOW + HIP_HIGH) * 0.5 - h) / ((HIP_HIGH - HIP_LOW) * 0.5), -1.0, 1.0)
	var hips := _ry(-HIP_YAW_DEG * cos(TAU * u)) * _rz(HIP_ROLL_DEG * cos(TAU * (u - HIP_ROLL_PEAK))) \
		* _rx(LEAN_DEG + LEAN_BOB_DEG * bob)
	var spine: int = ctx.spine
	var thigh_l: int = idx["thigh.L"]
	var thigh_r: int = idx["thigh.R"]
	var hips_basis := hips * ctx.g0[spine].basis
	var mid_off: Vector3 = (ctx.l0o[thigh_l] + ctx.l0o[thigh_r]) * 0.5
	var mid_y := ctx.g0[spine].origin.y + (hips_basis * mid_off).y
	var shift := Vector3(hip_sway(u), target_hip - mid_y, 0.0)
	var spine_origin: Vector3 = ctx.g0[spine].origin + shift

	var counter := _ry(CHEST_COUNTER_DEG * cos(TAU * (u - CHEST_LAG / LENGTH)))
	var swing_r := arm_swing(u)
	var swing_r_fore := arm_swing(u - FOREARM_LAG_FRAMES / FPS / LENGTH)
	var j := jolt(u)

	var want: Dictionary = {}     # bone -> explicit global basis
	var balls: Dictionary = {}
	var tips: Dictionary = {}
	for b in n:
		var p: int = ctx.parent[b]
		var name := ctx.skeleton.get_bone_name(b)
		# The bone's global basis: explicit where the pose says so, otherwise it inherits.
		if b == spine:
			ng[b] = hips_basis
			no[b] = spine_origin
			continue
		if p < 0:
			ng[b] = ctx.g0[b].basis
			no[b] = ctx.g0[b].origin
			continue
		no[b] = no[p] + ng[p] * ctx.l0o[b]
		var inherited: Basis = ng[p] * ctx.l0b[b]
		var basis := inherited
		var side := 1.0 if name.ends_with(".L") else -1.0
		match name:
			"spine.001":
				basis = counter * inherited
			"spine.003":
				var d_s1 := Quaternion((ng[p] * ctx.g0[p].basis.inverse()).orthonormalized())
				var part := d_s1.slerp(Quaternion.IDENTITY, CANOPY_CANCEL)
				basis = Basis(part) * ctx.g0[b].basis
			"shoulder.L", "shoulder.R":
				# The plant's impact: both shoulders drop and settle.
				basis = _rz(-JOLT_SHOULDER_DEG * j * side) * inherited
			"upper_arm.L", "upper_arm.R":
				# The left arm is the right arm's opposite: at the left plant the right is forward.
				var f := (-swing_r * side + 1.0) * 0.5
				var pitch := lerpf(ARM_BACK_DEG, ARM_FWD_DEG, f)
				var adduct := lerpf(-ABDUCT_BACK_DEG, ADDUCT_FWD_DEG, f)
				basis = _rz(-adduct * side) * _rx(-pitch) * inherited
			"forearm.L", "forearm.R":
				var f := (-swing_r_fore * side + 1.0) * 0.5
				var bend := lerpf(ELBOW_BACK_DEG, ELBOW_FWD_DEG, f) - JOLT_ELBOW_DEG * j
				# The standing elbow is already bent; the numbers are the absolute angle.
				basis = _rx(-(bend - _elbow_deg(ctx, name))) * inherited
			"hand.L", "hand.R":
				var f := (-swing_r_fore * side + 1.0) * 0.5
				basis = _rx(-HAND_CURL_DEG * f) * inherited
			"thigh.L", "thigh.R":
				var leg := _solve_leg(ctx, side > 0.0, u, no[b])
				for key in leg.want:
					want[key] = leg.want[key]
				balls[name] = leg.ball
				tips[name] = leg.tip
		if want.has(b):
			basis = want[b]
		ng[b] = basis

	var rot: Array[Quaternion] = []
	for b in n:
		var p: int = ctx.parent[b]
		var local: Basis = (ctx.rs.inverse() * ng[b]) if p < 0 else (ng[p].inverse() * ng[b])
		# Constant bones (the IK leftovers) never reach this with a change: they take the
		# standing local rotation outright.
		if not DRIVEN.has(ctx.skeleton.get_bone_name(b)) and p < 0:
			local = Basis(ctx.base_locals[b].basis.get_rotation_quaternion())
		rot.append(Quaternion(local.orthonormalized()))

	var standing_spine: Vector3 = ctx.base_locals[spine].origin
	var d_skel := ctx.rs.inverse() * shift / ctx.k
	return {rot = rot, spine_pos = standing_spine + d_skel, hip_mid_y = target_hip,
		balls = balls, tips = tips}

## The angle between a forearm and its upper arm in the standing pose, in degrees.
static func _elbow_deg(ctx: _Context, forearm: String) -> float:
	var f: int = ctx.idx[forearm]
	var h: int = ctx.idx[forearm.replace("forearm", "hand")]
	var ua: int = ctx.parent[f]
	var up_dir: Vector3 = (ctx.g0[f].origin - ctx.g0[ua].origin).normalized()
	var fa_dir: Vector3 = (ctx.g0[h].origin - ctx.g0[f].origin).normalized()
	return rad_to_deg(up_dir.angle_to(fa_dir))

## Solves one leg to its authored ball target. Returns the explicit global bases of thigh, shin,
## foot, toe and sole plate, and the ball and plate-tip targets. `hip` is the thigh's solved head.
static func _solve_leg(ctx: _Context, left: bool, u: float, hip: Vector3) -> Dictionary:
	var s := ".L" if left else ".R"
	var thigh: int = ctx.idx["thigh" + s]
	var shin: int = ctx.idx["shin" + s]
	var foot: int = ctx.idx["foot" + s]
	var toe: int = ctx.idx["toe" + s]
	var tip: int = ctx.idx["toe" + s + ".001"]
	var plate_vec := plate_vector(ctx, s)
	var st := leg_state(u if left else u + 0.5, Vector2(plate_vec.y, plate_vec.z).length())

	var ball := Vector3(ctx.g0[tip].origin.x, ctx.floor_y + st.h, ctx.hip_z + st.z)
	# The stilt (foot + toe, ankle to ball) leans as one piece about the ball.
	var v_up: Vector3 = ctx.g0[foot].origin - ctx.g0[tip].origin
	var stand_lean := rad_to_deg(atan2(-v_up.z, v_up.y))
	var tilt := _rx(-(st.stilt - stand_lean))
	var ankle := ball + tilt * v_up
	var plate := _rx(-st.plate)

	var a: float = (ctx.g0[shin].origin - ctx.g0[thigh].origin).length()
	var b: float = (ctx.g0[foot].origin - ctx.g0[shin].origin).length()
	var to_ankle := ankle - hip
	# Out of reach: the leg straightens and the foot comes up short rather than the solve
	# going to NaN. The tests hold every key inside the reach.
	var d := clampf(to_ankle.length(), 0.3, (a + b) * 0.998)
	var base := to_ankle.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var alpha := acos(cos_a)
	var pole := Vector3(0.0, 0.0, 1.0)
	var perp := pole - base * base.dot(pole)
	perp = perp.normalized() if perp.length() > 0.001 else Vector3.UP
	var knee := hip + a * (cos_a * base + sin(alpha) * perp)
	var reach := hip + base * d
	var d_th0: Vector3 = (ctx.g0[shin].origin - ctx.g0[thigh].origin).normalized()
	var d_sh0: Vector3 = (ctx.g0[foot].origin - ctx.g0[shin].origin).normalized()
	var want := {
		thigh: Basis(Quaternion(d_th0, (knee - hip).normalized())) * ctx.g0[thigh].basis,
		shin: Basis(Quaternion(d_sh0, (reach - knee).normalized())) * ctx.g0[shin].basis,
		foot: tilt * ctx.g0[foot].basis,
		toe: tilt * ctx.g0[toe].basis,
		tip: plate * ctx.g0[tip].basis,
	}
	return {want = want, ball = ball, tip = ball + plate * plate_vec}
