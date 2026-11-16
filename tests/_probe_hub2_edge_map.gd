extends SceneTree

# Throwaway probe (headless ok): dumps Hub2RoofDoor's edge-dusting map (rev 1) as a PNG of the
# distance on each cell's highest drop-edged level, plus lip counts and bake time.
var _f := 0
var _t := 0
func _initialize() -> void:
	change_scene_to_file("res://scenes/hub2.tscn")
func _process(_d: float) -> bool:
	_f += 1
	if _f == 3:
		_t = Time.get_ticks_msec()
	var door := current_scene.get_node_or_null("RoofDoor") as Hub2RoofDoor if current_scene != null else null
	if door == null or door.edge_dists == null:
		return _f > 3000
	print("EDGE baked by ", Time.get_ticks_msec() - _t, " ms after frame 3, frames ", _f, " size ", door.edge_dists.get_size(), " lips ", door.edge_lips)
	var img := door.edge_dists
	var hi := door.edge_heights
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	var levels := {}
	for z in h:
		for x in w:
			var d := img.get_pixel(x, z)
			var y := hi.get_pixel(x, z)
			var best := minf(minf(d.r, d.g), minf(d.b, d.a))
			out.set_pixel(x, z, Color(1.0 - best / 1.5, 0.2 if y.g > -999 else 0.0, 0.0))
			for c in [y.r, y.g, y.b, y.a]:
				if c > -999:
					levels[int(round(c))] = levels.get(int(round(c)), 0) + 1
	var ks := levels.keys()
	ks.sort()
	for k in ks:
		if levels[k] > 150:
			print("  y ", k, ": ", levels[k])
	out.save_png(OS.get_cmdline_user_args()[0] + "/edge_d.png")
	return true
