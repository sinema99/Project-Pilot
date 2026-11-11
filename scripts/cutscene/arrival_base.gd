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
# Revision 3 (spec R3) adds the structure's detail, each piece with its job named where it is built:
# glazing only where people work, the apron's craft / sheds / cargo yard / lift cores, skylights over
# the ops floors, base command on the crown, the plant deck's substation, power line and fuel farm,
# the left tower's skybridge, and brackets carrying every cap. Massing keeps its crease ink; small
# parts (`fine_*` materials) read by tone alone (R3-8), so they don't turn to ink noise at 1-2 km.
#
# Revision 5 (spec R5): abandoned for 200 years. The craft, pads, lane, landing ring and beacons are
# gone and nothing is plowed; everything else is ruined in place: bites spalled out of the deck
# edges (rubble under the big ones), dropped fascia panels, a collapse hole in the Lower deck, the
# towers' caps bitten or broken (TOWERS `wear`), glass gone, roofs of sheds fallen in, wires down.
# The growth itself is ArrivalGrowth's; this records where it can go (`walls`, `roof_blocks`,
# `tree_slots`, `rubble`).
#
# GENERATED like ArrivalLand: no owner, nothing saved into the .tscn. Built after Land (above it in
# the tree), which it asks for ground heights.

const CEL_BASE := "res://resources/cel_ground.tres"
const CREASE := "res://resources/cel_crease_material.tres"

## The reference's grade: snow roofs, walls apart from the bluish snow, near-black underside. Since
## R5 the walls are a weathered warm grey (200 years of weather) and the old safety orange has
## rusted out; seams and broken faces are the wall a few shades down.
const C_ROOF := Color(0.86, 0.87, 0.89)
const C_WALL := Color(0.45, 0.43, 0.4)
const C_UNDER := Color(0.08, 0.09, 0.11)
const C_RUST := Color(0.36, 0.24, 0.16)
const C_SEAM := Color(0.29, 0.28, 0.27)
## Spec R3: daytime glass (steel-blue, holding the sky); only a few panes are left (R5). The cargo
## yard's containers: dull steel among the rust.
const C_GLASS := Color(0.24, 0.32, 0.42)
const C_BOX := Color(0.3, 0.33, 0.35)
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
## A tower's bastion (spec R4-2): how many stepped tiers, and the drift line's width on each (m).
@export var bastion_tiers := 3
@export var bastion_drift := 2.0
## The road (spec R4-3): surface sample spacing along it (m). Its width and verge are the land's
## (`road_width`, `road_verge`), which clears for it.
@export var road_step := 6.0
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
## Off: the sister outpost is not built (the boss arena has it in its baked backdrop).
@export var outpost := true
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
## The glazed band on the decks people work in (spec R3-3): where it runs (fractions of the slab's
## thickness down from the top), how deep it is recessed (m), the overhang lip over it (reach, m),
## and the mullion width (m; 8 to a structural bay, wide enough to hold ~4 px at 1.4 km).
@export var glass_from := 0.26
@export var glass_to := 0.74
@export var glass_depth := 4.0
@export var lip_out := 2.5
@export var mullion := 2.2
## A deck's top storey: its floor this far (m) under the roof (service rings and the skybridge).
@export var storey := 15.0
## Ink fade (m) for the base's crease lines: the cel default (45-120 m) is far too short here.
@export var ink_fade_start := 5000.0
@export var ink_fade_end := 9000.0

## Each tower's cap-top centre (world), in TOWERS order.
var cap_tops: Array[Vector3] = []
## The outpost deck's top centre (world).
var outpost_top: Vector3
## The hangar mouth's centre on the Lower deck's front fascia (world).
var hangar: Vector3
## Spec R5-3: the collapse hole in the Lower deck's roof (world centre on the roof) and its outline.
var hole := Vector3.INF
var hole_outline := PackedVector2Array()
## Spec R5-7: the bites out of the deck edges, {deck, at (world, on the roof edge), width}.
var bites: Array[Dictionary] = []
## Spec R5-2: per tower (TOWERS order, then the outpost's), the fraction of its cap's rim gone.
var rim_loss := {}
## The comms mast's highest point now it is snapped (world y).
var mast_top := 0.0
## For ArrivalGrowth (spec R5-3/R5-4). `walls`: straight wall faces growth hangs from or climbs,
## {a, b (xz), out (xz), top, bottom (m), cover (0..1), climb (bool), floor (m, or INF: the land),
## streaks (bool), optional kind (&"shaft" / &"rim") + tower name, optional sag (m: the top dips by
## sag * sin(pi * f) along a to b, the skybridge)}. `roof_blocks`: footprints on a roof nothing grows
## through. `tree_slots`: where trees come up through the structure, {poly, y, count, height (Vector2)}. `rubble`: talus piles on
## the ground (world). `caps`: each main tower's rim top, {poly, y}. `break_spots`: broken edges
## spindrift streams off (world).
var walls: Array[Dictionary] = []
var roof_blocks: Array[PackedVector2Array] = []
var tree_slots: Array[Dictionary] = []
var rubble: Array[Vector3] = []
var caps: Array[Dictionary] = []
var break_spots: Array[Vector3] = []
## The power line's pylon count (spec R3-6), for the tests.
var pylons := 0
## The fuel farm's centre on the plant deck (world), for the tests.
var fuel_farm := Vector3.INF
## The skybridge's ends (world, deck end then tower end), for the tests.
var skybridge: Array[Vector3] = []

var _shot: ArrivalShot
var _land: ArrivalLand
var _mats := {}
## Every deck's world outline and top, for keeping roof things out from under the decks above.
var _decks: Array[Dictionary] = []
## The way up from the apron to base command (spec R3-4/R3-5), planned before the decks build so
## their roofs keep clear of it: the lift core against Mid's front wall, and the walkway across Mid's
## roof from it to Tier1's wall. {deck, core_on, core: box, core_out, core_top, path: box, door, door_e}.
var _walkway := {}
## The substation gantry's three wire points (world), where the power line leaves.
var _gantry: Array[Vector3] = []


func _ready() -> void:
	_shot = get_parent() as ArrivalShot
	_land = get_node(^"../Land") as ArrivalLand
	var crease := (load(CREASE) as ShaderMaterial).duplicate() as ShaderMaterial
	crease.set_shader_parameter("fade_start_m", ink_fade_start)
	crease.set_shader_parameter("fade_end_m", ink_fade_end)
	_mats = {roof = _cel(C_ROOF, crease), wall = _cel(C_WALL, crease), under = _cel(C_UNDER, crease),
			rust = _cel(C_RUST, crease), seam = _cel(C_SEAM, crease), glass = _cel(C_GLASS, crease),
			fine_roof = _cel(C_ROOF, null), fine_wall = _cel(C_WALL, null), fine_dark = _cel(C_UNDER, null),
			fine_seam = _cel(C_SEAM, null), fine_glass = _cel(C_GLASS, null), fine_box = _cel(C_BOX, null),
			fine_rust = _cel(C_RUST, null)}
	for deck: Dictionary in ArrivalShot.DECKS:
		_decks.append({name = deck.name, poly = deck_outline(deck), top = deck.top})
	_plan_walkway()
	for deck: Dictionary in ArrivalShot.DECKS:
		_build_deck(deck, deck_outline(deck))
	_build_tier_drifts()
	for tower: Dictionary in ArrivalShot.TOWERS:
		var top := _shot.at_distance(tower.u, tower.v, tower.distance)
		cap_tops.append(top)
		_build_tower(tower.name, top, tower.cap, tower.shaft, tower.role, tower.vary, true,
				tower.shaft * tower.get("bastion", 0.0), tower.wear)
	_build_skybridge()
	_build_road()
	_build_power_line()
	if outpost:
		_build_outpost()


## Every deck as {name, poly (world xz), top}, for ArrivalGrowth.
func deck_list() -> Array[Dictionary]:
	return _decks


## The outlines of the decks above height `top` (grown 10 m), for ArrivalGrowth.
func decks_above(top: float) -> Array[PackedVector2Array]:
	return _above(top)


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
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(deck.name) + 2329
	# Spec R5-7: bites spalled out of the edges facing the camera, the roof and upper fascia gone in
	# them down to the groove; the right extension's one sagging slab is a bite whose slab dropped.
	var cuts := _deck_bites(deck, poly, rng)
	# The roof, and the snow on it rounded over the edge.
	var lip := _inset(poly, -cornice_out)
	var y_lip := top - cornice_drop
	var roof := _bitten(lip, cuts)
	var hole_poly := PackedVector2Array()
	if deck.roof == &"apron":
		hole_poly = _plan_hole(top)
	if hole_poly.is_empty():
		_cap(s.roof, roof, top, Vector3.UP)
	else:
		_cap_holed(s.roof, roof, hole_poly, top)
	_walls_split(s.roof, s.seam, roof, lip, y_lip, top)
	if cuts.is_empty():
		_ring(s.roof, lip, poly, y_lip, Vector3.DOWN)
	# The fascia: lit, a dark groove, lit again. Where people worked (spec R3-3) the groove is a tall
	# recessed glazed band instead, under an overhang lip that shades it, mullions on the bay grid;
	# since R5 the glass is gone, the band a run of black openings.
	var glazed: bool = deck.get("glazing", &"") == &"band"
	var y_groove := top - thick * (glass_from if glazed else groove_from)
	var y_ledge := top - thick * (glass_to if glazed else groove_to)
	var groove := _inset(poly, glass_depth if glazed else groove_depth)
	_walls_split(s.wall, s.seam, _bitten(poly, cuts), poly, y_groove, y_lip)
	_walls(s.under, groove, y_ledge, y_groove)
	_ring(s.wall, poly, groove, y_ledge, Vector3.UP)
	_walls(s.wall, poly, bottom, y_ledge)
	if glazed:
		var overhang := _inset(poly, -lip_out)
		_walls(s.wall, overhang, y_groove - 1.2, y_groove + 0.6)
		_ring(s.wall, overhang, poly, y_groove + 0.6, Vector3.UP)
		_ring(s.under, overhang, groove, y_groove - 1.2, Vector3.DOWN)
		_mullions(s.fine_wall, groove, y_ledge, y_groove - 1.2)
	_bite_floors(s, deck, poly, cuts, top, y_groove)
	if not hole_poly.is_empty():
		_build_hole(s, hole_poly, top, thick)
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
		var bitten := _any_inside(PackedVector2Array([j.p - j.out * 1.0]), cuts)
		_panel(s.seam, j.p + j.out * 0.3, j.e, seam_width * 0.5, bottom + 1.0, y_groove if bitten else y_lip - 0.4, j.out)
	_dropped_panels(s, deck, poly, joints, bottom, y_ledge, rng)
	_growth_faces(deck, poly, lip, y_lip, bottom)
	match deck.roof:
		&"apron":
			_apron(s, deck, poly, top)
		&"ops":
			_ops(s, poly, top, 46.0 if deck.thick > 19.0 else 36.0, 130.0 if deck.thick > 19.0 else 80.0)
		&"utilities":
			_utilities(s, poly, top, bottom)
			_substation(s, poly, top)
			_fuel_farm(s, poly, top)
		&"crown":
			var crown := _inset(poly, 22.0)
			_walls(s.wall, crown, top, top + 9.0)
			_cap(s.roof, crown, top + 9.0, Vector3.UP)
			_drifts(s.roof, crown, top, 9.0)
			var crown2 := _inset(crown, 18.0)
			_walls(s.wall, crown2, top + 9.0, top + 15.0)
			_cap(s.roof, crown2, top + 15.0, Vector3.UP)
			_plant_enclosure(s, crown2, top + 15.0)
			roof_blocks.append(crown)
	if deck.name == _walkway.get("deck", &""):
		_build_walkway(s, top)
	if deck.name == _walkway.get("core_on", &""):
		_build_core(s)
	_commit(deck.name, s)


