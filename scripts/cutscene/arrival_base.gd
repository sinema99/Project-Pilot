class_name ArrivalBase
extends Node3D

# The base in the arrival shot (docs/specs/cutscene-arrival.md): the decks from ArrivalShot's DECKS
# (frame outlines on their top planes, extruded down) and the mushroom towers from TOWERS, plus the
# sister outpost on the far peak (OUTPOST).
#
# Revision 2's rule: nothing on it without a reason. A deck, top down: a snow roof rounded over the
# edge (a cornice), carrying what that deck is for (`roof`: the landing apron, ops housings, the
# utilities run), snow drifted against the windward side of everything that stands up; a lit fascia
# split by a dark groove, jointed at each structural bay; the dark recessed underside band; then its
# legs. `plinth` legs are the foundation: a dark wall in bays that steps down the slope, a lit footing
# ledge at its foot, and a buttress every few bays where the drop is big (the fascia's joints line up
# with them). `pillars` (the right extension) stand on a stepped footing strip.
# A tower: ribbed octagonal shaft on a flared footing half-buried in drift, collar, flared skirt, a
# two-slab rim with a dark gap, then a top that shows its job (`role`).
#
# GENERATED like ArrivalLand: no owner, nothing saved into the .tscn. Built after Land (above it in
# the tree), which it asks for ground heights.

const CEL_BASE := "res://resources/cel_ground.tres"
const CREASE := "res://resources/cel_crease_material.tres"

## The reference's grade: snow roofs, steel-grey walls apart from the bluish snow, near-black
## underside. Plowed deck where it is used (pads, the taxi lane), and one muted safety orange for the
## pad rings and the hangar's edge (spec R2-9). Seams and streaks are the wall a few shades down.
const C_ROOF := Color(0.86, 0.87, 0.89)
const C_WALL := Color(0.42, 0.43, 0.45)
const C_UNDER := Color(0.08, 0.09, 0.11)
const C_PLOWED := Color(0.5, 0.52, 0.55)
const C_ACCENT := Color(0.66, 0.36, 0.17)
const C_SEAM := Color(0.27, 0.28, 0.3)
## The wind blows toward +x (the spindrift streams right), so windward faces look toward -x.
const WIND_FROM := Vector2(-1.0, 0.0)

## The outpost deck, in metres around its centre: half length (along x), half depth, chamfer,
## slab thickness.
const OUTPOST_HALF := Vector2(300.0, 110.0)
const OUTPOST_CHAMFER := 60.0
const OUTPOST_THICK := 30.0
## The outpost's towers: x, z offset from the deck centre (m), cap top above the deck (m), cap and
## shaft radius (m).
const OUTPOST_TOWERS := [
	[-210.0, -50.0, 190.0, 110.0, 52.0],
	[170.0, -90.0, 260.0, 150.0, 70.0],
	[40.0, 50.0, 120.0, 80.0, 40.0],
]

## Pillars under the right extension: size (m square) and spacing along the edge (m).
@export var pillar_size := 9.0
@export var pillar_spacing := 15.0
## The foundation: bay length along the wall (m, the fascia's joints match it), the footing ledge's
## reach out of the wall and height over the bay's highest ground (m), a buttress every
## `buttress_every` bays where the wall drops more than `buttress_drop` m, and its half-width (m).
@export var bay := 48.0
@export var footing_out := 5.0
@export var footing_height := 5.0
@export var buttress_every := 3
@export var buttress_drop := 22.0
@export var buttress_half := 6.0
## The fascia's groove: where it runs (fractions of the slab's thickness down from the top) and how
## deep it is cut (m). Joints: width (m).
@export var groove_from := 0.45
@export var groove_to := 0.6
@export var groove_depth := 3.0
@export var seam_width := 1.6
## The snow over the deck edge: how far it stands out (m) and hangs down (m).
@export var cornice_out := 0.8
@export var cornice_drop := 1.8
## Drifts on the windward side: height as a fraction of what they lean on, length as a multiple of
## their height.
@export var drift_height := 0.7
@export var drift_length := 2.6
## The towers' cap proportions, fractions of the cap radius: upper step (radius, height), upper
## rim slab height, the dark gap's height, lower rim slab height, skirt height, collar height.
@export var step_radius := 0.6
@export var step_height := 0.1
@export var rim_height := 0.13
@export var gap_height := 0.05
@export var lower_rim_height := 0.09
@export var skirt_height := 0.22
@export var collar_height := 0.12
## Ribs around each shaft: count, and their size as a fraction of the shaft radius.
@export var ribs := 16
@export var rib_size := 0.12
## Ink fade (m) for the base's crease lines: the cel default (45-120 m) is far too short here.
@export var ink_fade_start := 5000.0
@export var ink_fade_end := 9000.0

## World points the shot hangs a blinking beacon on: the tower caps (the comms mast's tip), the top
## tier's corners, the outpost's tallest cap.
var beacon_spots: Array[Vector3] = []
## Each tower's cap-top centre (world), in TOWERS order.
var cap_tops: Array[Vector3] = []
## The exhaust tower's stack tops (world), for the steam plume.
var plume_spots: Array[Vector3] = []
## The outpost deck's top centre (world).
var outpost_top: Vector3
## The hangar mouth's centre on the Lower deck's front fascia (world), and the pad centres.
var hangar: Vector3
var pads: Array[Vector3] = []

