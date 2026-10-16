class_name IntroSpaceLightning
extends RefCounted

# The storm's lightning schedule (docs/specs/cutscene-intro-space.md, "Effects pass"). Built once
# from a seed, then asked "what is flashing at shot time t", so the same time always shows the
# same flashes (seekable, testable). Flashes live in the storm's own turning frame (storm-local
# degrees, see planet_earth.gdshaderinc::earth_storm_local), so they stay on the storm.
#
# Each flash flickers: 2-3 pulses inside ~0.2 s, each a sharp rise and quick decay. Some set off a
# neighbour a moment later (a chain). Steady from the first frame, building through the ship's
# dive; the shot ends on one big flash (the sting) placed by intro_space.gd where the ship is
# heading. Flashes sit on the storm's layers ("Storm eye rebuild"): the eyewall, the three inner
# rain bands (turning with them), and now and then the outer arm.

# Storm layout, as fractions of the storm radius. Must match planet_earth.gdshaderinc's defaults.
const EYE_RADIUS := 0.2
const WALL_RADIUS := 0.45
const BAND_INNER := 0.56
const BAND_OUTER := 1.05
const BAND_PITCH := 2.6

## One flash: when it starts, where (storm-local degrees), radius (degrees), peak brightness, and
## its pulses (offsets in seconds from `start`).
class Flash:
	var start := 0.0
	var pos := Vector2.ZERO
	var radius := 1.0
	var peak := 1.0
	var pulses := PackedFloat32Array()

	## Brightness at shot time `t` (0 = dark).
	func brightness_at(t: float, decay: float) -> float:
		var b := 0.0
		for i in pulses.size():
			var dt := t - (start + pulses[i])
			if dt >= 0.0 and dt < decay * 6.0:
				# Later pulses are a little weaker.
				b = maxf(b, exp(-dt / decay) * (1.0 - 0.18 * i))
		return b * peak

	func end_time(decay: float) -> float:
		return start + pulses[pulses.size() - 1] + decay * 6.0


var flashes: Array[Flash] = []
## The final sting, once add_sting ran. intro_space.gd moves it to where the ship is heading.
var sting: Flash
## Seconds each pulse takes to fade to a third.
var decay := 0.03


## Builds the schedule. Rate (flashes per second) is `rate_early` until `ramp_start`, then rises
## smoothly to `rate_late` at `ramp_end`; no ordinary flashes after `last`. `storm_radius` in
## degrees places them on the storm's layers; `band_spin_rate` (deg/s) keeps band flashes on the
## turning bands.
func build(seed_: int, rate_early: float, rate_late: float, ramp_start: float, ramp_end: float,
		last: float, storm_radius: float, chain_chance: float, band_spin_rate := 0.0) -> void:
	flashes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var t := rng.randf_range(0.2, 1.0)
	while t < last:
		var f := _flash(rng, t, _storm_spot(rng, storm_radius, band_spin_rate * t))
		flashes.append(f)
		if rng.randf() < chain_chance:
			var off := Vector2.from_angle(rng.randf() * TAU) * f.radius * rng.randf_range(1.2, 2.2)
			flashes.append(_flash(rng, t + rng.randf_range(0.05, 0.12), f.pos + off))
		var rate := lerpf(rate_early, rate_late, smoothstep(ramp_start, ramp_end, t))
		# Poisson gaps, clamped so two never land on the same frame.
		t += maxf(0.04, -log(maxf(rng.randf(), 1e-4)) / rate)


## Adds the final sting: a big, long flicker starting at `start`.
func add_sting(start: float, pos: Vector2, radius: float, peak: float) -> void:
	var f := Flash.new()
	f.start = start
	f.pos = pos
	f.radius = radius
	f.peak = peak
	f.pulses = PackedFloat32Array([0.0, 0.07, 0.13, 0.24])
	flashes.append(f)
	sting = f


## The brightest `slots` flashes at shot time `t`, as Vector4(x, y, radius, brightness), padded
## with dark entries.
func active_at(t: float, slots: int) -> Array[Vector4]:
	var live: Array[Vector4] = []
	for f in flashes:
		if t < f.start or t > f.end_time(decay):
			continue
		var b := f.brightness_at(t, decay)
		if b > 0.01:
			live.append(Vector4(f.pos.x, f.pos.y, f.radius, b))
	live.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.w > b.w)
	live.resize(mini(live.size(), slots))
	while live.size() < slots:
		live.append(Vector4.ZERO)
	return live


func _flash(rng: RandomNumberGenerator, start: float, pos: Vector2) -> Flash:
	var f := Flash.new()
	f.start = start
	f.pos = pos
	f.radius = rng.randf_range(0.9, 1.9)
	f.peak = rng.randf_range(0.6, 1.0)
	f.pulses = PackedFloat32Array([0.0, rng.randf_range(0.05, 0.09)])
	if rng.randf() < 0.6:
		f.pulses.append(rng.randf_range(0.13, 0.2))
	return f


# A spot on the eyewall (45%), along one of the three inner rain bands (45%, turned `band_turn`
# degrees with them) or on the outer arm (10%), storm-local degrees. A band's crest is where
# cos(3 * (angle + log(r) * BAND_PITCH)) = 1, the outer arm's where cos(angle + log(r) * 2.6) = 1.
func _storm_spot(rng: RandomNumberGenerator, storm_radius: float, band_turn := 0.0) -> Vector2:
	var sr: float
	var ang: float
	var pick := rng.randf()
	if pick < 0.45:
		sr = rng.randf_range(EYE_RADIUS * 1.1, WALL_RADIUS)
		ang = rng.randf() * TAU
	elif pick < 0.9:
		sr = rng.randf_range(BAND_INNER + 0.05, BAND_OUTER - 0.1)
		ang = -log(sr) * BAND_PITCH + rng.randi_range(0, 2) * TAU / 3.0 + rng.randf_range(-0.12, 0.12)
		ang += deg_to_rad(band_turn)
	else:
		sr = rng.randf_range(0.95, 1.3)
		ang = -log(sr) * 2.6 + rng.randf_range(-0.3, 0.3)
	return Vector2.from_angle(ang) * sr * storm_radius
