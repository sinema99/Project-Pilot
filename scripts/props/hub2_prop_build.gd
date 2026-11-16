class_name Hub2PropBuild
extends RefCounted

# The geometry of every Hub2Prop kind (docs/specs/hub2-storage.md). Each builder fills a PropKit
# and returns its collision boxes as [centre, size, basis?]. Sizes are real-world metres.
#
# Variants per kind:
#   CRATE_WOOD    0 small cube 0.8, 1 medium 1.2 x 0.9 x 1.0, 2 long 2.0 x 0.8 x 0.9, 3 medium broken open
#   CRATE_METAL   0 olive ammo box 1.0 x 0.6 x 0.6, 1 grey locker 0.9 x 1.9 x 0.6, 2 big grey chest 1.6 x 1.0 x 1.0
#   TOTE          0 blue, 1 grey, 2 green, 3 a stack of four (seeded colours)
#   PALLET        0 empty, 1 shrink-wrapped load, 2 cartons stacked
#   RACKING       0 one bay (2.7 w x 1.1 d x 5.4 h, beams at 0.15 / 1.9 / 3.6), 1 bay leaning / bent
#   FORKLIFT      0 yellow, 1 orange, 2 crushed wreck
#   REACH_STACKER 0 yellow
#   SCISSOR_LIFT  0 standing (lay it on its side with the node's rotation for the toppled one)
#   PALLET_JACK   0
#   FUEL_STATION  0 diesel pump + charger cabinet
#   WORKBENCH     0 bench, vice, tool board
#   DOCK_DOOR     0 closed roll-up (4 x 4.5, wall mounted, +Z out), 1 jammed half open
#   DOCK_LEVELLER 0 floor plate + bumpers (in front of a dock door)
#   SPREADER      0 container spreader frame, cables up by `length`
#   CABINET       0 electrical cabinet 1.2 x 2.0, 1 narrow 0.7 x 2.0
#   JUNCTION_BOX  0 box with conduit up by `length`
#   HOSE_REEL     0 red cabinet with reel
#   EXTINGUISHER  0 on a bracket with a sign plate
#   TERMINAL      0..3 = 1..4 screens in a bank; `powered` lights the screens; seed picks a cracked one
#   LAMP_HIGHBAY  0 straight, 1 hanging crooked on one chain; `length` = chain
#   LAMP_BULKHEAD 0 caged wall lamp
#   FLOODLIGHT    0 girder flood, aims down 45 deg along +Z
#   MOSS          0 floor patch ~1.5 m, 1 big ~3 m, 2 wall creep (flat on the XY plane, grows up +Y)
#   TUFT          0 grass, 1 weeds
#   SHRUB         0 small, 1 big
#   TREE          0 small gnarled, 1 bigger
#   VINE          0 hanging strand of `length`
#   LIGHT_SHAFT   0 faint additive cold column hanging `length` from the ceiling (room A's one natural light)
#   JERSEY_BARRIER 0 grimy concrete, 1 with faded yellow / black hazard stripes; `length` = metres long (1.1 m high, 0.6 wide)
#   PLATE_SHIELD  0 welded steel plate on two raked legs, 2.0 x 1.1 m, leaning back a few degrees; 1 olive paint
#   HANGAR_DOOR   0 sealed twin-leaf hangar door, HANGAR_W wide x `length` tall (wall mounted, +Z out), jogged seam

const K := Hub2Prop.Kind

const WOOD := Color(0.55, 0.40, 0.24)
const WOOD_DARK := Color(0.36, 0.25, 0.14)
const STEEL := Color(0.42, 0.44, 0.46)
const STEEL_DARK := Color(0.20, 0.21, 0.23)
const OLIVE := Color(0.33, 0.36, 0.20)
const RACK_ORANGE := Color(0.82, 0.38, 0.10)
const RACK_BLUE := Color(0.16, 0.28, 0.58)
const SAFETY_YELLOW := Color(0.88, 0.68, 0.10)
const BLACK := Color(0.07, 0.07, 0.08)
const RED := Color(0.68, 0.10, 0.08)
const LEAF := Color(0.24, 0.36, 0.13)
const LEAF_DARK := Color(0.13, 0.22, 0.09)
const MOSS_COL := Color(0.30, 0.40, 0.14)
const BARK := Color(0.28, 0.20, 0.13)
const CARTON := Color(0.62, 0.48, 0.30)
const WRAP := Color(0.74, 0.76, 0.78)

static var _crt_material: ShaderMaterial
static var _glow: Dictionary = {}


static func build(k: int, v: int, s: int, w: float, powered: bool, length: float) -> Dictionary:
	var kit := PropKit.new(w, s * 7919 + k * 31 + v)
	var rng := RandomNumberGenerator.new()
	rng.seed = s * 104729 + k * 613 + v
	var boxes: Array = []
	match k:
		K.CRATE_WOOD: boxes = _crate_wood(kit, v, rng)
		K.CRATE_METAL: boxes = _crate_metal(kit, v, rng)
		K.TOTE: boxes = _tote(kit, v, rng)
		K.PALLET: boxes = _pallet(kit, v, rng)
		K.RACKING: boxes = _racking(kit, v, rng)
		K.FORKLIFT: boxes = _forklift(kit, v, rng)
		K.REACH_STACKER: boxes = _reach_stacker(kit, rng)
		K.SCISSOR_LIFT: boxes = _scissor_lift(kit)
		K.PALLET_JACK: boxes = _pallet_jack(kit)
		K.FUEL_STATION: boxes = _fuel_station(kit)
		K.WORKBENCH: boxes = _workbench(kit, rng)
		K.DOCK_DOOR: boxes = _dock_door(kit, v)
		K.DOCK_LEVELLER: boxes = _dock_leveller(kit)
		K.SPREADER: boxes = _spreader(kit, length)
		K.CABINET: boxes = _cabinet(kit, v, rng)
		K.JUNCTION_BOX: boxes = _junction_box(kit, length)
		K.HOSE_REEL: boxes = _hose_reel(kit)
		K.EXTINGUISHER: boxes = _extinguisher(kit)
		K.TERMINAL: boxes = _terminal(kit, v, powered, rng)
		K.LAMP_HIGHBAY: boxes = _lamp_highbay(kit, v, powered, length)
		K.LAMP_BULKHEAD: boxes = _lamp_bulkhead(kit, powered)
		K.FLOODLIGHT: boxes = _floodlight(kit, powered)
		K.MOSS: boxes = _moss(kit, v, rng)
		K.TUFT: boxes = _tuft(kit, v, rng)
		K.SHRUB: boxes = _shrub(kit, v, rng)
		K.TREE: boxes = _tree(kit, v, rng)
		K.VINE: boxes = _vine(kit, length, rng)
		K.LIGHT_SHAFT: boxes = _light_shaft(kit, length)
		K.HANGAR_DOOR: boxes = _hangar_door(kit, length)
		K.JERSEY_BARRIER: boxes = _jersey_barrier(kit, v, length, rng)
		K.PLATE_SHIELD: boxes = _plate_shield(kit, v, rng)
	return {"mesh": kit.commit(), "boxes": boxes}


static func glow(c: Color) -> StandardMaterial3D:
	if not _glow.has(c):
		_glow[c] = PropKit.glow_material(c)
	return _glow[c]


static func crt_material() -> ShaderMaterial:
	if _crt_material == null:
		_crt_material = ShaderMaterial.new()
		_crt_material.shader = preload("res://shaders/hub2_crt.gdshader")
	return _crt_material


# -- cover (docs/specs/hub2-room-c-cover.md) --------------------------------------------------

const CONCRETE := Color(0.56, 0.55, 0.51)
const HAZARD_YELLOW := Color(0.72, 0.58, 0.14)