var _shot: ArrivalShot
var _land: ArrivalLand
var _mats := {}
## Every deck's world outline and top, for keeping roof things out from under the decks above.
var _decks: Array[Dictionary] = []


func _ready() -> void:
	_shot = get_parent() as ArrivalShot
	_land = get_node(^"../Land") as ArrivalLand
	var crease := (load(CREASE) as ShaderMaterial).duplicate() as ShaderMaterial
	crease.set_shader_parameter("fade_start_m", ink_fade_start)
	crease.set_shader_parameter("fade_end_m", ink_fade_end)
	_mats = {roof = _cel(C_ROOF, crease), wall = _cel(C_WALL, crease), under = _cel(C_UNDER, crease),
			plowed = _cel(C_PLOWED, crease), accent = _cel(C_ACCENT, crease), seam = _cel(C_SEAM, crease)}
	for deck: Dictionary in ArrivalShot.DECKS:
		_decks.append({poly = deck_outline(deck), top = deck.top})
	for deck: Dictionary in ArrivalShot.DECKS:
		_build_deck(deck, deck_outline(deck))
	_build_tier_drifts()
	for tower: Dictionary in ArrivalShot.TOWERS:
		var top := _shot.at_distance(tower.u, tower.v, tower.distance)
		cap_tops.append(top)
		_build_tower(tower.name, top, tower.cap, tower.shaft, tower.role, tower.vary)
	_build_outpost()


## A deck's outline in world xz.
func deck_outline(deck: Dictionary) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for p: Vector2 in deck.outline:
		var w := _shot.on_plane(p.x, p.y, deck.top)
		poly.append(Vector2(w.x, w.z))
	return poly


# --- decks -------------------------------------------------------------------------------------

func _build_deck(deck: Dictionary, poly: PackedVector2Array) -> void:
	var top: float = deck.top
	var thick: float = deck.thick
	var bottom := top - thick
	var s := _surfaces()
	# The roof, and the snow on it rounded over the edge.
	var lip := _inset(poly, -cornice_out)
	var y_lip := top - cornice_drop
	_cap(s.roof, lip, top, Vector3.UP)
	_walls(s.roof, lip, y_lip, top)
	_ring(s.roof, lip, poly, y_lip, Vector3.DOWN)
	# The fascia: lit, a dark groove, lit again.
	var y_groove := top - thick * groove_from
	var y_ledge := top - thick * groove_to
	var groove := _inset(poly, groove_depth)
	_walls(s.wall, poly, y_groove, y_lip)
	_walls(s.under, groove, y_ledge, y_groove)
	_ring(s.wall, poly, groove, y_ledge, Vector3.UP)
	_walls(s.wall, poly, bottom, y_ledge)
	_cap(s.under, poly, bottom, Vector3.DOWN)
	var legs_poly := poly
	var legs_from := bottom
	if deck.band > 0.0:
		legs_poly = _inset(poly, deck.inset)
		legs_from = bottom - deck.band
		_walls(s.under, legs_poly, legs_from, bottom)
	# Joints on the fascia: over the foundation's bays where it has one, else every bay of its own.
	var joints: Array[Dictionary] = []
	match deck.legs:
		&"plinth":
			joints = _foundation(s, legs_poly, legs_from, true)
			for j in joints:
				j.p += j.out * deck.inset
		&"pillars":
			_pillars(s, legs_poly, legs_from)
			# The dark mass behind them, so the legs are not a see-through fence.
			_foundation(s, _inset(legs_poly, pillar_size * 3.0), legs_from, false)
	if joints.is_empty():
		joints = _bays(poly)
	for j in joints:
		_panel(s.seam, j.p + j.out * 0.3, j.e, seam_width * 0.5, bottom + 1.0, y_lip - 0.4, j.out)
	match deck.roof:
		&"pads":
			_landing_apron(s, deck, poly, top)
		&"ops":
			_ops(s, poly, top, 46.0 if deck.thick > 19.0 else 36.0, 130.0 if deck.thick > 19.0 else 80.0)
		&"utilities":
			_utilities(s, poly, top, bottom)
		&"crown":
			var crown := _inset(poly, 22.0)
			_walls(s.wall, crown, top, top + 9.0)
			_cap(s.roof, crown, top + 9.0, Vector3.UP)
			_drifts(s.roof, crown, top, 9.0)
			var crown2 := _inset(crown, 18.0)
			_walls(s.wall, crown2, top + 9.0, top + 15.0)
			_cap(s.roof, crown2, top + 15.0, Vector3.UP)
			for p in poly:
				beacon_spots.append(Vector3(p.x, top + 4.0, p.y))
	_commit(deck.name, s)


# The foundation along `poly` from the underside `y` down into the land, in bays: each bay's dark wall
# goes down to its own lowest ground (so the wall steps down the slope) with a lit footing ledge at
# its foot, and every `buttress_every` bays where it drops far a buttress leans out of it. Returns the
# bay ends {p, e, out}, for the fascia's joints.
func _foundation(s: Dictionary, poly: PackedVector2Array, y: float, buttresses: bool) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	var outward := _orientation(poly)
	var count := 0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		var out := Vector2(e.y, -e.x) * outward
		var n := maxi(int(round(a.distance_to(b) / bay)), 1)
		for k in n:
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			marks.append({p = p0, e = e, out = out})
			var lo := INF
			var hi := -INF
			for q in 5:
				var p := p0.lerp(p1, q / 4.0) + out * 2.0
				var g := _land.height(p.x, p.y)
				lo = minf(lo, g)
				hi = maxf(hi, g)
			count += 1
			if lo > y - 1.0:
				continue
			_panel(s.under, p0, e, p0.distance_to(p1) * 0.5, lo - 12.0, y, out, true)
			var ledge := minf(hi + footing_height, y - 2.0)
			if ledge > lo - 12.0:
				_block(s.roof, s.wall, PackedVector2Array([p0, p1, p1 + out * footing_out, p0 + out * footing_out]),
						lo - 12.0 - footing_out, ledge)
			if buttresses and count % buttress_every == 0 and y - lo > buttress_drop:
				_buttress(s.wall, p0, e, out, y, lo)
	return marks


