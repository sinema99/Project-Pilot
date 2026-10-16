class_name FlyoverCity
extends DescentLand

# The flyover's slice of the dead city (docs/specs/cutscene-flyover.md, "Dead city + storm" and
# "City detail pass"): one hero skeleton high-rise where OP_1's building used to sit on screen,
# eleven landmark ruins round it, and the packed city filling every block out to the fog: gutted
# shells, snapped stumps with rooftop clutter, collapsed and empty lots, snow drifts in the lee of
# the walls, buried cars in the streets, one elevated highway with a snapped span. The descent's
# ruin kinds and box helpers are reused; `_box` is overridden to write raw arrays (thousands of
# boxes) and to give walls world-metre UVs, so the window tile repeats one bay x one floor.
#
# GENERATED like DescentLand: children have no owner, nothing is saved into the .tscn. The ground
# is not built here: the flyover's sky paints it (flyover_sky.gdshader), street grid included.

## Storey height (m) of the hero: fine enough to read as floors from 600-900 m.
const STOREY := 5.0
## Hero column grid: COLUMNS x COLUMNS across the footprint.
const COLUMNS := 5
## The city's five tones (times `concrete_shade`, like the descent's concrete): two cool
## concretes, a warm stone, a rust brick, a dark weathered block. Close in value on purpose.
const TONES: Array[Color] = [
	Color(0.25, 0.28, 0.34), Color(0.24, 0.25, 0.29), Color(0.32, 0.28, 0.23),
	Color(0.35, 0.22, 0.17), Color(0.21, 0.21, 0.22),
]
## The hero: a touch lighter than the city, so the eye lands on it.
const HERO_TONE := Color(0.33, 0.34, 0.38)
const CAR_TONES: Array[Color] = [Color(0.16, 0.16, 0.18), Color(0.22, 0.14, 0.12), Color(0.12, 0.14, 0.17)]
## Window tile: one bay (`window_bay` m) by one floor (`window_floor` m), a dark hole in the middle.
const TILE := 16
## A UV inside the tile's solid wall: boxes with no windows sample only this.
const SOLID_UV := Vector2(0.03, 0.03)

@export_group("Hero")
## Where the hero's foot centre is (world, on the ground) and its street-grid yaw (degrees).
@export var hero_at := Vector3(0.0, 0.0, 210.0)
@export var grid_degrees := 12.0
@export var hero_width := 60.0
@export var hero_height := 220.0
## The clad base (m) under the bare floors.
@export var podium_height := 20.0
## Fraction of the height where the top starts breaking up (partial slabs, ragged columns).
@export_range(0.0, 1.0, 0.01) var break_start := 0.72
## Which side the facade is torn off: the hero's local face whose outward normal is this (x, z).
@export var open_side := Vector2(-1.0, 0.0)

@export_group("City")
## The landmark ruins, relative to the hero's foot in its grid frame (x across, z along):
## [kind, x, z, width, depth, height]. Toppled: height is its length lying down (along x).
@export var neighbours: Array = [
	[&"snapped", -110.0, -40.0, 34.0, 30.0, 70.0],
	[&"facade", -105.0, 95.0, 40.0, 0.0, 60.0],
	[&"crane", 95.0, -95.0, 0.0, 0.0, 95.0],
	[&"snapped", 110.0, 30.0, 40.0, 36.0, 105.0],
	[&"toppled", 55.0, 260.0, 26.0, 0.0, 150.0],
	[&"skeleton", 190.0, 200.0, 36.0, 34.0, 120.0],
	[&"snapped", -210.0, 230.0, 46.0, 40.0, 45.0],
	[&"setback", 260.0, 420.0, 40.0, 40.0, 150.0],
	[&"snapped", -60.0, 420.0, 50.0, 44.0, 85.0],
	[&"facade", 140.0, -230.0, 36.0, 0.0, 50.0],
	[&"snapped", -230.0, -150.0, 38.0, 34.0, 55.0],
]
## Rubble mounds spilled into the streets and crossings within this radius (m) of the hero.
@export var rubble_count := 16
@export var rubble_radius := 420.0
@export var city_seed := 23
## Concrete colours times this (snow untouched). The storm fog drowns most of what the walls add,
## so it is high: at 0.55 the window holes and the five tones did not show at all.
@export_range(0.0, 2.0, 0.05) var concrete_shade := 1.8

@export_group("Streets")
## The street grid (shared with the sky's painted streets): block pitch (across, along) and the
## street width. The hero sits mid-block.
@export var street_block := Vector2(110.0, 130.0)
@export var street_width := 16.0
## Pavement between the street and the lot line.
@export var pavement := 3.0

