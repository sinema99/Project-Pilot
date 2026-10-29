extends RefCounted

# EXIA's gaits, and the pose solver every clip the mech builds in code goes through. See
# docs/specs/exia-movement.md (and docs/specs/exia-sprint.md for the rig and the sprint's history).
#
# A clip that plays on the spot while the body supplies the speed has one hard constraint: a
# planted foot must move backward through the mech at exactly the body's speed. Keying legs by hand
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
# Two layers:
#   - `pose_from(ctx, spec)` turns one pose spec (a Dictionary, see standing_spec) into every bone's
#     local rotation plus the spine's position. `bake()` keys any function of time that returns a
#     spec into a clip. mech_moves.gd builds the non-cycle clips that way.
#   - a `Gait` is the numbers of one run cycle, and `gait_spec()` is the cycle as a spec. `run()` and
#     `sprint()` are the two gaits - one family, two sets of numbers.

const FPS := 30

## One run cycle's numbers. The defaults are the sprint's (the 2026-10-12 grill, retuned
## 2026-10-13); run() overrides them. Grouped by bone and named for the pose they set.
class Gait extends RefCounted:
	var clip := "MECH_sprint"
	var speed := 14.0           # the body's speed the cycle is authored for
	var length := 1.0           # one cycle, two steps
	var contact := 0.35         # each foot's time on the floor
	# --- hips: heights of the thigh heads' midpoint above the floor. Lowest a beat after each
	# plant (the knee soaking up the landing), highest in the short moment both feet are up.
	var hip_low := 3.90
	var hip_high := 4.10
	var hip_low_at := 0.07      # seconds after the plant
	var hip_sway := 0.15        # sideways over the planted foot
	var hip_sway_peak := 0.2    # of the cycle: a little after mid-stance, the mass arriving late
	# --- pelvis and spine
	var lean := 8.0             # forward lean at `spine`
	var lean_bob := 1.0         # deeper at the low point, less at the high
	var hip_yaw := 6.0          # toward the reaching leg
	var hip_roll := 4.0         # the free side dropping through the low point
	var hip_roll_peak := 0.1    # of the cycle
	var chest_counter := 8.0    # spine.001 twists against the hips
	var chest_lag := 0.05       # seconds behind the hips
	# --- legs
	var stride_front := 1.85    # ball lands this far ahead of the hip
	var plate_land := 12.0      # sole plate tip up as it lands on its back edge
	var plate_flat_by := 0.2    # of the stance: slapped flat under the weight
	var pivot_from := 0.55      # of the stance: the heel lifts, pivoting on the plate's tip
	var plate_push := -35.0     # tip down, heel up, as it leaves the floor
	var stilt_land := 12.0      # ankle behind the ball: continuing the reaching leg's line
	var stilt_load := -6.0      # ankle forward over the ball: loaded, the low point
	var stilt_load_at := 0.3    # of the stance
	var stilt_push := -22.0     # ankle well forward: the stilt in line with the driving leg
	var stilt_kick := -25.0     # extra fold early in the swing: the heel coming up behind
	var swing_lift := 0.8       # heel height the swing adds on top of the toe-off height
	var swing_lift_shape := 1.15  # > 1: lifts slowly, peaks late, comes down firmly
	var swing_start_slope := -8.0 # ball z velocity per swing unit leaving the floor
	var swing_end_slope := -2.0   # and arriving: no visible paw-back
	var swing_warp := 0.35      # slow out of the push-off, fast through the passing pose
	# --- arms: each arm's forward peak is exactly the opposite foot's plant, held through the low
	# contact pose and quick through the middle - the legs' rhythm, not a sine.
	var arm_fwd := 30.0
	var arm_back := -25.0
	var elbow_fwd := 95.0       # absolute bend between upper arm and forearm
	var elbow_back := 80.0
	var adduct_fwd := 12.0      # forward fist in toward the chest's centreline
	var abduct_back := 8.0      # back fist out past the hip
	var hand_curl := 10.0
	var arm_hold := 2.0         # tanh sharpness: higher flattens the swing's ends into longer holds
	var forearm_lag_frames := 1.0
	var jolt_shoulder := 2.5    # each plant's impact up through the frame: shoulders drop
	var jolt_elbow := 4.0       # and the forearms sag
	var jolt_time := 0.04       # seconds to the jolt's peak

