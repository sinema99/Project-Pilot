class_name StormBeats
extends RefCounted

# The cockpit storm shot as pure functions of shot time: the storm's ramp (calm to storm), how far the
# snow has streamed, gusts, lightning, the route panel popping up and taking two taps, his right hand
# doing the taps, his left hand pressing three slots on the button strip, his head turning to the panel.
# CockpitStormDriver applies it. See docs/specs/cutscene-cockpit-storm.md.
#
# Seat space throughout: +Z his facing, +X his left, origin under the pan.

## The blizzard eases in from ramp_start and is full at ramp_end.
var ramp_start := 3.0
var ramp_end := 7.0
## How fast the snow streams into the vanishing point, log-angle units a second. One cruise speed for
## the whole shot: the ship never speeds up, it only flies into heavier weather.
var cruise_rate := 0.6
## The way the ship flies (sphere space; the snow streams away from it): his facing, so the vanishing
## point, its antipode, is directly behind him (seat -Z), level. Fixed all shot.
var ahead := Vector3(0.0, 0.0, 1.0)
## Lightning strikes, shot seconds.
var lightning_times := PackedFloat32Array([7.5, 9.0])

## The route panel: pops open, folds shut.
var route_pop := 1.0
var route_open := 0.12
var route_close := 2.7
var route_fold := 0.15
## The right hand: off the stick, to the panel, two taps, back.
var right_leave := 1.3
var right_reach := 0.4
var taps := PackedFloat32Array([1.9, 2.4])
var right_back := 0.5
## The left hand: off the stick, three presses on the strip, back.
var left_leave := 3.5
var left_reach := 0.25
var presses := PackedFloat32Array([3.85, 4.15, 4.45])
var left_back := 0.45
## A tap or press: hand in this long before the moment, out over press_out.
var press_in := 0.07
var press_out := 0.1
## How deep a tap or press goes, metres.
var press_depth := 0.025
## His head turns to the panel this long after it pops, over glance_in; back when it folds. A
## relaxed pilot's reaction, not a snap.
var glance_delay := 0.3
var glance_in := 0.45
var glance_out := 0.4
## A little glance down and to his left while the left hand presses the strip: not all the way to
## the buttons. Euler radians in seat axes (down = +X, his left = +Y). In this long after the hand
## leaves the stick, over strip_glance_in; out over strip_glance_out after the last press.
var strip_look := Vector3(deg_to_rad(12.0), deg_to_rad(9.0), 0.0)
var strip_glance_delay := 0.1
var strip_glance_in := 0.3
var strip_glance_out := 0.4

## Set from the scene: the wrists' rests on the grips, the panel's centre and its two buttons, the
## strip slots he presses, his head, and which way is "into" the panel and "down" onto the strip.
var right_rest := Vector3(-0.4, 0.78, 0.33)
var left_rest := Vector3(0.4, 0.78, 0.33)
var panel_point := Vector3(-0.46, 1.36, 0.42)
var buttons: Array[Vector3] = [Vector3(-0.46, 1.38, 0.42), Vector3(-0.46, 1.33, 0.42)]
var slots: Array[Vector3] = [Vector3(0.472, 0.672, 0.337), Vector3(0.472, 0.672, 0.379),
		Vector3(0.472, 0.672, 0.421)]
var head_point := Vector3(0.0, 1.15, -0.15)
## The wrist sits this far off a button (back toward his shoulder) when the fist touches it...
var tap_offset := Vector3(0.0, -0.06, -0.08)
## ...and this far off a strip slot.
var press_offset := Vector3(-0.02, 0.05, -0.06)


## 0 = calm light snow, 1 = full storm. Smooth in and out.
func storm(t: float) -> float:
	return _smooth((t - ramp_start) / (ramp_end - ramp_start))


## How far the snow has streamed by t (the shader's `travel`): the cruise speed, never changing.
func travel(t: float) -> float:
	return cruise_rate * t


## The way the snow streams from, sphere space: dead ahead, all shot.
func source_dir(_t: float) -> Vector3:
	return ahead.normalized()


## 0..1 gusts, only in the storm: three slow incommensurate swells.
func gust(t: float) -> float:
	var g := 0.5 + 0.25 * sin(t * 2.3) + 0.15 * sin(t * 3.7 + 1.1) + 0.1 * sin(t * 6.1 + 2.3)
	return clampf(g, 0.0, 1.0) * storm(t)


