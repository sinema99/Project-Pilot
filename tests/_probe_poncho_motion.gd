extends SceneTree

## Drives a bare Pilot9Poncho lattice (no skeleton, no colliders) through scripted body motion and
## prints the hem's peak and settled offsets, for tuning the "Poncho" group by numbers.
##   godot --headless --path . --script tests/_probe_poncho_motion.gd

const DT := 1.0 / 60.0

func _initialize() -> void:
	# name -> velocity at each frame time t (body translation only).
	_run("run start 0 -> 7.5", func(t: float) -> Vector3: return Vector3(0, 0, 7.5) if t > 0.2 else Vector3.ZERO)
	_run("run stop 7.5 -> 0", func(t: float) -> Vector3: return Vector3(0, 0, 7.5) if t < 0.2 else Vector3.ZERO)
	_run("landing 10 m/s", func(t: float) -> Vector3: return Vector3(0, -10.0 + 9.8 * 0.0, 0) if t < 0.2 else Vector3.ZERO)
	_run("free fall from rest", func(t: float) -> Vector3: return Vector3(0, -9.8 * maxf(t - 0.2, 0.0), 0))
	_run("steady 20 m/s", func(_t: float) -> Vector3: return Vector3(0, 0, 20))
	_run("steady 40 m/s", func(_t: float) -> Vector3: return Vector3(0, 0, 40))
	_run("dash 7.5 -> 40 for 0.25 s", func(t: float) -> Vector3: return Vector3(0, 0, 40) if t > 0.2 and t < 0.45 else Vector3(0, 0, 7.5))
	_run("run bob 3 cm @ 2.5 Hz", func(t: float) -> Vector3: return Vector3(0, 0.03 * TAU * 2.5 * cos(TAU * 2.5 * t), 7.5))
	quit()

func _run(label: String, velocity: Callable) -> void:
	var p := Pilot9Poncho.new()
	var pos := Vector3.ZERO
	var peak := 0.0
	var peak_at := 0.0
	var last := Vector3.ZERO
	var t := 0.0
	var hem_c := 0 # front hem column
	var hem_i := (Pilot9Poncho.ROWS - 1) * Pilot9Poncho.COLS + hem_c
	var back_i := (Pilot9Poncho.ROWS - 1) * Pilot9Poncho.COLS + Pilot9Poncho.COLS / 2
	for f in 150:
		t = f * DT
		pos += velocity.call(t) * DT
		var targets := PackedVector3Array()
		targets.resize(Pilot9Poncho.N)
		for i in Pilot9Poncho.N:
			targets[i] = p.rest[i] + pos
		p.step(DT, targets, pos)
		var d := p.offsets()
		var m := maxf(d[hem_i].length(), d[back_i].length())
		if m > peak:
			peak = m
			peak_at = t
		last = d[back_i]
	print("%-28s peak hem %5.1f cm at %.2f s   back hem at 2.5 s %s cm" % [label, peak * 100.0,
		peak_at, (last * 100.0).snapped(Vector3(0.1, 0.1, 0.1))])
	p.free()