## F-profile concrete barrier lying along X: stepped slab 0.6 -> 0.22 wide, 1.1 m high, lifting loops on top.
static func _jersey_barrier(kit: PropKit, v: int, length: float, rng: RandomNumberGenerator) -> Array:
	var h := maxf(length, 1.0) * 0.5
	var tone := CONCRETE.darkened(rng.randf() * 0.18)
	var steps := [[0.30, 0.0, 0.25], [0.21, 0.25, 0.55], [0.14, 0.55, 0.80], [0.11, 0.80, 1.10]]
	for st: Array in steps:
		var w: float = st[0]
		kit.box(Vector3(-h, st[1], -w), Vector3(h, st[2], w), tone.darkened(0.05 * st[1]))
	# Chipped corner and a dark seam where it butts the next one.
	kit.box(Vector3(h - 0.01, 0.0, -0.3), Vector3(h, 1.1, 0.3), tone.darkened(0.35), Transform3D.IDENTITY, false)
	for ex in [-h + 0.35, h - 0.35]:
		kit.box(Vector3(ex - 0.12, 1.1, -0.04), Vector3(ex + 0.12, 1.16, 0.04), STEEL_DARK)
	if v == 1:
		# Faded hazard stripes on the top block, both faces: yellow with black between.
		var x := -h + 0.2
		var i := 0
		while x < h - 0.35:
			var col := HAZARD_YELLOW.darkened(0.25 + rng.randf() * 0.2) if i % 2 == 0 else BLACK
			kit.box(Vector3(x, 0.82, 0.11), Vector3(x + 0.24, 1.08, 0.116), col, Transform3D.IDENTITY, false)
			kit.box(Vector3(x, 0.82, -0.116), Vector3(x + 0.24, 1.08, -0.11), col, Transform3D.IDENTITY, false)
			x += 0.24
			i += 1
	return [[Vector3(0, 0.55, 0), Vector3(h * 2.0, 1.1, 0.6)]]


## Welded steel plate shield: plate + frame + two raked legs, leaning back ~6 degrees. Faces +Z.
static func _plate_shield(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	var col := (STEEL if v == 0 else OLIVE).darkened(0.1 + rng.randf() * 0.15)
	var lean := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-6.0)), Vector3(0, 0, 0))
	kit.box(Vector3(-1.0, 0.1, -0.04), Vector3(1.0, 1.1, 0.04), col, lean)
	kit.box(Vector3(-1.04, 0.06, -0.07), Vector3(1.04, 0.14, 0.07), STEEL_DARK, lean)
	kit.box(Vector3(-1.04, 1.06, -0.07), Vector3(1.04, 1.12, 0.07), STEEL_DARK, lean)
	for ex in [-1.0, 1.0]:
		kit.box(Vector3(ex - 0.05, 0.06, -0.07), Vector3(ex + 0.05, 1.12, 0.07), STEEL_DARK, lean)
		# Raked leg to the back.
		kit.tube(Vector3(ex * 0.8, 0.5, -0.1), Vector3(ex * 0.8, 0.04, -0.45), 0.04, STEEL_DARK, 4)
		kit.box(Vector3(ex * 0.8 - 0.1, 0.0, -0.55), Vector3(ex * 0.8 + 0.1, 0.04, -0.3), STEEL_DARK)
	# Weld seams, a patch plate and a bullet-scarred slit.
	for wx in [-0.5, 0.0, 0.5]:
		kit.box(Vector3(wx - 0.02, 0.2, 0.04), Vector3(wx + 0.02, 1.0, 0.055), col.darkened(0.3), lean, false)
	kit.box(Vector3(0.25, 0.45, 0.04), Vector3(0.75, 0.8, 0.065), col.lightened(0.08), lean)
	kit.box(Vector3(-0.7, 0.78, 0.04), Vector3(-0.2, 0.84, 0.06), BLACK, lean, false)
	return [[Vector3(0, 0.56, -0.2), Vector3(2.1, 1.12, 0.6)]]


# -- storage ----------------------------------------------------------------------------------

static func _crate_wood(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	var sizes := [Vector3(0.8, 0.8, 0.8), Vector3(1.2, 0.9, 1.0), Vector3(2.0, 0.8, 0.9), Vector3(1.2, 0.9, 1.0)]
	var sz: Vector3 = sizes[v % 4]
	var h := sz * 0.5
	var tone := WOOD.darkened(rng.randf() * 0.2)
	var open := v == 3
	# Core (slightly inset) then slats proud of it, and corner battens.
	kit.box(Vector3(-h.x + 0.03, 0.0, -h.z + 0.03), Vector3(h.x - 0.03, sz.y - (0.12 if open else 0.03), h.z - 0.03), WOOD_DARK, Transform3D.IDENTITY, true, null, 4 if open else 0)
	var slats := int(round(sz.y / 0.2))
	for i in slats:
		var y0 := i * sz.y / slats + 0.01
		var y1 := (i + 1) * sz.y / slats - 0.02
		var c := tone.lightened(rng.randf() * 0.08)
		kit.box(Vector3(-h.x, y0, -h.z), Vector3(h.x, y1, -h.z + 0.03), c)
		kit.box(Vector3(-h.x, y0, h.z - 0.03), Vector3(h.x, y1, h.z), c)
		kit.box(Vector3(-h.x, y0, -h.z), Vector3(-h.x + 0.03, y1, h.z), c)
		kit.box(Vector3(h.x - 0.03, y0, -h.z), Vector3(h.x, y1, h.z), c)
	for ex in [-1.0, 1.0]:
		for ez in [-1.0, 1.0]:
			kit.box(Vector3(ex * h.x - 0.06, 0.0, ez * h.z - 0.06), Vector3(ex * h.x + 0.06, sz.y, ez * h.z + 0.06), WOOD_DARK.lightened(0.05))
	if open:
		# Lid knocked aside, straw inside, a broken slat.
		kit.obox(Vector3(h.x * 0.35, sz.y + 0.04, h.z * 0.6), Vector3(sz.x * 0.95, 0.05, sz.z * 0.9), tone, Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, 0.12))
		kit.box(Vector3(-h.x + 0.05, sz.y - 0.2, -h.z + 0.05), Vector3(h.x - 0.05, sz.y - 0.12, h.z - 0.05), Color(0.70, 0.60, 0.34))
		kit.obox(Vector3(-h.x - 0.25, 0.03, 0.2), Vector3(0.9, 0.04, 0.12), tone, Basis(Vector3.UP, 0.7))
	else:
		kit.box(Vector3(-h.x + 0.04, sz.y - 0.03, -h.z + 0.04), Vector3(h.x - 0.04, sz.y, h.z - 0.04), tone.darkened(0.08))
	# Stencil band.
	kit.box(Vector3(-h.x * 0.5, sz.y * 0.45, h.z + 0.001), Vector3(h.x * 0.5, sz.y * 0.6, h.z + 0.005), Color(0.15, 0.13, 0.10), Transform3D.IDENTITY, false)
	return [[Vector3(0, sz.y * 0.5, 0), sz]]


