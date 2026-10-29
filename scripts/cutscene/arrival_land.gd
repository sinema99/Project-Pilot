class_name ArrivalLand
extends Node3D

# The arrival shot's mountains (docs/specs/cutscene-arrival.md): one heightmap fanned out from the
# locked camera over its frustum, geometric rings from `near` to `far` so a cell is about the same
# size on screen everywhere. The near ridge the base is built into is shaped by ArrivalShot's CREST
# and HILLS tables. Past it the ranges come in three depth layers (spec R2-5: mid, main, far line),
# chains of warped ridged noise with uneven crests, one dominant massif in the main layer, and low
# foothills in the valleys between them (where the cloud sea pools).
#
# Filled per pixel by shaders/cutscene/arrival_terrain.gdshader. Where the forest grows is decided
# by the terrain (spec R2-2), `forest_score`: below the treeline, off the steeps and the flats, off
# the ridgelines (a per-vertex convexity, `ridges`), and out of the clearings. The clear map
# (`clear`) holds the clearings people and snow made: the base's aprons, the road, the power-line
# cut, the avalanche chutes (R), and the shade at the foot of the walls (G). A fine noise breaks the
# forest's edge up at tree scale. ArrivalForest reads the same rules to stand its spruce.
#
# GENERATED like DescentLand: children have no owner, so nothing is saved into the .tscn. Sits
# above Base and Forest in the tree, so it is built before they ask it for heights.

const TERRAIN_SHADER := preload("res://shaders/cutscene/arrival_terrain.gdshader")
const MASK_PIXELS := 512
## The range layers (spec R2-5): level distance of the chain (m), its half-width (m), and the low and
## high crest heights along it (m). Mid, main, far line.
const LAYERS := [
	[6500.0, 1900.0, -450.0, 150.0],
	[15000.0, 3800.0, -50.0, 600.0],
	[30000.0, 7000.0, 200.0, 1100.0],
]

@export var land_seed := 7
@export_group("Grid")
## Level distance (m) of the first and last ring, and the half-width of the fan (degrees).
@export var near := 350.0
@export var far := 45000.0
@export var half_angle_degrees := 34.0
## Columns across the fan; the rings are spaced to keep cells square.
@export var columns := 320

@export_group("Ridge")
## The near ridge's profile across the crest: a flat `shelf` (m) either side, then toward the camera
## it falls `front_drop` m with scale length `front_length`, away from it `back_drop` / `back_length`.
@export var shelf := 160.0
@export var front_drop := 650.0
@export var front_length := 1000.0
@export var back_drop := 900.0
@export var back_length := 1300.0

@export_group("Ranges")
## The ranges: valley floor (m), the foothills' tops between the layers (m), the ridged noise's
## feature size (m; stretched along the view so spurs run down toward the valleys), and how far its
## domain is warped (m).
@export var valley_floor := -1200.0
@export var foothill_top := -450.0
@export var range_size := 6000.0
@export var range_warp := 1800.0
## Ranges are kept off the base: they ramp in from this far either side of the crest (m).
@export var range_clear := 600.0
@export var range_full := 2600.0
## Gullies on every slope: size (m) and depth (m), fading out between these distances (m) so the far
## layers draw simpler.
@export var gully_size := 380.0
@export var gully_depth := 40.0
@export var gully_fade := Vector2(4000.0, 14000.0)

@export_group("Foot")
## Under the decks with a `sink` the land is pulled up to just below the underside band, then falls
## away from the band's line (under the overhang, so no flat shelf shows) at `foot_grade` (m down per
## m out), so the forest slope climbs into the base instead of the deck standing over it.
## `foot_blend` (m) rounds where it meets the ridge.
@export var foot_grade := 0.75
@export var foot_blend := 30.0

