extends RefCounted

# EXIA's non-cycle clips, built in code from pose specs. See docs/specs/exia-movement.md, "The clips".
#
# Every clip here is a function of time that returns a pose spec (mech_gait.gd's standing_spec, with
# fields changed), keyed by MechGait.bake(). The legs are solved, so a foot this file says is planted
# is planted. Clips that hand over to standing (the stop, the landing) end exactly on it, and the
# idle starts on it, so those joins need no crossfade to hide a pop.

const MechGait := preload("res://scripts/mech_gait.gd")

const STAND_IDLE := "MECH_stand_idle"
const TURN_STEP := "MECH_turn_step"
const STOP_L := "MECH_stop_L"
const STOP_R := "MECH_stop_R"
const JUMP_CROUCH := "MECH_jump_crouch"
const JUMP_AIR := "MECH_jump_air"
const LAND := "MECH_land"

# --- stand idle: breathing, 4 s. Every shape is 0 at u = 0, so frame 0 is the standing pose.
const IDLE_LENGTH := 4.0
const IDLE_BOB := 0.04          # hips down at the bottom of the breath
const IDLE_SWAY := 0.03         # side to side
const IDLE_LEAN := 0.6
const IDLE_COUNTER := 1.0
const IDLE_ARM := 2.0
const IDLE_ELBOW := 1.5

# --- turn step: stepping on the spot, 1.0 s, R swings in the first half (L planted), L in the second.
const TURN_LENGTH := 1.0
const TURN_SWING := 0.4         # of each half: the rest is both feet down
const TURN_LIFT := 0.55
const TURN_PLATE := 8.0         # tip up as it comes down
const TURN_KICK := -10.0        # stilt fold while it is up
const TURN_SWAY := 0.1          # hips over the planted foot
const TURN_DIP := 0.06
const TURN_ARM := 4.0

# --- stop: authored for a stop from the run speed. The body brakes linearly over STOP_TIME, and the
# lead foot is locked to the floor while it does.
const STOP_LENGTH := 1.0
const STOP_SPEED := 9.0
const STOP_TIME := 0.4
const STOP_TRAIL_FROM := -1.2   # trail ball's start, relative to its standing z
const STOP_TRAIL_LIFT := 0.5    # and height
const STOP_TRAIL_PLANT := 0.3   # seconds: the trail foot is down
const STOP_RUN_HIP := 4.20      # the run's mean hip height and lean, where the stop starts
const STOP_RUN_LEAN := 4.0
const STOP_BRACE_LEAN := -4.0   # leaning back into the brake, by STOP_TRAIL_PLANT
const STOP_SETTLE_AT := 0.5     # the settle's low point
const STOP_SETTLE_DROP := 0.35  # below standing
const STOP_SETTLE_LEAN := 3.0   # the momentum carrying on over the feet
const STOP_ARM := 15.0          # arms forward on the brake
const STOP_ELBOW := 10.0

# --- jump
const CROUCH_TIME := 0.25
const CROUCH_DROP := 1.0
const CROUCH_BACK := 0.25
const CROUCH_LEAN := 12.0
const CROUCH_ARM := -25.0
const CROUCH_ELBOW := 15.0
const CROUCH_STILT := -8.0      # ankles forward over the balls: loaded
const AIR_LENGTH := 1.2
const AIR_DRIFT := 0.03
const LAND_LENGTH := 0.6
const LAND_CONTACT_DROP := 0.1
const LAND_DROP := 1.1
const LAND_DROP_AT := 0.12
const LAND_HOLD_TO := 0.2
const LAND_LEAN := 14.0
const LAND_BACK := 0.2
const LAND_ARM := -10.0
const LAND_ELBOW := 15.0
const LAND_JOLT := 4.0
const LAND_STILT := -8.0

## Every clip the mech builds, by name: the two gaits and everything in this file.
static func build_all(skeleton: Skeleton3D, standing: Animation) -> Dictionary:
	var ctx := MechGait.context(skeleton, standing)
	var out := {}
	for g in [MechGait.run(), MechGait.sprint()]:
		out[g.clip] = MechGait.build(ctx, standing, g)
	out[STAND_IDLE] = MechGait.bake(ctx, standing, IDLE_LENGTH, true,
		func(c, t: float) -> Dictionary: return stand_idle_spec(c, t))
	out[TURN_STEP] = MechGait.bake(ctx, standing, TURN_LENGTH, true,
		func(c, t: float) -> Dictionary: return turn_step_spec(c, t))
	out[STOP_L] = MechGait.bake(ctx, standing, STOP_LENGTH, false,
		func(c, t: float) -> Dictionary: return stop_spec(c, t, ".L"))
	out[STOP_R] = MechGait.bake(ctx, standing, STOP_LENGTH, false,
		func(c, t: float) -> Dictionary: return stop_spec(c, t, ".R"))
	out[JUMP_CROUCH] = MechGait.bake(ctx, standing, CROUCH_TIME, false,
		func(c, t: float) -> Dictionary: return crouch_spec(c, t))
	out[JUMP_AIR] = MechGait.bake(ctx, standing, AIR_LENGTH, true,
		func(c, t: float) -> Dictionary: return air_spec(c, t))
	out[LAND] = MechGait.bake(ctx, standing, LAND_LENGTH, false,
		func(c, t: float) -> Dictionary: return land_spec(c, t))
	return out