# --- 200 years: the decks' damage (spec R5) ----------------------------------------------------

## Bites out of each deck's edge (spec R5-7); the outpost's decks keep theirs too far off to matter.
const BITE_COUNT := {"Lower": 5, "Right": 4, "Mid": 3, "Tier1": 3, "Tier2": 3}


# Spalled bites along the edges facing the camera: each a jagged notch `w` along the edge and up to
# `d` into the slab, 20 m apart and 10 m clear of the corners, clear of the hangar mouth. The right
# extension's first one is its sagging slab: wider and shallower, the slab dropped, not gone.
# Records them in `bites` and returns their cut polygons.
func _deck_bites(deck: Dictionary, poly: PackedVector2Array, rng: RandomNumberGenerator) -> Array[PackedVector2Array]:
	var cuts: Array[PackedVector2Array] = []
	var want: int = BITE_COUNT.get(deck.name, 0)
	if want == 0:
		return cuts
	var outward := _orientation(poly)
	var edges: Array[Dictionary] = []
	var total := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		var out := Vector2(e.y, -e.x) * outward
		if out.y > 0.25 and a.distance_to(b) > 40.0:
			edges.append({a = a, b = b, e = e, out = out})
			total += a.distance_to(b)
	var tries := 0
	while cuts.size() < want and tries < 200 and total > 0.0:
		tries += 1
		var pick := rng.randf() * total
		var edge: Dictionary = edges[0]
		for ed in edges:
			edge = ed
			pick -= (ed.a as Vector2).distance_to(ed.b)
			if pick <= 0.0:
				break
		var length: float = (edge.a as Vector2).distance_to(edge.b)
		var slump: bool = deck.name == "Right" and cuts.is_empty()
		var w := rng.randf_range(50.0, 70.0) if slump else rng.randf_range(6.0, 16.0)
		var d := 8.0 if slump else rng.randf_range(5.0, 12.0)
		var along := rng.randf_range(w * 0.5 + 10.0, length - w * 0.5 - 10.0)
		if along < w * 0.5 + 10.0:
			continue
		var at: Vector2 = (edge.a as Vector2) + edge.e * along
		var hangar_at := _shot.on_plane(ArrivalShot.HANGAR.u, ArrivalShot.HANGAR.v, deck.top)
		if deck.roof == &"apron" and at.distance_to(Vector2(hangar_at.x, hangar_at.z)) < ArrivalShot.HANGAR.width * 0.5 + w * 0.5 + 15.0:
			continue
		var clear := true
		for b in bites:
			if b.deck == deck.name and Vector2(b.at.x, b.at.z).distance_to(at) < (b.width + w) * 0.5 + 20.0:
				clear = false
		if not clear:
			continue
		var cut := _bite_shape(at, edge.e, -edge.out, w, d, rng)
		cuts.append(cut)
		bites.append({deck = deck.name, at = Vector3(at.x, deck.top, at.y), width = w, e = edge.e, out = edge.out,
				slump = slump, cut = cut})
	return cuts