@export_group("Cover")
@export var snow_color := Color(0.82, 0.85, 0.9)
@export var rock_color := Color(0.3, 0.33, 0.38)
@export var forest_color := Color(0.09, 0.16, 0.17)
## A face whose normal's y is above this is snow (or forest), below it rock. Cleared ground holds snow
## down to `clear_snow`.
@export_range(0.0, 1.0, 0.01) var snow_threshold := 0.72
@export_range(0.0, 1.0, 0.01) var clear_snow := 0.55
## Forest grows on faces between these normal y's (steeper is rock, dead flat is open snow),
## thinning out over `tree_band` m up to the `treeline` (m), and off ridgelines (convexity from
## `ridge_clear`.x to .y clears it). The break-up noise (tiled every `mask_size` m, features about
## `forest_size` m) is what the score has to beat, so the edge is ragged at tree scale.
@export_range(0.0, 1.0, 0.01) var forest_min_slope := 0.58
@export_range(0.0, 1.0, 0.001) var forest_max_slope := 0.998
@export var treeline := 140.0
@export var tree_band := 260.0
@export var ridge_clear := Vector2(0.05, 0.14)
@export var mask_size := 600.0
@export var forest_size := 16.0

@export_group("Clearings")
## The clear map's world rect (x, z, width, depth) and size in pixels.
@export var clear_rect := Rect2(-3000.0, -4300.0, 6000.0, 4000.0)
@export var clear_pixels := Vector2i(1536, 1024)
## The apron cleared round every footprint (m past the deck edge, or past a tower's footing), and
## how far the wall's shade reaches out over the land (m).
@export var apron := 20.0
@export var ao_reach := 30.0
## The road's and the power-line cut's cleared width (m).
@export var road_width := 8.0
@export var cut_width := 16.0
## Avalanche chutes: how many, and their width at the top and the bottom (m).
@export var chutes := 18
@export var chute_width := Vector2(10.0, 36.0)

## Every vertex, its normal and its ridge value (convexity), kept for ArrivalForest.
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var ridges := PackedFloat32Array()
## Triangles as index triples.
var triangles := PackedInt32Array()
## The forest break-up noise, shared with the shader.
var mask: Image
## The clear map (R cleared, G wall shade), shared with the shader.
var clear: Image
## Where the road leaves the foundation (world, on the ground) and the way out of the wall (xz).
var portal: Vector3
var portal_out: Vector2
## The avalanche chutes as world xz polylines.
var chute_paths: Array[PackedVector2Array] = []

var _ranges := FastNoiseLite.new()
var _gullies := FastNoiseLite.new()
## Along each range layer: crest height, and the chain's wander toward and away from the camera.
var _chain := FastNoiseLite.new()
var _wander := FastNoiseLite.new()
## The massif's position along the main layer (m of arc).
var _massif_along := 0.0
## The crest as world (x, z, height) points, sorted by x.
var _crest: Array[Vector3] = []
## Hills as {at: world xz, top, radius, fall}, spurs also {dir, length, rise, steep}.
var _hills: Array[Dictionary] = []
## Deck feet as {poly: world xz outline, y: ground height inside it, box: Rect2 it can reach}.
var _feet: Array[Dictionary] = []
## Every deck with legs: {outer: its edge, band: its band line} (world xz), for the aprons.
var _footprints: Array[Dictionary] = []
## Every tower's foot: {at: world xz, shaft: radius}.
var _tower_feet: Array[Dictionary] = []


func _ready() -> void:
	var shot := get_parent() as ArrivalShot
	_setup(shot)
	_build_clear(shot)
	_build()