@export_group("Packed city")
## Lots are built out to `city_radius` (m from the hero), with detail (shells, clutter, drifts,
## cars) out to `detail_radius`; past it plain boxes. Nothing new within `clear_radius`.
@export var city_radius := 1500.0
@export var detail_radius := 800.0
@export var clear_radius := 110.0
## Typical height (m) next to the clear zone and out at ~1.2 km.
@export var height_near := 50.0
@export var height_far := 15.0
## Lot mix: shells, stumps, collapsed (the rest are empty).
@export_range(0.0, 1.0, 0.01) var shell_chance := 0.35
@export_range(0.0, 1.0, 0.01) var stump_chance := 0.25
@export_range(0.0, 1.0, 0.01) var collapsed_chance := 0.25
## Window grid on the walls (m): one bay across, one floor up.
@export var window_bay := 3.5
@export var window_floor := 4.0
## How dark a window hole is (texture value, sRGB).
@export_range(0.0, 1.0, 0.01) var window_dark := 0.0
## Snow drifts: the wind blows toward world -Z (the storm's wind_direction), so the big drift
## lies in the lee, on each building's -Z face; a small one banks against the windward face.
@export var drift_height := Vector2(3.0, 8.0)
@export var drift_reach := Vector2(8.0, 16.0)

@export_group("Cars")
## Kerbside cars out to `car_radius`: one 6 m slot per kerb, filled with `car_chance`; and
## `jam_count` crossings jammed with a pile-up.
@export var car_radius := 800.0
@export_range(0.0, 1.0, 0.01) var car_chance := 0.3
@export var jam_count := 5

@export_group("Highway")
## The elevated highway in the hero's frame: a point on its line (x, z), its heading (degrees from
## the grid's +Z toward +X), deck width / height (m) and pillar spacing. The span whose middle is
## nearest `break_along` (m along from the point) is snapped.
@export var highway_point := Vector2(0.0, 330.0)
@export var highway_degrees := 45.0
@export var deck_width := 25.0
@export var deck_height := 20.0
@export var pillar_spacing := 40.0
@export var break_along := -350.0
@export_range(0.0, 1.0, 0.01) var deck_car_chance := 0.35

## The hero's frame: foot centre, +Y up, on the street grid. Set by _ready.
var hero_frame := Transform3D()
## Every packed-city lot built, for tests: [{kind, at (world), height, size (x, z)}].
var lots: Array[Dictionary] = []
## Cars built: in the streets and on the highway deck.
var street_cars := 0
var deck_cars := 0
## The highway, for tests: {start, end (world, deck level), break_at (world)}.
var highway := {}

## Colour -> [verts, normals, uvs].
var _arrays := {}
## Wall UVs on: the next boxes get the window grid on their vertical faces.
var _windows := false
## Keep-outs for the packed city and the cars, in the hero frame: (x, z, radius).
var _keep_out: Array[Vector3] = []
var _window_tex: ImageTexture


func _ready() -> void:
	ruins.clear()
	lots.clear()
	_arrays.clear()
	_keep_out.clear()
	street_cars = 0
	deck_cars = 0
	_rng.seed = city_seed
	_grid = deg_to_rad(grid_degrees)
	hero_frame = Transform3D(Basis(Vector3.UP, _grid), hero_at)
	_hero()
	for row: Array in neighbours:
		var frame := hero_frame.translated_local(Vector3(row[1], 0.0, row[2]))
		frame = Transform3D(Basis(Vector3.UP, _grid + deg_to_rad(_rng.randf_range(-4.0, 4.0))), frame.origin)
		_windows = row[0] in [&"snapped", &"setback", &"facade"]
		_ruin(row[0], frame, row[3], maxf(row[4], 1.0), row[5])
		_windows = false
		_keep_neighbour(row)
	_highway()
	_scatter_rubble()
	_packed_city()
	_street_cars()
	_commit()


## The middle of the hero at height fraction `f` (world).
func hero_point(f: float) -> Vector3:
	return hero_frame * Vector3(0.0, hero_height * f, 0.0)


func _commit() -> void:
	_window_tex = _make_window_tile()
	var root := Node3D.new()
	root.name = "Ruins"
	add_child(root)
	for col: Color in _arrays:
		var a: Array = _arrays[col]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = a[0]
		arrays[Mesh.ARRAY_NORMAL] = a[1]
		arrays[Mesh.ARRAY_TEX_UV] = a[2]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var shade := 1.0 if _is_snow(col) else concrete_shade
		var m := _cel(Color(col * shade, 1.0))
		m.set_shader_parameter(&"tile_texture", _window_tex)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


# One bay x one floor: solid wall, a dark hole across the middle half.
func _make_window_tile() -> ImageTexture:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	var dark := Color(window_dark, window_dark, window_dark)
	for y in range(5, 12):
		for x in range(4, 12):
			img.set_pixel(x, y, dark)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _is_snow(col: Color) -> bool:
	return col == C_PEAK_SNOW or col == C_SNOW


