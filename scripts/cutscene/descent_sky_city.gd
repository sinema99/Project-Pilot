class_name DescentSkyCity
extends MeshInstance3D

# The mega sky city far off in the descent shot (docs/specs/mega-sky-city.md): a flat 2D card of
# three silhouette layers in the fog's tones, platforms in the user's band (sketch px) with
# faceted 2-tier hulls, legs, braces and tanks hanging below it. The whole city is one flat
# colour (the user's pick), paler than the far ridge so it reads as the farthest thing in the shot. Generated at load from
# `city_seed`, placed like everything else in the shot by DescentShot.sketch_point, 20-22 km out
# so both mountain ranges hide the leg feet. Unshaded and fog-free: lightning never touches it,
# and it never moves.
#
# GENERATED like DescentLand: the mesh is built in _ready and nothing is saved into the .tscn.

const SHADER := preload("res://shaders/cutscene/sky_city.gdshader")

## The user's band, in sketch px: platforms from the left edge to END_X, tops and undersides
## between BAND_TOP and BAND_BOTTOM.
const BAND_TOP := 353.0
const BAND_BOTTOM := 427.0
const START_X := -120.0
const END_X := 1190.0
## Past this the platforms thin out toward END_X.
const TAPER_X := 920.0
## Hanging things end here: below the horizon, behind both ridges.
const DRAPE_END_Y := 570.0
## Haze: hanging things blend toward the sky from the band's bottom to this sketch y. Ends early,
## so the thin legs are gone well above the ridge: it reads farther and taller.
const HAZE_END_Y := 490.0
## `city_scale` shrinks the whole card toward this sketch point: mid band, on the tops' line.
const SCALE_ANCHOR := Vector2(535.0, 353.0)

@export var city_seed := 3
## The sky behind the band; the haze fades toward it.
@export var sky_color := Color(0.84, 0.83, 0.89)
## The whole card's size around SCALE_ANCHOR (1 = the user's full band). Legs still reach
## DRAPE_END_Y, so their feet stay behind the ridges.
@export_range(0.2, 1.0, 0.01) var city_scale := 0.7
## Sketch px the whole card sits lower than the user's band (after city_scale). Legs still reach
## DRAPE_END_Y. 40 (2026-10-16, user: way too high for that far away).
@export_range(0.0, 150.0, 1.0) var city_drop := 40.0
## The one colour of the whole city, every layer and every part.
@export var city_color := Color(0.79, 0.785, 0.85)
## Back to front: [distance (m), platform top range (px), slab thickness range (px),
## platform width range (px), leg width range (px)].
@export var city_layers: Array = [
	[22000.0, Vector2(352, 364), Vector2(3.6, 6), Vector2(42, 102), Vector2(1.8, 4.2)],
	[21000.0, Vector2(358, 378), Vector2(6, 9.6), Vector2(66, 144), Vector2(3, 6.6)],
	[20000.0, Vector2(368, 392), Vector2(9.6, 15.6), Vector2(90, 198), Vector2(4.8, 12)],
]
## How far down the haze takes a hanging thing toward sky_color (0 = none, 1 = gone). Off: the
## user wants the city one flat colour.
@export_range(0.0, 1.0, 0.01) var haze := 0.0
## How close the sky rails get to sky_color. Off, for the same reason.
@export_range(0.0, 1.0, 0.01) var rail_haze := 0.0

var _st: SurfaceTool
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	build()


func build() -> void:
	_rng.seed = city_seed
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in city_layers.size():
		_build_layer(city_layers[i], i > 0)
	mesh = _st.commit()
	var m := ShaderMaterial.new()
	m.shader = SHADER
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_layer(layer: Array, rail: bool) -> void:
	var dist: float = layer[0]
	var col := city_color
	var tops: Vector2 = layer[1]
	var thick: Vector2 = layer[2]
	var widths: Vector2 = layer[3]
	var legs: Vector2 = layer[4]
	# A long thin rail running between platforms (front two layers only).
	if rail:
		var rc := col.lerp(sky_color, rail_haze)
		var y := _rng.randf_range(BAND_TOP - 10.0, tops.y)
		var x0 := _rng.randf_range(START_X + 80.0, END_X * 0.45)
		var x1 := minf(x0 + _rng.randf_range(260.0, 520.0), END_X + 40.0)
		_rect(Rect2(x0, y, x1 - x0, _rng.randf_range(1.0, 1.6)), dist + 30.0, rc, rc)
	var x := START_X + _rng.randf_range(0.0, 36.0)
	var last_right := -INF
	var last_y := 0.0
	while x < END_X:
		var taper := clampf((x - TAPER_X) / (END_X - TAPER_X), 0.0, 1.0)
		var w := _rng.randf_range(widths.x, widths.y) * lerpf(1.0, 0.45, taper)
		w = minf(w, END_X - x)
		if w < widths.x * 0.3:
			break
		var top := _rng.randf_range(tops.x, tops.y) + taper * 4.0
		var th := _rng.randf_range(thick.x, thick.y) * lerpf(1.0, 0.6, taper)
		_platform(Rect2(x, top, w, th), dist, col, legs * lerpf(1.0, 0.7, taper))
		# A girder bridging the gap to the last platform.
		if last_right > -INF and _rng.randf() < 0.6:
			var by := (top + th * 0.5 + last_y) * 0.5
			_rect(Rect2(last_right - 3.0, by, x - last_right + 6.0, _rng.randf_range(1.0, 1.6)), dist + 10.0, col, col)
		last_right = x + w
		last_y = top + th * 0.5
		x += w + _rng.randf_range(11.0, 54.0) * lerpf(1.0, 2.2, taper)