func _setup(shot: ArrivalShot) -> void:
	_ranges.seed = land_seed
	_ranges.noise_type = FastNoiseLite.TYPE_PERLIN
	_ranges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ranges.fractal_octaves = 4
	_ranges.frequency = 1.0 / range_size
	_ranges.domain_warp_enabled = true
	_ranges.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_ranges.domain_warp_amplitude = range_warp
	_ranges.domain_warp_frequency = 0.5 / range_size
	_chain.seed = land_seed + 3
	_chain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_chain.fractal_octaves = 3
	_chain.frequency = 1.0 / 7000.0
	_wander.seed = land_seed + 4
	_wander.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_wander.fractal_octaves = 2
	_wander.frequency = 1.0 / 9000.0
	_gullies.seed = land_seed + 1
	_gullies.noise_type = FastNoiseLite.TYPE_PERLIN
	_gullies.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_gullies.fractal_octaves = 3
	_gullies.frequency = 1.0 / gully_size
	var forest := FastNoiseLite.new()
	forest.seed = land_seed + 2
	forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest.fractal_octaves = 3
	forest.frequency = mask_size / (forest_size * MASK_PIXELS)
	mask = forest.get_seamless_image(MASK_PIXELS, MASK_PIXELS)
	mask.convert(Image.FORMAT_L8)
	for c: Vector3 in ArrivalShot.CREST:
		var p := shot.on_plane(c.x, c.y, 0.0)
		_crest.append(Vector3(p.x, p.z, c.z))
	_crest.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	var m := ArrivalShot.MASSIF
	var mp := shot.at_distance(m.u, 8.0, m.distance)
	_massif_along = atan2(mp.x, -mp.z) * LAYERS[1][0]
	for h: Dictionary in ArrivalShot.HILLS:
		var p := shot.at_distance(h.u, h.v, h.distance)
		var hill := {at = Vector2(p.x, p.z), top = h.top, radius = h.radius, fall = h.fall}
		if h.has("spur"):
			var toward := shot.at_distance(h.toward.x, h.toward.y, h.toward_distance)
			hill.dir = (Vector2(toward.x, toward.z) - hill.at).normalized()
			hill.length = h.spur
			hill.rise = h.rise
			hill.steep = h.steep
		_hills.append(hill)
	# The outpost's peak: its top just under the outpost deck's underside.
	var o := ArrivalShot.OUTPOST
	var op := shot.at_distance(o.u, o.v, o.distance)
	_hills.append({at = Vector2(op.x, op.z), top = op.y - ArrivalBase.OUTPOST_THICK - 10.0,
			radius = o.peak_radius, fall = o.peak_fall})
	for deck: Dictionary in ArrivalShot.DECKS:
		var outer := PackedVector2Array()
		for q: Vector2 in deck.outline:
			var w := shot.on_plane(q.x, q.y, deck.top)
			outer.append(Vector2(w.x, w.z))
		var poly: PackedVector2Array = Geometry2D.offset_polygon(outer, -float(deck.inset), Geometry2D.JOIN_MITER)[0]
		if deck.legs != &"":
			_footprints.append({outer = outer, band = poly})
		if deck.sink <= 0.0:
			continue
		var y: float = deck.top - deck.thick - deck.band - deck.sink
		var box := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			box = box.expand(q)
		_feet.append({poly = poly, y = y, box = box.grow((y - valley_floor) / foot_grade)})
	for t: Dictionary in ArrivalShot.TOWERS:
		var p := shot.at_distance(t.u, t.v, t.distance)
		_tower_feet.append({at = Vector2(p.x, p.z), shaft = t.shaft})


## The crest under world x: (z, height), straight between points and carried on past the ends.
func crest_at(x: float) -> Vector2:
	var i := 0
	while i < _crest.size() - 2 and x > _crest[i + 1].x:
		i += 1
	var a := _crest[i]
	var b := _crest[i + 1]
	var k := (x - a.x) / (b.x - a.x)
	return Vector2(lerpf(a.y, b.y, k), lerpf(a.z, b.z, k))


## Ground height (m) at world (x, z).
func height(x: float, z: float) -> float:
	var crest := crest_at(x)
	# + toward the camera (which is at z = 0, the scene at -z).
	var s := z - crest.x
	var off := maxf(absf(s) - shelf, 0.0)
	var ridge: float
	if s > 0.0:
		ridge = crest.y - front_drop * (1.0 - exp(-off / front_length))
	else:
		ridge = crest.y - back_drop * (1.0 - exp(-off / back_length))
	var h := ridge
	for hill in _hills:
		h = _smooth_max(h, _hill(hill, Vector2(x, z)), 60.0)
	var dist := Vector2(x, z).length()
	var keep_off := smoothstep(range_clear, range_full, absf(s))
	h = _smooth_max(h, lerpf(valley_floor, ranges_at(x, z), keep_off), 120.0)
	var g := _gullies.get_noise_2d(x, z) * 0.5 + 0.5
	h -= gully_depth * g * (1.0 - smoothstep(gully_fade.x, gully_fade.y, dist))
	# After the gullies, so none cuts in under a deck.
	for foot in _feet:
		if (foot.box as Rect2).has_point(Vector2(x, z)):
			h = _smooth_max(h, foot.y - foot_grade * _outside(foot.poly, Vector2(x, z)), foot_blend)
	return h