func _concrete() -> Color:
	return TONES[_rng.randi() % TONES.size()]


## A `size` box centred on `xform`, appended to its colour's arrays. Vertical faces get world-metre
## UVs (the window grid) while `_windows` is on; everything else samples the tile's solid wall.
## The bottom face is skipped on upright boxes (it is in the ground or never seen).
func _box(size: Vector3, xform: Transform3D, col: Color) -> void:
	var a: Array = _arrays.get(col, [])
	if a.is_empty():
		a = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]
		_arrays[col] = a
	# Take the arrays out of `a` while appending: a second reference would make every append copy.
	var verts: PackedVector3Array = a[0]
	var normals: PackedVector3Array = a[1]
	var uvs: PackedVector2Array = a[2]
	a[0] = PackedVector3Array()
	a[1] = PackedVector3Array()
	a[2] = PackedVector2Array()
	var rot := xform.basis.orthonormalized()
	var upright := rot.y.y > 0.99
	var windows := _windows and not _is_snow(col)
	var half := size * 0.5
	for axis in 3:
		for sgn: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			if upright and axis == 1 and sgn < 0.0:
				continue
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := n.cross(u)
			var wn := rot * n
			var wall := windows and absf(wn.y) < 0.5
			var t := Vector3(-wn.z, 0.0, wn.x).normalized() if wall else Vector3.ZERO
			# Clockwise seen from outside: Godot's front face.
			for c: Vector3 in [n - u - v, n + u + v, n + u - v, n - u - v, n - u + v, n + u + v]:
				var p := xform * (c * half)
				verts.append(p)
				normals.append(wn)
				uvs.append(Vector2(p.dot(t) / window_bay, -p.y / window_floor) if wall else SOLID_UV)
	a[0] = verts
	a[1] = normals
	a[2] = uvs


# A triangle with outward normal `n`, wound clockwise from outside whatever order it comes in.
func _tri(p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3, col: Color) -> void:
	var a: Array = _arrays.get(col, [])
	if a.is_empty():
		a = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]
		_arrays[col] = a
	if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
		var swap := p1
		p1 = p2
		p2 = swap
	# Take the arrays out of `a` while appending: a second reference would make every append copy.
	var verts: PackedVector3Array = a[0]
	var normals: PackedVector3Array = a[1]
	var uvs: PackedVector2Array = a[2]
	a[0] = PackedVector3Array()
	a[1] = PackedVector3Array()
	a[2] = PackedVector2Array()
	for p: Vector3 in [p0, p1, p2]:
		verts.append(p)
		normals.append(n)
		uvs.append(SOLID_UV)
	a[0] = verts
	a[1] = normals
	a[2] = uvs


# --- the hero skeleton --------------------------------------------------------------------------
# A clad podium, then bare slabs every STOREY on a COLUMNS x COLUMNS grid of columns. Spandrel
# bands (the cladding left between windows) on the three closed sides, torn off at a ragged height
# per bay. The open side has none, so the slabs read as stripes. Above `break_start` the slabs go
# partial and then missing, and the columns stop at ragged heights, a few poking up past the last
# floor; one slab hangs off the break.

func _hero() -> void:
	var w := hero_width
	var h := hero_height
	var col := HERO_TONE
	var f := hero_frame
	_capped(Vector3(w + 8.0, podium_height, w + 8.0), f.translated_local(Vector3(0.0, podium_height * 0.5, 0.0)), HERO_TONE * 0.9)
	var spacing := (w - 2.0) / float(COLUMNS - 1)
	var top_y := h * break_start
	for i in COLUMNS:
		for k in COLUMNS:
			var x := -w * 0.5 + 1.0 + spacing * i
			var z := -w * 0.5 + 1.0 + spacing * k
			# Full height up to the break, then ragged: some snapped low, a few standing past the top.
			var ch := h if _rng.randf() < 0.25 else lerpf(top_y, h, _rng.randf())
			ch -= podium_height
			_box(Vector3(1.4, ch, 1.4), f.translated_local(Vector3(x, podium_height + ch * 0.5, z)), col)
	var y := podium_height + STOREY
	while y < h - STOREY:
		var u := (y - top_y) / (h - top_y)
		if y < top_y:
			_capped(Vector3(w, 0.8, w), f.translated_local(Vector3(0.0, y, 0.0)), col, 0.5)
		elif _rng.randf() > u * 0.8:
			# Partial: a piece clinging to one corner, smaller the higher it is.
			var sw := w * _rng.randf_range(0.3, 0.9) * (1.0 - 0.5 * u)
			var sd := w * _rng.randf_range(0.3, 0.9) * (1.0 - 0.5 * u)
			var at := Vector3((w - sw) * 0.5 * _sign(), y, (w - sd) * 0.5 * _sign())
			_capped(Vector3(sw, 0.8, sd), f.translated_local(at), col, 0.5)
		y += STOREY
	# The slab hanging off the break, tipped down over the open side.
	# Its +Z points out of the open face; +38 deg about its +X dips the outer end. Hinged on the edge.
	var open := Vector3(open_side.x, 0.0, open_side.y).normalized()
	var b := Basis(Vector3.UP.cross(open), Vector3.UP, open) * Basis(Vector3.RIGHT, deg_to_rad(38.0))
	var hinge := open * w * 0.5 + Vector3(0.0, top_y + STOREY * 2.0, 0.0)
	_capped(Vector3(w * 0.45, 0.8, 18.0), f * Transform3D(b, hinge + b.z * 9.0), col, 0.5)
	_spandrels(w, h, top_y)