static func _crate_metal(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	match v % 3:
		0:
			var sz := Vector3(1.0, 0.6, 0.6)
			kit.box(Vector3(-0.5, 0.0, -0.3), Vector3(0.5, 0.52, 0.3), OLIVE.darkened(rng.randf() * 0.15))
			kit.box(Vector3(-0.52, 0.5, -0.32), Vector3(0.52, 0.6, 0.32), OLIVE.darkened(0.12))
			for ex in [-0.3, 0.3]:
				kit.box(Vector3(ex - 0.06, 0.2, 0.3), Vector3(ex + 0.06, 0.4, 0.34), STEEL_DARK)
			kit.box(Vector3(-0.15, 0.25, 0.3), Vector3(0.15, 0.35, 0.305), SAFETY_YELLOW, Transform3D.IDENTITY, false)
			return [[Vector3(0, 0.3, 0), sz]]
		1:
			var col := STEEL.darkened(rng.randf() * 0.15)
			kit.box(Vector3(-0.45, 0.0, -0.3), Vector3(0.45, 1.9, 0.3), col)
			kit.box(Vector3(-0.005, 0.05, 0.3), Vector3(0.005, 1.85, 0.31), STEEL_DARK, Transform3D.IDENTITY, false)
			for ex in [-0.22, 0.22]:
				for vy in [1.6, 1.65, 1.7]:
					kit.box(Vector3(ex - 0.12, vy, 0.3), Vector3(ex + 0.12, vy + 0.02, 0.31), STEEL_DARK, Transform3D.IDENTITY, false)
				kit.box(Vector3(ex * 0.3 - 0.02, 0.9, 0.3), Vector3(ex * 0.3 + 0.02, 1.05, 0.33), BLACK)
			return [[Vector3(0, 0.95, 0), Vector3(0.9, 1.9, 0.6)]]
		_:
			var col2 := STEEL.darkened(0.1 + rng.randf() * 0.15)
			kit.box(Vector3(-0.8, 0.0, -0.5), Vector3(0.8, 0.9, 0.5), col2)
			kit.box(Vector3(-0.82, 0.88, -0.52), Vector3(0.82, 1.0, 0.52), col2.darkened(0.1))
			for ex in [-0.82, 0.78]:
				kit.box(Vector3(ex, 0.55, -0.15), Vector3(ex + 0.04, 0.62, 0.15), STEEL_DARK)
			for ez in [-0.5, 0.48]:
				kit.box(Vector3(-0.8, 0.0, ez), Vector3(0.8, 0.08, ez + 0.02), SAFETY_YELLOW)
			return [[Vector3(0, 0.5, 0), Vector3(1.6, 1.0, 1.0)]]


static func _tote_one(kit: PropKit, y: float, col: Color) -> void:
	kit.box(Vector3(-0.28, y, -0.19), Vector3(0.28, y + 0.36, 0.19), col)
	kit.box(Vector3(-0.30, y + 0.33, -0.21), Vector3(0.30, y + 0.38, 0.21), col.darkened(0.12))
	for ex in [-0.30, 0.285]:
		kit.box(Vector3(ex, y + 0.24, -0.08), Vector3(ex + 0.015, y + 0.3, 0.08), BLACK, Transform3D.IDENTITY, false)


static func _tote(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	var cols := [Color(0.18, 0.32, 0.60), Color(0.45, 0.46, 0.48), Color(0.20, 0.42, 0.24)]
	if v % 4 == 3:
		for i in 4:
			_tote_one(kit, i * 0.38, cols[rng.randi() % 3])
		return [[Vector3(0, 0.76, 0), Vector3(0.6, 1.52, 0.42)]]
	_tote_one(kit, 0.0, cols[v % 3])
	return [[Vector3(0, 0.19, 0), Vector3(0.6, 0.38, 0.42)]]


static func pallet_base(kit: PropKit, y := 0.0) -> void:
	for ez in [-0.45, 0.0, 0.45]:
		for ex in [-0.52, 0.0, 0.52]:
			kit.box(Vector3(ex - 0.07, y, ez - 0.07), Vector3(ex + 0.07, y + 0.09, ez + 0.07), WOOD_DARK)
	for ez in [-0.45, 0.0, 0.45]:
		kit.box(Vector3(-0.6, y + 0.09, ez - 0.05), Vector3(0.6, y + 0.12, ez + 0.05), WOOD)
	for i in 5:
		var ex := -0.52 + i * 0.26
		kit.box(Vector3(ex - 0.05, y + 0.12, -0.5), Vector3(ex + 0.05, y + 0.145, 0.5), WOOD.lightened(0.05))


static func _pallet(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	pallet_base(kit)
	match v % 3:
		1:
			var hgt := rng.randf_range(1.0, 1.4)
			kit.box(Vector3(-0.58, 0.145, -0.48), Vector3(0.58, 0.145 + hgt, 0.48), WRAP.darkened(rng.randf() * 0.15))
			for i in 3:
				var y := 0.3 + i * hgt / 3.0
				kit.box(Vector3(-0.59, y, -0.49), Vector3(0.59, y + 0.05, 0.49), WRAP.lightened(0.1), Transform3D.IDENTITY, false)
			return [[Vector3(0, (0.145 + hgt) * 0.5, 0), Vector3(1.2, 0.145 + hgt, 1.0)]]
		2:
			var layers := rng.randi_range(2, 4)
			for l in layers:
				for ix in 2:
					for iz in 2:
						var lo := Vector3(-0.58 + ix * 0.58, 0.145 + l * 0.4, -0.48 + iz * 0.48)
						kit.box(lo + Vector3(0.01, 0, 0.01), lo + Vector3(0.57, 0.39, 0.47), CARTON.darkened(rng.randf() * 0.2))
			var top := 0.145 + layers * 0.4
			return [[Vector3(0, top * 0.5, 0), Vector3(1.2, top, 1.0)]]
		_:
			return [[Vector3(0, 0.07, 0), Vector3(1.2, 0.145, 1.0)]]


## Racking bay: two upright frames and three beam levels. Shelf tops at RACK_LEVELS.
const RACK_LEVELS := [0.15, 1.9, 3.6]
const RACK_W := 2.7
const RACK_D := 1.1
const RACK_H := 5.4

static func _racking(kit: PropKit, v: int, _rng: RandomNumberGenerator) -> Array:
	var bent := v % 2 == 1
	var lean := Basis(Vector3.BACK, 0.09 if bent else 0.0)
	var xf := Transform3D(lean, Vector3.ZERO)
	for ex in [-RACK_W * 0.5, RACK_W * 0.5]:
		for ez in [-RACK_D * 0.5, RACK_D * 0.5]:
			kit.box(Vector3(ex - 0.05, 0.0, ez - 0.05), Vector3(ex + 0.05, RACK_H, ez + 0.05), RACK_BLUE, xf)
		var y := 0.4
		while y < RACK_H - 0.3:
			kit.box(Vector3(ex - 0.03, y, -RACK_D * 0.5), Vector3(ex + 0.03, y + 0.05, RACK_D * 0.5), RACK_BLUE.darkened(0.15), xf)
			y += 1.2
	for li in RACK_LEVELS.size():
		var ly: float = RACK_LEVELS[li]
		if li == 0:
			continue
		var droop := 0.25 if bent and li == 1 else 0.0
		for ez in [-RACK_D * 0.5, RACK_D * 0.5]:
			kit.box(Vector3(-RACK_W * 0.5, ly - 0.12 - droop, ez - 0.04), Vector3(RACK_W * 0.5, ly, ez + 0.04), RACK_ORANGE, xf)
		for i in 4:
			var ex := -RACK_W * 0.5 + 0.3 + i * (RACK_W - 0.6) / 3.0
			kit.box(Vector3(ex - 0.03, ly - 0.05 - droop, -RACK_D * 0.5), Vector3(ex + 0.03, ly, RACK_D * 0.5), STEEL_DARK, xf)
	return [[Vector3(-RACK_W * 0.5, RACK_H * 0.5, 0), Vector3(0.12, RACK_H, RACK_D)],
		[Vector3(RACK_W * 0.5, RACK_H * 0.5, 0), Vector3(0.12, RACK_H, RACK_D)],
		[Vector3(0, RACK_LEVELS[1] - 0.06, 0), Vector3(RACK_W, 0.12, RACK_D)],
		[Vector3(0, RACK_LEVELS[2] - 0.06, 0), Vector3(RACK_W, 0.12, RACK_D)]]


# -- machines ---------------------------------------------------------------------------------

static func _wheel(kit: PropKit, c: Vector3, r: float, w: float, xf := Transform3D.IDENTITY) -> void:
	kit.tube(c - Vector3(0, 0, w * 0.5), c + Vector3(0, 0, w * 0.5), r, BLACK, 8, xf)
	kit.tube(c - Vector3(0, 0, w * 0.5 + 0.01), c + Vector3(0, 0, w * 0.5 + 0.01), r * 0.5, STEEL_DARK, 6, xf)


static func _forklift(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	var body := SAFETY_YELLOW if v != 1 else Color(0.85, 0.42, 0.10)
	var crushed := v == 2
	var squash := Transform3D(Basis.from_scale(Vector3(1.0, 0.55, 1.0)) * Basis(Vector3.RIGHT, 0.08), Vector3(0, 0, 0)) if crushed else Transform3D.IDENTITY
	# Body along X, forks at +X.
	kit.box(Vector3(-1.3, 0.25, -0.55), Vector3(0.6, 1.1, 0.55), body, squash)
	kit.box(Vector3(-1.45, 0.25, -0.58), Vector3(-0.9, 1.25, 0.58), STEEL_DARK, squash)   # counterweight
	kit.box(Vector3(-0.7, 1.1, -0.35), Vector3(-0.2, 1.6, 0.35), BLACK, squash)          # seat
	# Overhead guard posts and roof.
	for px in [-1.0, 0.45]:
		for pz in [-0.5, 0.5]:
			kit.box(Vector3(px - 0.04, 1.1, pz - 0.04), Vector3(px + 0.04, 2.15, pz + 0.04), STEEL_DARK, squash)
	kit.box(Vector3(-1.05, 2.12, -0.55), Vector3(0.5, 2.2, 0.55), STEEL_DARK, squash)
	# Mast, carriage and forks.
	for pz in [-0.35, 0.35]:
		kit.box(Vector3(0.65, 0.1, pz - 0.06), Vector3(0.78, 2.4, pz + 0.06), STEEL_DARK, squash)
	var fork_y := rng.randf_range(0.05, 0.6)
	kit.box(Vector3(0.78, fork_y, -0.5), Vector3(0.85, fork_y + 0.6, 0.5), STEEL_DARK, squash)
	for pz in [-0.3, 0.3]:
		kit.box(Vector3(0.85, fork_y, pz - 0.06), Vector3(2.0, fork_y + 0.05, pz + 0.06), STEEL, squash)
	for wx in [-1.0, 0.35]:
		for wz in [-0.5, 0.5]:
			_wheel(kit, Vector3(wx, 0.28, wz), 0.28, 0.2, squash)
	var top := 1.3 if crushed else 2.2
	return [[Vector3(-0.4, top * 0.5, 0), Vector3(2.2, top, 1.2)]]


static func _reach_stacker(kit: PropKit, rng: RandomNumberGenerator) -> Array:
	var body := SAFETY_YELLOW.darkened(0.08)
	kit.box(Vector3(-5.0, 0.6, -1.5), Vector3(3.0, 1.6, 1.5), body)
	kit.box(Vector3(-5.6, 0.6, -1.4), Vector3(-4.8, 2.6, 1.4), STEEL_DARK)              # counterweight
	kit.box(Vector3(-1.5, 1.6, 0.3), Vector3(0.3, 3.6, 1.4), body.darkened(0.1))         # cab
	kit.box(Vector3(-1.4, 2.4, 0.29), Vector3(0.2, 3.4, 0.3), Color(0.12, 0.16, 0.2), Transform3D.IDENTITY, false)
	for wx in [-3.8, 1.8]:
		for wz in [-1.5, 1.5]:
			_wheel(kit, Vector3(wx, 0.8, wz), 0.8, 0.6)
	# Boom: pivot behind the cab, raised, telescoped, ending in a small spreader head.
	var angle := rng.randf_range(0.25, 0.45)
	var b := Basis(Vector3.BACK, angle)
	var pivot := Vector3(-3.6, 2.0, -0.4)
	kit.obox(pivot + b * Vector3(4.5, 0, 0), Vector3(9.0, 0.9, 0.7), body, b)
	kit.obox(pivot + b * Vector3(10.0, 0, 0), Vector3(3.0, 0.7, 0.5), body.lightened(0.05), b)
	var tip := pivot + b * Vector3(11.5, 0, 0)
	kit.box(tip + Vector3(-0.4, -1.0, -1.2), tip + Vector3(0.4, -0.2, 1.2), STEEL_DARK)
	kit.tube(Vector3(-1.0, 1.6, -0.4), pivot + b * Vector3(3.5, -0.4, 0), 0.18, STEEL, 6)
	return [[Vector3(-1.3, 1.3, 0), Vector3(9.2, 2.6, 3.2)]]


static func _scissor_lift(kit: PropKit) -> Array:
	kit.box(Vector3(-1.2, 0.15, -0.6), Vector3(1.2, 0.5, 0.6), Color(0.86, 0.32, 0.10))
	for wx in [-0.9, 0.9]:
		for wz in [-0.55, 0.55]:
			_wheel(kit, Vector3(wx, 0.16, wz), 0.16, 0.12)
	# Two X stages.
	for stage in 2:
		var y0 := 0.5 + stage * 1.0
		for pz in [-0.5, 0.5]:
			kit.obox(Vector3(0, y0 + 0.5, pz), Vector3(2.4, 0.08, 0.06), STEEL_DARK, Basis(Vector3.BACK, 0.4))
			kit.obox(Vector3(0, y0 + 0.5, pz), Vector3(2.4, 0.08, 0.06), STEEL_DARK, Basis(Vector3.BACK, -0.4))
	kit.box(Vector3(-1.25, 2.5, -0.62), Vector3(1.25, 2.6, 0.62), STEEL_DARK)
	for px in [-1.2, 1.2]:
		for pz in [-0.58, 0.58]:
			kit.box(Vector3(px - 0.025, 2.6, pz - 0.025), Vector3(px + 0.025, 3.7, pz + 0.025), SAFETY_YELLOW)
	for pz in [-0.58, 0.58]:
		kit.box(Vector3(-1.2, 3.65, pz - 0.025), Vector3(1.2, 3.7, pz + 0.025), SAFETY_YELLOW)
	for px in [-1.2, 1.2]:
		kit.box(Vector3(px - 0.025, 3.65, -0.58), Vector3(px + 0.025, 3.7, 0.58), SAFETY_YELLOW)
	return [[Vector3(0, 0.33, 0), Vector3(2.4, 0.5, 1.2)], [Vector3(0, 2.55, 0), Vector3(2.5, 0.1, 1.24)]]


static func _pallet_jack(kit: PropKit) -> Array:
	for pz in [-0.28, 0.28]:
		kit.box(Vector3(-0.2, 0.05, pz - 0.08), Vector3(1.15, 0.1, pz + 0.08), STEEL_DARK)
	kit.box(Vector3(-0.45, 0.05, -0.38), Vector3(-0.2, 0.35, 0.38), RED)
	kit.obox(Vector3(-0.65, 0.75, 0), Vector3(0.05, 1.0, 0.05), STEEL_DARK, Basis(Vector3.BACK, 0.35))
	kit.box(Vector3(-0.9, 1.15, -0.2), Vector3(-0.84, 1.21, 0.2), BLACK)
	return [[Vector3(0.3, 0.12, 0), Vector3(1.5, 0.24, 0.76)]]


static func _fuel_station(kit: PropKit) -> Array:
	kit.box(Vector3(-1.6, 0.0, -0.6), Vector3(1.6, 0.15, 0.6), Color(0.40, 0.40, 0.38))       # plinth
	kit.box(Vector3(-1.3, 0.15, -0.35), Vector3(-0.3, 1.9, 0.35), Color(0.60, 0.12, 0.08))    # pump
	kit.box(Vector3(-1.2, 1.2, 0.35), Vector3(-0.4, 1.6, 0.37), BLACK, Transform3D.IDENTITY, false)
	kit.tube(Vector3(-0.35, 1.3, 0.2), Vector3(-0.2, 0.3, 0.6), 0.03, BLACK, 4)
	kit.box(Vector3(0.2, 0.15, -0.3), Vector3(1.3, 2.1, 0.3), STEEL)                            # charger
	kit.box(Vector3(0.35, 1.5, 0.3), Vector3(1.15, 1.9, 0.31), BLACK, Transform3D.IDENTITY, false)
	for i in 2:
		kit.tube(Vector3(0.5 + i * 0.5, 1.0, 0.3), Vector3(0.6 + i * 0.4, 0.05, 0.9), 0.025, BLACK, 4)
	for px in [-1.5, 1.5]:
		kit.tube(Vector3(px, 0.15, 0.5), Vector3(px, 1.0, 0.5), 0.06, SAFETY_YELLOW, 6)
	return [[Vector3(0, 1.0, 0), Vector3(3.2, 2.0, 1.2)]]


static func _workbench(kit: PropKit, rng: RandomNumberGenerator) -> Array:
	kit.box(Vector3(-1.0, 0.85, -0.4), Vector3(1.0, 0.92, 0.4), WOOD_DARK)
	for px in [-0.95, 0.95]:
		for pz in [-0.35, 0.35]:
			kit.box(Vector3(px - 0.03, 0.0, pz - 0.03), Vector3(px + 0.03, 0.85, pz + 0.03), STEEL_DARK)
	kit.box(Vector3(-0.95, 0.15, -0.35), Vector3(0.95, 0.18, 0.35), STEEL_DARK)
	kit.box(Vector3(0.6, 0.92, 0.2), Vector3(0.8, 1.05, 0.35), Color(0.20, 0.30, 0.50))         # vice
	kit.box(Vector3(-1.0, 0.92, -0.42), Vector3(1.0, 2.0, -0.38), Color(0.38, 0.36, 0.30))     # tool board
	for i in 7:
		var x := -0.8 + i * 0.26
		kit.box(Vector3(x - 0.02, 1.2 + rng.randf() * 0.4, -0.38), Vector3(x + 0.02, 1.6 + rng.randf() * 0.3, -0.35), STEEL_DARK)
	kit.box(Vector3(-0.7, 0.92, -0.1), Vector3(-0.2, 1.1, 0.15), RED.darkened(0.2))            # toolbox
	return [[Vector3(0, 0.5, 0), Vector3(2.0, 1.0, 0.8)]]


static func _dock_door(kit: PropKit, v: int) -> Array:
	var open_h := 1.1 if v == 1 else 0.0
	# Frame on the wall, slatted shutter, drum housing on top. Wall plane z = 0.
	kit.box(Vector3(-2.3, 0.0, 0.0), Vector3(-2.0, 4.8, 0.25), SAFETY_YELLOW)
	kit.box(Vector3(2.0, 0.0, 0.0), Vector3(2.3, 4.8, 0.25), SAFETY_YELLOW)
	kit.box(Vector3(-2.3, 4.5, 0.0), Vector3(2.3, 5.2, 0.6), STEEL_DARK)
	if open_h > 0.0:
		kit.box(Vector3(-2.0, 0.0, 0.0), Vector3(2.0, open_h, 0.02), BLACK, Transform3D.IDENTITY, false)
	var y := open_h
	while y < 4.5:
		kit.box(Vector3(-2.0, y, 0.0), Vector3(2.0, y + 0.18, 0.08), STEEL.darkened(0.05))
		y += 0.2
	for i in 8:
		var x := -1.9 + i * 0.55
		kit.box(Vector3(x, 0.0, 0.0), Vector3(x + 0.25, 0.15, 0.27), SAFETY_YELLOW if i % 2 == 0 else BLACK, Transform3D.IDENTITY, false)
	return [[Vector3(0, 2.6, 0.12), Vector3(4.6, 5.2, 0.25)]]


static func _dock_leveller(kit: PropKit) -> Array:
	kit.box(Vector3(-1.1, 0.0, 0.0), Vector3(1.1, 0.06, 2.6), STEEL_DARK)
	for i in 12:
		kit.box(Vector3(-1.0, 0.06, 0.2 + i * 0.2), Vector3(1.0, 0.075, 0.24 + i * 0.2), STEEL)
	for px in [-1.6, 1.4]:
		kit.box(Vector3(px, 0.6, 0.0), Vector3(px + 0.2, 1.0, 0.25), BLACK)
	return []


static func _spreader(kit: PropKit, length: float) -> Array:
	kit.box(Vector3(-3.0, 0.0, -1.2), Vector3(3.0, 0.4, -1.0), SAFETY_YELLOW)
	kit.box(Vector3(-3.0, 0.0, 1.0), Vector3(3.0, 0.4, 1.2), SAFETY_YELLOW)
	kit.box(Vector3(-0.8, 0.0, -1.2), Vector3(0.8, 0.8, 1.2), SAFETY_YELLOW.darkened(0.1))
	for px in [-3.0, 3.0]:
		kit.box(Vector3(px - 0.2, -0.15, -1.25), Vector3(px + 0.2, 0.4, 1.25), STEEL_DARK)
	for px in [-0.6, 0.6]:
		for pz in [-0.8, 0.8]:
			kit.tube(Vector3(px, 0.8, pz), Vector3(px * 0.3, 0.8 + length, pz * 0.3), 0.03, BLACK, 4)
	return [[Vector3(0, 0.3, 0), Vector3(6.4, 0.8, 2.5)]]


# -- wall kit (wall plane z = 0, sticks out +Z) -------------------------------------------------

static func _cabinet(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	var w := 1.2 if v % 2 == 0 else 0.7
	var col := Color(0.45, 0.50, 0.46).darkened(rng.randf() * 0.15)
	kit.box(Vector3(-w * 0.5, 0.1, 0.0), Vector3(w * 0.5, 2.1, 0.45), col)
	kit.box(Vector3(-0.005, 0.15, 0.45), Vector3(0.005, 2.05, 0.46), STEEL_DARK, Transform3D.IDENTITY, false)
	kit.box(Vector3(-w * 0.3, 1.6, 0.45), Vector3(-w * 0.1, 1.8, 0.46), SAFETY_YELLOW, Transform3D.IDENTITY, false)
	for ex in [-0.08, 0.06]:
		kit.box(Vector3(ex, 1.0, 0.45), Vector3(ex + 0.02, 1.2, 0.49), BLACK)
	for i in 3:
		kit.box(Vector3(-w * 0.4, 0.4 + i * 0.06, 0.45), Vector3(w * 0.4, 0.42 + i * 0.06, 0.46), STEEL_DARK, Transform3D.IDENTITY, false)
	kit.tube(Vector3(0, 2.1, 0.2), Vector3(0, 3.5, 0.2), 0.06, STEEL_DARK, 6)
	return [[Vector3(0, 1.1, 0.22), Vector3(w, 2.0, 0.45)]]


static func _junction_box(kit: PropKit, length: float) -> Array:
	kit.box(Vector3(-0.25, 1.2, 0.0), Vector3(0.25, 1.8, 0.22), Color(0.50, 0.52, 0.50))
	kit.box(Vector3(-0.1, 1.45, 0.22), Vector3(0.1, 1.6, 0.23), SAFETY_YELLOW, Transform3D.IDENTITY, false)
	kit.tube(Vector3(0, 1.8, 0.1), Vector3(0, 1.8 + length, 0.1), 0.04, STEEL_DARK, 6)
	return []


static func _hose_reel(kit: PropKit) -> Array:
	kit.box(Vector3(-0.45, 0.9, 0.0), Vector3(0.45, 1.8, 0.3), RED)
	kit.tube(Vector3(0, 1.35, 0.3), Vector3(0, 1.35, 0.4), 0.32, RED.darkened(0.25), 8)
	kit.tube(Vector3(0, 1.35, 0.4), Vector3(0, 1.35, 0.42), 0.15, STEEL_DARK, 6)
	kit.box(Vector3(-0.3, 1.95, 0.0), Vector3(0.3, 2.25, 0.02), RED.lightened(0.15), Transform3D.IDENTITY, false)
	return []


static func _extinguisher(kit: PropKit) -> Array:
	kit.box(Vector3(-0.12, 0.7, 0.0), Vector3(0.12, 0.76, 0.12), STEEL_DARK)
	kit.tube(Vector3(0, 0.5, 0.14), Vector3(0, 1.05, 0.14), 0.09, RED, 6)
	kit.box(Vector3(-0.03, 1.05, 0.11), Vector3(0.03, 1.15, 0.17), BLACK)
	kit.box(Vector3(-0.15, 1.3, 0.0), Vector3(0.15, 1.6, 0.01), RED.lightened(0.1), Transform3D.IDENTITY, false)
	return []


static func _terminal(kit: PropKit, v: int, powered: bool, rng: RandomNumberGenerator) -> Array:
	var n := (v % 4) + 1
	var pitch := 0.95
	var w := n * pitch + 0.3
	var bezel := Color(0.36, 0.38, 0.36)
	# Thick bezel slab on the wall with a recessed screen window per screen.
	kit.box(Vector3(-w * 0.5, 0.75, 0.0), Vector3(w * 0.5, 0.95, 0.42), bezel)                # keyboard shelf base
	kit.box(Vector3(-w * 0.5, 0.95, 0.0), Vector3(w * 0.5, 2.25, 0.08), bezel.darkened(0.2))   # back
	kit.box(Vector3(-w * 0.5, 2.25, 0.0), Vector3(w * 0.5, 2.45, 0.38), bezel)                 # top lip
	kit.box(Vector3(-w * 0.5, 0.95, 0.0), Vector3(-w * 0.5 + 0.15, 2.25, 0.38), bezel)
	kit.box(Vector3(w * 0.5 - 0.15, 0.95, 0.0), Vector3(w * 0.5, 2.25, 0.38), bezel)
	var crt := crt_material()
	var cracked := rng.randi() % 5 == 0
	for i in n:
		var cx := -w * 0.5 + 0.15 + pitch * (i + 0.5)
		# Bezel frame round each screen, the screen set back in it.
		kit.box(Vector3(cx - 0.45, 1.25, 0.08), Vector3(cx + 0.45, 1.33, 0.36), bezel)
		kit.box(Vector3(cx - 0.45, 2.05, 0.08), Vector3(cx + 0.45, 2.25, 0.36), bezel)
		if i < n - 1:
			kit.box(Vector3(cx + 0.4, 1.33, 0.08), Vector3(cx + 0.55, 2.05, 0.36), bezel)
		var a := Vector3(cx - 0.4, 1.33, 0.2)
		var b := Vector3(cx + 0.4, 1.33, 0.2)
		var c := Vector3(cx + 0.4, 2.05, 0.2)
		var d := Vector3(cx - 0.4, 2.05, 0.2)
		var lit := powered and not (cracked and i == 0)
		if lit:
			var sst := kit.extra_surface(crt)
			kit.screen_quad(a, b, c, d, sst)
		else:
			kit.quad(a, b, c, d, Color(0.05, 0.07, 0.07), Transform3D.IDENTITY, false)
			if cracked and i == 0:
				kit.tri(Vector3(cx - 0.1, 1.7, 0.201), Vector3(cx + 0.3, 1.9, 0.201), Vector3(cx + 0.25, 1.95, 0.201), Color(0.4, 0.45, 0.45))
		# Keyboard.
		kit.box(Vector3(cx - 0.35, 0.95, 0.12), Vector3(cx + 0.35, 1.0, 0.36), Color(0.22, 0.22, 0.20))
		# Status lamps.
		for j in 3:
			var lc: Color = [Color(0.9, 0.2, 0.1), Color(0.95, 0.7, 0.1), Color(0.2, 0.9, 0.3)][j] if powered and rng.randf() < 0.6 else Color(0.12, 0.12, 0.12)
			var lo := Vector3(cx - 0.3 + j * 0.1, 1.15, 0.081)
			if powered and lc.r + lc.g > 0.5:
				kit.box(lo, lo + Vector3(0.05, 0.05, 0.02), Color.WHITE, Transform3D.IDENTITY, false, kit.extra_surface(glow(lc)))
			else:
				kit.box(lo, lo + Vector3(0.05, 0.05, 0.02), lc, Transform3D.IDENTITY, false)
	# Conduit up the wall.
	kit.tube(Vector3(w * 0.5 - 0.3, 2.45, 0.1), Vector3(w * 0.5 - 0.3, 4.5, 0.1), 0.07, STEEL_DARK, 6)
	return [[Vector3(0, 1.6, 0.2), Vector3(w, 1.7, 0.42)]]


# -- lamps ------------------------------------------------------------------------------------

const SODIUM := Color(1.0, 0.62, 0.25)

static func _lamp_highbay(kit: PropKit, v: int, powered: bool, length: float) -> Array:
	var crooked := v % 2 == 1
	var tilt := Basis(Vector3.BACK, 0.5) if crooked else Basis.IDENTITY
	var hang := Vector3(0, -length, 0)
	# Chain(s) from the ceiling, then the canopy and the dome.
	if crooked:
		kit.tube(Vector3(0.0, 0, 0), hang + Vector3(0.0, 0, 0), 0.015, STEEL_DARK, 4, Transform3D.IDENTITY, false)
	else:
		for px in [-0.15, 0.15]:
			kit.tube(Vector3(px, 0, 0), hang + Vector3(px * 0.3, 0, 0), 0.015, STEEL_DARK, 4, Transform3D.IDENTITY, false)
	var xf := Transform3D(tilt, hang)
	kit.box(Vector3(-0.15, -0.25, -0.15), Vector3(0.15, 0.0, 0.15), STEEL_DARK, xf)
	kit.tube(Vector3(0, -0.25, 0), Vector3(0, -0.6, 0), 0.18, STEEL, 8, xf, false, null, 0.55)
	if powered:
		kit.tube(Vector3(0, -0.55, 0), Vector3(0, -0.62, 0), 0.4, Color.WHITE, 8, xf, true, kit.extra_surface(glow(SODIUM)))
	else:
		kit.tube(Vector3(0, -0.55, 0), Vector3(0, -0.58, 0), 0.35, Color(0.12, 0.12, 0.12), 8, xf)
	return []


static func _lamp_bulkhead(kit: PropKit, powered: bool) -> Array:
	kit.box(Vector3(-0.25, -0.15, 0.0), Vector3(0.25, 0.15, 0.08), STEEL_DARK)
	if powered:
		kit.box(Vector3(-0.18, -0.1, 0.08), Vector3(0.18, 0.1, 0.22), Color.WHITE, Transform3D.IDENTITY, false, kit.extra_surface(glow(SODIUM)))
	else:
		kit.box(Vector3(-0.18, -0.1, 0.08), Vector3(0.18, 0.1, 0.16), Color(0.15, 0.14, 0.12))
	for i in 3:
		var x := -0.18 + i * 0.18
		kit.box(Vector3(x - 0.01, -0.13, 0.08), Vector3(x + 0.01, 0.13, 0.26), STEEL_DARK)
	kit.box(Vector3(-0.2, -0.13, 0.24), Vector3(0.2, -0.11, 0.26), STEEL_DARK)
	kit.box(Vector3(-0.2, 0.11, 0.24), Vector3(0.2, 0.13, 0.26), STEEL_DARK)
	return []


## Room A's light column: a faint additive open cylinder, wide at the mouth, a little narrower at the floor,
## in five stepped bands so it reads as a PS1 volume. No collision.
static func _light_shaft(kit: PropKit, length: float) -> Array:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	var sst := kit.extra_surface(mat)
	var sides := 14
	var bands := 5
	for b in bands:
		var t0 := float(b) / bands
		var t1 := float(b + 1) / bands
		var r0 := lerpf(36.0, 29.0, t0)
		var r1 := lerpf(36.0, 29.0, t1)
		var c0 := Color(0.035, 0.05, 0.08).lerp(Color(0.008, 0.012, 0.022), t0)
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var p00 := Vector3(cos(a0) * r0, -t0 * length, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, -t0 * length, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, -t1 * length, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, -t1 * length, sin(a1) * r1)
			kit.tri(p00, p01, p11, c0, Transform3D.IDENTITY, sst)
			kit.tri(p00, p11, p10, c0, Transform3D.IDENTITY, sst)
	return []


## Room A's sealed hangar door (docs/specs/hub2-storage.md "Room A storage hall"): fills the south bay,
## HANGAR_W wide and `height` tall, wall plane z = 0, sticking out along +Z. Two interlocking leaves met by the
## user's jogged seam (straight down from the top left of centre, a diagonal step at mid height, straight down
## to the floor right of centre), a header box, floor track, jambs, ribs, hazard chevrons, dead beacons, rust
## streaks. It never opens.
const HANGAR_W := 77.0
const HANGAR_HEADER := 8.0

## Seam x at height y on a door `leaf_top` tall (centred, metres), from the drawing.
static func hangar_seam_x(y: float, leaf_top: float) -> float:
	var t := clampf(1.0 - y / leaf_top, 0.0, 1.0)   # 0 at the top, 1 at the floor
	var f := 0.462
	if t > 0.589:
		f = lerpf(0.538, 0.547, (t - 0.589) / 0.411)
	elif t > 0.446:
		f = lerpf(0.462, 0.538, (t - 0.446) / 0.143)
	return (f - 0.5) * HANGAR_W


static func _hangar_door(kit: PropKit, height: float) -> Array:
	kit.cell = 3.0
	kit.grime_height = 9.0
	var hw := HANGAR_W * 0.5
	var h := maxf(height, 30.0)
	var leaf_top := h - HANGAR_HEADER
	var door_a := Color(0.33, 0.36, 0.39)
	var door_b := Color(0.29, 0.32, 0.35)
	var gap := 0.2
	var zl := 0.9    # left leaf face
	var zr := 1.2    # right leaf face (the lip stands proud of the left one)
	# Breakpoints: every 6 m, plus the two corners of the diagonal step.
	var ys: Array[float] = [0.0, leaf_top]
	var y := 6.0
	while y < leaf_top - 0.5:
		ys.append(y)
		y += 6.0
	ys.append(leaf_top * (1.0 - 0.446))
	ys.append(leaf_top * (1.0 - 0.589))
	ys.sort()
	# Seam gap, black, behind the leaves.
	for i in ys.size() - 1:
		var y0 := ys[i]
		var y1 := ys[i + 1]
		if y1 - y0 < 0.01:
			continue
		var s0 := hangar_seam_x(y0, leaf_top)
		var s1 := hangar_seam_x(y1, leaf_top)
		kit.quad(Vector3(s0 - 0.5, y0, 0.5), Vector3(s0 + 0.5, y0, 0.5), Vector3(s1 + 0.5, y1, 0.5), Vector3(s1 - 0.5, y1, 0.5), BLACK, Transform3D.IDENTITY, false)
		var c := door_a if i % 2 == 0 else door_b
		kit.quad(Vector3(-hw + 0.4, y0, zl), Vector3(s0 - gap, y0, zl), Vector3(s1 - gap, y1, zl), Vector3(-hw + 0.4, y1, zl), c)
		kit.quad(Vector3(s0 + gap, y0, zr), Vector3(hw - 0.4, y0, zr), Vector3(hw - 0.4, y1, zr), Vector3(s1 + gap, y1, zr), c.lightened(0.04))
		# The lip of the right leaf: the step between the two faces along the seam.
		kit.quad(Vector3(s0 + gap, y0, zl), Vector3(s0 + gap, y0, zr), Vector3(s1 + gap, y1, zr), Vector3(s1 + gap, y1, zl), STEEL_DARK, Transform3D.IDENTITY, false)
	# Horizontal panel joints across both leaves (stopping short of the seam).
	for i in range(1, ys.size() - 1):
		var yj := ys[i]
		if absf(yj - leaf_top * (1.0 - 0.446)) < 0.1 or absf(yj - leaf_top * (1.0 - 0.589)) < 0.1:
			continue
		var sj := hangar_seam_x(yj, leaf_top)
		kit.box(Vector3(-hw + 0.4, yj - 0.12, zl), Vector3(sj - 0.6, yj + 0.12, zl + 0.1), STEEL_DARK, Transform3D.IDENTITY, false)
		kit.box(Vector3(sj + 0.6, yj - 0.12, zr), Vector3(hw - 0.4, yj + 0.12, zr + 0.1), STEEL_DARK, Transform3D.IDENTITY, false)
	# Vertical ribs, every ~9.6 m, clear of the seam.
	var rx := -hw + 4.8
	while rx < hw - 2.0:
		var sx_mid := hangar_seam_x(leaf_top * 0.5, leaf_top)
		var near_seam := absf(rx - hangar_seam_x(leaf_top * 0.85, leaf_top)) < 3.2 or absf(rx - hangar_seam_x(leaf_top * 0.15, leaf_top)) < 3.2 or absf(rx - sx_mid) < 3.2
		if not near_seam:
			var zf := zl if rx < sx_mid else zr
			kit.box(Vector3(rx - 0.5, 0.4, zf), Vector3(rx + 0.5, leaf_top - 0.6, zf + 0.4), STEEL.darkened(0.12))
		rx += 9.6
	# Hazard chevrons down both sides of the seam.
	var yy := 0.0
	var n := 0
	while yy < leaf_top - 1.2:
		var s0 := hangar_seam_x(yy, leaf_top)
		var s1 := hangar_seam_x(yy + 1.2, leaf_top)
		var col := SAFETY_YELLOW if n % 2 == 0 else BLACK
		kit.quad(Vector3(s0 - 3.6, yy, zl + 0.03), Vector3(s0 - 0.5, yy, zl + 0.03), Vector3(s1 - 0.5, yy + 1.2, zl + 0.03), Vector3(s1 - 3.6, yy + 1.2, zl + 0.03), col)
		kit.quad(Vector3(s0 + 0.5, yy, zr + 0.03), Vector3(s0 + 3.6, yy, zr + 0.03), Vector3(s1 + 3.6, yy + 1.2, zr + 0.03), Vector3(s1 + 0.5, yy + 1.2, zr + 0.03), col)
		yy += 1.2
		n += 1
	# Hazard band along the bottom, slanted stripes either side of the seam.
	var bx := -hw + 0.4
	var k := 0
	while bx < hw - 3.0:
		var seam_here := hangar_seam_x(1.5, leaf_top)
		if absf(bx + 1.2 - seam_here) > 4.2:
			var zf := zl if bx < seam_here else zr
			var c := SAFETY_YELLOW if k % 2 == 0 else BLACK
			kit.quad(Vector3(bx, 0.0, zf + 0.04), Vector3(bx + 2.2, 0.0, zf + 0.04), Vector3(bx + 4.2, 3.0, zf + 0.04), Vector3(bx + 2.0, 3.0, zf + 0.04), c)
		bx += 2.2
		k += 1
	# Rust streaks from the header and the panel joints.
	for i in 22:
		var x := lerpf(-hw + 2.0, hw - 2.0, PropKit.hash3(Vector3(i * 7.3, 1.0, 2.0)))
		if absf(x - hangar_seam_x(leaf_top * 0.5, leaf_top)) < 4.5:
			continue
		var top := leaf_top - lerpf(0.5, 30.0, PropKit.hash3(Vector3(i * 3.1, 4.0, 9.0)) ** 2.0)
		var drop := lerpf(6.0, 34.0, PropKit.hash3(Vector3(i * 5.7, 8.0, 3.0)))
		var zf := zl if x < hangar_seam_x(top, leaf_top) else zr
		kit.quad(Vector3(x - 0.15, top - drop, zf + 0.05), Vector3(x + 0.15, top - drop, zf + 0.05), Vector3(x + 0.3, top, zf + 0.05), Vector3(x - 0.3, top, zf + 0.05), Color(0.22, 0.14, 0.10), Transform3D.IDENTITY, false)
	# A slab behind the leaves: the bay's back wall steps back ~3.3 m toward its sides, and this fills the gap.
	kit.box(Vector3(-hw - 0.8, 0.0, -4.0), Vector3(hw + 0.8, leaf_top, 0.5), STEEL_DARK, Transform3D.IDENTITY, false)
	# Jambs, header, floor track.
	kit.box(Vector3(-hw - 0.8, 0.0, -4.0), Vector3(-hw + 0.4, h, 2.0), STEEL)
	kit.box(Vector3(hw - 0.4, 0.0, -4.0), Vector3(hw + 0.8, h, 2.0), STEEL)
	kit.box(Vector3(-hw - 0.8, leaf_top, -4.0), Vector3(hw + 0.8, h, 3.4), STEEL_DARK)
	kit.box(Vector3(-hw, leaf_top - 1.0, 0.0), Vector3(hw, leaf_top, 2.6), STEEL.darkened(0.2))
	for gx in 9:
		var x := lerpf(-hw + 3.0, hw - 3.0, gx / 8.0)
		kit.box(Vector3(x - 0.4, leaf_top - 6.0, 2.6), Vector3(x + 0.4, leaf_top, 3.4), STEEL)
	kit.box(Vector3(-hw, 0.0, 0.3), Vector3(hw, 0.4, 2.6), STEEL_DARK)
	kit.box(Vector3(-hw, 0.4, 0.3), Vector3(hw, 0.55, 0.7), STEEL.darkened(0.1))
	# Two dead warning beacons on the header.
	for bxs in [-0.62, 0.62]:
		var bp := Vector3(bxs * hw, leaf_top - 1.4, 3.4)
		kit.box(bp + Vector3(-0.8, -0.2, -0.1), bp + Vector3(0.8, 0.2, 0.7), STEEL_DARK)
		kit.tube(bp + Vector3(0, 0.2, 0.7), bp + Vector3(0, -1.0, 0.7), 0.8, Color(0.30, 0.18, 0.08), 6)
	return [[Vector3(0, h * 0.5, 1.7), Vector3(HANGAR_W + 1.6, h, 3.4)]]


static func _floodlight(kit: PropKit, powered: bool) -> Array:
	kit.box(Vector3(-0.05, -0.3, -0.05), Vector3(0.05, 0.0, 0.05), STEEL_DARK)
	var xf := Transform3D(Basis(Vector3.RIGHT, 0.8), Vector3(0, -0.3, 0))
	kit.box(Vector3(-0.35, -0.25, -0.1), Vector3(0.35, 0.25, 0.25), STEEL_DARK, xf)
	if powered:
		kit.box(Vector3(-0.3, -0.2, 0.25), Vector3(0.3, 0.2, 0.28), Color.WHITE, xf, false, kit.extra_surface(glow(Color(1.0, 0.9, 0.7))))
	else:
		kit.box(Vector3(-0.3, -0.2, 0.25), Vector3(0.3, 0.2, 0.27), Color(0.1, 0.1, 0.1), xf)
	return []


# -- plants -----------------------------------------------------------------------------------

## A flat irregular patch on the XZ plane (or XY for wall creep), a few mm proud.
static func _patch(kit: PropKit, radius: float, rng: RandomNumberGenerator, wall: bool, col: Color) -> void:
	if wall:
		_wall_moss(kit, radius, rng, col)
		return
	var sides := 9
	var pts: Array[Vector3] = []
	for i in sides:
		var a := TAU * i / sides
		var r := radius * rng.randf_range(0.55, 1.1)
		pts.append(Vector3(cos(a) * r, 0.02, sin(a) * r) if not wall else Vector3(cos(a) * r, (sin(a) * 0.5 + 0.5) * radius * 1.6, 0.02))
	var centre := Vector3(0, 0.03, 0) if not wall else Vector3(0, radius * 0.8, 0.03)
	for i in sides:
		var j := (i + 1) % sides
		var shade := col.darkened(rng.randf() * 0.2)
		kit.tri_out(centre, pts[i], pts[j], shade, centre - (Vector3.UP if not wall else Vector3.BACK))
	# A few mounds.
	if not wall:
		for i in rng.randi_range(2, 4):
			var a := rng.randf() * TAU
			var r := rng.randf() * radius * 0.5
			kit.blob(Vector3(cos(a) * r, 0.0, sin(a) * r), Vector3(0.25, 0.08, 0.25) * radius, col.lightened(0.05), rng, Transform3D.IDENTITY, 2, 5)


## Moss creeping up a wall from the floor line: a low ragged band, flat along the floor, highest in
## the middle (2026-11-14 review: the old round wall disc read as a green ball stuck on the wall).
static func _wall_moss(kit: PropKit, radius: float, rng: RandomNumberGenerator, col: Color) -> void:
	var cols := 8
	var half := radius * 1.5
	var tops: Array[float] = []
	for i in cols + 1:
		var t := float(i) / cols * 2.0 - 1.0
		tops.append(radius * rng.randf_range(0.2, 0.75) * (1.0 - t * t) + 0.04)
	for i in cols:
		var x0 := -half + 2.0 * half * i / cols
		var x1 := -half + 2.0 * half * (i + 1) / cols
		var shade := col.darkened(rng.randf() * 0.2)
		var b0 := Vector3(x0, 0.0, 0.02)
		var b1 := Vector3(x1, 0.0, 0.02)
		var t0 := Vector3(x0, tops[i], 0.02)
		var t1 := Vector3(x1, tops[i + 1], 0.02)
		var inside := Vector3((x0 + x1) * 0.5, 0.1, -1.0)
		kit.tri_out(b0, b1, t1, shade, inside)
		kit.tri_out(b0, t1, t0, shade, inside)
	# A floor fringe in front, so it meets the ground instead of stopping at the wall line.
	for i in cols:
		var x0 := -half + 2.0 * half * i / cols
		var x1 := -half + 2.0 * half * (i + 1) / cols
		var d0 := tops[i] * 0.6
		var d1 := tops[i + 1] * 0.6
		kit.tri_out(Vector3(x0, 0.02, 0.02), Vector3(x1, 0.02, d1), Vector3(x1, 0.02, 0.02), col.darkened(0.1), Vector3(0, -1, 0.3))
		kit.tri_out(Vector3(x0, 0.02, 0.02), Vector3(x0, 0.02, d0), Vector3(x1, 0.02, d1), col.darkened(0.1), Vector3(0, -1, 0.3))


static func _moss(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	match v % 3:
		0: _patch(kit, 0.8, rng, false, MOSS_COL)
		1: _patch(kit, 1.6, rng, false, MOSS_COL.darkened(0.1))
		_: _patch(kit, 1.0, rng, true, MOSS_COL.darkened(0.05))
	return []


static func _blade(kit: PropKit, base: Vector3, h: float, lean: Vector3, col: Color) -> void:
	var w := 0.035
	var side := lean.cross(Vector3.UP).normalized() if lean.length() > 0.01 else Vector3.RIGHT
	var tip := base + Vector3.UP * h + lean * h
	kit.tri(base - side * w, base + side * w, tip, col)
	kit.tri(base + side * w, base - side * w, tip, col.darkened(0.2))


static func _tuft(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	var col := Color(0.42, 0.48, 0.20) if v % 2 == 0 else Color(0.30, 0.40, 0.16)
	for i in rng.randi_range(7, 12):
		var a := rng.randf() * TAU
		var r := rng.randf() * 0.18
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.1, 0.5)
		_blade(kit, base, rng.randf_range(0.2, 0.5) * (1.4 if v % 2 == 1 else 1.0), lean, col.lightened(rng.randf() * 0.1))
	return []


static func _shrub(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	var s := 0.6 if v % 2 == 0 else 1.1
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var r := rng.randf() * s * 0.5
		kit.blob(Vector3(cos(a) * r, s * rng.randf_range(0.3, 0.6), sin(a) * r), Vector3(s, s * 0.7, s) * rng.randf_range(0.45, 0.7),
			LEAF.lerp(LEAF_DARK, rng.randf()), rng)
	return []


static func _tree(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	var h := 4.5 if v % 2 == 0 else 7.0
	var r := 0.18 if v % 2 == 0 else 0.3
	# Gnarled trunk: a few bent segments.
	var p := Vector3.ZERO
	var dir := Vector3.UP
	var segs := 4
	var tops: Array[Vector3] = []
	for i in segs:
		var nxt := p + dir * (h * 0.6 / segs)
		kit.tube(p, nxt, r * (1.0 - 0.15 * i), BARK, 6, Transform3D.IDENTITY, true, null, r * (1.0 - 0.15 * (i + 1)))
		p = nxt
		dir = (dir + Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))).normalized()
	# Branches up and out, each ending in a leaf clump.
	for i in rng.randi_range(3, 5):
		var out := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.5, 1.2), rng.randf_range(-1, 1)).normalized()
		var end := p + out * h * rng.randf_range(0.25, 0.4)
		kit.tube(p, end, r * 0.45, BARK.darkened(0.1), 5, Transform3D.IDENTITY, true, null, r * 0.2)
		tops.append(end)
	for t in tops:
		kit.blob(t, Vector3(1, 0.7, 1) * h * rng.randf_range(0.18, 0.25), LEAF.lerp(LEAF_DARK, rng.randf()), rng)
	kit.blob(p + Vector3.UP * h * 0.15, Vector3(1, 0.7, 1) * h * 0.25, LEAF, rng)
	# Roots.
	for i in 4:
		var a := TAU * i / 4.0 + rng.randf() * 0.5
		kit.tube(Vector3(0, 0.3, 0), Vector3(cos(a) * r * 4.0, 0.0, sin(a) * r * 4.0), r * 0.5, BARK, 5, Transform3D.IDENTITY, true, null, r * 0.15)
	return [[Vector3(0, h * 0.3, 0), Vector3(r * 2.0, h * 0.6, r * 2.0)]]


static func _vine(kit: PropKit, length: float, rng: RandomNumberGenerator) -> Array:
	var p := Vector3.ZERO
	var steps := maxi(2, int(length / 0.5))
	for i in steps:
		var nxt := p + Vector3(rng.randf_range(-0.12, 0.12), -length / steps, rng.randf_range(-0.12, 0.12))
		kit.tube(p, nxt, 0.025, LEAF_DARK.darkened(0.2), 4, Transform3D.IDENTITY, false)
		if rng.randf() < 0.7:
			var leaf := LEAF.lerp(LEAF_DARK, rng.randf())
			var s := rng.randf_range(0.1, 0.2)
			var o := Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))
			kit.tri(nxt + o, nxt + o + Vector3(s, s * 0.5, 0.05), nxt + o + Vector3(s * 0.3, -s, 0.0), leaf)
			kit.tri(nxt + o, nxt + o + Vector3(s * 0.3, -s, 0.0), nxt + o + Vector3(s, s * 0.5, 0.05), leaf.darkened(0.2))
		p = nxt
	return []