## A hill's height at `p`: a cone, or for a spur a ridge climbing from the top along its heading,
## widening as it goes, its right flank (as the camera sees it) steeper.
func _hill(hill: Dictionary, p: Vector2) -> float:
	var rel: Vector2 = p - hill.at
	if not hill.has("dir"):
		return hill.top - hill.fall * pow(rel.length() / hill.radius, 1.5)
	var dir: Vector2 = hill.dir
	var t := clampf(rel.dot(dir) / hill.length, 0.0, 1.0)
	var side: Vector2 = rel - dir * (t * hill.length)
	var right := Vector2(-dir.y, dir.x)
	var w: float = hill.radius * (1.0 + 1.5 * t) * (hill.steep if side.dot(right) > 0.0 else 1.0)
	var crest: float = hill.top + hill.rise * smoothstep(0.0, 1.0, t)
	return crest - hill.fall * pow(side.length() / w, 1.3)


## The ranges at world (x, z): low ridged foothills in the valleys, and over them the three layers'
## chains, each a band across the view whose crest height wanders along it (the massif standing out
## of the main one), shaped by the same warped ridged noise so spurs run down off every crest.
func ranges_at(x: float, z: float) -> float:
	var dist := Vector2(x, z).length()
	var a := atan2(x, -z)
	var r := clampf(_ranges.get_noise_2d(x, z * 0.45) * 0.5 + 0.5, 0.0, 1.0)
	var h := valley_floor + (foothill_top - valley_floor) * r
	for i in LAYERS.size():
		var layer: Array = LAYERS[i]
		var along: float = a * layer[0]
		var d: float = dist + _wander.get_noise_2d(along, i * 5000.0) * layer[1] * 0.5
		var e := clampf(1.0 - absf(d - layer[0]) / layer[1], 0.0, 1.0)
		if e <= 0.0:
			continue
		var k := clampf(_chain.get_noise_2d(along, i * 7000.0) * 0.7 + 0.5, 0.0, 1.0)
		var crest := lerpf(layer[2], layer[3], k)
		if i == 1:
			var m := ArrivalShot.MASSIF
			crest += m.height * exp(-pow((along - _massif_along) / m.width, 2.0))
		var shape := pow(e, 2.2) * (0.3 + 0.7 * r)
		h = _smooth_max(h, valley_floor + (crest - valley_floor) * shape, 150.0)
	return h


## How far (m) `p` is outside polygon `poly`; 0 inside.
static func _outside(poly: PackedVector2Array, p: Vector2) -> float:
	if Geometry2D.is_point_in_polygon(p, poly):
		return 0.0
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_squared_to(q))
	return sqrt(best)


static func _smooth_max(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (a - b) / k, 0.0, 1.0)
	return lerpf(b, a, h) + k * h * (1.0 - h)


## The break-up noise at world (x, z), 0..1, bilinear like the shader's sampler.
func mask_at(x: float, z: float) -> float:
	var fx := fposmod(x / mask_size, 1.0) * MASK_PIXELS - 0.5
	var fz := fposmod(z / mask_size, 1.0) * MASK_PIXELS - 0.5
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var tx := fx - x0
	var tz := fz - z0
	var a := lerpf(_px(x0, z0), _px(x0 + 1, z0), tx)
	var b := lerpf(_px(x0, z0 + 1), _px(x0 + 1, z0 + 1), tx)
	return lerpf(a, b, tz)


func _px(x: int, z: int) -> float:
	return mask.get_pixel(posmod(x, MASK_PIXELS), posmod(z, MASK_PIXELS)).r


## The clear map at world (x, z): (cleared 0..1, wall shade 0..1); nothing outside its rect.
func clear_at(x: float, z: float) -> Vector2:
	var uv := (Vector2(x, z) - clear_rect.position) / clear_rect.size
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return Vector2.ZERO
	var c := clear.get_pixel(int(uv.x * clear_pixels.x), int(uv.y * clear_pixels.y))
	return Vector2(c.r, c.g)