## The 14 m/s sprint: the 2026-10-13 numbers, unchanged.
static func sprint() -> Gait:
	return Gait.new()

## The 9 m/s run: the sprint's body, upright and unhurried. 5.4 m steps, 0.42 s on each foot.
static func run() -> Gait:
	var g := Gait.new()
	g.clip = "MECH_run"
	g.speed = 9.0
	g.length = 1.2
	g.contact = 0.42
	g.hip_low = 4.12
	g.hip_high = 4.28
	g.hip_low_at = 0.08
	g.hip_sway = 0.12
	g.lean = 4.0
	g.lean_bob = 0.6
	g.hip_yaw = 4.0
	g.hip_roll = 3.0
	g.chest_counter = 5.0
	g.chest_lag = 0.06
	g.stride_front = 1.6
	g.plate_land = 10.0
	g.pivot_from = 0.6
	g.plate_push = -25.0
	g.stilt_load = -4.0
	g.stilt_push = -15.0
	g.stilt_kick = -18.0
	g.swing_lift = 0.6
	g.swing_lift_shape = 1.1
	g.swing_start_slope = -6.0
	g.swing_warp = 0.3
	g.arm_fwd = 18.0
	g.arm_back = -14.0
	g.elbow_fwd = 55.0
	g.elbow_back = 48.0
	g.adduct_fwd = 6.0
	g.abduct_back = 4.0
	g.hand_curl = 6.0
	g.arm_hold = 1.6
	g.forearm_lag_frames = 1.5
	g.jolt_shoulder = 1.5
	g.jolt_elbow = 2.5
	g.jolt_time = 0.05
	return g

# Bones the poses drive. Everything else holds its MECH_standing value.
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

# --- curves -----------------------------------------------------------------------

