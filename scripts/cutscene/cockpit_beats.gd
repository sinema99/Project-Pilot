class_name CockpitBeats
extends RefCounted

# The cockpit shot's ending as pure functions of shot time: the WARNING panel popping up on the big
# jolt, his glance at it, the left-hand backhand that flicks it away, the hand back on the stick, and
# both sticks pushed forward. CockpitReentry applies it. See docs/specs/cutscene-cockpit.md,
# "Ending: warning swipe and push".
#
# Seat space throughout: +Z his facing, +X his left, origin under the pan.

## Shot times of the two method keys (`warning()`, `push()`); INF = never.
var warning_time := INF
var push_time := INF
## When the ship answers the push (push_time + the answer delay); INF = never.
var answer_time := INF

## Seconds after the warning before the hand lets go of the stick.
var react := 1.0
## Pop-open: line to full height.
var open := 0.12
## Stick to the panel's inner edge.
var reach := 0.22
## The flick across: contact to gone, panel and hand together.
var flick := 0.25
## Follow-through hang at the end of the flick.
var hang := 0.15
## Back to the stick.
var back := 0.45
## His head snaps to the warning this long after it opens, over glance_in.
var glance_delay := 0.08
var glance_in := 0.15
## Head back to the front over this, from when the hand starts back.
var glance_out := 0.35
## The sticks' tilt over this.
var push_duration := 0.25
var stick_tilt := deg_to_rad(20.0)
## The push lean in three beats: he winds up to windup_lean over `windup` before the push (head
## tucked by head_tuck), drives to push_lean with the sticks, and the ship's answer presses him back
## to pushback_lean over `pushback`, held.
var windup := 0.3
var windup_lean := deg_to_rad(18.0)
var push_lean := deg_to_rad(22.0)
var pushback := 0.3
var pushback_lean := deg_to_rad(12.0)
var head_tuck := deg_to_rad(8.0)
## His torso turns toward the panel this much while he looks at it.
var torso_turn := deg_to_rad(5.0)
## The cartoon "!" by his head: pops in with the head snap over startle_pop, overshooting to
## startle_overshoot, and hard-cuts out startle_hold after it appeared.
var startle_pop := 0.1
var startle_hold := 0.55
var startle_overshoot := 1.3

## The warning panel's centre (seat space) and where his head is; set from the scene.
var panel_point := Vector3(0.3, 1.22, 0.37)
var head_point := Vector3(0.0, 1.15, -0.15)
## The left wrist's rest target (on the grip).
var wrist_rest := Vector3(0.4, 0.78, 0.33)
## The flinch: with the head snap the left forearm comes up to guard his chest, the wrist here (seat
## space, in front of his left shoulder), over guard_in with a guard_overshoot share of overshoot, and
## holds until the swipe leaves from it.
var guard_point := Vector3(0.26, 1.0, 0.2)
var guard_in := 0.12
var guard_overshoot := 0.1
## Half the panel's width: the hand starts the flick this far in from the centre.
var panel_half_width := 0.15
## How far past the panel's centre the flick carries the hand and the panel.
var throw_distance := 0.4
## The hand stays this far in front of the panel's face (toward his head).
var hand_clearance := 0.04


## The panel's pop-open, 0 (a line) -> 1 (full height). 0 before the warning.
func warning_open(t: float) -> float:
	return _smooth((t - warning_time) / open)


## The flick: 0 until contact, 1 when the panel is gone.
func warning_gone(t: float) -> float:
	return _ease_out((t - _flick_start()) / flick)


## True while any of the panel shows.
func warning_visible(t: float) -> bool:
	return t >= warning_time and warning_gone(t) < 1.0


## Where the panel sits (seat space) on its way out: thrown outward with the hand.
func warning_offset(t: float) -> Vector3:
	return outward() * throw_distance * 1.1 * warning_gone(t)


## The left wrist's target, seat space.
func left_wrist(t: float) -> Vector3:
	var s0 := warning_time + react
	var s1 := s0 + reach
	var s2 := s1 + flick
	var s3 := s2 + hang
	var s4 := s3 + back
	var a := _contact()
	var b := _flick_end()
	if t >= s4:
		return wrist_rest
	if t <= s0:
		return wrist_rest.lerp(guard_point, guard(t))
	if t < s1:
		return guard_point.lerp(a, _smooth((t - s0) / reach))
	if t < s2:
		return a.lerp(b, _ease_out((t - s1) / flick))
	if t < s3:
		return b + outward() * 0.03 * _smooth((t - s2) / hang)
	var u := _smooth((t - s3) / back)
	var from := b + outward() * 0.03
	# A little arc on the way down, so it swings back rather than sliding.
	return from.lerp(wrist_rest, u) + Vector3(0.0, 0.05, 0.0) * sin(u * PI)