# A buttress leaning out of the wall at `p`: full height at the wall, sloping down to a toe at
# ground level, its reach growing with the drop.
func _buttress(st: SurfaceTool, p: Vector2, e: Vector2, out: Vector2, y: float, ground: float) -> void:
	var reach := clampf((y - ground) * 0.4, 8.0, 26.0)
	var toe := ground + 6.0
	var low := ground - 14.0 - reach * 0.8
	var i0 := p - e * buttress_half
	var i1 := p + e * buttress_half
	var o0 := i0 + out * reach
	var o1 := i1 + out * reach
	var v := func(q: Vector2, h: float) -> Vector3: return Vector3(q.x, h, q.y)
	var side := Vector3(e.x, 0.0, e.y)
	var front := Vector3(out.x, 0.0, out.y)
	for pair in [[i0, o0, -side], [i1, o1, side]]:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		_tri(st, v.call(a, low), v.call(b, low), v.call(b, toe), pair[2])
		_tri(st, v.call(a, low), v.call(b, toe), v.call(a, y), pair[2])
	_tri(st, v.call(o0, low), v.call(o1, low), v.call(o1, toe), front)
	_tri(st, v.call(o0, low), v.call(o1, toe), v.call(o0, toe), front)
	var slope := (front * (y - toe) + Vector3.UP * reach).normalized()
	_tri(st, v.call(o0, toe), v.call(o1, toe), v.call(i1, y), slope)
	_tri(st, v.call(o0, toe), v.call(i1, y), v.call(i0, y), slope)


# The ends of `bay`-long stretches along every edge of `poly`: {p, e, out}.
func _bays(poly: PackedVector2Array) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	var outward := _orientation(poly)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		var n := maxi(int(round(a.distance_to(b) / bay)), 1)
		for k in range(1, n):
			marks.append({p = a.lerp(b, float(k) / n), e = e, out = Vector2(e.y, -e.x) * outward})
	return marks


# Pillars along every edge of `poly`, from `y` down into the land wherever it is lower, each pair
# standing on a stretch of footing strip that steps down with the ground.
func _pillars(s: Dictionary, poly: PackedVector2Array, y: float) -> void:
	var half := pillar_size * 0.5
	var outward := _orientation(poly)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		var across := Vector2(e.y, -e.x) * outward * pillar_size * 0.9
		var n := maxi(int(a.distance_to(b) / pillar_spacing), 1)
		for k in n:
			var p := a.lerp(b, (k + 0.5) / n)
			var ground := _land.height(p.x, p.y)
			if ground > y - 3.0:
				continue
			var square := PackedVector2Array([p + Vector2(-half, -half), p + Vector2(half, -half),
					p + Vector2(half, half), p + Vector2(-half, half)])
			_walls(s.under, square, ground - 10.0, y)
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			var lo := minf(_land.height(p0.x, p0.y), _land.height(p1.x, p1.y))
			var hi := maxf(maxf(_land.height(p0.x, p0.y), _land.height(p1.x, p1.y)), ground)
			_block(s.roof, s.wall, PackedVector2Array([p0 - across, p1 - across, p1 + across, p0 + across]),
					lo - 10.0, minf(hi + 4.0, y - 2.0))


# --- what the roofs are for --------------------------------------------------------------------

# The landing apron (spec R2-3): plowed pads with orange rings, the plowed taxi lane through them to
# the front edge, and the hangar mouth cut into the fascia there, edged in orange.
func _landing_apron(s: Dictionary, deck: Dictionary, poly: PackedVector2Array, top: float) -> void:
	var lane := PackedVector2Array()
	for q: Vector2 in ArrivalShot.LANE:
		var w := _shot.on_plane(q.x, q.y, top)
		lane.append(Vector2(w.x, w.z))
	var half := ArrivalShot.LANE_WIDTH * 0.5
	for k in lane.size() - 1:
		var e := (lane[k + 1] - lane[k]).normalized()
		var n := Vector2(-e.y, e.x) * half
		var b := lane[k + 1] + e * (half if k < lane.size() - 2 else -cornice_out - 1.0)
		_cap(s.plowed, PackedVector2Array([lane[k] - n, b - n, b + n, lane[k] + n]), top + 0.25, Vector3.UP)
	for pad: Dictionary in ArrivalShot.PADS:
		var w := _shot.on_plane(pad.u, pad.v, top)
		var c := Vector2(w.x, w.z)
		pads.append(Vector3(c.x, top, c.y))
		var r: float = pad.radius
		_cap(s.plowed, _circle(c, r + 10.0, 24), top + 0.3, Vector3.UP)
		_ring(s.accent, _circle(c, r, 24), _circle(c, r - 3.5, 24), top + 0.4, Vector3.UP)
	# The hangar: on the front edge nearest the lane's end.
	var end := lane[lane.size() - 1]
	var best := 0
	var best_d := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(end, poly[i], poly[(i + 1) % poly.size()])
		if q.distance_to(end) < best_d:
			best_d = q.distance_to(end)
			best = i
	var a := poly[best]
	var b := poly[(best + 1) % poly.size()]
	var e := (b - a).normalized()
	var out := Vector2(e.y, -e.x) * _orientation(poly)
	var at := Geometry2D.get_closest_point_to_segment(end, a, b)
	var hw := ArrivalShot.HANGAR_WIDTH * 0.5
	var y0: float = top - deck.thick + 1.5
	var y1 := top - cornice_drop - 3.0
	hangar = Vector3(at.x, (y0 + y1) * 0.5, at.y)
	_panel(s.accent, at + out * 0.4, e, hw + 2.0, y0, y1 + 2.0, out)
	_panel(s.under, at + out * 0.7, e, hw, y0, y1, out)