# Spandrel bands on every side but the open one: one per storey per bay, up to a ragged tear
# height per bay (lower toward the open side, so the tear runs down the corner).
func _spandrels(w: float, h: float, top_y: float) -> void:
	var col := HERO_TONE * 0.95
	var open := Vector2(open_side.x, open_side.y).normalized()
	var bays := COLUMNS - 1
	var bay := w / float(bays)
	for side: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		if side.dot(open) > 0.9:
			continue
		var along := Vector2(-side.y, side.x)
		for b in bays:
			var s := -w * 0.5 + bay * (b + 0.5)
			# 1 at the far corner from the open side, 0 next to it.
			var away := 0.5 - 0.5 * (along * s / (w * 0.5)).dot(open)
			var adjacent := absf(side.dot(open)) < 0.1
			var tear := lerpf(podium_height + 4.0 * STOREY, top_y, away if adjacent else 1.0)
			tear *= _rng.randf_range(0.75, 1.05)
			var y := podium_height + STOREY
			while y < minf(tear, h):
				var at := Vector3(side.x * (w * 0.5 + 0.4) + along.x * s, y - 1.2, side.y * (w * 0.5 + 0.4) + along.y * s)
				var size := Vector3(bay - 0.6, 1.8, 0.6) if absf(side.y) > 0.5 else Vector3(0.6, 1.8, bay - 0.6)
				_box(size, hero_frame.translated_local(at), col)
				y += STOREY


func _sign() -> float:
	return 1.0 if _rng.randf() < 0.5 else -1.0


# The landmark's footprint as keep-out circles (the toppled tower as a row of them along its length).
func _keep_neighbour(row: Array) -> void:
	var at := Vector2(row[1], row[2])
	match row[0]:
		&"toppled":
			var length: float = row[5]
			var x := -length * 0.5
			while x <= length * 0.5:
				_keep_out.append(Vector3(at.x + x, at.y, row[3] + 6.0))
				x += 15.0
		&"crane":
			_keep_out.append(Vector3(at.x, at.y, 14.0))
		_:
			_keep_out.append(Vector3(at.x, at.y, maxf(row[3], row[4]) * 0.72 + 6.0))


func _kept_out(x: float, z: float, radius: float) -> bool:
	for k: Vector3 in _keep_out:
		if Vector2(x - k.x, z - k.y).length() < radius + k.z:
			return true
	return false


# Hero-frame point (x, z) on the ground -> world.
func _at(x: float, z: float, y := 0.0) -> Vector3:
	return hero_frame * Vector3(x, y, z)


# A frame on the grid at hero-frame (x, z), turned `yaw` radians more.
func _lot_frame(x: float, z: float, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _grid + yaw), _at(x, z))


# --- rubble in the streets -----------------------------------------------------------------------
# Concrete spilled out of the lots: each mound snapped onto a street line, some onto a crossing.

func _scatter_rubble() -> void:
	var n := 0
	var tries := 0
	while n < rubble_count and tries < rubble_count * 20:
		tries += 1
		var a := _rng.randf() * TAU
		var r := lerpf(60.0, rubble_radius, sqrt(_rng.randf()))
		var p := Vector2(cos(a), sin(a)) * r
		# A crossing (both snapped), else onto one street or the other.
		var crossing := _rng.randf() < 0.3
		var on_x := crossing or _rng.randf() < 0.5
		if on_x:
			p.x = _street_line(p.x, street_block.x)
		if crossing or not on_x:
			p.y = _street_line(p.y, street_block.y)
		if _kept_out(p.x, p.y, 10.0):
			continue
		var size := Vector3(_rng.randf_range(10.0, 22.0), _rng.randf_range(3.0, 7.0), _rng.randf_range(8.0, 18.0))
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(-10.0, 10.0)))
		var frame := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * tilt, _at(p.x, p.y, size.y * 0.3))
		_capped(size, frame, _concrete(), 1.5)
		_keep_out.append(Vector3(p.x, p.y, maxf(size.x, size.z) * 0.5))
		n += 1