## How much forest the land carries (0..1) at height `y` on a face with normal y `ny`, ridge value
## `ridge`, cleared by `cleared`: the shader's forest_score, line for line. The forest stands where
## this beats `forest_bar`.
func forest_score(y: float, ny: float, ridge: float, cleared: float) -> float:
	var alt := 1.0 - smoothstep(treeline - tree_band, treeline, y)
	var slope := smoothstep(forest_min_slope, forest_min_slope + 0.08, ny) \
			* (1.0 - smoothstep(forest_max_slope - 0.012, forest_max_slope, ny))
	var open := 1.0 - smoothstep(ridge_clear.x, ridge_clear.y, ridge)
	return alt * slope * open * (1.0 - cleared)


## The break-up the forest score has to beat at world (x, z).
func forest_bar(x: float, z: float) -> float:
	return lerpf(0.15, 0.85, mask_at(x, z))


# --- the clear map -----------------------------------------------------------------------------

func _build_clear(shot: ArrivalShot) -> void:
	clear = Image.create(clear_pixels.x, clear_pixels.y, false, Image.FORMAT_RGBA8)
	clear.fill(Color(0.0, 0.0, 0.0, 1.0))
	# The aprons: cleared to `apron` past the deck edge, the wall's shade spreading from the band line.
	for fp in _footprints:
		var outer: PackedVector2Array = fp.outer
		var band: PackedVector2Array = fp.band
		var box := Rect2(outer[0], Vector2.ZERO)
		for q in outer:
			box = box.expand(q)
		_fill(box.grow(apron + 20.0), func(p: Vector2) -> Vector2:
			return Vector2(1.0 - smoothstep(apron, apron + 14.0, _outside(outer, p)),
					1.0 - smoothstep(0.0, ao_reach, _outside(band, p))))
	for tf in _tower_feet:
		var at: Vector2 = tf.at
		var s: float = tf.shaft
		_fill(Rect2(at, Vector2.ZERO).grow(s * 2.0 + apron + 20.0), func(p: Vector2) -> Vector2:
			var d := p.distance_to(at)
			return Vector2(1.0 - smoothstep(s * 1.8 + apron * 0.7, s * 1.8 + apron * 0.7 + 12.0, d),
					1.0 - smoothstep(s * 1.3, s * 1.3 + ao_reach, d)))
	_build_road()
	var pc := ArrivalShot.POWER_CUT
	var right: Dictionary = ArrivalShot.DECKS[1]
	var a := shot.on_plane(pc.from.x, pc.from.y, right.top)
	var b := shot.at_distance(pc.to.x, pc.to.y, pc.distance)
	_stroke(PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z)]), PackedFloat32Array([cut_width, cut_width]))
	_build_chutes()


# The road: out of the portal in the Lower deck's band wall, straight down the slope, then
# switchbacks across it.
func _build_road() -> void:
	var r := ArrivalShot.ROAD
	var band: PackedVector2Array = _footprints[0].band
	# The front edge: the one nearest the camera (offset_polygon does not keep the outline's order).
	var front := 0
	for i in band.size():
		if (band[i] + band[(i + 1) % band.size()]).y > (band[front] + band[(front + 1) % band.size()]).y:
			front = i
	var a := band[front]
	var b := band[(front + 1) % band.size()]
	if a.x > b.x:
		var swap := a
		a = b
		b = swap
	var e := (b - a).normalized()
	var out := Vector2(e.y, -e.x)
	var p := a.lerp(b, r.at)
	if Geometry2D.is_point_in_polygon(p + out, band):
		out = -out
	portal = Vector3(p.x, height(p.x, p.y), p.y)
	portal_out = out
	var path := PackedVector2Array([p, p + out * r.out])
	var sign := -1.0
	for k in r.legs:
		path.append(path[path.size() - 1] + e * sign * r.leg + out * r.advance)
		sign = -sign
	var widths := PackedFloat32Array()
	widths.resize(path.size())
	widths.fill(road_width)
	_stroke(path, widths)