func _platform(r: Rect2, dist: float, col: Color, leg_w: Vector2) -> void:
	_rect(r, dist, col, col)
	var under := r.end.y
	var w := r.size.x
	var th := r.size.y
	var l0 := r.position.x
	var r0 := r.end.x
	# Faceted hull, 2 tiers: angle in, a flat ledge, angle in again. `lean` makes one side
	# steeper than the other, per platform.
	var lean := _rng.randf_range(0.2, 0.8)
	var t1 := w * _rng.randf_range(0.22, 0.32)
	var ledge := w * _rng.randf_range(0.04, 0.08)
	var t2 := w * _rng.randf_range(0.18, 0.26)
	var y1 := under + th * _rng.randf_range(0.8, 1.2)
	var y2 := y1 + th * _rng.randf_range(0.6, 0.9)
	var l1 := l0 + t1 * lean
	var r1 := r0 - t1 * (1.0 - lean)
	_quad(Vector2(l0, under - 0.5), Vector2(r0, under - 0.5), Vector2(r1, y1), Vector2(l1, y1), dist, col, col)
	var l2 := l1 + ledge * lean
	var r2 := r1 - ledge * (1.0 - lean)
	_quad(Vector2(l2, y1 - 0.5), Vector2(r2, y1 - 0.5), Vector2(r2 - t2 * (1.0 - lean), y2), Vector2(l2 + t2 * lean, y2), dist, col, col)
	# A girder line under the slab, overhanging its ends.
	if _rng.randf() < 0.5:
		_rect(Rect2(l0 - 6.0, under + _rng.randf_range(1.0, 3.0), w + 12.0, 1.2), dist + 5.0, col, col)
	# Legs on the outer parts of the slab, where the hull has tapered away, so they show. About
	# 1 in 4 platforms stands on an A-frame pair leaning in 8-12 deg. Each leg is (top x, bottom x).
	var drop := _drape_end() - under
	var legs: Array[Vector2] = []
	if _rng.randf() < 0.25:
		var lean_px := tan(deg_to_rad(_rng.randf_range(8.0, 12.0))) * drop
		var la := l0 + w * _rng.randf_range(0.08, 0.2)
		var lb := r0 - w * _rng.randf_range(0.08, 0.2)
		legs.append(Vector2(la, la + lean_px))
		legs.append(Vector2(lb, lb - lean_px))
	else:
		var sides := [0, 1] if _rng.randf() < 0.5 else [_rng.randi_range(0, 1)]
		for side in sides:
			var f := _rng.randf_range(0.08, 0.3)
			var lx := l0 + w * (f if side == 0 else 1.0 - f)
			legs.append(Vector2(lx, lx))
	for leg in legs:
		_drape(leg.x, leg.y, under, _rng.randf_range(leg_w.x, leg_w.y), _drape_end(), _rng.randf_range(0.45, 0.8), dist + 5.0, col)
		# A knee brace from the leg out to the slab's underside, toward the near edge.
		if _rng.randf() < 0.8:
			var by := under + _rng.randf_range(6.0, 12.0)
			var out := -1.0 if leg.x - l0 < r0 - leg.x else 1.0
			var reach := minf(by - under, absf((r0 if out > 0.0 else l0) - leg.x) + 2.0)
			_line(Vector2(leg.x + out * reach, under), Vector2(_leg_x(leg, by, under, drop), by), 1.1, dist + 5.0, col, _hazed(col, by))
	# One X-truss between a pair, on about 1 in 3 platforms.
	if legs.size() == 2 and _rng.randf() < 0.33:
		var ya := under + _rng.randf_range(10.0, 18.0)
		var yb := ya + _rng.randf_range(16.0, 28.0)
		var a := legs[0]
		var b := legs[1]
		var ca := _hazed(col, ya)
		var cb := _hazed(col, yb)
		_line(Vector2(_leg_x(a, ya, under, drop), ya), Vector2(_leg_x(b, yb, under, drop), yb), 1.0, dist + 6.0, ca, cb)
		_line(Vector2(_leg_x(b, ya, under, drop), ya), Vector2(_leg_x(a, yb, under, drop), yb), 1.0, dist + 6.0, ca, cb)
	# At most one hanging tank on a strut, corners clipped.
	if _rng.randf() < 0.6:
		var tx := lerpf(l2, r2, _rng.randf_range(0.2, 0.8))
		var tank_top := y2 + _rng.randf_range(2.0, 10.0)
		_rect(Rect2(tx - 0.5, y1, 1.0, tank_top - y1), dist + 5.0, col, _hazed(col, tank_top))
		var tw := _rng.randf_range(6.0, 13.0) * leg_w.y / 12.0
		_tank(tx, tank_top, tw, tw * _rng.randf_range(0.7, 1.1), dist + 5.0, col)
	# Thin cables trailing down.
	for i in _rng.randi_range(0, 2):
		var cx := lerpf(l1, r1, _rng.randf())
		_drape(cx, cx, y1, _rng.randf_range(0.7, 1.3), y1 + _rng.randf_range(10.0, 45.0), 0.6, dist + 5.0, col)