## 0..1 lightning: a hard pop, a dip, a second smaller pop, gone in half a second.
func flash(t: float) -> float:
	var f := 0.0
	for strike in lightning_times:
		var s := t - strike
		if s < 0.0:
			continue
		var pop := exp(-s / 0.07)
		var second := 0.7 * exp(-(s - 0.14) / 0.12) if s >= 0.14 else 0.0
		f = maxf(f, maxf(pop, second))
	return clampf(f, 0.0, 1.0)


## The route panel's pop-open, 0 (a line) -> 1 (full height) -> 0 again as it folds.
func route_amount(t: float) -> float:
	return _smooth((t - route_pop) / route_open) * (1.0 - _smooth((t - route_close) / route_fold))


func route_visible(t: float) -> bool:
	return t >= route_pop and t < route_close + route_fold


## How many of its buttons have been tapped by t.
func route_taps(t: float) -> int:
	var n := 0
	for tap in taps:
		if t >= tap:
			n += 1
	return n


## The confirm flash on the last tap: 1 at once, fading over about a quarter second.
func route_confirm(t: float) -> float:
	var s := t - taps[taps.size() - 1]
	return exp(-s / 0.12) if s >= 0.0 else 0.0


## Which strip slots are lit by t (they stay lit).
func slot_lit(t: float, i: int) -> bool:
	return i < presses.size() and t >= presses[i]


## The right wrist's target, seat space.
func right_wrist(t: float) -> Vector3:
	var keys: Array = [[right_leave, right_rest]]
	var into := _into_panel()
	for i in taps.size():
		var hover := buttons[i] + tap_offset
		var press := hover + into * press_depth
		var tap := taps[i]
		keys.append([right_leave + right_reach if i == 0 else tap - press_in - 0.06, hover])
		keys.append([tap - press_in, hover])
		keys.append([tap, press])
		keys.append([tap + press_out, hover])
	keys.append([route_close, buttons[buttons.size() - 1] + tap_offset])
	keys.append([route_close + right_back, right_rest])
	return _keyed(t, keys)


## The left wrist's target, seat space.
func left_wrist(t: float) -> Vector3:
	var keys: Array = [[left_leave, left_rest]]
	for i in presses.size():
		var hover := slots[i] + press_offset
		var press := hover + Vector3.DOWN * press_depth
		var p := presses[i]
		keys.append([left_leave + left_reach if i == 0 else p - press_in - 0.08, hover])
		keys.append([p - press_in, hover])
		keys.append([p, press])
		keys.append([p + press_out, hover])
	var last := presses[presses.size() - 1] + press_out
	keys.append([last + left_back, left_rest])
	return _keyed(t, keys)


## 0..1: how far his head has turned to the route panel.
func glance(t: float) -> float:
	var on := _smooth((t - route_pop - glance_delay) / glance_in)
	var off := _smooth((t - route_close) / glance_out)
	return on * (1.0 - off)


## The head's turn to the panel, euler radians in seat axes (yaw toward his left = +Y).
func head_look(t: float) -> Vector3:
	var d := panel_point - head_point
	var yaw := atan2(d.x, d.z)
	var pitch := -atan2(d.y, Vector2(d.x, d.z).length())
	return Vector3(pitch, yaw, 0.0) * glance(t) + strip_look * strip_glance(t)


## 0..1: how far into his little glance down at the strip.
func strip_glance(t: float) -> float:
	var on := _smooth((t - left_leave - strip_glance_delay) / strip_glance_in)
	var off := _smooth((t - presses[presses.size() - 1] - press_out) / strip_glance_out)
	return on * (1.0 - off)


# Into the panel's face: from his head toward it.
func _into_panel() -> Vector3:
	return (panel_point - head_point).normalized()


# Position through [time, point] keys, eased between each pair (so it settles at every key), with a
# small lift on the long moves so the hand arcs instead of sliding. Before the first key and after
# the last it holds.
static func _keyed(t: float, keys: Array) -> Vector3:
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		var t1: float = keys[i][0]
		if t < t1:
			var t0: float = keys[i - 1][0]
			var a: Vector3 = keys[i - 1][1]
			var b: Vector3 = keys[i][1]
			var u := _smooth((t - t0) / maxf(t1 - t0, 1e-4))
			var lift := 0.06 * sin(u * PI) * clampf(a.distance_to(b) / 0.3, 0.0, 1.0)
			return a.lerp(b, u) + Vector3(0.0, lift, 0.0)
	return keys[keys.size() - 1][1]


static func _smooth(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)
