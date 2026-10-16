class_name CockpitShake
extends RefCounted

# The cockpit's re-entry shake as pure functions of shot time: a fine buzz all shot, plus jolts
# that kick the seat and settle. Everything that reacts to it (seat, camera tremor, his spine and
# head, the hologram panels, the red flashes, the fire flare) samples it here, so R replays it
# exactly and tests can sample any instant. See docs/specs/cutscene-cockpit.md, "Atmosphere pass".
#
# Seat space throughout: +Z his facing, +X his left, origin under the pan.

## Seat rotations happen round this point (about hip height), not the floor under the seat.
const PIVOT := Vector3(0.0, 0.5, 0.0)
## The spine chain's effective lever (shorter than the torso: the bend is shared up three bones):
## a kick of d metres throws his head about throw * d.
const TORSO := 0.3

## Each jolt's direction (move) and tilt axis, by its index on the track. Mostly up, each a
## different side, so three hits never look like one repeated.
const KICK_DIRS: Array[Vector3] = [Vector3(0.5, 0.8, -0.25), Vector3(-0.7, 0.6, 0.2), Vector3(0.35, 1.0, 0.3)]
const KICK_AXES: Array[Vector3] = [Vector3(0.3, 0.0, 1.0), Vector3(-0.5, 0.0, -1.0), Vector3(1.0, 0.0, -0.6)]

# Buzz frequencies (Hz): three per axis, incommensurate so it never visibly loops.
const BUZZ_HZ := [15.3, 17.9, 19.7]

## Buzz: metres and radians at its peak.
var buzz_move := 0.005
var buzz_tilt := deg_to_rad(0.4)
## A strength-1.0 jolt's kick.
var kick_move := 0.05
var kick_tilt := deg_to_rad(3.0)
## Seconds for a jolt to settle on the seat. The body and panels take longer (softer springs).
var settle := 0.3
## His head swings this many times the seat's kick, opposite it.
var body_throw := 1.5
## Head nod in the buzz, radians.
var head_wobble := deg_to_rad(0.6)

## The ship's answer to the sticks going forward: from surge_time it ramps up over surge_ramp and
## holds. INF = never.
var surge_time := INF
var surge_ramp := 0.35
## The buzz grows by this share at full surge.
var surge_buzz := 0.3
## The fire closes over the wake over this, from surge_time.
var swallow_ramp := 0.5

## [{time, strength, dir, axis}], sorted by time.
var jolts: Array[Dictionary] = []


## Fills `jolts` from (time, strength) pairs, giving each its direction by index.
func set_jolts(times: PackedFloat32Array, strengths: PackedFloat32Array) -> void:
	jolts.clear()
	for i in times.size():
		jolts.append({
			time = times[i], strength = strengths[i],
			dir = KICK_DIRS[i % KICK_DIRS.size()].normalized(),
			axis = KICK_AXES[i % KICK_AXES.size()].normalized(),
		})
	jolts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)


## The seat's shake as a transform in seat space (apply on top of its rest).
func seat_offset(t: float) -> Transform3D:
	return _offset(seat_motion(t))


## The panels' shake: the same buzz, the jolts through a softer, later spring, so they trail.
func panel_offset(t: float) -> Transform3D:
	return _offset(_motion(t, settle * 1.4, 1.0))


## {move: Vector3, rot: Vector3 (euler radians)} of the seat at t. The camera takes a share of it.
func seat_motion(t: float) -> Dictionary:
	return _motion(t, settle, 1.0)


## His spine's lean off the seat (euler radians, seat axes): thrown opposite each kick, back with
## an overshoot. Hands and feet stay put: the arms are solved after this.
func body_sway(t: float) -> Vector3:
	var sway := Vector3.ZERO
	for j: Dictionary in jolts:
		var k: float = kick_shape(t - j.time, settle * 2.0) * j.strength * body_throw
		var d: Vector3 = j.dir * kick_move
		# Up-kick folds him forward a little; sideways and fore-aft throw him the other way.
		sway.x += k * (-d.z + d.y * 0.5) / TORSO
		sway.z += k * d.x / TORSO
		sway -= j.axis * kick_tilt * j.strength * kick_shape(t - j.time, settle * 2.0) * 0.5
	return sway


