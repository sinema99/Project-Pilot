extends SceneTree

# Throwaway probe, headless: the rev 5 panel swing through a scripted drive (stand, run start, run,
# sprint, release + stop, jump, land), drawn as a chart. The speed ramps are mech.gd's; the footfall
# cadence is approximate (0.35 s run, 0.3 s sprint). See docs/specs/exia-back-panels.md "Rev 5".
#   godot --headless --path . --script tests/_probe_mech_panels_sway_trace.gd -- <out.png>

const Panels := preload("res://scripts/mech_back_panels.gd")
const DT := 1.0 / 60.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://sway_trace.png"
	# [label, seconds, accel m/s^2, footfall interval (0 none), footfall sprinting, kick at start]
	var phases := [
		["stand", 1.0, 0.0, 0.0, false, 0.0],
		["run start", 0.6, 15.0, 0.35, false, 0.0],
		["run", 2.0, 0.0, 0.35, false, 0.0],
		["sprint ramp", 0.5, 10.0, 0.3, true, 0.0],
		["sprint", 2.0, 0.0, 0.3, true, 0.0],
		["release", 0.5, -10.0, 0.3, true, 0.0],
		["stop", 0.4, -22.5, 0.0, false, 0.0],
		["stand", 2.0, 0.0, 0.0, false, 0.0],
		["jump", 1.2, 0.0, 0.0, false, Panels.SWAY_TAKEOFF_KICK],
		["land", 2.5, 0.0, 0.0, false, Panels.land_kick(3.0, 3.0)],
	]
	var st := Vector2.ZERO
	var acc := 0.0
	var samples: PackedFloat32Array = []
	var marks: Array = []
	for ph: Array in phases:
		marks.append([samples.size(), ph[0]])
		st.y += float(ph[5])
		var n := int(round(float(ph[1]) / DT))
		var since := 0.0
		var lo := INF
		var hi := -INF
		for i in n:
			if float(ph[3]) > 0.0:
				since += DT
				if since >= float(ph[3]):
					since = 0.0
					st.y += Panels.footfall_kick(ph[4])
			acc = Panels.smooth_accel(acc, float(ph[2]), DT)
			st = Panels.step_sway(st, Panels.sway_drive(acc, 0.0), DT)
			samples.append(st.x)
			lo = minf(lo, st.x)
			hi = maxf(hi, st.x)
		print("%-12s min %6.2f  max %6.2f  end %6.2f deg" % [ph[0], lo, hi, st.x])
	var w := samples.size() * 2
	var h := 400
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.08, 0.08, 0.1))
	var y_of := func(deg: float) -> int: return clampi(int(h * 0.5 - deg * 30.0), 0, h - 1)
	for x in w:
		img.set_pixel(x, y_of.call(0.0), Color(0.4, 0.4, 0.4))
		img.set_pixel(x, y_of.call(Panels.SWAY_OUT_CAP_DEG), Color(0.6, 0.3, 0.3))
		img.set_pixel(x, y_of.call(-Panels.SWAY_IN_CAP_DEG), Color(0.3, 0.3, 0.7))
	for m: Array in marks:
		for y in h:
			img.set_pixel(int(m[0]) * 2, y, Color(0.25, 0.25, 0.3))
	for i in samples.size() - 1:
		var y0: int = y_of.call(samples[i])
		var y1: int = y_of.call(samples[i + 1])
		for y in range(mini(y0, y1), maxi(y0, y1) + 1):
			img.set_pixel(i * 2, y, Color(1, 0.85, 0.3))
			img.set_pixel(i * 2 + 1, y, Color(1, 0.85, 0.3))
	print("saved ", out, " ", img.save_png(out))
	quit()