## Where a (top x, bottom x) leg is at sketch y.
func _leg_x(leg: Vector2, y: float, under: float, drop: float) -> float:
	return lerpf(leg.x, leg.y, (y - under) / drop)


## Where a leg ends before city_scale and city_drop, so it lands on DRAPE_END_Y after them.
func _drape_end() -> float:
	return SCALE_ANCHOR.y + (DRAPE_END_Y - city_drop - SCALE_ANCHOR.y) / city_scale


## A chamfered (octagonal) tank, `w` x `h`, hanging from (x, top).
func _tank(x: float, top: float, w: float, h: float, dist: float, col: Color) -> void:
	var c := minf(w, h) * 0.3
	var l := x - w * 0.5
	var r := x + w * 0.5
	var y1 := top + c
	var y2 := top + h - c
	var bot := top + h
	_quad(Vector2(l + c, top), Vector2(r - c, top), Vector2(r, y1), Vector2(l, y1), dist, _hazed(col, top), _hazed(col, y1))
	_quad(Vector2(l, y1), Vector2(r, y1), Vector2(r, y2), Vector2(l, y2), dist, _hazed(col, y1), _hazed(col, y2))
	_quad(Vector2(l, y2), Vector2(r, y2), Vector2(r - c, bot), Vector2(l + c, bot), dist, _hazed(col, y2), _hazed(col, bot))


## A hanging column from (x_top, from_y) down to (x_bottom, to_y), `w` wide at the top and
## `narrow` of that at the bottom, hazing toward the sky as it goes down.
func _drape(x_top: float, x_bottom: float, from_y: float, w: float, to_y: float, narrow: float, dist: float, col: Color) -> void:
	var tl := Vector2(x_top - w * 0.5, from_y)
	var tr := Vector2(x_top + w * 0.5, from_y)
	var br := Vector2(x_bottom + w * 0.5 * narrow, to_y)
	var bl := Vector2(x_bottom - w * 0.5 * narrow, to_y)
	_quad(tl, tr, br, bl, dist, _hazed(col, from_y), _hazed(col, to_y))


## A thin straight strut from `a` (upper end, colour `top`) to `b`, `w` px wide.
func _line(a: Vector2, b: Vector2, w: float, dist: float, top: Color, bottom: Color) -> void:
	var n := (b - a).orthogonal().normalized() * w * 0.5
	_quad(a - n, a + n, b + n, b - n, dist, top, bottom)


func _hazed(col: Color, y: float) -> Color:
	var f := clampf((y - BAND_BOTTOM) / (HAZE_END_Y - BAND_BOTTOM), 0.0, 1.0)
	return col.lerp(sky_color, f * haze)


func _rect(r: Rect2, dist: float, top: Color, bottom: Color) -> void:
	_quad(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), dist, top, bottom)


## One quad from sketch-px corners (clockwise from top left), pushed out to `dist`.
func _quad(tl: Vector2, tr: Vector2, br: Vector2, bl: Vector2, dist: float, top: Color, bottom: Color) -> void:
	var p := [tl, tr, br, bl].map(func(v: Vector2) -> Vector3:
		return DescentShot.sketch_point(SCALE_ANCHOR + (v - SCALE_ANCHOR) * city_scale + Vector2(0.0, city_drop), dist))
	var c := [top, top, bottom, bottom]
	for i in [0, 1, 2, 0, 2, 3]:
		_st.set_color(c[i].srgb_to_linear())
		_st.add_vertex(p[i])