# Ops housings (spec R2-3): long shallow plant rooms in rows along the deck's longest edge, on a
# regular grid, wherever a whole one fits clear of the rim and of the decks above. Snow on their
# roofs, drifted against their windward ends.
func _ops(s: Dictionary, poly: PackedVector2Array, top: float, row_spacing: float, length: float) -> void:
	var frame := _deck_frame(poly)
	var axis: Vector2 = frame.axis
	var across: Vector2 = frame.across
	var inner := _inset(poly, 16.0)
	var above := _above(top)
	var width := row_spacing * 0.42
	var h := 4.5
	var row: float = frame.across_min + row_spacing * 0.5
	while row < frame.across_max:
		var along: float = frame.along_min + 12.0
		while along + length < frame.along_max:
			var c: Vector2 = frame.origin + axis * (along + length * 0.5) + across * row
			var corners := PackedVector2Array([c - axis * length * 0.5 - across * width * 0.5,
					c + axis * length * 0.5 - across * width * 0.5, c + axis * length * 0.5 + across * width * 0.5,
					c - axis * length * 0.5 + across * width * 0.5])
			if _all_inside(corners, inner) and not _any_inside(corners + PackedVector2Array([c]), above):
				_block(s.roof, s.wall, corners, top, top + h)
				_drifts(s.roof, corners, top, h)
			along += length + 24.0
		row += row_spacing


# The utilities run (spec R2-3) on the right extension: one long vent duct down its spine with vent
# heads at a regular pitch, and toward the far end a radiator strip of plates standing across the
# deck, bare of snow (they run warm), streaking the fascia below them.
func _utilities(s: Dictionary, poly: PackedVector2Array, top: float, bottom: float) -> void:
	var frame := _deck_frame(poly)
	var axis: Vector2 = frame.axis
	var across: Vector2 = frame.across
	var span: float = frame.along_max - frame.along_min
	var mid: float = (frame.across_min + frame.across_max) * 0.5
	var above := _above(top)
	var at := func(f: float, off: float) -> Vector2:
		return frame.origin + axis * (frame.along_min + span * f) + across * (mid + off)
	var a: Vector2 = at.call(0.08, 0.0)
	var b: Vector2 = at.call(0.6, 0.0)
	var duct := PackedVector2Array([a - across * 5.0, b - across * 5.0, b + across * 5.0, a + across * 5.0])
	_block(s.roof, s.wall, duct, top, top + 3.0)
	_drifts(s.roof, duct, top, 3.0)
	var n := int(a.distance_to(b) / 26.0)
	for k in n:
		var c := a.lerp(b, (k + 0.5) / n)
		var head := PackedVector2Array([c - axis * 3.0 - across * 3.0, c + axis * 3.0 - across * 3.0,
				c + axis * 3.0 + across * 3.0, c - axis * 3.0 + across * 3.0])
		_block(s.under, s.wall, head, top + 3.0, top + 5.5)
	var plates := 0
	var f := 0.68
	while f < 0.9:
		var c: Vector2 = at.call(f, 0.0)
		var plate := PackedVector2Array([c - axis * 0.8 - across * 18.0, c + axis * 0.8 - across * 18.0,
				c + axis * 0.8 + across * 18.0, c - axis * 0.8 + across * 18.0])
		if not _any_inside(plate, above):
			_block(s.wall, s.wall, plate, top, top + 7.0)
			plates += 1
		f += 6.0 / span
	if plates == 0:
		return
	# Streaks down the fascia nearest the radiators.
	var centre: Vector2 = at.call(0.79, 0.0)
	var best := INF
	var edge := Vector4.ZERO
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var near := Geometry2D.get_closest_point_to_segment(centre, p, q)
		if near.distance_to(centre) < best:
			best = near.distance_to(centre)
			edge = Vector4(near.x, near.y, (q - p).normalized().x, (q - p).normalized().y)
	var e := Vector2(edge.z, edge.w)
	var out := Vector2(e.y, -e.x) * _orientation(poly)
	for k in 5:
		var p := Vector2(edge.x, edge.y) + e * (k - 2) * 9.0 + out * 0.3
		_panel(s.seam, p, e, 1.2, bottom + 6.0 + k % 2 * 4.0, top - cornice_drop, out)