# A bite's cut: from 8 m outside the edge to a jagged inner line up to `d` in (deepest mid-way).
static func _bite_shape(at: Vector2, e: Vector2, inward: Vector2, w: float, d: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := PackedVector2Array([at - e * (w * 0.5 + 3.0) - inward * 8.0, at + e * (w * 0.5 + 3.0) - inward * 8.0])
	var n := 6
	for k in n + 1:
		var f := 1.0 - float(k) / n
		var depth := d * (sin(PI * f) * 0.7 + 0.3) * rng.randf_range(0.7, 1.1)
		if k == 0 or k == n:
			depth = rng.randf_range(0.5, 1.5)
		pts.append(at + e * lerpf(-w * 0.5, w * 0.5, f) + inward * depth)
	return pts


# What a bite leaves: the broken floor at the groove (dark, the slab's inside), rebar standing out
# of the break, and under the bigger ones a rubble talus where the pieces landed (spec R5-7). The
# sagging slab is the piece dropped 3.5 m and still snowed over.
func _bite_floors(s: Dictionary, deck: Dictionary, poly: PackedVector2Array, cuts: Array[PackedVector2Array], top: float,
		y_groove: float) -> void:
	for b in bites:
		if b.deck != deck.name:
			continue
		var cut: PackedVector2Array = b.cut
		for piece in Geometry2D.intersect_polygons(poly, cut):
			if b.slump:
				_cap(s.roof, piece, top - 3.5, Vector3.UP)
				_walls(s.wall, piece, y_groove, top - 3.5)
			else:
				_cap(s.under, piece, y_groove + 0.1, Vector3.UP)
		var out: Vector2 = b.out
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(b.at)
		for k in range(3, cut.size() - 1):
			var p := cut[k]
			if not Geometry2D.is_point_in_polygon(p - out * 0.5, poly):
				continue
			for j in 2:
				var y := rng.randf_range(y_groove + 1.5, top - 2.0)
				var e: Vector2 = b.e
				var q := p + out * rng.randf_range(2.0, 5.0) + e * rng.randf_range(-1.5, 1.5)
				_beam(s.fine_rust, Vector3(p.x, y, p.y), Vector3(q.x, y - rng.randf_range(0.3, 2.0), q.y), 0.7)
		if not b.slump and b.width >= 11.0:
			var at := Vector2(b.at.x, b.at.z) + out * 10.0
			var under := _deck_under(at, top)
			var y: float = under.top if not under.is_empty() else _land.height(at.x, at.y)
			_rubble_pile(s, Vector3(at.x, y, at.y), out, rng)


# A talus of fallen slab: blocks of 1.5-5 m spilled out from the wall, half sunk, snow on their
# tops (they've lain there long enough). ArrivalGrowth puts saplings in it.
func _rubble_pile(s: Dictionary, c: Vector3, out: Vector2, rng: RandomNumberGenerator) -> void:
	for k in 8:
		var size := rng.randf_range(1.5, 5.0)
		var p := Vector2(c.x, c.z) + out * rng.randf_range(-4.0, 9.0) + Vector2(out.y, -out.x) * rng.randf_range(-9.0, 9.0)
		var g := c.y if _land.height(p.x, p.y) < c.y - 1.0 else _land.height(p.x, p.y)
		var a := rng.randf() * TAU
		var box := PackedVector2Array()
		for q in 4:
			box.append(p + Vector2.from_angle(a + TAU * q / 4.0) * size * 0.7)
		_block(s.fine_roof, s.fine_seam, box, g - 1.5, g + size * 0.6)
	rubble.append(c)


## Panels dropped off the lower fascia (spec R5-7): dark gaps a bay long on the seam line.
const DROPPED_PANELS := {"Lower": 2, "Right": 1, "Mid": 1}


func _dropped_panels(s: Dictionary, deck: Dictionary, poly: PackedVector2Array, joints: Array[Dictionary], bottom: float,
		y_ledge: float, rng: RandomNumberGenerator) -> void:
	var want: int = DROPPED_PANELS.get(deck.name, 0)
	var spots: Array[Dictionary] = []
	for j in joints:
		var end: Vector2 = j.p + j.e * bay
		if j.out.y > 0.25 and _boundary_distance(end, poly) < 3.0:
			spots.append(j)
	for k in mini(want, spots.size()):
		var j: Dictionary = spots[rng.randi_range(0, spots.size() - 1)]
		spots.erase(j)
		_panel(s.under, j.p + j.e * bay * 0.5 + j.out * 0.35, j.e, bay * 0.5 - 2.0, bottom + 1.5, y_ledge - 1.0, j.out)


# The deck's edges as faces for ArrivalGrowth (spec R5-4): curtains hang off the cornice down the
# fascia; where the wall stands on a deck below, growth also climbs from that roof.
func _growth_faces(deck: Dictionary, poly: PackedVector2Array, lip: PackedVector2Array, y_lip: float, bottom: float) -> void:
	if not BITE_COUNT.has(deck.name):
		return
	var outward := _orientation(lip)
	for i in lip.size():
		var a := lip[i]
		var b := lip[(i + 1) % lip.size()]
		var e := (b - a).normalized()
		var out := Vector2(e.y, -e.x) * outward
		var below := _deck_under((a + b) * 0.5 + out * 8.0, deck.top)
		var floor_y: float = below.top if not below.is_empty() and below.top > bottom - 12.0 else INF
		walls.append({a = a, b = b, out = out, top = y_lip, bottom = bottom, cover = 0.38, climb = floor_y != INF,
				floor = floor_y, streaks = true})


# --- the collapse hole (spec R5-3) -------------------------------------------------------------

# Where the second pad was, a ragged hole about 50 m across: recorded in `hole` / `hole_outline`.
func _plan_hole(top: float) -> PackedVector2Array:
	var w := _shot.on_plane(ArrivalShot.HOLE.u, ArrivalShot.HOLE.v, top)
	var c := Vector2(w.x, w.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1729
	var poly := PackedVector2Array()
	for i in 15:
		poly.append(c + Vector2.from_angle(TAU * i / 15.0) * ArrivalShot.HOLE.radius * rng.randf_range(0.72, 1.12))
	hole = Vector3(c.x, top, c.y)
	hole_outline = poly
	return poly


# The hole's inside: the broken slab's cut edge (a lighter band) over a dark shaft down to the level
# below, rebar off the edge, one slab hanging in from the edge nearest the camera; the trees that
# come up out of it are ArrivalGrowth's (a tree slot on the floor).
func _build_hole(s: Dictionary, poly: PackedVector2Array, top: float, thick: float) -> void:
	var y_floor := top - minf(thick, 20.0)
	var c := _centroid(poly)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1730
	var near := 0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		var n_in := Vector2(-e.y, e.x)
		if n_in.dot(c - (a + b) * 0.5) < 0.0:
			n_in = -n_in
		_panel(s.seam, (a + b) * 0.5, e, a.distance_to(b) * 0.5, top - 3.0, top, n_in)
		_panel(s.under, (a + b) * 0.5, e, a.distance_to(b) * 0.5, y_floor, top - 3.0, n_in)
		if (a + b).y > (poly[near] + poly[(near + 1) % poly.size()]).y:
			near = i
		for j in 2:
			var p := a.lerp(b, rng.randf())
			var q := p + (c - p).normalized() * rng.randf_range(3.0, 6.0)
			_beam(s.fine_rust, Vector3(p.x, top - 1.5, p.y), Vector3(q.x, top - rng.randf_range(2.0, 4.0), q.y), 0.7)
	_cap(s.under, poly, y_floor, Vector3.UP)
	# The hanging slab: snow still on it, its far edge dropped into the dark.
	var p0 := poly[near].lerp(poly[(near + 1) % poly.size()], 0.1)
	var p1 := poly[near].lerp(poly[(near + 1) % poly.size()], 0.9)
	var q0 := p0 + (c - p0).normalized() * 14.0
	var q1 := p1 + (c - p1).normalized() * 14.0
	var v := func(q: Vector2, h: float) -> Vector3: return Vector3(q.x, h, q.y)
	var up: Vector3 = ((v.call(p1, top) - v.call(p0, top)) as Vector3).cross(v.call(q0, top - 11.0) - v.call(p0, top)).normalized()
	if up.y < 0.0:
		up = -up
	_tri(s.roof, v.call(p0, top - 0.6), v.call(p1, top - 0.6), v.call(q1, top - 11.0), up)
	_tri(s.roof, v.call(p0, top - 0.6), v.call(q1, top - 11.0), v.call(q0, top - 11.6), up)
	tree_slots.append({poly = _inset(poly, 4.0), y = y_floor, count = 16, height = Vector2(16.0, 27.0)})
	roof_blocks.append(_inset(poly, -3.0))


# Mullions across the glazed band, 8 to each structural bay (so they line up with the fascia's
# joints): the glass's frame, a fine part with no ink. Since R5 one in three has fallen.
func _mullions(st: SurfaceTool, poly: PackedVector2Array, y0: float, y1: float) -> void:
	var outward := _orientation(poly)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		var out := Vector2(e.y, -e.x) * outward
		var n := maxi(int(round(a.distance_to(b) / bay)), 1) * 8
		for k in range(1, n):
			if (k * 7 + i) % 3 != 0:
				_panel(st, a.lerp(b, float(k) / n) + out * 0.3, e, mullion * 0.5, y0, y1, out)


# Base command's plant (spec R3-5): the HVAC on top of the crown, hidden in one louvred screen box
# (the screen's slats are dark bands; the open top shows the dark plant inside).
func _plant_enclosure(s: Dictionary, roof: PackedVector2Array, y: float) -> void:
	var frame := _deck_frame(roof)
	var axis: Vector2 = frame.axis
	var across: Vector2 = frame.across
	var c: Vector2 = frame.origin + axis * (frame.along_min + frame.along_max) * 0.5 \
			+ across * (frame.across_min + frame.across_max) * 0.5
	var hl: float = (frame.along_max - frame.along_min) * 0.22
	var hw: float = (frame.across_max - frame.across_min) * 0.3
	var box := PackedVector2Array([c - axis * hl - across * hw, c + axis * hl - across * hw,
			c + axis * hl + across * hw, c - axis * hl + across * hw])
	var h := 7.0
	_walls(s.seam, box, y, y + h)
	_ring(s.wall, box, _inset(box, 1.5), y + h, Vector3.UP)
	_cap(s.under, _inset(box, 1.5), y + h - 0.5, Vector3.UP)
	var outward := _orientation(box)
	for i in box.size():
		var a := box[i]
		var b := box[(i + 1) % box.size()]
		var e := (b - a).normalized()
		var out := Vector2(e.y, -e.x) * outward
		# Half the slats are down (spec R5-5): the dark plant shows through the gaps.
		for k in 3:
			if (i + k) % 2 == 0:
				var y0 := y + 1.2 + k * 2.0
				_panel(s.fine_dark, (a + b) * 0.5 + out * 0.2, e, a.distance_to(b) * 0.5 - 1.0, y0, y0 + 0.9, out)
	_drifts(s.roof, box, y, h)


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
			if buttresses:
				walls.append({a = p0 + out * 0.2, b = p1 + out * 0.2, out = out, top = y, bottom = lo - 2.0, cover = 0.18,
						climb = true, floor = INF, streaks = false})
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


# --- the way up: lift core and walkway ---------------------------------------------------------

# The lift core stands against Mid's front wall over the apron (the crews' way between the pads and
# the floors above), a door at each level; from its top door a walkway crossed Mid's roof
# straight to a door in Tier1's wall, the way into base command.
func _plan_walkway() -> void:
	var lower := _deck_named(&"Lower")
	var mid := _deck_named(&"Mid")
	var tier := _deck_named(&"Tier1")
	var poly: PackedVector2Array = mid.poly
	var outward := _orientation(poly)
	# Mid's front edge: the one facing the camera (+z) most.
	var best := 0
	var best_z := -INF
	for i in poly.size():
		var e := (poly[(i + 1) % poly.size()] - poly[i]).normalized()
		var out := Vector2(e.y, -e.x) * outward
		if out.y > best_z and poly[i].distance_to(poly[(i + 1) % poly.size()]) > 200.0:
			best_z = out.y
			best = i
	var a := poly[best]
	var b := poly[(best + 1) % poly.size()]
	if a.x > b.x:
		var swap := a
		a = b
		b = swap
	var e := (b - a).normalized()
	var out := Vector2(e.y, -e.x)
	if out.y < 0.0:
		out = -out
	# Its left end, the pads' side, wherever its foot is on the Lower roof.
	var f := 0.1
	while f < 0.5 and not Geometry2D.is_point_in_polygon(a.lerp(b, f) + out * 14.0, lower.poly):
		f += 0.02
	var p := a.lerp(b, f)
	var c := p + out * 3.0
	var core := PackedVector2Array([c - e * 9.0 - out * 7.0, c + e * 9.0 - out * 7.0, c + e * 9.0 + out * 7.0,
			c - e * 9.0 + out * 7.0])
	# The walkway: from the core's back face across Mid to the nearest point of Tier1's wall.
	var start := c - out * 7.0
	var end := start
	var near := INF
	var t: PackedVector2Array = tier.poly
	for i in t.size():
		var q := Geometry2D.get_closest_point_to_segment(start, t[i], t[(i + 1) % t.size()])
		if q.distance_to(start) < near:
			near = q.distance_to(start)
			end = q
	var d := (end - start).normalized()
	var side := Vector2(-d.y, d.x) * 3.0
	_walkway = {deck = &"Mid", core_on = &"Lower", core = core, core_out = out, core_e = e, core_top = mid.top + 8.0,
			front_a = a, front_b = b, core_f = f,
			path = PackedVector2Array([start - side, end - side, end + side, start + side]), door = end, door_e = Vector2(-d.y, d.x),
			door_out = -d}


func _deck_named(deck_name: StringName) -> Dictionary:
	for d in _decks:
		if d.name == deck_name:
			return d
	return {}


# The walkway across Mid's roof (spec R3-5) is under snow and growth since R5; only the doorway in
# Tier1's wall is left, black.
func _build_walkway(s: Dictionary, top: float) -> void:
	_panel(s.fine_dark, _walkway.door + _walkway.door_out * 0.4, _walkway.door_e, 3.0, top, top + 6.0, _walkway.door_out)


# The lift core: a tower of its own from the Lower roof to over Mid's roof, a snow-capped head with
# the lift machinery, a door onto the apron and one onto the walkway, both black; rust runs down
# its face from the machinery.
func _build_core(s: Dictionary) -> void:
	var core: PackedVector2Array = _walkway.core
	var lower := _deck_named(&"Lower")
	var y0: float = lower.top
	var y1: float = _walkway.core_top
	_walls(s.wall, core, y0, y1)
	_cap(s.roof, core, y1, Vector3.UP)
	_drifts(s.roof, core, y1 - 8.0, 8.0)
	var out: Vector2 = _walkway.core_out
	var e: Vector2 = _walkway.core_e
	var c := _centroid(core)
	_panel(s.fine_dark, c + out * 7.4, e, 4.0, y0, y0 + 7.0, out)
	_panel(s.fine_dark, c - out * 7.4, e, 2.5, y1 - 7.0, y1 - 1.5, -out)
	_panel(s.fine_rust, c + out * 7.3 + e * 6.0, e, 0.8, y1 - 20.0, y1 - 1.0, out)
	roof_blocks.append(_inset(core, -2.0))


# --- what the roofs were for -------------------------------------------------------------------

# The old landing apron (spec R2-3), abandoned since R5: the pads, the lane and the craft are gone
# under snow and growth. The hangar mouth stays on the front fascia, black, its orange edge rusted
# out; the crew room's glass is gone; the sheds, the cargo yard and the lift head stand ruined.
func _apron(s: Dictionary, deck: Dictionary, poly: PackedVector2Array, top: float) -> void:
	var w := _shot.on_plane(ArrivalShot.HANGAR.u, ArrivalShot.HANGAR.v, top)
	var end := Vector2(w.x, w.z)
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
	var hw: float = ArrivalShot.HANGAR.width * 0.5
	var y0: float = top - deck.thick + 1.5
	var y1 := top - cornice_drop - 3.0
	hangar = Vector3(at.x, (y0 + y1) * 0.5, at.y)
	_panel(s.rust, at + out * 0.4, e, hw + 2.0, y0, y1 + 2.0, out)
	_panel(s.under, at + out * 0.7, e, hw, y0, y1, out)
	# The crew room (spec R3-3): the deck's only glazing, a strip high on the fascia beside the
	# hangar; the panes are gone, the frame half down.
	var corner := a if at.distance_to(a) < at.distance_to(b) else b
	var dir := (corner - at).normalized()
	var from := hw + 12.0
	var to := minf(at.distance_to(corner) - 14.0, from + 96.0)
	if to > from + 20.0:
		var mid := at + dir * (from + to) * 0.5 + out * 0.3
		var gy0: float = top - deck.thick * 0.42
		var gy1 := top - cornice_drop - 2.5
		_panel(s.under, mid, dir, (to - from) * 0.5, gy0, gy1, out)
		var n := int((to - from) / 6.0)
		for k in range(1, n):
			if k % 3 != 1:
				_panel(s.fine_wall, at + dir * lerpf(from, to, float(k) / n) + out * 0.6, dir, mullion * 0.5, gy0, gy1, out)
	_sheds(s, poly, top)
	_cargo_yard(s, poly, top, at, e, out)
	_pad_lift(s, poly, top)


# Maintenance sheds (spec R3-4): three along the back of the apron, against Mid's front wall, doors
# onto the apron. Two have lost their roofs (spec R5-5): bare walls round a dark floor that trees
# have come up through (a tree slot); the first still has its roof, under snow.
func _sheds(s: Dictionary, poly: PackedVector2Array, top: float) -> void:
	var a: Vector2 = _walkway.front_a
	var b: Vector2 = _walkway.front_b
	var e := (b - a).normalized()
	var out: Vector2 = _walkway.core_out
	var inner := _inset(poly, 8.0)
	var placed := 0
	var f: float = _walkway.core_f + 0.09
	while placed < 3 and f < 0.95:
		var c := a.lerp(b, f) + out * 17.0
		var box := PackedVector2Array([c - e * 22.0 - out * 13.0, c + e * 22.0 - out * 13.0, c + e * 22.0 + out * 13.0,
				c - e * 22.0 + out * 13.0])
		if _all_inside(box, inner) and not _on_hole(box):
			if placed == 0:
				_block(s.fine_roof, s.fine_wall, box, top, top + 12.0)
				_drifts(s.roof, box, top, 12.0)
			else:
				_walls(s.fine_wall, box, top, top + 12.0)
				_walls(s.fine_seam, _inset(box, 0.8), top, top + 11.0, true)
				_ring(s.fine_wall, box, _inset(box, 0.8), top + 12.0, Vector3.UP)
				_cap(s.fine_dark, _inset(box, 0.8), top + 0.3, Vector3.UP)
				tree_slots.append({poly = _inset(box, 4.0), y = top, count = 4, height = Vector2(6.0, 13.0)})
			_panel(s.fine_dark, c + out * 13.3, e, 15.0, top, top + 9.0, out)
			roof_blocks.append(_inset(box, -1.0))
			placed += 1
			f += 60.0 / a.distance_to(b)
		else:
			f += 0.02


# The cargo staging yard (spec R3-4): beside the hangar mouth, on the roof over it, the containers
# still in their blocks but rusted and slumped (spec R5-5): stacks one or two high where they were
# three, the tops fallen and lying askew beside them, snow on everything, scrub between (a slot).
func _cargo_yard(s: Dictionary, poly: PackedVector2Array, top: float, hangar_at: Vector2, e: Vector2, out: Vector2) -> void:
	var inner := _inset(poly, 10.0)
	# The side of the hangar away from where the pads were.
	var site := _shot.on_plane(ArrivalShot.LIFT_SITE.x, ArrivalShot.LIFT_SITE.y, top)
	var away := e if (Vector2(site.x, site.z) - hangar_at).dot(e) < 0.0 else -e
	var origin := hangar_at + away * (ArrivalShot.HANGAR.width * 0.5 + 10.0) - out * 18.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2329
	var tones := ["fine_rust", "fine_box", "fine_rust", "fine_seam"]
	var yard := PackedVector2Array()
	for bx in 4:
		for by in 2:
			# A block: 6 containers side by side across the lane, 12.2 m long.
			var c0 := origin + away * (bx * 18.0) - out * (by * 24.0)
			var block := PackedVector2Array([c0, c0 + away * 12.2, c0 + away * 12.2 - out * 15.6, c0 - out * 15.6])
			if not _all_inside(block, inner) or _on_hole(block):
				continue
			yard.append_array(block)
			roof_blocks.append(block)
			for k in 6:
				var q := c0 - out * (k * 2.6 + 0.08)
				var box := PackedVector2Array([q, q + away * 12.2, q + away * 12.2 - out * 2.44, q - out * 2.44])
				var tiers := rng.randi_range(1, 2)
				for tier in tiers:
					var key: String = tones[rng.randi_range(0, tones.size() - 1)]
					_block(s.fine_roof, s[key], box, top + tier * 2.6, top + tier * 2.6 + 2.55)
				# One in four of the old top tier lies where it fell, askew off the end of its row.
				if rng.randf() < 0.25:
					var fall := _centroid(box) + away * rng.randf_range(9.0, 13.0) - out * rng.randf_range(-2.0, 2.0)
					var yaw := rng.randf_range(-0.6, 0.6)
					var ax := away.rotated(yaw)
					var cx := Vector2(ax.y, -ax.x)
					var lying := PackedVector2Array([fall - ax * 6.1 - cx * 1.22, fall + ax * 6.1 - cx * 1.22,
							fall + ax * 6.1 + cx * 1.22, fall - ax * 6.1 + cx * 1.22])
					if _all_inside(lying, inner):
						_block(s.fine_roof, s[tones[rng.randi_range(0, tones.size() - 1)]], lying, top, top + 2.55)
						roof_blocks.append(lying)
	if yard.is_empty():
		return
	var hull := Geometry2D.convex_hull(yard)
	tree_slots.append({poly = _inset(hull, -6.0), y = top, count = 14, height = Vector2(1.5, 5.0)})


# The lift head (spec R3-4): a small head where the first pad was, the crews' way up from the levels
# below; its door black, rust down its face.
func _pad_lift(s: Dictionary, poly: PackedVector2Array, top: float) -> void:
	var w := _shot.on_plane(ArrivalShot.LIFT_SITE.x, ArrivalShot.LIFT_SITE.y, top)
	var c := Vector2(w.x, w.z)
	var back := (c - Vector2(hole.x, hole.z)).normalized() if hole != Vector3.INF else Vector2.LEFT
	var side := Vector2(-back.y, back.x)
	var inner := _inset(poly, 8.0)
	for sign_: float in [1.0, -1.0]:
		var p := c + (back * 0.3 + side * sign_).normalized() * 66.0
		var to_pad := (c - p).normalized()
		var across := Vector2(-to_pad.y, to_pad.x)
		var box := PackedVector2Array([p - to_pad * 6.0 - across * 8.0, p + to_pad * 6.0 - across * 8.0,
				p + to_pad * 6.0 + across * 8.0, p - to_pad * 6.0 + across * 8.0])
		if _all_inside(box, inner) and not _on_hole(box):
			_block(s.fine_roof, s.fine_wall, box, top, top + 8.0)
			_panel(s.fine_dark, p + to_pad * 6.3, across, 2.5, top, top + 5.5, to_pad)
			_panel(s.fine_rust, p + to_pad * 6.2 + across * 4.5, across, 0.7, top + 1.0, top + 7.5, to_pad)
			_drifts(s.roof, box, top, 8.0)
			roof_blocks.append(_inset(box, -1.0))
			return


## True if any of `points` is in or by the collapse hole.
func _on_hole(points: PackedVector2Array) -> bool:
	if hole == Vector3.INF:
		return false
	for p in points:
		if p.distance_to(Vector2(hole.x, hole.z)) < ArrivalShot.HOLE.radius * 1.2 + 15.0:
			return true
	return false


# Skylights over the ops floors (spec R3-5, they were R2's plant housings): long low strips in rows
# along the deck's longest edge on the building's grid, wherever a whole one fits clear of the rim,
# the decks above and the walkway. Since R5 the glass is gone: dark open slots, two bars in three
# fallen, and in every third one saplings come up out of the floor below (a tree slot).
func _ops(s: Dictionary, poly: PackedVector2Array, top: float, row_spacing: float, length: float) -> void:
	var frame := _deck_frame(poly)
	var axis: Vector2 = frame.axis
	var across: Vector2 = frame.across
	var inner := _inset(poly, 16.0)
	var above := _above(top)
	if _walkway.has("path"):
		above.append(_inset(_walkway.path, -8.0))
		above.append(_inset(_walkway.core, -8.0))
	var width := row_spacing * 0.42
	var h := 1.6
	var slots := 0
	var row: float = frame.across_min + row_spacing * 0.5
	while row < frame.across_max:
		var along: float = frame.along_min + 12.0
		while along + length < frame.along_max:
			var c: Vector2 = frame.origin + axis * (along + length * 0.5) + across * row
			var corners := PackedVector2Array([c - axis * length * 0.5 - across * width * 0.5,
					c + axis * length * 0.5 - across * width * 0.5, c + axis * length * 0.5 + across * width * 0.5,
					c - axis * length * 0.5 + across * width * 0.5])
			if _all_inside(corners, inner) and not _any_inside(corners + PackedVector2Array([c]), above):
				_block(s.under, s.fine_wall, corners, top, top + h)
				roof_blocks.append(_inset(corners, -1.0))
				slots += 1
				if slots % 3 == 1:
					tree_slots.append({poly = _inset(corners, 2.0), y = top - 6.0, count = 3, height = Vector2(8.0, 14.0)})
				var bars := int(length / 6.0)
				for k in range(1, bars):
					if k % 3 != 0:
						continue
					var q: Vector2 = c - axis * length * 0.5 + axis * length * k / bars
					_cap(s.fine_wall, PackedVector2Array([q - axis * 0.9 - across * width * 0.5, q + axis * 0.9 - across * width * 0.5,
							q + axis * 0.9 + across * width * 0.5, q - axis * 0.9 + across * width * 0.5]), top + h + 0.1, Vector3.UP)
			along += length + 24.0
		row += row_spacing


# The utilities run (spec R2-3) on the right extension: one long vent duct down its spine with vent
# heads at a regular pitch, and toward the far end a radiator strip of plates standing across the
# deck, streaking the fascia below them. Cold for 200 years (spec R5-5): snow on all of it.
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
	roof_blocks.append(_inset(duct, -2.0))
	var n := int(a.distance_to(b) / 26.0)
	for k in n:
		var c := a.lerp(b, (k + 0.5) / n)
		var head := PackedVector2Array([c - axis * 3.0 - across * 3.0, c + axis * 3.0 - across * 3.0,
				c + axis * 3.0 + across * 3.0, c - axis * 3.0 + across * 3.0])
		_block(s.roof, s.wall, head, top + 3.0, top + 5.5)
	var plates := 0
	var f := 0.68
	while f < 0.9:
		var c: Vector2 = at.call(f, 0.0)
		var plate := PackedVector2Array([c - axis * 0.8 - across * 18.0, c + axis * 0.8 - across * 18.0,
				c + axis * 0.8 + across * 18.0, c - axis * 0.8 + across * 18.0])
		if not _any_inside(plate, above):
			_block(s.roof, s.wall, plate, top, top + 7.0)
			roof_blocks.append(_inset(plate, -2.0))
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
	# The louvres (spec R3-3) the radiators' plant vents through: a dark panel high on the fascia,
	# lit slats across it. The streaks run down from it.
	var vent := Vector2(edge.x, edge.y)
	var thick := top - bottom
	var ly0 := top - thick * 0.44
	var ly1 := top - cornice_drop - 1.5
	_panel(s.under, vent + out * 0.3, e, 26.0, ly0, ly1, out)
	var slats := int((ly1 - ly0) / 2.2)
	for k in slats:
		var y := ly0 + 0.6 + k * 2.2
		_panel(s.fine_wall, vent + out * 0.6, e, 25.0, y, y + 0.9, out)
	for k in 5:
		var p := vent + e * (k - 2) * 9.0 + out * 0.4
		_panel(s.seam, p, e, 1.2, bottom + 6.0 + k % 2 * 4.0, ly0, out)


# The substation (spec R3-6) where the power-line cut leaves the plant deck: a fenced yard of
# transformers, a switch house, and on the deck edge the line's first gantry, whose crossbeam the
# three wires leave from (`_gantry`). Since R5 the yard is grown over, the fence half down, the
# transformers rusted.
func _substation(s: Dictionary, poly: PackedVector2Array, top: float) -> void:
	var pc := ArrivalShot.POWER_CUT
	var w := _shot.on_plane(pc.from.x, pc.from.y, top)
	var from := Vector2(w.x, w.z)
	var best := INF
	var at := from
	var e := Vector2.RIGHT
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(from, poly[i], poly[(i + 1) % poly.size()])
		if q.distance_to(from) < best:
			best = q.distance_to(from)
			at = q
			e = (poly[(i + 1) % poly.size()] - poly[i]).normalized()
	var out := Vector2(e.y, -e.x) * _orientation(poly)
	# The yard, just in from the edge.
	var c := at - out * 30.0
	var yard := PackedVector2Array([c - e * 34.0 - out * 18.0, c + e * 34.0 - out * 18.0, c + e * 34.0 + out * 18.0,
			c - e * 34.0 + out * 18.0])
	tree_slots.append({poly = yard, y = top, count = 10, height = Vector2(1.5, 7.0)})
	# The fence: a 3 m dark mesh round it, two sides still up, one sagged to half height.
	var outward := _orientation(yard)
	for i in yard.size():
		if i == 3:
			continue
		var a := yard[i]
		var b := yard[(i + 1) % yard.size()]
		var fe := (b - a).normalized()
		_panel(s.fine_dark, (a + b) * 0.5, fe, a.distance_to(b) * 0.5, top, top + (1.4 if i == 1 else 3.0), Vector2(fe.y, -fe.x) * outward)
	# Three transformers in a row, the switch house behind them.
	for k in 3:
		var t := c + e * (k - 1) * 16.0 + out * 5.0
		var tf := PackedVector2Array([t - e * 4.0 - out * 3.0, t + e * 4.0 - out * 3.0, t + e * 4.0 + out * 3.0,
				t - e * 4.0 + out * 3.0])
		_block(s.fine_roof, s.fine_rust, tf, top, top + 6.0)
		roof_blocks.append(_inset(tf, -1.0))
	var hc := c - out * 10.0
	var house := PackedVector2Array([hc - e * 12.0 - out * 6.0, hc + e * 12.0 - out * 6.0, hc + e * 12.0 + out * 6.0,
			hc - e * 12.0 + out * 6.0])
	_block(s.fine_roof, s.fine_wall, house, top, top + 8.0)
	_drifts(s.roof, house, top, 8.0)
	roof_blocks.append(_inset(house, -1.0))
	# The gantry on the deck edge: two posts and a crossbeam across the line's heading.
	var g := at - out * 4.0
	var gh := 24.0
	for side: float in [-1.0, 1.0]:
		_block(s.fine_dark, s.fine_dark, _square(g + e * side * 10.0, 0.8), top, top + gh)
	_block(s.fine_dark, s.fine_dark, PackedVector2Array([g - e * 11.0 - out * 0.7, g + e * 11.0 - out * 0.7,
			g + e * 11.0 + out * 0.7, g - e * 11.0 + out * 0.7]), top + gh - 1.6, top + gh)
	for k in 3:
		var p := g + e * (k - 1) * 7.0
		_gantry.append(Vector3(p.x, top + gh - 2.0, p.y))


# The fuel farm (spec R3-6): four squat tanks for the craft's fuel, inside a low bund wall that would
# hold a spill, at the plant deck's apron end, away from where people work; a pipe rack along the
# duct carries the fuel back to the apron. Since R5: rust down the tanks, one crumpled, scrub in
# the bund, a span of the rack fallen.
func _fuel_farm(s: Dictionary, poly: PackedVector2Array, top: float) -> void:
	var frame := _deck_frame(poly)
	var axis: Vector2 = frame.axis
	var across: Vector2 = frame.across
	var inner := _inset(poly, 14.0)
	var above := _above(top)
	var span: float = frame.along_max - frame.along_min
	var mid: float = (frame.across_min + frame.across_max) * 0.5
	var half := 24.0
	var front: Vector2 = Vector2(_gantry[1].x, _gantry[1].z) if not _gantry.is_empty() else frame.origin
	# The duct's side away from the substation if it fits there (Mid overhangs most of it), else the
	# substation's side, well clear of it; as near the apron end (the deck frame's far end, the one
	# under Mid) as it fits.
	var origin: Vector2 = frame.origin
	var away := -signf((front - origin).dot(across) - mid)
	for side: float in [away, -away]:
		var off := side * (5.0 + 6.0 + half)
		var f := 0.9
		while f > 0.2:
			var c: Vector2 = origin + axis * (frame.along_min + span * f) + across * (mid + off)
			var bund := PackedVector2Array([c - axis * half - across * half, c + axis * half - across * half,
					c + axis * half + across * half, c - axis * half + across * half])
			if _all_inside(bund, inner) and not _any_inside(bund + PackedVector2Array([c]), above) 					and c.distance_to(front) > half + 60.0:
				_tank_farm(s, c, axis, across, half, top)
				_pipe_rack(s, c - across * side * half + axis * half, axis, top, frame, above)
				fuel_farm = Vector3(c.x, top, c.y)
				return
			f -= 0.02


func _tank_farm(s: Dictionary, c: Vector2, axis: Vector2, across: Vector2, half: float, top: float) -> void:
	var bund := PackedVector2Array([c - axis * half - across * half, c + axis * half - across * half,
			c + axis * half + across * half, c - axis * half + across * half])
	_ring(s.fine_wall, bund, _inset(bund, 1.5), top + 2.5, Vector3.UP)
	_walls(s.fine_wall, bund, top, top + 2.5)
	tree_slots.append({poly = _inset(bund, 2.0), y = top, count = 8, height = Vector2(1.5, 5.0)})
	for k in 4:
		var t := c + axis * (k % 2 - 0.5) * half + across * (floorf(k * 0.5) - 0.5) * half
		var shell := _circle(t, 9.0, 16)
		roof_blocks.append(_circle(t, 10.0, 16))
		if k == 2:
			_crumpled_tank(s, t, axis, top)
			continue
		_walls(s.wall, shell, top, top + 10.0)
		_cap(s.roof, shell, top + 10.0, Vector3.UP)
		_frustum(s.roof, _circle(t, 5.5, 16), top + 11.5, shell, top + 10.0)
		_cap(s.roof, _circle(t, 5.5, 16), top + 11.5, Vector3.UP)
		for j in 2:
			var d := axis.rotated(0.6 + j * 0.9)
			_panel(s.fine_rust, t + d * 9.05, Vector2(-d.y, d.x), 0.9, top + 2.0, top + 9.8, d)


# A tank that has given way (spec R5-5): its shell slumped to 4-7 m, leaning, the roof gone, rust
# and dark inside.
func _crumpled_tank(s: Dictionary, t: Vector2, axis: Vector2, top: float) -> void:
	var shell := _circle(t, 9.2, 16)
	for i in shell.size():
		var a := shell[i]
		var b := shell[(i + 1) % shell.size()]
		var ha := top + 5.5 + 1.5 * sin(i * 1.7) - 1.5 * (a - t).normalized().dot(axis)
		var hb := top + 5.5 + 1.5 * sin((i + 1) * 1.7) - 1.5 * (b - t).normalized().dot(axis)
		var out := ((a + b) * 0.5 - t).normalized()
		var n := Vector3(out.x, 0.0, out.y)
		_tri(s.fine_rust, Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(b.x, hb, b.y), n)
		_tri(s.fine_rust, Vector3(a.x, top, a.y), Vector3(b.x, hb, b.y), Vector3(a.x, ha, a.y), n)
		_tri(s.fine_dark, Vector3(a.x, top, a.y), Vector3(b.x, hb, b.y), Vector3(b.x, top, b.y), -n)
		_tri(s.fine_dark, Vector3(a.x, top, a.y), Vector3(a.x, ha, a.y), Vector3(b.x, hb, b.y), -n)
	_cap(s.fine_dark, _circle(t, 9.0, 16), top + 0.4, Vector3.UP)


# The pipe rack from the fuel farm back along the duct toward the apron, until it runs in under the
# deck above: a deck of pipes on bents every 12 m, 4 m up so the deck can be crossed under it.
func _pipe_rack(s: Dictionary, start: Vector2, axis: Vector2, top: float, frame: Dictionary,
		above: Array[PackedVector2Array]) -> void:
	var dir := axis
	var p := start
	var side := Vector2(-dir.y, dir.x)
	var origin: Vector2 = frame.origin
	var span := 0
	while (p - origin).dot(axis) < frame.along_max - 10.0:
		var q := p + dir * 12.0
		if _any_inside(PackedVector2Array([q]), above):
			break
		_block(s.fine_dark, s.fine_dark, _square(p, 0.7), top, top + 4.0)
		if span == 3:
			# The fallen span: one end still on its bent, the other down on the deck.
			_beam(s.fine_rust, Vector3(p.x, top + 4.6, p.y), Vector3(q.x, top + 0.6, q.y), 2.4)
		else:
			_block(s.fine_roof, s.fine_seam, PackedVector2Array([p - side * 1.6, q - side * 1.6, q + side * 1.6, p + side * 1.6]),
					top + 4.0, top + 5.2)
		span += 1
		p = q


# The power line (spec R3-6): from the substation's gantry, lattice pylons every ~250 m down the
# cut, on off the frame into the mist. Since R5 the pylons stand but most spans are down: the first
# and the fourth still carry their three wires; elsewhere one wire hangs from an arm to the ground.
func _build_power_line() -> void:
	if _gantry.is_empty():
		return
	var pc := ArrivalShot.POWER_CUT
	var b := _shot.at_distance(pc.to.x, pc.to.y, pc.distance)
	var a := Vector2(_gantry[1].x, _gantry[1].z)
	var end := Vector2(b.x, b.z)
	var dir := (end - a).normalized()
	var across := Vector2(-dir.y, dir.x)
	var s := _surfaces()
	var span := 250.0
	var count := int(a.distance_to(end) / span) + 2
	var arms: Array = [_gantry]
	for k in range(1, count + 1):
		var p := a + dir * (span * k - 60.0)
		var ground := _land.height(p.x, p.y)
		arms.append(_pylon(s, p, dir, across, ground))
	for k in arms.size() - 1:
		if k == 0 or k == 3:
			for w in 3:
				_wire(s.fine_dark, arms[k][w], arms[k + 1][w])
		elif k % 2 == 1:
			# Snapped mid-span: the end still on the arm hangs down to the slope.
			var from: Vector3 = arms[k][k % 3]
			var to: Vector3 = arms[k + 1][k % 3]
			var g := from.lerp(to, 0.18)
			g.y = _land.height(g.x, g.z)
			_wire(s.fine_dark, from, g)
	pylons = arms.size() - 1
	_commit("PowerLine", s)


# A lattice pylon on the ground at `p`, 38 m: four legs tapering in, cross-braced on every face, a
# crossarm square to the line. Returns the three wire points under the arm.
func _pylon(s: Dictionary, p: Vector2, dir: Vector2, across: Vector2, ground: float) -> Array:
	var h := 38.0
	var y_top := ground + h
	var base := 6.0
	var head := 1.6
	var corners := func(r: float) -> Array:
		return [p + (dir + across) * r, p + (dir - across) * r, p + (-dir - across) * r, p + (-dir + across) * r]
	var low: Array = corners.call(base)
	var high: Array = corners.call(head)
	var v := func(q: Vector2, y: float) -> Vector3: return Vector3(q.x, y, q.y)
	for i in 4:
		_beam(s.fine_dark, v.call(low[i], ground - 3.0), v.call(high[i], y_top), 1.2)
	# Bracing: an X on each face in three panels.
	for i in 4:
		var j := (i + 1) % 4
		for k in 3:
			var t0 := k / 3.0
			var t1 := (k + 1) / 3.0
			var a0: Vector3 = v.call((low[i] as Vector2).lerp(high[i], t0), lerpf(ground, y_top, t0))
			var b0: Vector3 = v.call((low[j] as Vector2).lerp(high[j], t0), lerpf(ground, y_top, t0))
			var a1: Vector3 = v.call((low[i] as Vector2).lerp(high[i], t1), lerpf(ground, y_top, t1))
			var b1: Vector3 = v.call((low[j] as Vector2).lerp(high[j], t1), lerpf(ground, y_top, t1))
			_beam(s.fine_dark, a0, b1, 0.8)
			_beam(s.fine_dark, b0, a1, 0.8)
	var arm_y := y_top - 1.0
	_beam(s.fine_dark, v.call(p - across * 9.0, arm_y), v.call(p + across * 9.0, arm_y), 1.4)
	var out := []
	for k in 3:
		out.append(v.call(p + across * (k - 1) * 7.0, arm_y - 2.5))
	return out


# A wire from `a` to `b`, sagging 3% of the span at the middle: a thin cross-section ribbon (two
# quads at right angles, so it reads from any side).
func _wire(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var n := 12
	var sag := a.distance_to(b) * 0.03
	var prev := a
	for k in range(1, n + 1):
		var t := float(k) / n
		var q := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		_beam(st, prev, q, 0.8)
		prev = q


# A square beam `size` thick from `a` to `b`.
func _beam(st: SurfaceTool, a: Vector3, b: Vector3, size: float) -> void:
	var d := (b - a).normalized()
	var up := Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT
	var u := d.cross(up).normalized() * size * 0.5
	var w := d.cross(u).normalized() * size * 0.5
	var ring := [u + w, u - w, -u - w, -u + w]
	for i in 4:
		var j := (i + 1) % 4
		var n: Vector3 = ((ring[i] + ring[j]) as Vector3).normalized()
		_tri(st, a + ring[i], b + ring[i], b + ring[j], n)
		_tri(st, a + ring[i], b + ring[j], a + ring[j], n)


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
		detail := true, bastion := 0.0, wear := &"") -> void:
	var centre := Vector2(top.x, top.z)
	var s := _surfaces()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tower_name) + 7
	var step_h := r * (0.16 if role == &"control" else step_height)
	var y_step := top.y if role == &"pad" else top.y - step_h
	var y_rim := y_step - rim_height * r
	var y_gap := y_rim - gap_height * r
	var y_low := y_gap - lower_rim_height * r
	# Flight control's cab (spec R3-7) is the skirt itself, glazed and raked out toward the pads, so
	# it gets a little more height.
	var y_skirt := y_low - skirt_height * r * vary * (1.3 if role == &"control" else 1.0)
	var y_collar := y_skirt - collar_height * r * vary
	var ground := _land.height(top.x, top.z)
	# On a slope the footing's downhill side carries on down as a plinth to the lowest ground round it.
	var lowest := ground
	for i in 8:
		var q := centre + Vector2.from_angle(TAU * i / 8.0) * sr * 1.6
		lowest = minf(lowest, _land.height(q.x, q.y))
	var foot := minf(ground - 20.0, lowest - 10.0)
	# Spec R5-2: what 200 years took out of the cap, cut layer by layer (upper step, rim, the dark
	# gap, lower rim), each a little shallower going down so a big break steps. Broken faces in seam.
	var cuts := _cap_cuts(wear, r, rng)
	var step_cuts := _layer_cuts(cuts, centre, r, 0)
	if role != &"pad":
		var sp := r * step_radius * (0.85 if role == &"sensor" else 1.0)
		var step0 := _octagon(centre, sp)
		var step := _bitten(step0, step_cuts)
		_cap(s.roof, step, top.y, Vector3.UP)
		_walls_split(s.wall, s.seam, step, step0, y_step, top.y)
	var rim0 := _octagon(centre, r)
	var rim := _bitten(rim0, _layer_cuts(cuts, centre, r, 1))
	_cap(s.roof, rim, y_step, Vector3.UP)
	_walls_split(s.wall, s.seam, rim, rim0, y_rim, y_step)
	var gap := _bitten(_octagon(centre, r * 0.9), _layer_cuts(cuts, centre, r, 2))
	_walls(s.under, gap, y_gap, y_rim)
	var low0 := _octagon(centre, r * 0.97)
	var low_cuts := _layer_cuts(cuts, centre, r, 3)
	var low := _bitten(low0, low_cuts)
	if cuts.is_empty():
		_ring(s.wall, low0, _octagon(centre, r * 0.9), y_gap, Vector3.UP)
	else:
		_cap(s.under, gap, y_rim - 0.2, Vector3.UP)
		_cap(s.seam, low, y_gap, Vector3.UP)
		for c in low_cuts:
			for piece in Geometry2D.intersect_polygons(_octagon(centre, r * 0.9), c):
				_cap(s.under, piece, y_low + 0.2, Vector3.UP)
		_rebar(s, rim, rim0, centre, y_rim, y_step, r, rng)
		_rebar(s, low, low0, centre, y_low, y_gap, r, rng)
	_walls_split(s.wall, s.seam, low, low0, y_low, y_gap)
	rim_loss[tower_name] = 1.0 - _area(rim) / _area(rim0)
	if wear == &"broken":
		var mid := centre + Vector2.from_angle(cuts[0].angle) * r * 0.75
		break_spots.append(Vector3(mid.x, y_step, mid.y))
	if role == &"control":
		_cab(s, centre, r, sr, y_low, y_skirt)
	else:
		_frustum(s.under, _octagon(centre, r * 0.9), y_low, _octagon(centre, sr * 1.15), y_skirt)
	if detail:
		_brackets(s, centre, r, sr, y_low, y_collar, step_cuts + _layer_cuts(cuts, centre, r, 1), rng)
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
	var floor_y := INF
	if bastion > 0.0:
		floor_y = _bastion(s, centre, bastion)
	else:
		_footing(s, centre, sr, ground)
		if lowest < ground - sr * 0.4:
			_walls(s.wall, _octagon(centre, sr * 1.5), lowest - 10.0, ground - sr * 0.4)
	if detail:
		_service_rings(s, centre, sr, ground)
	match role:
		&"comms":
			_comms(s, centre, r, top.y, wear == &"snapped")
		&"exhaust":
			_exhaust(s, centre, r, top.y, y_step, y_low, step_cuts)
		&"sensor":
			_radome(s, centre, r * 0.3, top.y)
	if detail:
		_tower_growth(tower_name, centre, r, sr, rim, rim0, y_step, y_low, y_collar, ground, floor_y)
	_commit(tower_name, s)


# The cuts a tower's `wear` takes out of its cap (spec R5-2), as {angle, width (rad), inner (per
# layer: the break's radius as a fraction of the cap's), seed}. `broken`: one wedge a third of the
# way round, on the cap's right where it cuts the silhouette against the sky, deep (into the upper
# step). `snapped` / `bitten`: two
# or three shallow bites out of the rim on the side the camera sees.
func _cap_cuts(wear: StringName, r: float, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var cuts: Array[Dictionary] = []
	match wear:
		&"broken":
			cuts.append({angle = 0.3, width = 2.1, inner = [0.28, 0.42, 0.5, 0.56], seed = rng.randi()})
		&"snapped", &"bitten":
			for k in rng.randi_range(2, 3):
				var depth := rng.randf_range(0.84, 0.9)
				cuts.append({angle = rng.randf_range(0.2, 2.9), width = rng.randf_range(0.22, 0.38),
						inner = [depth, depth, depth + 0.02, depth + 0.04], seed = rng.randi()})
	return cuts


# The cut polygons for cap layer `layer` (0 step, 1 rim, 2 gap, 3 lower rim): each wedge from well
# outside the cap in to its jagged break line, the same jag on every layer so the break steps.
func _layer_cuts(cuts: Array[Dictionary], centre: Vector2, r: float, layer: int) -> Array[PackedVector2Array]:
	var polys: Array[PackedVector2Array] = []
	for c in cuts:
		var rng := RandomNumberGenerator.new()
		rng.seed = c.seed
		var a0: float = c.angle - c.width * 0.5
		var a1: float = c.angle + c.width * 0.5
		var poly := PackedVector2Array()
		for k in 4:
			poly.append(centre + Vector2.from_angle(lerpf(a0, a1, k / 3.0)) * r * 1.5)
		var n := maxi(int(c.width / 0.12), 4)
		var inner: float = c.inner[layer]
		for k in n + 1:
			var f := 1.0 - float(k) / n
			var jag := rng.randf_range(-0.06, 0.06) if k > 0 and k < n else 0.0
			poly.append(centre + Vector2.from_angle(lerpf(a0, a1, f)) * r * clampf(inner + jag, 0.1, 1.2))
		polys.append(poly)
	return polys


# Rebar standing out of a cap's broken faces: at each corner of the break line (a corner of `poly`
# not on the whole outline `whole`), two bars out from the break, fine rust.
func _rebar(s: Dictionary, poly: PackedVector2Array, whole: PackedVector2Array, centre: Vector2, y0: float, y1: float,
		r: float, rng: RandomNumberGenerator) -> void:
	for p in poly:
		if _boundary_distance(p, whole) < 0.5:
			continue
		for j in 2:
			var y := rng.randf_range(y0 + 0.5, y1 - 0.5)
			var q := p + (p - centre).normalized().rotated(rng.randf_range(-0.5, 0.5)) * r * rng.randf_range(0.04, 0.09)
			_beam(s.fine_rust, Vector3(p.x, y, p.y), Vector3(q.x, y - rng.randf_range(0.0, r * 0.03), q.y), maxf(r * 0.008, 0.6))


# Flight control's cab (spec R3-7): the raked skirt glazed all round. Since R5 the glass is gone but
# for two faces' worth (the panes catch the sky), and a third of the mullions have fallen.
func _cab(s: Dictionary, centre: Vector2, r: float, sr: float, y_low: float, y_skirt: float) -> void:
	for i in 8:
		_frustum(s.glass if i == 2 or i == 5 else s.under, _octagon(centre, r * 0.9), y_low, _octagon(centre, sr * 1.15),
				y_skirt, i)
	for i in 32:
		if i % 3 == 0:
			continue
		var a := TAU * (i + 0.5) / 32.0
		var dir := Vector2(cos(a), sin(a))
		var p0 := centre + dir * r * 0.9 * cos(PI / 8.0) * 1.02
		var p1 := centre + dir * sr * 1.15 * cos(PI / 8.0) * 1.02
		_beam(s.fine_wall, Vector3(p0.x, y_low, p0.y), Vector3(p1.x, y_skirt, p1.y), 1.4)


# The tower as faces for ArrivalGrowth (spec R5-4): the shaft's eight faces (curtains from under the
# collar, growth climbing from the ground or the bastion's top) and the rim's whole faces (a fringe
# over the dark gap). The nearest tower, the left one, carries the most. The strips' ragged edges
# fill about two thirds of them, so the strip shares sit over the spec's wall cover (R5-4).
func _tower_growth(tower_name: String, centre: Vector2, r: float, sr: float, rim: PackedVector2Array, rim0: PackedVector2Array,
		y_step: float, y_low: float, y_collar: float, ground: float, floor_y: float) -> void:
	var cover := 0.75 if tower_name == ArrivalShot.TOWERS[0].name else 0.6
	# The shaft's ribs stand ~0.13 sr proud of its faces, so growth only hangs in the bays between
	# them (spec R6-1): each face split at the ribs that cross it, a rib's half width + 0.6 m clear.
	var shaft := _octagon(centre, sr)
	var clear := sr * rib_size * 0.5 + 0.6
	for i in 8:
		var a := shaft[i]
		var b := shaft[(i + 1) % 8]
		var out := ((a + b) * 0.5 - centre).normalized()
		var length := a.distance_to(b)
		var cuts: Array[float] = []
		for k in ribs:
			var hit: Variant = Geometry2D.segment_intersects_segment(centre, centre + Vector2.from_angle(TAU * k / ribs) * sr * 2.0,
					a.lerp(b, -0.01), b.lerp(a, -0.01))
			if hit != null:
				cuts.append(clampf(a.distance_to(hit), 0.0, length))
		cuts.sort()
		var ends: Array[float] = [0.0]
		for c in cuts:
			ends.append_array([c - clear, c + clear])
		ends.append(length)
		var e := (b - a) / length
		for k in range(0, ends.size(), 2):
			var x0 := maxf(ends[k], 0.0)
			var x1 := minf(ends[k + 1], length)
			if x1 - x0 < 3.0:
				continue
			walls.append({a = a + e * x0, b = a + e * x1, out = out, top = y_collar,
					bottom = maxf(ground, floor_y if floor_y != INF else ground) + 2.0, cover = cover, climb = true,
					floor = floor_y, streaks = true, kind = &"shaft", tower = tower_name})
	# The rim's fringe hangs over the dark gap and stops at the lower rim's foot (spec R6-1): below
	# it the skirt pulls in and anything longer hangs in the air.
	for i in rim.size():
		var a := rim[i]
		var b := rim[(i + 1) % rim.size()]
		if _boundary_distance((a + b) * 0.5, rim0) > 0.5 or a.distance_to(b) < 6.0:
			continue
		var out := ((a + b) * 0.5 - centre).normalized()
		walls.append({a = a, b = b, out = out, top = y_step, bottom = y_low, cover = 0.35, climb = false,
				floor = INF, streaks = true, kind = &"rim", tower = tower_name})
	caps.append({poly = rim, y = y_step, inner = r * step_radius, tower = tower_name})


# Brackets (spec R3-7): eight radial fins under the cap's skirt, from under the rim down past the
# collar into the shaft, so the cantilevered cap is visibly carried. Fine parts (no ink). Only on the
# main base's towers; at the outpost's 7 km they'd be under a pixel. Since R5 one has fallen, and
# none is left under a broken stretch of rim (`cuts`).
func _brackets(s: Dictionary, centre: Vector2, r: float, sr: float, y_low: float, y_collar: float,
		cuts: Array[PackedVector2Array], rng: RandomNumberGenerator) -> void:
	var t := r * 0.03
	var fallen := rng.randi_range(0, 7)
	for i in 8:
		var a := TAU * i / 8.0
		var dir := Vector2(cos(a), sin(a))
		if i == fallen or _any_inside(PackedVector2Array([centre + dir * r * 0.8]), cuts):
			continue
		# The profile in (radius, height): under the rim, out along the skirt, down onto the shaft.
		var profile := PackedVector2Array([Vector2(r * 0.94, y_low), Vector2(sr * 1.34, y_collar),
				Vector2(sr * 0.98, y_collar - r * 0.35), Vector2(sr * 0.5, y_low)])
		_fin(s.fine_seam, centre, dir, profile, t)


# A flat fin `half` thick either side of the vertical plane through `centre` along `dir`, its outline
# `profile` in (distance out along `dir`, height).
func _fin(st: SurfaceTool, centre: Vector2, dir: Vector2, profile: PackedVector2Array, half: float) -> void:
	var side := Vector3(-dir.y, 0.0, dir.x)
	var radial := Vector3(dir.x, 0.0, dir.y)
	var o := Vector3(centre.x, 0.0, centre.y)
	var pt := func(q: Vector2, k: float) -> Vector3: return o + radial * q.x + Vector3.UP * q.y + side * half * k
	var idx := Geometry2D.triangulate_polygon(profile)
	for t in range(0, idx.size(), 3):
		for k: float in [-1.0, 1.0]:
			_tri(st, pt.call(profile[idx[t]], k), pt.call(profile[idx[t + 1]], k), pt.call(profile[idx[t + 2]], k), side * k)
	var c := _centroid(profile)
	for i in profile.size():
		var a := profile[i]
		var b := profile[(i + 1) % profile.size()]
		var n2 := Vector2(b.y - a.y, a.x - b.x).normalized()
		if n2.dot((a + b) * 0.5 - c) < 0.0:
			n2 = -n2
		var n := (radial * n2.x + Vector3.UP * n2.y).normalized()
		_tri(st, pt.call(a, -1.0), pt.call(b, -1.0), pt.call(b, 1.0), n)
		_tri(st, pt.call(a, -1.0), pt.call(b, 1.0), pt.call(a, 1.0), n)


# Service rings (spec R3-7): only where a deck comes up to the shaft, a maintenance platform round
# it at the floor of that deck's top storey, snow on it, a door in the shaft facing the deck.
func _service_rings(s: Dictionary, centre: Vector2, sr: float, ground: float) -> void:
	for d in _decks:
		var poly: PackedVector2Array = d.poly
		if Geometry2D.is_point_in_polygon(centre, poly):
			continue
		var near := centre
		var best := INF
		for i in poly.size():
			var q := Geometry2D.get_closest_point_to_segment(centre, poly[i], poly[(i + 1) % poly.size()])
			if q.distance_to(centre) < best:
				best = q.distance_to(centre)
				near = q
		var y: float = d.top - storey
		if best - sr > 60.0 or y < ground + 10.0:
			continue
		_service_ring(s, centre, sr, y, (near - centre).normalized())


func _service_ring(s: Dictionary, centre: Vector2, sr: float, y: float, toward: Vector2) -> void:
	var outer := _octagon(centre, sr * 1.0 + 6.0)
	var inner := _octagon(centre, sr * 0.9)
	_ring(s.fine_roof, outer, inner, y, Vector3.UP)
	_walls(s.fine_wall, outer, y - 1.5, y)
	_ring(s.fine_dark, outer, inner, y - 1.5, Vector3.DOWN)
	var across := Vector2(-toward.y, toward.x)
	_panel(s.fine_dark, centre + toward * (sr * cos(PI / 8.0) + 0.5), across, 3.5, y, y + 7.0, toward)


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


# A bastion (spec R4-2), the foot of a tower that stands down the slope: a retaining plinth cut into
# the hill in `bastion_tiers` octagonal tiers out to `rb`, the top one level with the uphill ground,
# each further one a step lower and wider, so the downhill face is a stepped wall in the foundation's
# dark, ribbed like it. The tops are snowed over (since R5, nobody plows the tower's yard) with a thin
# drift line along each edge, and their faces are growth faces (curtains, climbing). The land clears
# only its own octagon (ArrivalLand), so the forest comes to the wall. Returns the top tier's height.
func _bastion(s: Dictionary, centre: Vector2, rb: float) -> float:
	var radii := PackedFloat32Array()
	for i in bastion_tiers:
		radii.append(rb * lerpf(0.62, 1.0, float(i) / maxi(bastion_tiers - 1, 1)))
	var high := -INF
	var low := INF
	for k in 16:
		var dir := Vector2.from_angle(TAU * k / 16.0)
		var q := centre + dir * radii[0]
		high = maxf(high, _land.height(q.x, q.y))
		q = centre + dir * (rb + 6.0)
		low = minf(low, _land.height(q.x, q.y))
	var y_top := high + 3.0
	var drop := (y_top - low) / bastion_tiers
	for i in bastion_tiers:
		var y := y_top - drop * i
		var poly := _octagon(centre, radii[i])
		_walls(s.under, poly, low - 14.0, y)
		if i == 0:
			_cap(s.roof, poly, y, Vector3.UP)
		else:
			_ring(s.roof, poly, _octagon(centre, radii[i - 1]), y, Vector3.UP)
		_ring(s.fine_roof, poly, _octagon(centre, radii[i] - bastion_drift), y + 0.3, Vector3.UP)
		# Ribs: pilasters on every face, in seam tone (light fins read as windows, spec R3).
		for f in 8:
			var a := poly[f]
			var b := poly[(f + 1) % 8]
			var e := (b - a).normalized()
			var out := Vector2(e.y, -e.x)
			if out.dot((a + b) * 0.5 - centre) < 0.0:
				out = -out
			for j in 3:
				var c := a.lerp(b, (j + 1) / 4.0)
				_block(s.fine_seam, s.fine_seam, PackedVector2Array([c - e * 1.6, c + e * 1.6,
						c + e * 1.6 + out * 1.4, c - e * 1.6 + out * 1.4]), low - 14.0, y - 1.5)
			walls.append({a = a + out * 1.5, b = b + out * 1.5, out = out, top = y, bottom = low - 2.0, cover = 0.3, climb = true,
					floor = INF, streaks = false})
	return y_top


# Comms: a tapered mast off the cap's centre with two yardarms, and one dish on a plinth at the rim,
# tilted up toward the sky. `snapped` (spec R5-2): the mast broken halfway, its top hanging off the
# stump toward the camera's left with one yardarm still on it; the dish torn off its plinth and
# lying tipped on its edge on the rim.
func _comms(s: Dictionary, centre: Vector2, r: float, y: float, snapped: bool) -> void:
	var tip := y + r * 1.1
	var at := centre + Vector2(-0.55, 0.55).normalized() * r * 0.72
	var y_rim := y - step_height * r
	_block(s.roof, s.wall, _square(at, r * 0.06), y_rim, y_rim + r * 0.08)
	if not snapped:
		_frustum(s.wall, _square(centre, r * 0.012), tip, _square(centre, r * 0.05), y)
		for f: float in [0.62, 0.84]:
			var h := lerpf(y, tip, f)
			var arm := PackedVector2Array([centre + Vector2(-r * 0.16, -r * 0.008), centre + Vector2(r * 0.16, -r * 0.008),
					centre + Vector2(r * 0.16, r * 0.008), centre + Vector2(-r * 0.16, r * 0.008)])
			_block(s.wall, s.wall, arm, h - r * 0.012, h)
		_dish(s.wall, Vector3(at.x, y_rim + r * 0.2, at.y), Vector3(-0.5, 0.75, 0.45).normalized(), r * 0.17, r * 0.06)
		mast_top = tip
		return
	var hb := lerpf(y, tip, 0.5)
	_frustum(s.wall, _square(centre, r * 0.031), hb, _square(centre, r * 0.05), y)
	var foot := Vector3(centre.x, hb, centre.y)
	var lean := Vector3(-0.6, 0.25, 0.7).normalized()
	var end := foot + lean * r * 0.5
	_beam(s.wall, foot, end, r * 0.05)
	var across := lean.cross(Vector3.UP).normalized()
	var arm_at := foot.lerp(end, 0.6)
	_beam(s.wall, arm_at - across * r * 0.14, arm_at + across * r * 0.14, r * 0.02)
	mast_top = maxf(hb, end.y)
	var lying := centre + Vector2(0.6, 0.5).normalized() * r * 0.62
	_dish(s.wall, Vector3(lying.x, y_rim + r * 0.11, lying.y), Vector3(0.7, 0.3, 0.65).normalized(), r * 0.17, r * 0.06)


# Exhaust: a row of short stacks on the cap's downwind side, open (dark) at the top, soot streaking
# the step and the rim below them. Cold since R5: the ones on the broken stretch (`cuts`) went down
# with it, the rest are snapped short.
func _exhaust(s: Dictionary, centre: Vector2, r: float, y: float, y_step: float, y_low: float,
		cuts: Array[PackedVector2Array]) -> void:
	for k in 5:
		var z := (k - 2) * r * 0.12
		var c := centre + Vector2(r * 0.32, z)
		if _any_inside(PackedVector2Array([c]), cuts):
			continue
		var stack := _octagon(c, r * 0.055)
		var h := r * (0.035 + 0.03 * (k % 2))
		_walls(s.wall, stack, y, y + h)
		_cap(s.under, stack, y + h, Vector3.UP)
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


# --- the skybridge -----------------------------------------------------------------------------

# The skybridge (spec R3-2): the left (comms) tower stands down the slope, so the way to it is an
# enclosed bridge from the Lower deck's nearest edge into its shaft at deck level. A boxed truss 12 m
# deep: steel sides with diagonals, a glazed strip along them, snow on its roof, the comms cable
# tray hung under it. It lands on the shaft's service ring (`_service_rings`). No pier: the span is
# short (spec: only over ~150 m). Since R5 (spec R5-5) it sags in the middle, the glazing is black
# but for one pane a side, and the tray has torn off at the deck end and hangs down; growth hangs
# off its sides.
func _build_skybridge() -> void:
	var tower: Dictionary = ArrivalShot.TOWERS[0]
	var top := cap_tops[0]
	var c := Vector2(top.x, top.z)
	var sr: float = tower.shaft
	var lower := _deck_named(&"Lower")
	var poly: PackedVector2Array = lower.poly
	var near := c
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(c, poly[i], poly[(i + 1) % poly.size()])
		if q.distance_to(c) < best:
			best = q.distance_to(c)
			near = q
	var d := (near - c).normalized()
	var side := Vector2(-d.y, d.x)
	var a := c + d * sr * 0.8
	var b := near + d * 12.0
	# Its floor on the deck's top storey, like the service ring the tower has there.
	var y0: float = lower.top - storey
	var y1 := y0 + 12.0
	var hw := 7.0
	var sag := 3.0
	skybridge = [Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)]
	var s := _surfaces()
	var length := a.distance_to(b)
	var bays := maxi(int(length / 10.0), 1)
	var dip := func(f: float) -> float: return -sag * sin(PI * f)
	for i in bays:
		var f0 := float(i) / bays
		var f1 := float(i + 1) / bays
		var p0 := a.lerp(b, f0)
		var p1 := a.lerp(b, f1)
		var h0: float = dip.call(f0)
		var h1: float = dip.call(f1)
		var v := func(q: Vector2, y: float) -> Vector3: return Vector3(q.x, y, q.y)
		# Roof (snow, 0.8 m proud), floor, and each side: steel, the glazed strip, steel.
		_quad(s.roof, v.call(p0 - side * (hw + 0.6), y1 + 0.8 + h0), v.call(p1 - side * (hw + 0.6), y1 + 0.8 + h1),
				v.call(p1 + side * (hw + 0.6), y1 + 0.8 + h1), v.call(p0 + side * (hw + 0.6), y1 + 0.8 + h0), Vector3.UP)
		_quad(s.under, v.call(p0 - side * hw, y0 + h0), v.call(p1 - side * hw, y0 + h1), v.call(p1 + side * hw, y0 + h1),
				v.call(p0 + side * hw, y0 + h0), Vector3.DOWN)
		for k: float in [-1.0, 1.0]:
			var out := side * k
			var n := Vector3(out.x, 0.0, out.y)
			var e0 := p0 + out * hw
			var e1 := p1 + out * hw
			var pane: bool = i == (bays / 3 if k < 0.0 else bays * 2 / 3)
			for band: Array in [[y0, y0 + 4.0, s.wall], [y0 + 4.0, y0 + 8.5, s.glass if pane else s.under], [y0 + 8.5, y1 + 0.8, s.wall]]:
				_quad(band[2], v.call(e0, band[0] + h0), v.call(e1, band[0] + h1), v.call(e1, band[1] + h1), v.call(e0, band[1] + h0), n)
			# The truss: a diagonal per 10 m bay, alternating, standing just proud of the side.
			var q0 := p0 + out * (hw + 0.6)
			var q1 := p1 + out * (hw + 0.6)
			if i % 2 == 0:
				_beam(s.fine_wall, v.call(q0, y0 + 0.5 + h0), v.call(q1, y1 - 0.5 + h1), 1.0)
			else:
				_beam(s.fine_wall, v.call(q0, y1 - 0.5 + h0), v.call(q1, y0 + 0.5 + h1), 1.0)
		if i == 0 or i == bays - 1:
			var cap_at := p0 if i == 0 else p1
			var hh := h0 if i == 0 else h1
			_panel(s.wall, cap_at, side, hw, y0 + hh, y1 + 0.8 + hh, -d if i == 0 else d)
	# The cable tray, hung 2 m under the floor from the tower end; torn off at three quarters of the
	# way and hanging down from there.
	var t0 := Vector3(a.x, y0 - 2.6, a.y)
	var t1 := Vector3(a.lerp(b, 0.72).x, y0 - 2.6 + dip.call(0.72), a.lerp(b, 0.72).y)
	_beam(s.fine_dark, t0, t1, 2.4)
	_beam(s.fine_dark, t1, t1 + Vector3(d.x * 3.0, -26.0, d.y * 3.0), 2.0)
	for k: float in [-1.0, 1.0]:
		var out := side * k
		walls.append({a = a + out * (hw + 1.0), b = b + out * (hw + 1.0), out = out, top = y1 + 0.8, bottom = y0 - 15.0,
				cover = 0.4, climb = false, floor = INF, streaks = false, sag = sag})
	_commit("Skybridge", s)


# --- the road ----------------------------------------------------------------------------------

# The access road (spec R4-3) on the land's rounded centreline: a surface kept level across (cut
# into the slope) and a dark cut bank where the uphill side stands over it. Unplowed for 200 years
# (spec R5-5): the surface is snow and the berm is gone; young trees (ArrivalGrowth) grow on it, so
# it reads as a faint scar following its cut bank. Fine parts: at ~900 m an 8 m road is a line of
# tone, ink would only add noise.
func _build_road() -> void:
	var path := _land.road_path
	if path.size() < 2:
		return
	var pts := PackedVector2Array()
	for i in path.size() - 1:
		var n := maxi(int(ceil(path[i].distance_to(path[i + 1]) / road_step)), 1)
		for k in n:
			pts.append(path[i].lerp(path[i + 1], float(k) / n))
	pts.append(path[path.size() - 1])
	var s := _surfaces()
	var hw := _land.road_width * 0.5
	var verge := _land.road_verge
	var rows: Array[Dictionary] = []
	for i in pts.size():
		var e := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var n := Vector2(-e.y, e.x)
		var p := pts[i]
		var hl := _land.height(p.x - n.x * hw, p.y - n.y * hw)
		var hr := _land.height(p.x + n.x * hw, p.y + n.y * hw)
		# Uphill: the side the slope rises to.
		var up := n if hr > hl else -n
		var y := maxf(maxf(hl, hr), _land.height(p.x, p.y)) + 0.4
		var bank := p + up * (hw + verge)
		var toe := p - up * (hw + verge)
		rows.append({p = p, up = up, y = y, bank = bank, bank_y = maxf(_land.height(bank.x, bank.y), y),
				toe = toe, toe_y = minf(_land.height(toe.x, toe.y), y)})
	var v := func(q: Vector2, h: float) -> Vector3: return Vector3(q.x, h, q.y)
	for i in rows.size() - 1:
		var a: Dictionary = rows[i]
		var b: Dictionary = rows[i + 1]
		var a_up: Vector2 = a.p + a.up * hw
		var a_dn: Vector2 = a.p - a.up * hw
		var b_up: Vector2 = b.p + b.up * hw
		var b_dn: Vector2 = b.p - b.up * hw
		# The surface, under snow.
		_tri(s.fine_roof, v.call(a_up, a.y), v.call(b_up, b.y), v.call(b_dn, b.y), Vector3.UP)
		_tri(s.fine_roof, v.call(a_up, a.y), v.call(b_dn, b.y), v.call(a_dn, a.y), Vector3.UP)
		# The cut bank: from the road's uphill edge up to the slope.
		var bank_n := Vector3(-a.up.x, 0.6, -a.up.y).normalized()
		_tri(s.fine_seam, v.call(a_up, a.y), v.call(b_up, b.y), v.call(b.bank, b.bank_y), bank_n)
		_tri(s.fine_seam, v.call(a_up, a.y), v.call(b.bank, b.bank_y), v.call(a.bank, a.bank_y), bank_n)
		# The downhill edge falls away to the slope, snowed over.
		var fall_n := Vector3(-a.up.x, 1.0, -a.up.y).normalized()
		_tri(s.fine_roof, v.call(a_dn, a.y), v.call(b_dn, b.y), v.call(b.toe, b.toe_y), fall_n)
		_tri(s.fine_roof, v.call(a_dn, a.y), v.call(b.toe, b.toe_y), v.call(a.toe, a.toe_y), fall_n)
	_commit("Road", s)


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
		if top.y > tallest.y:
			tallest = top
	# Spec R5-2: the outpost's tallest cap is the one broken.
	for i in OUTPOST_TOWERS.size():
		var t: Array = OUTPOST_TOWERS[i]
		var top := outpost_top + Vector3(t[0], t[2], t[1])
		_build_tower("OutpostTower%d" % i, top, t[3], t[4], &"", 1.0, false, 0.0, &"broken" if top == tallest else &"")


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


## `poly` with each of `cuts` taken out of it (the largest piece left after each cut).
static func _bitten(poly: PackedVector2Array, cuts: Array[PackedVector2Array]) -> PackedVector2Array:
	var out := poly
	for cut in cuts:
		var parts := Geometry2D.clip_polygons(out, cut)
		if parts.is_empty():
			continue
		var best: PackedVector2Array = parts[0]
		for q in parts:
			if _area(q) > _area(best):
				best = q
		out = best
	return out


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


## How far `p` is from the outline of `poly`.
static func _boundary_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
	return best


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


# A flat face over `poly` at `y` with `hole` (inside it) left open: the outline split down a line
# through the hole into two halves, each with its share of the hole cut out of its edge, so neither
# piece has a hole of its own to triangulate.
func _cap_holed(st: SurfaceTool, poly: PackedVector2Array, hole_poly: PackedVector2Array, y: float) -> void:
	var c := _centroid(hole_poly)
	var big := 100000.0
	for side: float in [-1.0, 1.0]:
		var half := PackedVector2Array([Vector2(c.x, c.y - big), Vector2(c.x + side * big, c.y - big),
				Vector2(c.x + side * big, c.y + big), Vector2(c.x, c.y + big)])
		for piece in Geometry2D.intersect_polygons(poly, half):
			for q in Geometry2D.clip_polygons(piece, hole_poly):
				_cap(st, q, y, Vector3.UP)


# A quad a-b-c-d facing `want`.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3) -> void:
	_tri(st, a, b, c, want)
	_tri(st, a, c, d, want)


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


# The walls of a bitten outline `poly` from `y0` to `y1`: the stretches still on the whole outline
# `whole` in `st`, the broken faces the cuts made in `st_break`.
func _walls_split(st: SurfaceTool, st_break: SurfaceTool, poly: PackedVector2Array, whole: PackedVector2Array, y0: float,
		y1: float) -> void:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var keep := _boundary_distance((a + b) * 0.5, whole) < 0.5
		_walls(st if keep else st_break, PackedVector2Array([a, b]), y0, y1, false, poly)


# The side walls of polygon `poly` (xz) from `y0` up to `y1`, facing out (`inward`: facing in, the
# inside of a roofless box). With `inside_of`, `poly` is a run of edges and that polygon says which
# way is out.
func _walls(st: SurfaceTool, poly: PackedVector2Array, y0: float, y1: float, inward := false,
		inside_of := PackedVector2Array()) -> void:
	var ref := poly if inside_of.is_empty() else inside_of
	var n_edges := poly.size() if inside_of.is_empty() else poly.size() - 1
	for i in n_edges:
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		var out := Vector2(e.y, -e.x)
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + out * 0.05, ref) != inward:
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
# out; only face `only` if given.
func _frustum(st: SurfaceTool, upper: PackedVector2Array, y_up: float, lower: PackedVector2Array, y_low: float,
		only := -1) -> void:
	var centre := _centroid(upper)
	for i in upper.size():
		if only >= 0 and i != only:
			continue
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