# The nearest street centre line to `v` on a grid of `pitch` (the hero is mid-block).
func _street_line(v: float, pitch: float) -> float:
	return (roundf(v / pitch + 0.5) - 0.5) * pitch


# --- the packed city -----------------------------------------------------------------------------
# Every block inside `city_radius` split into 2-3 x 2-3 lots; each lot a shell, a stump, a
# collapsed heap or empty. Taller toward the hero. Past `detail_radius` only plain boxes.

func _packed_city() -> void:
	var nx := ceili(city_radius / street_block.x) + 1
	var nz := ceili(city_radius / street_block.y) + 1
	var hx := street_block.x * 0.5 - street_width * 0.5 - pavement
	var hz := street_block.y * 0.5 - street_width * 0.5 - pavement
	for i in range(-nx, nx + 1):
		for j in range(-nz, nz + 1):
			var centre := Vector2(i * street_block.x, j * street_block.y)
			if centre.length() - street_block.length() * 0.5 > city_radius:
				continue
			var xs := _splits(-hx, hx, 2 if _rng.randf() < 0.55 else 3)
			var zs := _splits(-hz, hz, 2 if _rng.randf() < 0.45 else 3)
			for a in xs.size() - 1:
				for b in zs.size() - 1:
					var lo := Vector2(xs[a], zs[b]) + centre
					var hi := Vector2(xs[a + 1], zs[b + 1]) + centre
					_lot(lo, hi)


# `n` lots between `lo` and `hi`: n + 1 split points, the inner ones jittered.
func _splits(lo: float, hi: float, n: int) -> Array[float]:
	var out: Array[float] = [lo]
	var step := (hi - lo) / n
	for k in range(1, n):
		out.append(lo + step * (k + _rng.randf_range(-0.2, 0.2)))
	out.append(hi)
	return out


func _lot(lo: Vector2, hi: Vector2) -> void:
	# Party walls nearly touch: a 0.5-2 m gap, more set back from the street now and then.
	var inset := Vector2(_rng.randf_range(0.5, 2.0), _rng.randf_range(0.5, 2.0))
	var size := hi - lo - inset * 2.0
	var c := (lo + hi) * 0.5
	var r := c.length()
	var reach := size.length() * 0.5
	if r > city_radius or r - reach < clear_radius:
		return
	if _kept_out(c.x, c.y, reach * 0.8) or _on_highway(c, reach):
		return
	var pick := _rng.randf()
	var kind: StringName = &"empty"
	if pick < shell_chance:
		kind = &"shell"
	elif pick < shell_chance + stump_chance:
		kind = &"stump"
	elif pick < shell_chance + stump_chance + collapsed_chance:
		kind = &"collapsed"
	var near := 1.0 - smoothstep(clear_radius, 1200.0, r)
	var h := lerpf(height_far, height_near, near) * _rng.randf_range(0.55, 1.1)
	h = clampf(window_floor * roundf(h / window_floor), 8.0, 56.0)
	var frame := _lot_frame(c.x, c.y)
	var col := _concrete()
	var detail := r < detail_radius
	match kind:
		&"shell":
			if detail:
				_shell(frame, size, h, col)
			else:
				_plain(frame, size, h, col)
		&"stump":
			if detail:
				_stump(frame, size, h, col)
			else:
				_plain(frame, size, h, col)
		&"collapsed":
			_collapsed(frame, size, col, detail)
		_:
			h = 0.0
	if detail and (kind == &"shell" or kind == &"stump"):
		_drifts(frame, size, h)
	lots.append({kind = kind, at = frame.origin, height = h, size = size})


func _plain(frame: Transform3D, size: Vector2, h: float, col: Color) -> void:
	_windows = true
	_capped(Vector3(size.x, h, size.y), frame.translated_local(Vector3(0.0, h * 0.5, 0.0)), col, 1.0)
	_windows = false


# Roofless: four walls with ragged tops (each wall in 2-4 runs of their own height), a run now and
# then missing, sometimes a piece of one floor left inside.
func _shell(frame: Transform3D, size: Vector2, h: float, col: Color) -> void:
	var t := 1.2
	_windows = true
	for side: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var length := size.y if side.x != 0.0 else size.x
		var runs := _rng.randi_range(2, 4)
		var run := length / runs
		for k in runs:
			if _rng.randf() < 0.12:
				continue
			var rh := h * _rng.randf_range(0.55, 1.0)
			var s := -length * 0.5 + run * (k + 0.5)
			var at := Vector3(side.x * (size.x - t) * 0.5, rh * 0.5, side.y * (size.y - t) * 0.5)
			var dims := Vector3(t, rh, run)
			if side.x != 0.0:
				at.z = s
			else:
				at.x = s
				dims = Vector3(run, rh, t)
			_capped(dims, frame.translated_local(at), col, 0.6)
	_windows = false
	if _rng.randf() < 0.4 and h > 3.0 * window_floor:
		var y := window_floor * _rng.randi_range(1, int(h / window_floor) - 2)
		var sw := (size.x - 2.0 * t) * _rng.randf_range(0.3, 0.7)
		var at := Vector3((size.x - 2.0 * t - sw) * 0.5 * _sign(), y, 0.0)
		_capped(Vector3(sw, 0.6, size.y - 2.0 * t), frame.translated_local(at), col, 0.5)