# Drifts against the windward walls of the upper decks, on the deck each one stands on.
func _build_tier_drifts() -> void:
	var st := _surface()
	for upper: Dictionary in _decks:
		var below := -INF
		for d: Dictionary in _decks:
			if d.top < upper.top and d.top > below and Geometry2D.is_point_in_polygon(_centroid(upper.poly), d.poly):
				below = d.top
		if below == -INF:
			continue
		var outward := _orientation(upper.poly)
		for i in upper.poly.size():
			var a: Vector2 = upper.poly[i]
			var b: Vector2 = upper.poly[(i + 1) % upper.poly.size()]
			var e := (b - a).normalized()
			var out := Vector2(e.y, -e.x) * outward
			if out.dot(WIND_FROM) < 0.5:
				continue
			# Only where the foot of the wall is on the deck below, not over its edge.
			var lower := _deck_under(a.lerp(b, 0.5) + out * 10.0, upper.top)
			if lower.is_empty() or lower.top != below:
				continue
			_drift(st, a.lerp(b, 0.08), b.lerp(a, 0.08), out, below, minf(upper.top - below, 12.0) * drift_height)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, _mats.roof)
		var mi := MeshInstance3D.new()
		mi.name = "TierDrifts"
		mi.mesh = mesh
		add_child(mi)


# --- towers ------------------------------------------------------------------------------------

func _build_tower(tower_name: String, top: Vector3, r: float, sr: float, role: StringName, vary: float,
		beacons := true) -> void:
	var centre := Vector2(top.x, top.z)
	var s := _surfaces()
	var step_h := r * (0.16 if role == &"control" else step_height)
	var y_step := top.y if role == &"pad" else top.y - step_h
	var y_rim := y_step - rim_height * r
	var y_gap := y_rim - gap_height * r
	var y_low := y_gap - lower_rim_height * r
	var y_skirt := y_low - skirt_height * r * vary
	var y_collar := y_skirt - collar_height * r * vary
	var ground := _land.height(top.x, top.z)
	var foot := ground - 20.0
	if role != &"pad":
		var sp := r * step_radius * (0.85 if role == &"sensor" else 1.0)
		var step := _octagon(centre, sp)
		_cap(s.roof, step, top.y, Vector3.UP)
		if role == &"control":
			# One continuous glazing band round the cap, a thin steel lip over it.
			_walls(s.wall, step, top.y - r * 0.025, top.y)
			_walls(s.under, step, y_step, top.y - r * 0.025)
		else:
			_walls(s.wall, step, y_step, top.y)
	var rim := _octagon(centre, r)
	_cap(s.roof, rim, y_step, Vector3.UP)
	_walls(s.wall, rim, y_rim, y_step)
	var gap := _octagon(centre, r * 0.9)
	_walls(s.under, gap, y_gap, y_rim)
	var low := _octagon(centre, r * 0.97)
	_ring(s.wall, low, gap, y_gap, Vector3.UP)
	_walls(s.wall, low, y_low, y_gap)
	_frustum(s.under, _octagon(centre, r * 0.9), y_low, _octagon(centre, sr * 1.15), y_skirt)
	var collar := _octagon(centre, sr * 1.22)
	_ring(s.wall, collar, _octagon(centre, sr * 1.15), y_skirt, Vector3.UP)
	_walls(s.wall, collar, y_collar, y_skirt)
	var shaft := _octagon(centre, sr)
	_walls(s.wall, shaft, foot, y_collar)
	var w := sr * rib_size
	for i in ribs:
		var a := TAU * i / ribs
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x)
		var c := centre + dir * (sr * 0.95)
		var box := PackedVector2Array([c - side * w * 0.5, c + dir * w - side * w * 0.5,
				c + dir * w + side * w * 0.5, c + side * w * 0.5])
		_walls(s.wall, box, foot, y_collar)
	_footing(s, centre, sr, ground)
	var y_beacon := y_step + 4.0
	match role:
		&"comms":
			_comms(s, centre, r, top.y)
		&"pad":
			_cap(s.plowed, _circle(centre, r * 0.72, 24), top.y + 0.3, Vector3.UP)
			_ring(s.accent, _circle(centre, r * 0.6, 24), _circle(centre, r * 0.55, 24), top.y + 0.4, Vector3.UP)
		&"exhaust":
			_exhaust(s, centre, r, top.y, y_step, y_low)
		&"sensor":
			_radome(s, centre, r * 0.3, top.y)
	if beacons:
		for u in [-1.0, 1.0]:
			beacon_spots.append(Vector3(top.x + u * r * 0.85, y_beacon, top.z))
		beacon_spots.append(top + Vector3.UP * (r * 1.12 if role == &"comms" else 4.0))
	_commit(tower_name, s)


# The tower's foot: a flared steel footing into the ground, half-buried in a ring of drifted snow.
# Sized off the ground at the centre; on a slope the land itself covers the downhill side.
func _footing(s: Dictionary, centre: Vector2, sr: float, ground: float) -> void:
	var y_top := ground + sr * 0.3
	var y_low := ground - sr * 0.4
	_frustum(s.wall, _octagon(centre, sr * 1.2), y_top, _octagon(centre, sr * 1.5), y_low)
	_cap(s.wall, _octagon(centre, sr * 1.2), y_top, Vector3.UP)
	var y_drift := ground + sr * 0.1
	var inner := _octagon(centre, sr * lerpf(1.2, 1.5, (y_top - y_drift) / (y_top - y_low)))
	_frustum(s.roof, _octagon(centre, sr * 1.55), y_drift, _octagon(centre, sr * 1.8), y_low)
	_ring(s.roof, _octagon(centre, sr * 1.55), inner, y_drift, Vector3.UP)


