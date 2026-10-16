extends SceneTree

# Bakes the Earth texture for the intro cutscene planet (docs/specs/cutscene-intro-space.md,
# "Planet upgrade") from a NOAA ETOPO1 crop, so only the part of the Earth the camera sees gets
# detail. Input: an ESRI ASCII grid from ERDDAP (public domain), e.g.
#   https://coastwatch.pfeg.noaa.gov/erddap/griddap/etopo180.esriAscii?altitude[(-8):3:(52)][(-142):3:(-32)]
# Run:
#   godot --headless --path . --script tools/gen_planet_earth.gd -- <grid.asc>
# The crop box must match EARTH_LAT / EARTH_LON in shaders/space/planet_earth.gdshaderinc; the
# box itself comes from tools/gen_planet_earth_frame.gd ("visible box") plus a margin.
#
# Channels (8 bit each, linear):
#   R  elevation, signed square root: 0.5 = sea level, 0 = -OCEAN_DEPTH, 1 = +LAND_HEIGHT. The root
#      keeps the fine steps near sea level, where the coast and shelf bands are cut.
#   G  land height smoothed, linear 0..LAND_HEIGHT (ocean 0). The shaders take normals from it.
#   B  mountain mask: local relief (height above its 300 km surroundings), so ranges shade and
#      high flat plateaus do not.

const OUT := "res://assets/textures/planet_earth_na.png"
const OCEAN_DEPTH := 6000.0
const LAND_HEIGHT := 4500.0
# Relief above this many metres is a full-strength mountain in B.
const RELIEF_FULL := 900.0
const SMOOTH_RADIUS := 1
const RELIEF_RADIUS := 30


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() > 0, "pass the ETOPO grid: -- <grid.asc>")
	var f := FileAccess.open(args[0], FileAccess.READ)
	assert(f != null, "cannot open " + args[0])
	var header := {}
	for i in 6:
		var parts := f.get_line().strip_edges().split(" ", false)
		header[parts[0].to_lower()] = parts[1].to_float()
	var w := int(header["ncols"])
	var h := int(header["nrows"])
	print("grid %d x %d, lower-left (%s, %s), cell %s" % [w, h, header["xllcenter"],
			header["yllcenter"], header["cellsize"]])
	var elev := PackedFloat32Array()
	elev.resize(w * h)
	for y in h:
		var row := f.get_line().split_floats(" ", false)
		assert(row.size() == w, "row %d has %d values" % [y, row.size()])
		for x in w:
			elev[y * w + x] = row[x]
	f.close()

	var land := PackedFloat32Array()
	land.resize(w * h)
	for i in w * h:
		land[i] = maxf(elev[i], 0.0)
	var smooth := _box_blur(_box_blur(land, w, h, SMOOTH_RADIUS), w, h, SMOOTH_RADIUS)
	var wide := _box_blur(_box_blur(smooth, w, h, RELIEF_RADIUS), w, h, RELIEF_RADIUS)
	var relief := PackedFloat32Array()
	relief.resize(w * h)
	for i in w * h:
		relief[i] = clampf((smooth[i] - wide[i]) / RELIEF_FULL, 0.0, 1.0) if elev[i] > 0.0 else 0.0
	relief = _box_blur(relief, w, h, 3)

	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := y * w + x
			var e := elev[i]
			var r := 0.5 + 0.5 * (sqrt(minf(e / LAND_HEIGHT, 1.0)) if e >= 0.0
					else -sqrt(minf(-e / OCEAN_DEPTH, 1.0)))
			img.set_pixel(x, y, Color(r, clampf(smooth[i] / LAND_HEIGHT, 0.0, 1.0),
					relief[i], 1.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	img.save_png(OUT)
	print("saved ", OUT)
	quit()


# Separable box blur with a running sum, clamped at the edges.
func _box_blur(src: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	var inv := 1.0 / float(2 * r + 1)
	for y in h:
		var row := y * w
		var sum := 0.0
		for k in range(-r, r + 1):
			sum += src[row + clampi(k, 0, w - 1)]
		for x in w:
			tmp[row + x] = sum * inv
			sum += src[row + mini(x + r + 1, w - 1)] - src[row + maxi(x - r, 0)]
	var out := PackedFloat32Array()
	out.resize(w * h)
	for x in w:
		var sum := 0.0
		for k in range(-r, r + 1):
			sum += tmp[clampi(k, 0, h - 1) * w + x]
		for y in h:
			out[y * w + x] = sum * inv
			sum += tmp[mini(y + r + 1, h - 1) * w + x] - tmp[maxi(y - r, 0) * w + x]
	return out