# Solid with its roof: a jagged stub or two where the top floors sheared, and clutter on the roof.
func _stump(frame: Transform3D, size: Vector2, h: float, col: Color) -> void:
	_windows = true
	_capped(Vector3(size.x, h, size.y), frame.translated_local(Vector3(0.0, h * 0.5, 0.0)), col, 1.0)
	if _rng.randf() < 0.5:
		var sw := size.x * _rng.randf_range(0.25, 0.5)
		var sd := size.y * _rng.randf_range(0.4, 0.9)
		var sh := window_floor * _rng.randi_range(1, 2)
		var at := Vector3((size.x - sw) * 0.5 * _sign(), h + sh * 0.5, (size.y - sd) * 0.5 * _sign())
		_capped(Vector3(sw, sh, sd), frame.translated_local(at), col, 0.6)
	_windows = false
	_clutter(frame.translated_local(Vector3(0.0, h + 0.6, 0.0)), size)


# Rooftop clutter: water tanks, a stair housing, a cluster of AC boxes. Never on the edge.
func _clutter(roof: Transform3D, size: Vector2) -> void:
	var col := TONES[4]
	var room := size * 0.5 - Vector2(4.0, 4.0)
	if room.x <= 0.0 or room.y <= 0.0:
		return
	for i in _rng.randi_range(1, 4):
		var at := Vector3(_rng.randf_range(-room.x, room.x), 0.0, _rng.randf_range(-room.y, room.y))
		var yaw := Basis(Vector3.UP, deg_to_rad(_rng.randf_range(-6.0, 6.0)))
		match _rng.randi() % 3:
			0:
				# A tank up on its frame: the frame reads as a dark base.
				_box(Vector3(3.0, 2.5, 3.0), roof * Transform3D(yaw, at + Vector3(0.0, 1.25, 0.0)), col)
				_capped(Vector3(4.0, 3.5, 4.0), roof * Transform3D(yaw, at + Vector3(0.0, 4.25, 0.0)), TONES[2], 0.6)
			1:
				_capped(Vector3(4.0, 3.5, 6.0), roof * Transform3D(yaw, at + Vector3(0.0, 1.75, 0.0)), col, 0.6)
			_:
				for k in _rng.randi_range(2, 4):
					var off := Vector3(k * 2.6 - 3.0, 0.75, _rng.randf_range(-0.5, 0.5))
					_capped(Vector3(2.0, 1.5, 2.0), roof * Transform3D(yaw, at + yaw * off), col, 0.4)


# Fallen in: heaps inside the footprint, sometimes one wall fragment still up.
func _collapsed(frame: Transform3D, size: Vector2, col: Color, detail: bool) -> void:
	var heaps := _rng.randi_range(3, 6) if detail else 1
	for i in heaps:
		var hs := Vector3(size.x * _rng.randf_range(0.25, 0.55), _rng.randf_range(2.0, 7.0), size.y * _rng.randf_range(0.25, 0.55))
		var at := Vector3(_rng.randf_range(-0.5, 0.5) * (size.x - hs.x), hs.y * 0.3, _rng.randf_range(-0.5, 0.5) * (size.y - hs.z))
		var tilt := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(-12.0, 12.0)))
		_capped(hs, frame * Transform3D(tilt, at), col, 1.2)
	if detail and _rng.randf() < 0.4:
		var fh := window_floor * _rng.randi_range(2, 4)
		var fw := size.x * _rng.randf_range(0.3, 0.7)
		_windows = true
		_capped(Vector3(fw, fh, 1.2), frame.translated_local(Vector3((size.x - fw) * 0.5 * _sign(), fh * 0.5, (size.y - 1.2) * 0.5 * _sign())), col, 0.6)
		_windows = false


# Snow drifts: a long wedge banked against the lee (-Z) wall, a short one against the windward wall.
func _drifts(frame: Transform3D, size: Vector2, h: float) -> void:
	var lee := Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, -size.y * 0.5))
	var dh := minf(_rng.randf_range(drift_height.x, drift_height.y), h * 0.6)
	_wedge(frame * lee, size.x * _rng.randf_range(0.6, 1.0), dh, _rng.randf_range(drift_reach.x, drift_reach.y))
	if _rng.randf() < 0.6:
		var wind := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, size.y * 0.5))
		_wedge(frame * wind, size.x * _rng.randf_range(0.4, 0.8), dh * 0.4, dh * 0.8)