# Comms: a tapered mast off the cap's centre with two yardarms, and one dish on a plinth at the rim,
# tilted up toward the sky.
func _comms(s: Dictionary, centre: Vector2, r: float, y: float) -> void:
	var tip := y + r * 1.1
	_frustum(s.wall, _square(centre, r * 0.012), tip, _square(centre, r * 0.05), y)
	for f: float in [0.62, 0.84]:
		var h := lerpf(y, tip, f)
		var arm := PackedVector2Array([centre + Vector2(-r * 0.16, -r * 0.008), centre + Vector2(r * 0.16, -r * 0.008),
				centre + Vector2(r * 0.16, r * 0.008), centre + Vector2(-r * 0.16, r * 0.008)])
		_block(s.wall, s.wall, arm, h - r * 0.012, h)
	var at := centre + Vector2(-0.55, 0.55).normalized() * r * 0.72
	var y_rim := y - step_height * r
	_block(s.roof, s.wall, _square(at, r * 0.06), y_rim, y_rim + r * 0.08)
	var facing := Vector3(-0.5, 0.75, 0.45).normalized()
	_dish(s.wall, Vector3(at.x, y_rim + r * 0.2, at.y), facing, r * 0.17, r * 0.06)


# Exhaust: a row of short stacks on the cap's downwind side, open (dark) at the top, soot streaking
# the step and the rim below them. Their tops are where the steam leaves.
func _exhaust(s: Dictionary, centre: Vector2, r: float, y: float, y_step: float, y_low: float) -> void:
	for k in 5:
		var z := (k - 2) * r * 0.12
		var c := centre + Vector2(r * 0.32, z)
		var stack := _octagon(c, r * 0.055)
		_walls(s.wall, stack, y, y + r * 0.16)
		_cap(s.under, stack, y + r * 0.16, Vector3.UP)
		plume_spots.append(Vector3(c.x, y + r * 0.16, c.y))
		var face_step := centre + Vector2(r * step_radius * cos(PI / 8.0) + 0.3, z)
		_panel(s.seam, face_step, Vector2(0.0, 1.0), r * 0.018, y_step + r * 0.02, y - r * 0.01, Vector2.RIGHT)
		var face_rim := centre + Vector2(r * cos(PI / 8.0) + 0.3, z * 1.4)
		_panel(s.seam, face_rim, Vector2(0.0, 1.0), r * 0.018, y_low + r * 0.03, y_step - r * 0.01, Vector2.RIGHT)


# Sensor: a radome on a short drum.
func _radome(s: Dictionary, centre: Vector2, radius: float, y: float) -> void:
	var drum := _octagon(centre, radius * 1.02)
	_walls(s.wall, drum, y, y + radius * 0.2)
	_cap(s.wall, drum, y + radius * 0.2, Vector3.UP)
	var st: SurfaceTool = s.roof
	var base := Vector3(centre.x, y + radius * 0.2, centre.y)
	var rings := 6
	var segs := 16
	var pt := func(i: int, j: int) -> Vector3:
		var lat := PI * 0.5 * i / rings
		var lon := TAU * j / segs
		return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
	for i in rings:
		for j in segs:
			var a: Vector3 = pt.call(i, j)
			var b: Vector3 = pt.call(i, j + 1)
			var c: Vector3 = pt.call(i + 1, j + 1)
			var d: Vector3 = pt.call(i + 1, j)
			_smooth_tri(st, base, radius, a, b, c)
			if i < rings - 1:
				_smooth_tri(st, base, radius, a, c, d)


# --- the sister outpost ------------------------------------------------------------------------

func _build_outpost() -> void:
	var o := ArrivalShot.OUTPOST
	outpost_top = _shot.at_distance(o.u, o.v, o.distance)
	var c := Vector2(outpost_top.x, outpost_top.z)
	var hx := OUTPOST_HALF.x
	var hz := OUTPOST_HALF.y
	var k := OUTPOST_CHAMFER
	var poly := PackedVector2Array()
	for p: Vector2 in [Vector2(-hx + k, -hz), Vector2(hx - k, -hz), Vector2(hx, -hz + k), Vector2(hx, hz - k),
			Vector2(hx - k, hz), Vector2(-hx + k, hz), Vector2(-hx, hz - k), Vector2(-hx, -hz + k)]:
		poly.append(c + p)
	_build_deck({name = "OutpostDeck", top = outpost_top.y, thick = OUTPOST_THICK, band = 12.0, inset = 20.0,
			legs = &"plinth", roof = &""}, poly)
	var tallest := Vector3(0.0, -INF, 0.0)
	for i in OUTPOST_TOWERS.size():
		var t: Array = OUTPOST_TOWERS[i]
		var top := outpost_top + Vector3(t[0], t[2], t[1])
		_build_tower("OutpostTower%d" % i, top, t[3], t[4], &"", 1.0, false)
		if top.y > tallest.y:
			tallest = top
	beacon_spots.append(tallest + Vector3.UP * 4.0)


# --- deck helpers ------------------------------------------------------------------------------

