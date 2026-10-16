## The firing range's running totals: what the dummy took, what pilot took, and the DPS over the
## last few seconds. Pure data - the HUD only reads it. See docs/specs/firing-range.md.
extends RefCounted

## Seconds of damage the DPS readout averages over.
const DPS_WINDOW := 3.0

var damage_dealt: float = 0.0
var hits_on_dummy: int = 0
var hits_taken: int = 0
var reflects_perfect: int = 0
var reflects_normal: int = 0

# [time, amount] pairs inside the DPS window.
var _recent: Array = []


func reset() -> void:
	damage_dealt = 0.0
	hits_on_dummy = 0
	hits_taken = 0
	reflects_perfect = 0
	reflects_normal = 0
	_recent.clear()


func record_dummy_hit(amount: float, now: float) -> void:
	damage_dealt += amount
	hits_on_dummy += 1
	_recent.append([now, amount])


func record_pilot_hit() -> void:
	hits_taken += 1


func record_reflect(perfect: bool) -> void:
	if perfect:
		reflects_perfect += 1
	else:
		reflects_normal += 1


## Damage per second over the last DPS_WINDOW seconds ending at `now`.
func dps(now: float) -> float:
	while not _recent.is_empty() and now - float(_recent[0][0]) > DPS_WINDOW:
		_recent.pop_front()
	var sum := 0.0
	for e in _recent:
		sum += float(e[1])
	return sum / DPS_WINDOW