## The head's extra rotation on the neck: whiplash on the jolts plus a small nod in the buzz.
func head_sway(t: float) -> Vector3:
	var nod := Vector3(
		sin(TAU * 6.3 * t) * 0.6 + sin(TAU * 8.9 * t + 1.7) * 0.4,
		0.0,
		sin(TAU * 7.4 * t + 0.6) * 0.6 + sin(TAU * 5.1 * t + 2.9) * 0.4) * head_wobble
	var whip := Vector3.ZERO
	for j: Dictionary in jolts:
		var k: float = kick_shape(t - j.time - 0.04, settle * 2.0) * j.strength * body_throw * 0.6
		var d: Vector3 = j.dir * kick_move
		whip.x += k * (-d.z + d.y * 0.5) / TORSO
		whip.z += k * d.x / TORSO
	return nod + whip


## 1.0 on a jolt, fading over about half a second: the panels' red warnings and the alarm lamp.
func flash(t: float) -> float:
	var f := 0.0
	for j: Dictionary in jolts:
		var s: float = t - j.time
		if s >= 0.0:
			f = maxf(f, exp(-s / 0.4))
	return f


## 1.0 for the first couple of frames after each jolt: the panels tear and flicker.
func glitch(t: float) -> float:
	for j: Dictionary in jolts:
		var s: float = t - j.time
		if s >= 0.0 and s < 0.07:
			return 1.0
	return 0.0


## 0..1: the ship's answer to the push, eased in, held to the end.
func surge(t: float) -> float:
	var u := clampf((t - surge_time) / surge_ramp, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## 0..1: the fire closing over the wake as the ship answers, eased, held to the end.
func swallow(t: float) -> float:
	var u := clampf((t - surge_time) / swallow_ramp, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## The fire's flare: jumps by the jolt's strength and dies over a quarter second.
func flare(t: float) -> float:
	var f := 0.0
	for j: Dictionary in jolts:
		var s: float = t - j.time
		if s >= 0.0:
			f += j.strength * exp(-s / 0.25)
	return f


## A kick that peaks at 1.0 almost at once, swings back about a fifth and has settled by `settle_s`.
## 0 before it starts.
static func kick_shape(s: float, settle_s: float) -> float:
	if s <= 0.0:
		return 0.0
	var tau := settle_s / 4.0
	var w := TAU / (settle_s * 0.8)
	var s_peak := atan(w * tau) / w
	var peak := exp(-s_peak / tau) * sin(w * s_peak)
	return exp(-s / tau) * sin(w * s) / peak


## A vector buzz around zero, about +/-1 per axis.
static func buzz(t: float, noise_seed: float) -> Vector3:
	var v := Vector3.ZERO
	for axis in 3:
		var n := 0.0
		var weights := [0.5, 0.3, 0.2]
		for i in 3:
			var hz: float = BUZZ_HZ[(i + axis) % 3] * (1.0 + 0.031 * axis)
			n += sin(TAU * hz * t + noise_seed * 1.7 + axis * 2.3 + i * 4.1) * weights[i]
		v[axis] = n
	return v


func _motion(t: float, settle_s: float, scale: float) -> Dictionary:
	var gain := 1.0 + surge_buzz * surge(t)
	var move := buzz(t, 0.0) * buzz_move * gain
	var rot := buzz(t, 7.0) * buzz_tilt * gain
	for j: Dictionary in jolts:
		var k: float = kick_shape(t - j.time, settle_s) * j.strength * scale
		move += j.dir * kick_move * k
		rot += j.axis * kick_tilt * k
	return {move = move, rot = rot}


static func _offset(m: Dictionary) -> Transform3D:
	var b := Basis.from_euler(m.rot)
	return Transform3D(b, PIVOT + m.move - b * PIVOT)