## A deck's own frame: its longest edge's direction (`axis`), the one across it, an origin, and the
## outline's extent along both.
func _deck_frame(poly: PackedVector2Array) -> Dictionary:
	var axis := Vector2.RIGHT
	var longest := 0.0
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length() > longest:
			longest = e.length()
			axis = e.normalized()
	var across := Vector2(-axis.y, axis.x)
	var origin := poly[0]
	var f := {axis = axis, across = across, origin = origin,
			along_min = INF, along_max = -INF, across_min = INF, across_max = -INF}
	for p in poly:
		var d := p - origin
		f.along_min = minf(f.along_min, d.dot(axis))
		f.along_max = maxf(f.along_max, d.dot(axis))
		f.across_min = minf(f.across_min, d.dot(across))
		f.across_max = maxf(f.across_max, d.dot(across))
	return f


## The outlines (grown 10 m) of every deck above height `top`.
func _above(top: float) -> Array[PackedVector2Array]:
	var above: Array[PackedVector2Array] = []
	for d in _decks:
		if d.top > top:
			above.append(_inset(d.poly, -10.0))
	return above


## The highest deck under `p` lower than `top`, or {}.
func _deck_under(p: Vector2, top: float) -> Dictionary:
	var best := {}
	for d in _decks:
		if d.top < top and Geometry2D.is_point_in_polygon(p, d.poly) and (best.is_empty() or d.top > best.top):
			best = d
	return best


# Drifts against the windward faces of the box `corners` standing on `y`, `h` tall.
func _drifts(st: SurfaceTool, corners: PackedVector2Array, y: float, h: float) -> void:
	var outward := _orientation(corners)
	for i in corners.size():
		var a := corners[i]
		var b := corners[(i + 1) % corners.size()]
		var e := (b - a).normalized()
		var out := Vector2(e.y, -e.x) * outward
		if out.dot(WIND_FROM) > 0.5:
			_drift(st, a, b, out, y, h * drift_height)


# A snow wedge along the wall from `a` to `b` (xz) on floor `y`: `h` up the wall, running out
# `drift_length` times that from it, tapering off at both ends.
func _drift(st: SurfaceTool, a: Vector2, b: Vector2, out: Vector2, y: float, h: float) -> void:
	var e := (b - a).normalized()
	var taper := minf(h * 1.5, a.distance_to(b) * 0.3)
	var a1 := a + e * taper
	var b1 := b - e * taper
	var reach := out * h * drift_length
	var v := func(q: Vector2, hh: float) -> Vector3: return Vector3(q.x, hh, q.y)
	var slope := (Vector3(out.x, 0.0, out.y) * h + Vector3.UP * h * drift_length).normalized()
	_tri(st, v.call(a1, y + h), v.call(b1, y + h), v.call(b1 + reach, y + 0.2), slope)
	_tri(st, v.call(a1, y + h), v.call(b1 + reach, y + 0.2), v.call(a1 + reach, y + 0.2), slope)
	# The tapered ends: a wedge each, down to nothing at the wall's corner.
	_tri(st, v.call(a, y + 0.2), v.call(a1, y + h), v.call(a1 + reach, y + 0.2), (slope - Vector3(e.x, 0.0, e.y)).normalized())
	_tri(st, v.call(b1, y + h), v.call(b, y + 0.2), v.call(b1 + reach, y + 0.2), (slope + Vector3(e.x, 0.0, e.y)).normalized())


# --- polygon helpers ---------------------------------------------------------------------------

## A regular octagon of corner radius `r` around `c`, flat faces square to the axes.
static func _octagon(c: Vector2, r: float) -> PackedVector2Array:
	return _circle(c, r, 8, 0.5)


static func _circle(c: Vector2, r: float, n: int, phase := 0.0) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i in n:
		var a := TAU * (i + phase) / n
		poly.append(c + Vector2(cos(a), sin(a)) * r)
	return poly


static func _square(c: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-half, -half), c + Vector2(half, -half),
			c + Vector2(half, half), c + Vector2(-half, half)])


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p / poly.size()
	return c


## +1 if `poly` winds so that an edge's (e.y, -e.x) points out of it, else -1.
static func _orientation(poly: PackedVector2Array) -> float:
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	return 1.0 if area > 0.0 else -1.0


## `poly` moved `d` m inward (negative: outward), corner for corner, mitred.
static func _inset(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var outward := _orientation(poly)
	var n := poly.size()
	var out := PackedVector2Array()
	for i in n:
		var p := poly[i]
		var e0 := (p - poly[(i - 1 + n) % n]).normalized()
		var e1 := (poly[(i + 1) % n] - p).normalized()
		var n0 := -Vector2(e0.y, -e0.x) * outward
		var n1 := -Vector2(e1.y, -e1.x) * outward
		var m := (n0 + n1).normalized()
		out.append(p + m * d / maxf(m.dot(n0), 0.35))
	return out


static func _all_inside(points: PackedVector2Array, poly: PackedVector2Array) -> bool:
	for p in points:
		if not Geometry2D.is_point_in_polygon(p, poly):
			return false
	return true


static func _any_inside(points: PackedVector2Array, polys: Array[PackedVector2Array]) -> bool:
	for poly in polys:
		for p in points:
			if Geometry2D.is_point_in_polygon(p, poly):
				return true
	return false


# --- mesh helpers ------------------------------------------------------------------------------

func _surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## One surface tool per material, keyed like `_mats`.
func _surfaces() -> Dictionary:
	var s := {}
	for key in _mats:
		s[key] = _surface()
	return s


func _commit(node_name: String, s: Dictionary) -> void:
	var mesh := ArrayMesh.new()
	for key in s:
		var st: SurfaceTool = s[key]
		var before := mesh.get_surface_count()
		st.commit(mesh)
		if mesh.get_surface_count() > before:
			mesh.surface_set_material(before, _mats[key])
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	add_child(mi)


# A flat face over polygon `poly` (xz) at height `y`, facing `want` (up or down).
func _cap(st: SurfaceTool, poly: PackedVector2Array, y: float, want: Vector3) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for t in range(0, idx.size(), 3):
		var a := poly[idx[t]]
		var b := poly[idx[t + 1]]
		var c := poly[idx[t + 2]]
		_tri(st, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), want)