# Avalanche chutes: from convex, steep-ish spots, straight down the fall line until the slope eases,
# narrow at the top and fanning out at the runout. None starts at or runs into the base.
func _build_chutes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = land_seed + 9
	var tries := 0
	while chute_paths.size() < chutes and tries < chutes * 60:
		tries += 1
		var p := clear_rect.position + Vector2(rng.randf(), rng.randf()) * clear_rect.size
		if clear_at(p.x, p.y).x > 0.0 or _near_base(p, 250.0):
			continue
		var h := height(p.x, p.y)
		var around := (height(p.x + 100.0, p.y) + height(p.x - 100.0, p.y)
				+ height(p.x, p.y + 100.0) + height(p.x, p.y - 100.0)) * 0.25
		var grad := _gradient(p)
		# Chutes start inside the forest, so they read as clear strips through the trees.
		if h - around < 6.0 or grad.length() < 0.4 or grad.length() > 1.4 or h > treeline - 60.0:
			continue
		var crowded := false
		for other in chute_paths:
			for q in other:
				if q.distance_to(p) < 260.0:
					crowded = true
					break
			if crowded:
				break
		if crowded:
			continue
		var path := PackedVector2Array([p])
		var dir := -grad.normalized()
		var length := 0.0
		while length < 950.0:
			var g := _gradient(p)
			if g.length() < 0.15 and length > 200.0:
				break
			# The fall line, with a little wander so no chute is ruled straight.
			dir = (dir - g.normalized() + Vector2(-dir.y, dir.x) * rng.randf_range(-0.35, 0.35)).normalized()
			p += dir * 12.0
			length += 12.0
			if _near_base(p, 60.0) or not clear_rect.has_point(p):
				break
			path.append(p)
		# A chute is where snow slides: it needs a real drop.
		if length < 260.0 or h - height(p.x, p.y) < 60.0:
			continue
		var widths := PackedFloat32Array()
		for k in path.size():
			var t := float(k) / (path.size() - 1)
			widths.append(lerpf(chute_width.x, chute_width.y, t) * (1.0 + 0.8 * smoothstep(0.8, 1.0, t)))
		_stroke(path, widths)
		chute_paths.append(path)


func _gradient(p: Vector2) -> Vector2:
	return Vector2(height(p.x + 8.0, p.y) - height(p.x - 8.0, p.y),
			height(p.x, p.y + 8.0) - height(p.x, p.y - 8.0)) / 16.0


func _near_base(p: Vector2, margin: float) -> bool:
	for fp in _footprints:
		if _outside(fp.outer, p) < margin:
			return true
	for tf in _tower_feet:
		if p.distance_to(tf.at) < tf.shaft * 2.0 + margin:
			return true
	return false


# Runs `paint` (world xz -> (cleared, shade)) over the clear map's pixels inside world rect `box`,
# keeping the larger of old and new.
func _fill(box: Rect2, paint: Callable) -> void:
	var px := clear_rect.size / Vector2(clear_pixels)
	var x0 := clampi(int((box.position.x - clear_rect.position.x) / px.x), 0, clear_pixels.x - 1)
	var x1 := clampi(int((box.end.x - clear_rect.position.x) / px.x), 0, clear_pixels.x - 1)
	var y0 := clampi(int((box.position.y - clear_rect.position.y) / px.y), 0, clear_pixels.y - 1)
	var y1 := clampi(int((box.end.y - clear_rect.position.y) / px.y), 0, clear_pixels.y - 1)
	for j in range(y0, y1 + 1):
		for i in range(x0, x1 + 1):
			var w := clear_rect.position + (Vector2(i, j) + Vector2(0.5, 0.5)) * px
			var v: Vector2 = paint.call(w)
			if v.x <= 0.0 and v.y <= 0.0:
				continue
			var c := clear.get_pixel(i, j)
			clear.set_pixel(i, j, Color(maxf(c.r, v.x), maxf(c.g, v.y), 0.0, 1.0))