static func smooth(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func _hermite(p0: float, m0: float, p1: float, m1: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return ((2.0 * t3 - 3.0 * t2 + 1.0) * p0 + (t3 - 2.0 * t2 + t) * m0
		+ (-2.0 * t3 + 3.0 * t2) * p1 + (t3 - t2) * m1)

## The thigh heads' midpoint height above the floor at cycle phase `u`. Repeats every step: lowest
## hip_low_at after each plant, highest half way through the flight, a half cosine between.
static func hip_height(g: Gait, u: float) -> float:
	var half := g.length * 0.5
	var high_at := g.contact + (half - g.contact) * 0.5
	var s := fposmod(u * g.length, half)
	if s < g.hip_low_at:
		s += half
	var amp := g.hip_high - g.hip_low
	if s < high_at:
		return g.hip_low + amp * 0.5 * (1.0 - cos(PI * (s - g.hip_low_at) / (high_at - g.hip_low_at)))
	return g.hip_high - amp * 0.5 * (1.0 - cos(PI * (s - high_at) / (half + g.hip_low_at - high_at)))

## The hips' sideways shift over the planted foot at phase `u`, metres, + = the left (+X).
static func hip_sway(g: Gait, u: float) -> float:
	return g.hip_sway * cos(TAU * (u - g.hip_sway_peak))

## The right arm's swing at phase `u`: +1 forward at the left foot's plant, -1 back at the right's.
## The left arm is its negative. A tanh flattens the ends into holds and speeds up the middle.
static func arm_swing(g: Gait, u: float) -> float:
	return tanh(g.arm_hold * cos(TAU * u)) / tanh(g.arm_hold)

## The latest plant's impact travelling up the frame at phase `u`, 0..1: peaks jolt_time after
## each plant, settled by about four times that.
static func jolt(g: Gait, u: float) -> float:
	var t := fposmod(u * g.length, g.length * 0.5) / g.jolt_time
	return t * exp(1.0 - t)

## The ball (the sole plate's back edge) when the plate's floor contact is at `flat_z` - where the
## ball would be with the plate flat. Tip up, the plate rocks on its back edge, which stays down;
## heel up, it pivots on its tip, which stays down, and the ball rises. Returns (z, height).
static func ball_on_floor(flat_z: float, plate_deg: float, plate_len: float) -> Vector2:
	if plate_deg >= 0.0:
		return Vector2(flat_z, 0.0)
	var a := deg_to_rad(plate_deg)
	return Vector2(flat_z + plate_len - plate_len * cos(a), -plate_len * sin(a))

## One foot at cycle phase `p` (0 = its plant): the ball's z relative to the hip anchor and height
## above the floor, the sole plate's pitch (degrees, + = tip up), the stilt's lean (degrees, + =
## ankle behind the ball) and whether it is on the floor. `plate_len` is the plate's length in the
## side view.
static func leg_state(g: Gait, p: float, plate_len: float) -> Dictionary:
	p = fposmod(p, 1.0)
	var cf := g.contact / g.length
	if p < cf:
		var w := p / cf
		# Planted: the floor contact moves back through the mech at exactly the body's speed.
		var flat_z := g.stride_front - g.speed * p * g.length
		var plate := 0.0
		if w < g.plate_flat_by:
			plate = lerpf(g.plate_land, 0.0, smooth(w / g.plate_flat_by))
		elif w > g.pivot_from:
			var k := (w - g.pivot_from) / (1.0 - g.pivot_from)
			plate = g.plate_push * k * k
		var stilt := (lerpf(g.stilt_land, g.stilt_load, smooth(w / g.stilt_load_at))
			if w < g.stilt_load_at
			else lerpf(g.stilt_load, g.stilt_push, smooth((w - g.stilt_load_at) / (1.0 - g.stilt_load_at))))
		var b := ball_on_floor(flat_z, plate, plate_len)
		return {z = b.x, h = b.y, plate = plate, stilt = stilt, planted = true}
	# The swing, from the toe-off pose to the next plant. Warped so it leaves slowly, as if lifting
	# a load, and whips through the passing pose; the lift peaks late and comes down firmly.
	var q := (p - cf) / (1.0 - cf)
	var start := ball_on_floor(g.stride_front - g.speed * g.contact, g.plate_push, plate_len)
	var x := q - g.swing_warp * sin(PI * q) / PI
	var kick := 6.75 * q * (1.0 - q) * (1.0 - q)   # peaks at 1 a third of the way through
	return {
		z = _hermite(start.x, g.swing_start_slope, g.stride_front, g.swing_end_slope, x),
		h = start.y * (1.0 - smooth(q)) + g.swing_lift * sin(PI * pow(q, g.swing_lift_shape)),
		plate = lerpf(g.plate_push, g.plate_land, smooth(q / 0.85)),
		stilt = lerpf(g.stilt_push, g.stilt_land, smooth(q)) + g.stilt_kick * kick,
		planted = false,
	}

static func _rx(deg: float) -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(deg))

static func _ry(deg: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(deg))

static func _rz(deg: float) -> Basis:
	return Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(deg))

# --- the context: the standing pose, worked out once ------------------------------

## The standing pose in mech space and each bone's rigid local offset from its parent, plus the
## standing values every pose spec is relative to.
class Context extends RefCounted:
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
	var stand_hip_h := 0.0          # the thigh heads' midpoint above the floor
	var idx: Dictionary = {}
	# Per side (".L" / ".R"):
	var stand_ball_z: Dictionary = {}   # ball z relative to hip_z
	var stand_stilt: Dictionary = {}    # stilt lean, degrees, + = ankle behind the ball
	var stand_elbow: Dictionary = {}    # elbow bend, degrees
	var pole: Dictionary = {}           # the knee's side of the hip-ankle line, unit, mech space
	var plate_len: Dictionary = {}      # the sole plate's length in the side view