## The flinch guard: 0 on the stick -> 1 up in front of his chest, with a little overshoot, held until
## the swipe. Starts with the head snap.
func guard(t: float) -> float:
	var u := (t - _startle_start()) / guard_in
	if u <= 0.0:
		return 0.0
	if u < 1.0:
		return _ease_out(u) * (1.0 + guard_overshoot)
	# Settle the overshoot back over another guard_in.
	return 1.0 + guard_overshoot * (1.0 - _smooth(u - 1.0))


## 0..1: how far his head (and torso) has turned to the warning.
func glance(t: float) -> float:
	var on := _smooth((t - warning_time - glance_delay) / glance_in)
	var off := _smooth((t - (_flick_start() + flick + hang)) / glance_out)
	return on * (1.0 - off)


## The head's turn to the warning, euler radians in seat axes (yaw toward his left = +Y).
func head_look(t: float) -> Vector3:
	var d := panel_point - head_point
	var yaw := atan2(d.x, d.z)
	var pitch := -atan2(d.y, Vector2(d.x, d.z).length())
	return Vector3(pitch, yaw, 0.0) * glance(t) + Vector3(head_tuck * wind_up(t), 0.0, 0.0)


## True while the "!" shows: from the head snap, startle_hold long, then a hard cut.
func startle_visible(t: float) -> bool:
	var u := t - _startle_start()
	return u >= 0.0 and u < startle_hold


## The "!"'s scale: 0 -> startle_overshoot -> 1 over startle_pop, then 1. 0 when hidden.
func startle_scale(t: float) -> float:
	if not startle_visible(t):
		return 0.0
	var u := clampf((t - _startle_start()) / startle_pop, 0.0, 1.0)
	if u < 0.5:
		return startle_overshoot * _smooth(u * 2.0)
	return lerpf(startle_overshoot, 1.0, _smooth(u * 2.0 - 1.0))


## 0..1..0 over the pop: the "!"'s little hop up.
func startle_bounce(t: float) -> float:
	if not startle_visible(t):
		return 0.0
	return sin(clampf((t - _startle_start()) / startle_pop, 0.0, 1.0) * PI)


## The spine's extra lean (euler radians, seat axes): the turn to the panel, then the push lean.
func body(t: float) -> Vector3:
	return Vector3(lean(t), torso_turn * glance(t), 0.0)


## The push's forward lean, radians: wind-up, drive, pressed back.
func lean(t: float) -> float:
	var back := _ease_out((t - answer_time) / pushback)
	return windup_lean * wind_up(t) + (push_lean - windup_lean) * push(t) - (push_lean - pushback_lean) * back


## 0..1: the wind-up before the push, eased in, held.
func wind_up(t: float) -> float:
	return _smooth((t - (push_time - windup)) / windup)


## 0..1: the sticks' tilt forward, eased in, held.
func push(t: float) -> float:
	return _smooth((t - push_time) / push_duration)


## The sticks' forward tilt, radians round seat X (top toward his facing).
func stick_angle(t: float) -> float:
	return stick_tilt * push(t)


## Outward to his left, in the panel's plane (sideways, square to the line to his head).
func outward() -> Vector3:
	var to_head := (head_point - panel_point).normalized()
	var o := Vector3.RIGHT - to_head * Vector3.RIGHT.dot(to_head)
	return o.normalized()


func _startle_start() -> float:
	return warning_time + glance_delay


func _flick_start() -> float:
	return warning_time + react + reach


func _contact() -> Vector3:
	var to_head := (head_point - panel_point).normalized()
	return panel_point - outward() * panel_half_width + to_head * hand_clearance


func _flick_end() -> Vector3:
	var to_head := (head_point - panel_point).normalized()
	return panel_point + outward() * throw_distance + to_head * hand_clearance + Vector3(0.0, 0.02, 0.0)


static func _smooth(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


static func _ease_out(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 3.0)