# The flat band between `outer` and `inner` (same corner count) at height `y`, facing `want`.
func _ring(st: SurfaceTool, outer: PackedVector2Array, inner: PackedVector2Array, y: float, want: Vector3) -> void:
	for i in outer.size():
		var j := (i + 1) % outer.size()
		var a := Vector3(outer[i].x, y, outer[i].y)
		var b := Vector3(outer[j].x, y, outer[j].y)
		var c := Vector3(inner[j].x, y, inner[j].y)
		var d := Vector3(inner[i].x, y, inner[i].y)
		_tri(st, a, b, c, want)
		_tri(st, a, c, d, want)


# The side walls of polygon `poly` (xz) from `y0` up to `y1`, facing out.
func _walls(st: SurfaceTool, poly: PackedVector2Array, y0: float, y1: float) -> void:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		var out := Vector2(e.y, -e.x)
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + out * 0.05, poly):
			out = -out
		var want := Vector3(out.x, 0.0, out.y)
		var a0 := Vector3(a.x, y0, a.y)
		var b0 := Vector3(b.x, y0, b.y)
		var a1 := Vector3(a.x, y1, a.y)
		var b1 := Vector3(b.x, y1, b.y)
		_tri(st, a0, b0, b1, want)
		_tri(st, a0, b1, a1, want)


# A box over `corners` (xz) from `y0` to `y1`: walls in `wall`, the top in `roof`.
func _block(roof: SurfaceTool, wall: SurfaceTool, corners: PackedVector2Array, y0: float, y1: float) -> void:
	_walls(wall, corners, y0, y1)
	_cap(roof, corners, y1, Vector3.UP)


# A flat vertical panel facing `out`: centred on `c` (xz), `half` m either way along `e`, from `y0` to
# `y1`. With `beside`, `c` is the panel's start, not its centre.
func _panel(st: SurfaceTool, c: Vector2, e: Vector2, half: float, y0: float, y1: float, out: Vector2, beside := false) -> void:
	var a := c if beside else c - e * half
	var b := c + e * half * (2.0 if beside else 1.0)
	var want := Vector3(out.x, 0.0, out.y)
	_tri(st, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), want)
	_tri(st, Vector3(a.x, y0, a.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), want)


# The sloped band between polygon `upper` at `y_up` and `lower` at `y_low` (same corner count), facing
# out.
func _frustum(st: SurfaceTool, upper: PackedVector2Array, y_up: float, lower: PackedVector2Array, y_low: float) -> void:
	var centre := _centroid(upper)
	for i in upper.size():
		var j := (i + 1) % upper.size()
		var a1 := Vector3(upper[i].x, y_up, upper[i].y)
		var b1 := Vector3(upper[j].x, y_up, upper[j].y)
		var a0 := Vector3(lower[i].x, y_low, lower[i].y)
		var b0 := Vector3(lower[j].x, y_low, lower[j].y)
		var mid := (upper[i] + upper[j]) * 0.5 - centre
		var want := (b1 - a1).cross(a0 - a1).normalized()
		if want.dot(Vector3(mid.x, 0.0, mid.y)) < 0.0:
			want = -want
		_tri(st, a0, b0, b1, want)
		_tri(st, a0, b1, a1, want)


# A shallow dish: a cone of `radius`, `depth` deep, its bowl facing `facing`, rim centred on `at`.
func _dish(st: SurfaceTool, at: Vector3, facing: Vector3, radius: float, depth: float) -> void:
	var basis := Basis.looking_at(-facing)
	var back := at - facing * depth
	var n := 14
	for i in n:
		var a := basis * Vector3(cos(TAU * i / n), sin(TAU * i / n), 0.0) * radius + at
		var b := basis * Vector3(cos(TAU * (i + 1) / n), sin(TAU * (i + 1) / n), 0.0) * radius + at
		_tri(st, back, a, b, facing)
		_tri(st, back, b, a, -facing)


# A triangle on a dome of `radius` sat on `base`, from unit directions, with the dome's smooth normals.
func _smooth_tri(st: SurfaceTool, base: Vector3, radius: float, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (c - a).cross(b - a).dot(a + b + c) < 0.0:
		var swap := b
		b = c
		c = swap
	for d in [a, b, c]:
		st.set_normal(d)
		st.add_vertex(base + d * radius)


# One flat-shaded triangle, wound so its front faces `want` (Godot: clockwise from the front).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3) -> void:
	if (c - a).cross(b - a).dot(want) < 0.0:
		var swap := b
		b = c
		c = swap
	st.set_normal(want)
	st.add_vertex(a)
	st.set_normal(want)
	st.add_vertex(b)
	st.set_normal(want)
	st.add_vertex(c)


func _cel(col: Color, crease: ShaderMaterial) -> ShaderMaterial:
	var m := (load(CEL_BASE) as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("color", col)
	m.next_pass = crease
	return m