static func context(sk: Skeleton3D, standing: Animation) -> Context:
	var ctx := Context.new()
	var locals := locals_at(sk, standing, 0.0)
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
	var g := ctx.g0
	var idx := ctx.idx
	ctx.floor_y = minf(g[idx["toe.L.001"]].origin.y, g[idx["toe.R.001"]].origin.y)
	ctx.hip_z = (g[idx["thigh.L"]].origin.z + g[idx["thigh.R"]].origin.z) * 0.5
	ctx.stand_hip_h = (g[idx["thigh.L"]].origin.y + g[idx["thigh.R"]].origin.y) * 0.5 - ctx.floor_y
	for s in [".L", ".R"]:
		var tip: Vector3 = g[idx["toe" + s + ".001"]].origin
		var ankle: Vector3 = g[idx["foot" + s]].origin
		var knee: Vector3 = g[idx["shin" + s]].origin
		var hip: Vector3 = g[idx["thigh" + s]].origin
		ctx.stand_ball_z[s] = tip.z - ctx.hip_z
		var v_up := ankle - tip
		ctx.stand_stilt[s] = rad_to_deg(atan2(-v_up.z, v_up.y))
		var base := (ankle - hip).normalized()
		var off := (knee - hip) - base * base.dot(knee - hip)
		ctx.pole[s] = off.normalized() if off.length() > 0.001 else Vector3(0.0, 0.0, 1.0)
		var pv := plate_vector(ctx, s)
		ctx.plate_len[s] = Vector2(pv.y, pv.z).length()
		var f: int = idx["forearm" + s]
		var h: int = idx["hand" + s]
		var ua: int = ctx.parent[f]
		var up_dir: Vector3 = (g[f].origin - g[ua].origin).normalized()
		var fa_dir: Vector3 = (g[h].origin - g[f].origin).normalized()
		ctx.stand_elbow[s] = rad_to_deg(up_dir.angle_to(fa_dir))
	return ctx

## The sole plate, ball to tip, standing, in mech space. The tip is where the unparented
## `toe.*.002` IK leftover sits; without it, the plate bone's own axis at the measured 0.86 m.
static func plate_vector(ctx: Context, side: String) -> Vector3:
	var tip: int = ctx.idx["toe" + side + ".001"]
	if ctx.idx.has("toe" + side + ".002"):
		var v: Vector3 = ctx.g0[ctx.idx["toe" + side + ".002"]].origin - ctx.g0[tip].origin
		if v.length() > 0.1:
			return v
	return ctx.g0[tip].basis.y.normalized() * 0.86

# --- the pose spec -----------------------------------------------------------------

## The standing pose as a spec. Every other pose starts from a copy of this. Fields:
##   hip_h          thigh heads' midpoint above the floor, metres (absolute)
##   sway, hip_dz   the hips' shift sideways (+ = left) and forward, metres
##   lean, yaw, roll  the hips' rotation, degrees: + lean = forward, yaw about up, roll about the nose
##   counter        spine.001's yaw against the hips, degrees
##   shoulder_drop  both shoulders, degrees
##   arms[side]     {pitch (+ forward), elbow (+ more bend), adduct (+ in), curl}, degree deltas
##   feet[side]     {z (ball, relative to the standing hip z), h (ball above the floor),
##                   plate (+ tip up, deg), stilt (absolute lean, deg)}
static func standing_spec(ctx: Context) -> Dictionary:
	var arms := {}
	var feet := {}
	for s in [".L", ".R"]:
		arms[s] = {pitch = 0.0, elbow = 0.0, adduct = 0.0, curl = 0.0}
		feet[s] = {z = ctx.stand_ball_z[s], h = 0.0, plate = 0.0, stilt = ctx.stand_stilt[s]}
	return {hip_h = ctx.stand_hip_h, sway = 0.0, hip_dz = 0.0, lean = 0.0, yaw = 0.0, roll = 0.0,
		counter = 0.0, shoulder_drop = 0.0, arms = arms, feet = feet}

## A deep copy of `spec`, so a pose function can edit it freely.
static func copy_spec(spec: Dictionary) -> Dictionary:
	return spec.duplicate(true)