# A drift: a prism along frame X, `height` against the wall at z = 0 sloping to the snow at
# z = `reach` (frame +Z points out of the wall), sunk a little. Ends rounded off by a shorter top.
func _wedge(frame: Transform3D, length: float, height: float, reach: float) -> void:
	var col := C_PEAK_SNOW
	var l := length * 0.5
	var top := l * 0.8
	var a0 := frame * Vector3(-top, height, 0.0)
	var b0 := frame * Vector3(top, height, 0.0)
	var a1 := frame * Vector3(-l, -0.3, reach)
	var b1 := frame * Vector3(l, -0.3, reach)
	var a2 := frame * Vector3(-l - reach * 0.5, -0.3, 0.0)
	var b2 := frame * Vector3(l + reach * 0.5, -0.3, 0.0)
	var slope := (b0 - a0).cross(a1 - a0).normalized()
	if slope.y < 0.0:
		slope = -slope
	_tri(a0, b0, a1, slope, col)
	_tri(b0, b1, a1, slope, col)
	var na := (a1 - a0).cross(a2 - a0).normalized()
	if na.dot(frame.basis.x) > 0.0:
		na = -na
	_tri(a0, a1, a2, na, col)
	var nb := (b1 - b0).cross(b2 - b0).normalized()
	if nb.dot(frame.basis.x) < 0.0:
		nb = -nb
	_tri(b0, b1, b2, nb, col)


# --- cars --------------------------------------------------------------------------------------
# Snow-buried cars parked along both kerbs of every street out to `car_radius`, and a pile-up at a
# few crossings.

func _street_cars() -> void:
	var kerb := street_width * 0.5 - 2.2
	for axis in 2:
		var pitch := street_block.x if axis == 0 else street_block.y
		var along_pitch := street_block.y if axis == 0 else street_block.x
		var n := ceili(car_radius / pitch) + 1
		for k in range(-n, n):
			var line := (k + 0.5) * pitch
			var s := -car_radius
			while s < car_radius:
				for side: float in [-1.0, 1.0]:
					if _rng.randf() >= car_chance:
						continue
					var p := Vector2(line + side * kerb, s) if axis == 0 else Vector2(s, line + side * kerb)
					# Not across a crossing.
					var into := fposmod(s + along_pitch * 0.5, along_pitch)
					if into < street_width * 0.7 or into > along_pitch - street_width * 0.7:
						continue
					if p.length() > car_radius or _kept_out(p.x, p.y, 3.0):
						continue
					var yaw := (0.0 if axis == 0 else PI * 0.5) + deg_to_rad(_rng.randf_range(-8.0, 8.0))
					_car(_lot_frame(p.x, p.y, yaw))
					street_cars += 1
				s += 6.0
	for i in jam_count:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(150.0, car_radius * 0.85)
		var at := Vector2(_street_line(cos(a) * r, street_block.x), _street_line(sin(a) * r, street_block.y))
		for k in _rng.randi_range(8, 14):
			var p := at + Vector2(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-12.0, 12.0))
			if _kept_out(p.x, p.y, 3.0):
				continue
			_car(_lot_frame(p.x, p.y, _rng.randf() * TAU))
			street_cars += 1


# A car under snow: a dark body, a cabin, and a snow cap (thick on half of them: just a lump).
func _car(frame: Transform3D) -> void:
	var col := CAR_TONES[_rng.randi() % CAR_TONES.size()]
	_box(Vector3(1.9, 1.0, 4.6), frame.translated_local(Vector3(0.0, 0.5, 0.0)), col)
	var snow := 0.3 if _rng.randf() < 0.5 else 0.9
	_capped(Vector3(1.7, 0.6, 2.4), frame.translated_local(Vector3(0.0, 1.3, -0.2)), col, snow)


# --- the elevated highway ------------------------------------------------------------------------
# A straight deck on pillars across the grid, clipped to the city's radius. One span is snapped in
# the middle: its two halves hang off their pillars, broken ends dropped toward each other, the
# middle of it in a heap below. Stalled cars on the deck, packed near the break.

func _highway_dir() -> Vector2:
	var a := deg_to_rad(highway_degrees)
	return Vector2(sin(a), cos(a))


func _on_highway(c: Vector2, reach: float) -> bool:
	var d := _highway_dir()
	var off := c - highway_point
	var across := absf(off.x * d.y - off.y * d.x)
	return across < reach + deck_width * 0.5 + 4.0


