## Finds the drawings of a walk / run cycle from the live pose, so ANIME's held drawings land on
## real foot plants whatever the blend. Pure logic, fed one value a frame by AnimePoseHold. See
## docs/specs/anime-animation.md, "Stride tracker".
##
## The signal is s = (left foot - right foot) . travel. Its peaks are the contacts (s > 0: the
## left foot is ahead) and its zero crossings the passing poses - the four quarter boundaries of a
## cycle. Each quarter shows drawings_per_cycle / 4 drawings: one on the boundary, the rest spaced
## by the last quarter's length.
class_name AnimeStride
extends RefCounted

## Metres. s must leave this band before a crossing counts, so jitter around zero cannot fire one.
const DEAD_BAND := 0.02
## A peak is called once s falls back from its extreme by this much, or by PEAK_FRACTION of the
## extreme if that is larger - about a frame after the true peak at run speed.
const PEAK_DROP := 0.01
const PEAK_FRACTION := 0.04
## Seconds with no boundary before a drawing is taken anyway and the tracker starts over.
const STALL := 0.4
## Quarter lengths outside this are not believed (a stall, or two boundaries a frame apart).
const QUARTER_MIN := 0.04

var drawings_per_cycle := 8
## The boundary that fired last: &"contact_l", &"contact_r", &"passing" or &"". Read by tests.
var last_event := &""

var _side := 0
var _extreme := 0.0
var _peak_called := false
var _last_boundary := -1.0
var _quarter := 0.15
var _between: Array[float] = []
var _last_drawing := -1.0


func reset() -> void:
	_side = 0
	_extreme = 0.0
	_peak_called = false
	_last_boundary = -1.0
	_between.clear()
	_last_drawing = -1.0
	last_event = &""


## One frame at time `now` with stride signal `s`. True when this frame shows a new drawing.
## Half a frame early (`delta`) counts as on time for the in-between drawings.
func update(now: float, s: float, delta: float = 0.0) -> bool:
	var boundary := false
	var mag := absf(s)
	if mag > DEAD_BAND:
		var side := 1 if s > 0.0 else -1
		if _side != 0 and side != _side:
			boundary = true
			last_event = &"passing"
			_extreme = mag
			_peak_called = false
		_side = side
	if mag >= _extreme:
		_extreme = mag
	elif not boundary and not _peak_called and _side != 0 and _extreme > DEAD_BAND 			and _extreme - mag >= maxf(PEAK_DROP, _extreme * PEAK_FRACTION):
		_peak_called = true
		boundary = true
		last_event = &"contact_l" if _side > 0 else &"contact_r"

	if boundary:
		if _last_boundary >= 0.0:
			var q := now - _last_boundary
			if q >= QUARTER_MIN and q < STALL:
				_quarter = q
		_last_boundary = now
		_between.clear()
		var per := maxi(int(drawings_per_cycle / 4.0), 1)
		for k in range(1, per):
			_between.append(now + _quarter * float(k) / float(per))
		return _drew(now)
	if not _between.is_empty() and now + delta * 0.5 >= _between[0]:
		_between.pop_front()
		return _drew(now)
	if _last_drawing >= 0.0 and now - _last_drawing > STALL:
		var keep := _last_drawing
		reset()
		_last_drawing = keep
		return _drew(now)
	if _last_drawing < 0.0:
		_last_drawing = now
	return false


func _drew(now: float) -> bool:
	_last_drawing = now
	return true