static func _other(s: String) -> String:
	return ".R" if s == ".L" else ".L"

static func _side(s: String) -> float:
	return 1.0 if s == ".L" else -1.0

# --- stand idle -----------------------------------------------------------------------

static func stand_idle_spec(ctx, t: float) -> Dictionary:
	var spec := MechGait.standing_spec(ctx)
	var u := t / IDLE_LENGTH
	var breath := (1.0 - cos(TAU * u)) * 0.5
	var drift := sin(TAU * u)
	spec.hip_h -= IDLE_BOB * breath
	spec.sway = IDLE_SWAY * drift
	spec.lean = IDLE_LEAN * breath
	spec.counter = IDLE_COUNTER * drift
	spec.arms[".L"].pitch = IDLE_ARM * drift
	spec.arms[".R"].pitch = -IDLE_ARM * drift
	spec.arms[".L"].elbow = IDLE_ELBOW * breath
	spec.arms[".R"].elbow = IDLE_ELBOW * breath
	return spec

# --- turn step ------------------------------------------------------------------------

## How far through its swing foot `s` is at phase `u`, 0..1, or -1 while it is down.
static func turn_swing(s: String, u: float) -> float:
	var start := 0.0 if s == ".R" else 0.5
	var p := fposmod(u - start, 1.0) / 0.5
	var lead := (1.0 - TURN_SWING) * 0.5
	if p < lead or p > lead + TURN_SWING:
		return -1.0
	return (p - lead) / TURN_SWING

## Which foot is down for the turn's pivot at phase `u`: the left through the first half (the right
## is the one stepping), the right through the second.
static func turn_pivot(u: float) -> String:
	return ".L" if fposmod(u, 1.0) < 0.5 else ".R"

static func turn_step_spec(ctx, t: float) -> Dictionary:
	var spec := MechGait.standing_spec(ctx)
	var u := t / TURN_LENGTH
	spec.sway = TURN_SWAY * sin(TAU * u)
	spec.hip_h -= TURN_DIP * (1.0 + cos(2.0 * TAU * u)) * 0.5
	for s in [".L", ".R"]:
		var q := turn_swing(s, u)
		if q >= 0.0:
			var arc := sin(PI * q)
			spec.feet[s].h = TURN_LIFT * arc
			spec.feet[s].plate = TURN_PLATE * arc
			spec.feet[s].stilt += TURN_KICK * arc
	spec.arms[".L"].pitch = TURN_ARM * sin(TAU * u)
	spec.arms[".R"].pitch = -TURN_ARM * sin(TAU * u)
	return spec

# --- stop -----------------------------------------------------------------------------

## The ground the body covers `t` seconds into a stop from `v0`: a linear brake over STOP_TIME.
static func stop_distance(t: float, v0: float = STOP_SPEED) -> float:
	var tt := clampf(t, 0.0, STOP_TIME)
	return v0 * (tt - tt * tt / (2.0 * STOP_TIME))

## The body's speed `t` seconds into a stop from `v0`.
static func stop_speed(t: float, v0: float = STOP_SPEED) -> float:
	return v0 * maxf(1.0 - t / STOP_TIME, 0.0)