func _highway() -> void:
	var d := _highway_dir()
	# Where the line leaves the city's circle: |point + s d| = city_radius.
	var b := highway_point.dot(d)
	var disc := b * b - (highway_point.length_squared() - city_radius * city_radius)
	if disc <= 0.0:
		return
	var s0 := -b - sqrt(disc)
	var s1 := -b + sqrt(disc)
	var yaw := atan2(d.x, d.y)
	var col := TONES[0]
	var spans := floori((s1 - s0) / pillar_spacing)
	var broken := clampi(floori((break_along - s0) / pillar_spacing), 0, spans - 1)
	for k in spans + 1:
		var s := s0 + k * pillar_spacing
		var p := highway_point + d * s
		var f := _lot_frame(p.x, p.y, yaw)
		_box(Vector3(4.0, deck_height - 2.0, 3.5), f.translated_local(Vector3(0.0, (deck_height - 2.0) * 0.5, 0.0)), col)
		_box(Vector3(deck_width * 0.8, 2.0, 3.5), f.translated_local(Vector3(0.0, deck_height - 2.5, 0.0)), col)
		_keep_out.append(Vector3(p.x, p.y, 6.0))
	for k in spans:
		var mid := highway_point + d * (s0 + (k + 0.5) * pillar_spacing)
		var f := _lot_frame(mid.x, mid.y, yaw)
		if k == broken:
			_broken_span(f, col)
		else:
			_span(f, pillar_spacing, col)
			_deck_cars(f, pillar_spacing)
	var a := highway_point + d * s0
	var e := highway_point + d * s1
	var gap := highway_point + d * (s0 + (broken + 0.5) * pillar_spacing)
	highway = {start = _at(a.x, a.y, deck_height), end = _at(e.x, e.y, deck_height), break_at = _at(gap.x, gap.y, deck_height)}


# One span of deck along frame Z, `length` long, its top at deck_height: slab, parapets, median.
func _span(f: Transform3D, length: float, col: Color) -> void:
	_capped(Vector3(deck_width, 1.8, length), f.translated_local(Vector3(0.0, deck_height - 0.9, 0.0)), col, 0.5)
	for side: float in [-1.0, 1.0]:
		_capped(Vector3(0.8, 1.1, length), f.translated_local(Vector3(side * (deck_width - 0.8) * 0.5, deck_height + 0.55, 0.0)), col, 0.3)
	_capped(Vector3(0.8, 0.9, length), f.translated_local(Vector3(0.0, deck_height + 0.45, 0.0)), col, 0.3)


# The snapped span: each half hinged at its pillar, tipped down toward the gap, cars slid toward
# the broken ends; the middle lies in a heap on the snow.
func _broken_span(f: Transform3D, col: Color) -> void:
	var half := pillar_spacing * 0.5 - 3.0
	for side: float in [-1.0, 1.0]:
		var drop := deg_to_rad(_rng.randf_range(18.0, 28.0))
		var hinge := f.translated_local(Vector3(0.0, deck_height, -side * pillar_spacing * 0.5))
		# Turning about +X by `side * drop` dips the end that points at the gap.
		var piece := hinge * Transform3D(Basis(Vector3.RIGHT, side * drop), Vector3.ZERO)
		var centre := piece.translated_local(Vector3(0.0, 0.0, side * half * 0.5))
		_capped(Vector3(deck_width * _rng.randf_range(0.85, 1.0), 1.8, half), centre.translated_local(Vector3(0.0, -0.9, 0.0)), col, 0.5)
		for k in _rng.randi_range(2, 4):
			var at := Vector3(_rng.randf_range(-9.0, 9.0), 0.0, side * _rng.randf_range(half * 0.55, half * 0.95))
			_car(piece * Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.6, 0.6)), at))
			deck_cars += 1
	for i in 3:
		var hs := Vector3(deck_width * _rng.randf_range(0.4, 0.8), 2.0, _rng.randf_range(6.0, 10.0))
		var at := Vector3(_rng.randf_range(-6.0, 6.0), 1.0, _rng.randf_range(-6.0, 6.0))
		var tilt := Basis(Vector3.UP, _rng.randf_range(-0.5, 0.5)) * Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(-15.0, 15.0)))
		_capped(hs, f * Transform3D(tilt, at), col, 1.0)


# Stalled cars on a span: three lanes each way, `deck_car_chance` per 7 m slot.
func _deck_cars(f: Transform3D, length: float) -> void:
	for lane: float in [-10.0, -6.5, -3.0, 3.0, 6.5, 10.0]:
		var z := -length * 0.5 + 3.5
		while z < length * 0.5 - 2.0:
			if _rng.randf() < deck_car_chance:
				var at := Vector3(lane + _rng.randf_range(-0.6, 0.6), deck_height, z)
				_car(f * Transform3D(Basis(Vector3.UP, deg_to_rad(_rng.randf_range(-10.0, 10.0))), at))
				deck_cars += 1
			z += 7.0