# Clears a stroke along `path` (world xz), `widths` (m) at each point, cut into short pieces so each
# only walks the pixels near it.
func _stroke(path: PackedVector2Array, widths: PackedFloat32Array) -> void:
	for k in path.size() - 1:
		var a := path[k]
		var b := path[k + 1]
		var n := maxi(int(ceil(a.distance_to(b) / 30.0)), 1)
		for i in n:
			var p := a.lerp(b, float(i) / n)
			var q := a.lerp(b, float(i + 1) / n)
			var half := lerpf(widths[k], widths[k + 1], (i + 0.5) / n) * 0.5
			_fill(Rect2(p, Vector2.ZERO).expand(q).grow(half + 8.0), func(w: Vector2) -> Vector2:
				var d := w.distance_to(Geometry2D.get_closest_point_to_segment(w, p, q))
				return Vector2(1.0 - smoothstep(half, half + 6.0, d), 0.0))


# --- the mesh ----------------------------------------------------------------------------------

func _build() -> void:
	var half := deg_to_rad(half_angle_degrees)
	var step := 2.0 * half / columns
	var ratio := 1.0 + step
	var rings := int(ceil(log(far / near) / log(ratio))) + 1
	var cols := columns + 1
	vertices.resize(rings * cols)
	for j in rings:
		var r := near * pow(ratio, j)
		for i in cols:
			var a := -half + step * i
			var x := sin(a) * r
			var z := -cos(a) * r
			vertices[j * cols + i] = Vector3(x, height(x, z), z)
	# Convexity per vertex against its neighbours two cells out, in cell sizes: ridgelines high.
	ridges.resize(vertices.size())
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	for j in rings:
		var cell := near * pow(ratio, j) * step * 2.0
		for i in cols:
			var around := (vertices[j * cols + maxi(i - 2, 0)].y + vertices[j * cols + mini(i + 2, cols - 1)].y
					+ vertices[maxi(j - 2, 0) * cols + i].y + vertices[mini(j + 2, rings - 1) * cols + i].y) * 0.25
			var c := (vertices[j * cols + i].y - around) / cell
			ridges[j * cols + i] = c
			# Signed, packed into 0..1 for the shader: 0.5 is flat.
			colors[j * cols + i] = Color(clampf(c * 0.5 + 0.5, 0.0, 1.0), 0.0, 0.0, 1.0)
	normals.resize(vertices.size())
	for j in rings:
		for i in cols:
			var l := vertices[j * cols + maxi(i - 1, 0)]
			var rt := vertices[j * cols + mini(i + 1, cols - 1)]
			var nr := vertices[maxi(j - 1, 0) * cols + i]
			var fr := vertices[mini(j + 1, rings - 1) * cols + i]
			var n := (rt - l).cross(nr - fr).normalized()
			normals[j * cols + i] = n if n.y > 0.0 else -n
	triangles.resize((rings - 1) * columns * 6)
	var t := 0
	for j in rings - 1:
		for i in columns:
			var a := j * cols + i
			var c := a + cols
			# Near ring first, wound clockwise from above so the faces point up: (a, c, b), (b, c, d).
			triangles[t] = a
			triangles[t + 1] = c
			triangles[t + 2] = a + 1
			triangles[t + 3] = a + 1
			triangles[t + 4] = c
			triangles[t + 5] = c + 1
			t += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = triangles
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material())
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	add_child(mi)


func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	m.set_shader_parameter(&"snow_color", snow_color)
	m.set_shader_parameter(&"rock_color", rock_color)
	m.set_shader_parameter(&"forest_color", forest_color)
	m.set_shader_parameter(&"snow_threshold", snow_threshold)
	m.set_shader_parameter(&"clear_snow", clear_snow)
	m.set_shader_parameter(&"forest_min_slope", forest_min_slope)
	m.set_shader_parameter(&"forest_max_slope", forest_max_slope)
	m.set_shader_parameter(&"treeline", treeline)
	m.set_shader_parameter(&"tree_band", tree_band)
	m.set_shader_parameter(&"ridge_clear", ridge_clear)
	m.set_shader_parameter(&"mask_tex", ImageTexture.create_from_image(mask))
	m.set_shader_parameter(&"mask_size", mask_size)
	m.set_shader_parameter(&"clear_tex", ImageTexture.create_from_image(clear))
	m.set_shader_parameter(&"clear_rect", Vector4(clear_rect.position.x, clear_rect.position.y,
			clear_rect.size.x, clear_rect.size.y))
	m.set_shader_parameter(&"forest_fade", Vector2(ArrivalForest.REACH, ArrivalForest.REACH * 3.0))
	return m