## The stop with `lead` the foot planted ahead when the keys were let go. The lead ball is locked to
## the floor while the body slides past it; the trail foot swings through and plants on the same
## locked path; then the settle. Ends exactly on the standing pose.
static func stop_spec(ctx, t: float, lead: String) -> Dictionary:
	var spec := MechGait.standing_spec(ctx)
	var trail := _other(lead)
	var total := stop_distance(STOP_TIME)
	var locked := total - stop_distance(t)   # how far ahead of standing a planted ball is now

	var lf: Dictionary = spec.feet[lead]
	lf.z += locked
	lf.plate = lerpf(10.0, 0.0, MechGait.smooth(t / 0.08))
	lf.stilt = lerpf(12.0, ctx.stand_stilt[lead], MechGait.smooth(t / STOP_TIME))

	var tf: Dictionary = spec.feet[trail]
	if t < STOP_TRAIL_PLANT:
		var q := t / STOP_TRAIL_PLANT
		var land_z: float = tf.z + total - stop_distance(STOP_TRAIL_PLANT)
		tf.z = lerpf(tf.z + STOP_TRAIL_FROM, land_z, MechGait.smooth(q))
		tf.h = STOP_TRAIL_LIFT * (1.0 - q) + 0.4 * sin(PI * q)
		tf.plate = lerpf(-20.0, 8.0, MechGait.smooth(q))
		tf.stilt = lerpf(-10.0, 12.0, MechGait.smooth(q))
	else:
		var since := t - STOP_TRAIL_PLANT
		tf.z += locked
		tf.plate = lerpf(8.0, 0.0, MechGait.smooth(since / 0.06))
		tf.stilt = lerpf(12.0, ctx.stand_stilt[trail], MechGait.smooth(since / (STOP_LENGTH - STOP_TRAIL_PLANT)))

	var stand_h: float = spec.hip_h
	var arm := 0.0
	if t < STOP_TRAIL_PLANT:
		var w := MechGait.smooth(t / STOP_TRAIL_PLANT)
		spec.hip_h = lerpf(STOP_RUN_HIP, stand_h - 0.1, w)
		spec.lean = lerpf(STOP_RUN_LEAN, STOP_BRACE_LEAN, w)
		arm = MechGait.smooth(t / 0.35)
	elif t < STOP_SETTLE_AT:
		var w := MechGait.smooth((t - STOP_TRAIL_PLANT) / (STOP_SETTLE_AT - STOP_TRAIL_PLANT))
		spec.hip_h = lerpf(stand_h - 0.1, stand_h - STOP_SETTLE_DROP, w)
		spec.lean = lerpf(STOP_BRACE_LEAN, STOP_SETTLE_LEAN, w)
		arm = 1.0
	else:
		var w := MechGait.smooth((t - STOP_SETTLE_AT) / (STOP_LENGTH - STOP_SETTLE_AT))
		spec.hip_h = lerpf(stand_h - STOP_SETTLE_DROP, stand_h, w)
		spec.lean = lerpf(STOP_SETTLE_LEAN, 0.0, w)
		arm = 1.0 - w
	spec.sway = 0.1 * _side(lead) * (1.0 - MechGait.smooth(t / STOP_LENGTH))
	for s in [".L", ".R"]:
		spec.arms[s].pitch = STOP_ARM * arm
		spec.arms[s].elbow = STOP_ELBOW * arm
	return spec

## Which foot leads a stop begun at run phase `u` (0 = the left plant): the one that planted last,
## because it is the one ahead.
static func stop_lead(u: float) -> String:
	var p := fposmod(u + 0.25, 1.0)
	return ".L" if p < 0.5 else ".R"

# --- jump -----------------------------------------------------------------------------

static func crouch_spec(ctx, t: float) -> Dictionary:
	var spec := MechGait.standing_spec(ctx)
	var w := MechGait.smooth(t / CROUCH_TIME)
	spec.hip_h -= CROUCH_DROP * w
	spec.hip_dz = -CROUCH_BACK * w
	spec.lean = CROUCH_LEAN * w
	spec.shoulder_drop = 3.0 * w
	for s in [".L", ".R"]:
		spec.arms[s].pitch = CROUCH_ARM * w
		spec.arms[s].elbow = CROUCH_ELBOW * w
		spec.feet[s].stilt += CROUCH_STILT * w
	return spec

static func air_spec(ctx, t: float) -> Dictionary:
	var spec := MechGait.standing_spec(ctx)
	var d := sin(TAU * t / AIR_LENGTH)
	spec.hip_h += 0.05 * d
	spec.lean = 4.0
	var l: Dictionary = spec.feet[".L"]
	l.z += 0.8 * (1.0 + AIR_DRIFT * d)
	l.h = 0.7 * (1.0 + AIR_DRIFT * d)
	l.plate = -15.0
	l.stilt = 20.0
	var r: Dictionary = spec.feet[".R"]
	r.z -= 0.6 * (1.0 - AIR_DRIFT * d)
	r.h = 1.0 * (1.0 - AIR_DRIFT * d)
	r.plate = -25.0
	r.stilt = 30.0
	spec.arms[".L"] = {pitch = 6.0 + 3.0 * d, elbow = -10.0, adduct = -22.0, curl = 0.0}
	spec.arms[".R"] = {pitch = -14.0 - 3.0 * d, elbow = -10.0, adduct = -22.0, curl = 0.0}
	return spec

## How deep the landing has the hips at `t`, 0..1 of LAND_DROP below standing.
static func land_depth(t: float) -> float:
	if t < LAND_DROP_AT:
		var q := t / LAND_DROP_AT
		var ease_out := 1.0 - (1.0 - q) * (1.0 - q)
		return lerpf(LAND_CONTACT_DROP / LAND_DROP, 1.0, ease_out)
	if t < LAND_HOLD_TO:
		return 1.0
	return 1.0 - MechGait.smooth((t - LAND_HOLD_TO) / (LAND_LENGTH - LAND_HOLD_TO))

static func land_spec(ctx, t: float) -> Dictionary:
	var spec := MechGait.standing_spec(ctx)
	var k := land_depth(t)
	spec.hip_h -= LAND_DROP * k
	spec.hip_dz = -LAND_BACK * k
	spec.lean = LAND_LEAN * k
	var jolt_t := t / 0.05
	spec.shoulder_drop = LAND_JOLT * jolt_t * exp(1.0 - jolt_t)
	for s in [".L", ".R"]:
		spec.arms[s].pitch = LAND_ARM * k
		spec.arms[s].elbow = LAND_ELBOW * k
		spec.feet[s].stilt += LAND_STILT * k
	return spec