## Mixes two specs field by field: `w` = 0 is `a`, 1 is `b`.
static func mix_spec(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := copy_spec(a)
	for key in a:
		if a[key] is float:
			out[key] = lerpf(a[key], b[key], w)
	for group in ["arms", "feet"]:
		for s in a[group]:
			for key in a[group][s]:
				out[group][s][key] = lerpf(a[group][s][key], b[group][s][key], w)
	return out

## The cycle at phase `u` in [0, 1) as a spec. u = 0 is the left foot's plant.
static func gait_spec(ctx: Context, g: Gait, u: float) -> Dictionary:
	var spec := standing_spec(ctx)
	var h := hip_height(g, u)
	var bob := clampf(((g.hip_low + g.hip_high) * 0.5 - h) / ((g.hip_high - g.hip_low) * 0.5), -1.0, 1.0)
	spec.hip_h = h
	spec.sway = hip_sway(g, u)
	spec.lean = g.lean + g.lean_bob * bob
	spec.yaw = -g.hip_yaw * cos(TAU * u)
	spec.roll = g.hip_roll * cos(TAU * (u - g.hip_roll_peak))
	spec.counter = g.chest_counter * cos(TAU * (u - g.chest_lag / g.length))
	var j := jolt(g, u)
	spec.shoulder_drop = g.jolt_shoulder * j
	var swing_r := arm_swing(g, u)
	var swing_r_fore := arm_swing(g, u - g.forearm_lag_frames / FPS / g.length)
	for s in [".L", ".R"]:
		var side := 1.0 if s == ".L" else -1.0
		# The left arm is the right arm's opposite: at the left plant the right is forward.
		var f := (-swing_r * side + 1.0) * 0.5
		var f_fore := (-swing_r_fore * side + 1.0) * 0.5
		spec.arms[s] = {
			pitch = lerpf(g.arm_back, g.arm_fwd, f),
			adduct = lerpf(-g.abduct_back, g.adduct_fwd, f),
			# The numbers are the absolute angle; the standing elbow is already bent.
			elbow = lerpf(g.elbow_back, g.elbow_fwd, f_fore) - g.jolt_elbow * j - ctx.stand_elbow[s],
			curl = g.hand_curl * f_fore,
		}
		var st := leg_state(g, u if s == ".L" else u + 0.5, ctx.plate_len[s])
		spec.feet[s] = {z = st.z, h = st.h, plate = st.plate, stilt = st.stilt}
	return spec

# --- the solve ---------------------------------------------------------------------

## One pose from `spec`: the local rotation of every bone (skeleton space) and the spine's position
## track value. Also returns each leg's ball and plate tip targets (mech space) so a test can check
## them against what the clip really plays.
static func pose_from(ctx: Context, spec: Dictionary) -> Dictionary:
	var n := ctx.skeleton.get_bone_count()
	var idx := ctx.idx
	var ng: Array[Basis] = []
	var no: Array[Vector3] = []
	ng.resize(n)
	no.resize(n)

	# --- hips: pitch, yaw, roll, shift, and the height the spine's position track has to supply
	var target_hip: float = spec.hip_h + ctx.floor_y
	var hips := _ry(spec.yaw) * _rz(spec.roll) * _rx(spec.lean)
	var spine: int = ctx.spine
	var thigh_l: int = idx["thigh.L"]
	var thigh_r: int = idx["thigh.R"]
	var hips_basis := hips * ctx.g0[spine].basis
	var mid_off: Vector3 = (ctx.l0o[thigh_l] + ctx.l0o[thigh_r]) * 0.5
	var mid_y := ctx.g0[spine].origin.y + (hips_basis * mid_off).y
	var shift := Vector3(spec.sway, target_hip - mid_y, spec.hip_dz)
	var spine_origin: Vector3 = ctx.g0[spine].origin + shift
	var counter := _ry(spec.counter)

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
		var s := name.right(2)
		var side := 1.0 if s == ".L" else -1.0
		match name:
			"spine.001":
				basis = counter * inherited
			"spine.003":
				# The canopy undoes most of the lean and twist below it: the pilot's view stays level.
				var d_s1 := Quaternion((ng[p] * ctx.g0[p].basis.inverse()).orthonormalized())
				var part := d_s1.slerp(Quaternion.IDENTITY, CANOPY_CANCEL)
				basis = Basis(part) * ctx.g0[b].basis
			"shoulder.L", "shoulder.R":
				basis = _rz(-spec.shoulder_drop * side) * inherited
			"upper_arm.L", "upper_arm.R":
				var arm: Dictionary = spec.arms[s]
				basis = _rz(-arm.adduct * side) * _rx(-arm.pitch) * inherited
			"forearm.L", "forearm.R":
				basis = _rx(-spec.arms[s].elbow) * inherited
			"hand.L", "hand.R":
				basis = _rx(-spec.arms[s].curl) * inherited
			"thigh.L", "thigh.R":
				var leg := _solve_leg(ctx, s, spec.feet[s], no[b])
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

# spine.003 undoes this share of the lean and twist below it.
const CANOPY_CANCEL := 0.7

## Solves one leg to its foot spec. Returns the explicit global bases of thigh, shin, foot, toe and
## sole plate, and the ball and plate-tip targets. `hip` is the thigh's solved head.
##
## The knee bends in the plane the standing pose's knee sits in (ctx.pole), so the standing foot
## spec gives back MECH_standing's leg exactly.
static func _solve_leg(ctx: Context, s: String, foot_spec: Dictionary, hip: Vector3) -> Dictionary:
	var thigh: int = ctx.idx["thigh" + s]
	var shin: int = ctx.idx["shin" + s]
	var foot: int = ctx.idx["foot" + s]
	var toe: int = ctx.idx["toe" + s]
	var tip: int = ctx.idx["toe" + s + ".001"]
	var plate_vec := plate_vector(ctx, s)

	var ball := Vector3(ctx.g0[tip].origin.x, ctx.floor_y + foot_spec.h, ctx.hip_z + foot_spec.z)
	# The stilt (foot + toe, ankle to ball) leans as one piece about the ball.
	var v_up: Vector3 = ctx.g0[foot].origin - ctx.g0[tip].origin
	var tilt := _rx(-(foot_spec.stilt - ctx.stand_stilt[s]))
	var ankle := ball + tilt * v_up
	var plate := _rx(-foot_spec.plate)

	var a: float = (ctx.g0[shin].origin - ctx.g0[thigh].origin).length()
	var b: float = (ctx.g0[foot].origin - ctx.g0[shin].origin).length()
	var to_ankle := ankle - hip
	# Out of reach: the leg straightens and the foot comes up short rather than the solve
	# going to NaN. The tests hold every key inside the reach.
	var d := clampf(to_ankle.length(), 0.3, (a + b) * 0.998)
	var base := to_ankle.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var alpha := acos(cos_a)
	var pole: Vector3 = ctx.pole[s]
	var perp := pole - base * base.dot(pole)
	perp = perp.normalized() if perp.length() > 0.001 else Vector3(0.0, 0.0, 1.0)
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

# --- the bake ----------------------------------------------------------------------

## Keys `spec_at` - a Callable(ctx, t_seconds) -> spec - into a clip on `skeleton`, 30 fps. A loop's
## last key equals its first. Track paths come off `standing` so they match the AnimationPlayer's
## root; every bone gets a rotation track, the spine and every bone standing keys a position on get
## position tracks, and standing's scale tracks are held.
static func bake(ctx: Context, standing: Animation, length: float, loop: bool,
		spec_at: Callable) -> Animation:
	var skeleton := ctx.skeleton
	var clip := Animation.new()
	clip.length = length
	clip.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	clip.step = 1.0 / FPS

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

	var frames := maxi(int(round(length * FPS)), 1)
	for k in frames + 1:
		var t := float(k) / FPS
		var t_spec := float(k % frames) / FPS if loop else minf(t, length)
		var pose := pose_from(ctx, spec_at.call(ctx, t_spec))
		t = minf(t, length)
		for b in bones:
			clip.rotation_track_insert_key(rot_tracks[b], t, pose.rot[b])
			if pos_tracks.has(b):
				clip.position_track_insert_key(pos_tracks[b], t,
					pose.spine_pos if b == ctx.spine else ctx.base_locals[b].origin)
			if scale_tracks.has(b):
				clip.scale_track_insert_key(scale_tracks[b], t,
					base_scales.get(skeleton.get_bone_name(b), Vector3.ONE))
	return clip

## Builds `g`'s cycle as a looping clip.
static func build(ctx: Context, standing: Animation, g: Gait) -> Animation:
	return bake(ctx, standing, g.length, true,
		func(c: Context, t: float) -> Dictionary: return gait_spec(c, g, t / g.length))
