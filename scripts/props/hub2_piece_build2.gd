class_name Hub2PieceBuild2
extends RefCounted

# Room furniture, signage, light and structure meshes for Hub2Piece (docs/specs/hub2-final-pass.md).
# Same conventions as Hub2PieceBuild: fill `kit`, return collision boxes [[centre, size, basis?]].

const K := Hub2Piece.Kind


const STEEL := Color(0.42, 0.44, 0.46)
const STEEL_DARK := Color(0.20, 0.21, 0.23)
const BLACK := Color(0.07, 0.07, 0.08)
const GLASS := Color(0.08, 0.10, 0.11)
const PANEL := Color(0.55, 0.56, 0.53)
const PANEL_DARK := Color(0.33, 0.34, 0.33)
const OPERATOR := Color(0.50, 0.21, 0.14)
const OLIVE := Color(0.33, 0.35, 0.23)
const SAFETY_YELLOW := Color(0.84, 0.65, 0.13)
const FIRE_RED := Color(0.62, 0.11, 0.08)
const WOOD := Color(0.45, 0.33, 0.20)
const CHAR := Color(0.12, 0.09, 0.07)
const COAT := Color(0.30, 0.22, 0.14)
const CLOTH := Color(0.26, 0.28, 0.22)
const WATER := Color(0.09, 0.11, 0.13)
const WARM := Color(1.0, 0.62, 0.28)
const SPRAY := [Color(0.70, 0.12, 0.09), Color(0.85, 0.85, 0.82), Color(0.25, 0.62, 0.30), Color(0.85, 0.70, 0.15)]


static func build(kit: PropKit, k: int, v: int, st: int, rng: RandomNumberGenerator, sz: Vector3, t: String, p: bool) -> Array:
	match k:
		K.LOCKERS: return _lockers(kit, sz, st, rng)
		K.BENCH: return _bench(kit)
		K.VENDING: return _vending(kit, rng)
		K.TABLE: return _table(kit, v)
		K.CHAIR: return _chair(kit, v)
		K.DESK: return _desk(kit, v, rng)
		K.BOARD: return _board(kit, t, rng)
		K.BEDROLL: return _bedroll(kit, v, rng)
		K.CAMPFIRE: return _campfire(kit, p, rng)
		K.STRING_LIGHT: return _string_light(kit, sz, p, rng)
		K.CHEMLIGHT: return _chemlight(kit, p)
		K.GENERATOR: return _generator(kit, rng)
		K.FUEL_TANK: return _fuel_tank(kit, t)
		K.DRUM: return _drum(kit, v, st, p, rng)
		K.PUMP: return _pump(kit, v)
		K.TANK_V: return _tank_v(kit, sz, t)
		K.VENT_FAN: return _vent_fan(kit, rng)
		K.WEAPON_RACK: return _weapon_rack(kit)
		K.SCANNER_ARCH: return _scanner_arch(kit)
		K.BOOTH: return _booth(kit, rng)
		K.INSPECT_TABLE: return _inspect_table(kit)
		K.VEHICLE_LIFT: return _vehicle_lift(kit, v)
		K.TOOL_WALL: return _tool_wall(kit, rng)
		K.BODY: return _body(kit, rng)
		K.HOLO_RING: return _holo_ring(kit, v)
		K.CONE: return _cone(kit, v)
		K.BOLLARD: return _bollard(kit)
		K.PAPERS: return _papers(kit, sz, rng)
		K.CANS: return _cans(kit, rng)
		K.TARP: return _tarp(kit, sz, v)
		K.STENCIL: return _stencil(kit, t, sz, v)
		K.TAG: return _tag(kit, v, st, sz, t, rng)
		K.BAY_NUMBER: return _bay_number(kit, t, sz, p)
		K.LED_STRIP: return _led_strip(kit, sz, p, rng)
		K.KEYPAD: return _keypad(kit, v)
		K.EMERGENCY_LAMP: return _emergency_lamp(kit, v, p)
		K.PUDDLE: return _puddle(kit, sz, rng)
		K.STAIN: return _stain(kit, sz, rng)
		K.RAILING: return _railing(kit, sz, v, rng)
		K.STAIR: return _stair(kit, sz)
		K.DECK: return _deck(kit, sz)
		K.CABIN: return _cabin(kit, v, st, rng)
		K.SHED: return _shed(kit, sz)
		K.FENCE: return _fence(kit, sz, v)
		K.SHUTTER: return _shutter(kit, sz, st, t, rng)
		K.BULKHEAD: return _bulkhead(kit, sz, v, t)
		K.LADDER: return _ladder(kit, sz)
		K.COLD_CAGE: return _cold_cage(kit, sz, rng)
		K.SKYLIGHT: return _skylight(kit, sz, p, rng)
		K.PIPE_FALLEN: return _pipe_fallen(kit, sz, rng)
	return []


static func _glow(kit: PropKit, c: Color) -> SurfaceTool:
	return kit.extra_surface(Hub2PieceBuild.glow(c))


# -- rooms ------------------------------------------------------------------------------------

## A bank of lockers along X, `size.x` wide (0.5 m each), doors at +Z. state 1 = pried and looted.
static func _lockers(kit: PropKit, sz: Vector3, st: int, rng: RandomNumberGenerator) -> Array:
	var n := maxi(int(sz.x / 0.5), 1)
	var w := n * 0.5
	var col := Color(0.36, 0.42, 0.44)
	kit.box(Vector3(-w * 0.5, 0, -0.5), Vector3(w * 0.5, 0.08, 0.0), BLACK)
	kit.box(Vector3(-w * 0.5, 0.08, -0.5), Vector3(w * 0.5, 1.95, -0.47), col.darkened(0.3))
	kit.box(Vector3(-w * 0.5, 1.92, -0.5), Vector3(w * 0.5, 1.98, 0.0), col)
	for i in n + 1:
		var x := -w * 0.5 + i * 0.5
		kit.box(Vector3(x - 0.015, 0.08, -0.5), Vector3(x + 0.015, 1.92, 0.0), col)
	for i in n:
		var x := -w * 0.5 + i * 0.5
		kit.box(Vector3(x + 0.02, 0.08, -0.47), Vector3(x + 0.48, 1.92, -0.46), Color(0.10, 0.10, 0.10))   # dark inside
		var ang := 0.0
		if st == 1 and rng.randf() < 0.7:
			ang = rng.randf_range(0.6, 2.2)
		var xf := Transform3D(Basis(Vector3.UP, -ang), Vector3(x + 0.02, 0, 0))
		kit.box(Vector3(0, 0.1, 0.0), Vector3(0.46, 1.9, 0.025), col.lightened(0.04), xf)
		for j in 3:
			kit.box(Vector3(0.12, 1.6 + j * 0.06, 0.025), Vector3(0.34, 1.63 + j * 0.06, 0.03), BLACK, xf)
		Hub2PieceBuild.paint_text(kit, str(i + 1 + rng.randi_range(0, 3) * n), Vector3(0.18, 1.35, 0.03), Vector3.RIGHT, Vector3.UP, 0.025, Color(0.85, 0.85, 0.8), xf)
		if ang > 0.0 and rng.randf() < 0.4:
			kit.box(Vector3(x + 0.1, 0.1, -0.35), Vector3(x + 0.4, 0.14, -0.05), CLOTH)
	return [[Vector3(0, 0.99, -0.25), Vector3(w, 1.98, 0.5)]]


static func _bench(kit: PropKit) -> Array:
	kit.box(Vector3(-1.0, 0.42, -0.18), Vector3(1.0, 0.47, 0.18), WOOD)
	for x in [-0.85, 0.85]:
		kit.box(Vector3(x - 0.03, 0, -0.15), Vector3(x + 0.03, 0.42, 0.15), STEEL_DARK)
	return [[Vector3(0, 0.235, 0), Vector3(2.0, 0.47, 0.36)]]


## Vending machine, front glass smashed out, shelves mostly empty, sign panel dead.
static func _vending(kit: PropKit, rng: RandomNumberGenerator) -> Array:
	var c := Color(0.55, 0.16, 0.12)
	kit.box(Vector3(-0.5, 0, -0.4), Vector3(0.5, 1.95, 0.4), c)
	kit.box(Vector3(-0.42, 0.55, 0.38), Vector3(0.18, 1.75, 0.41), Color(0.04, 0.04, 0.05))
	for i in 5:
		var y := 0.65 + i * 0.22
		kit.box(Vector3(-0.42, y, 0.0), Vector3(0.18, y + 0.02, 0.38), STEEL_DARK)
		for j in 4:
			if rng.randf() < 0.25:
				kit.box(Vector3(-0.38 + j * 0.14, y + 0.02, 0.15), Vector3(-0.28 + j * 0.14, y + 0.17, 0.3), [Color(0.7, 0.6, 0.2), Color(0.2, 0.4, 0.6), Color(0.6, 0.2, 0.2)][j % 3])
	# shards of glass left in the frame
	kit.tri(Vector3(-0.42, 0.55, 0.405), Vector3(-0.1, 0.55, 0.405), Vector3(-0.42, 0.9, 0.405), Color(0.3, 0.38, 0.4))
	kit.tri(Vector3(0.18, 1.75, 0.405), Vector3(-0.05, 1.75, 0.405), Vector3(0.18, 1.45, 0.405), Color(0.3, 0.38, 0.4))
	kit.box(Vector3(0.22, 1.0, 0.39), Vector3(0.45, 1.5, 0.42), STEEL_DARK)
	kit.box(Vector3(-0.45, 1.78, 0.39), Vector3(0.45, 1.92, 0.42), Color(0.2, 0.2, 0.2))
	Hub2PieceBuild.paint_text(kit, "NOVA COLA", Vector3(-0.38, 1.81, 0.425), Vector3.RIGHT, Vector3.UP, 0.02, Color(0.8, 0.75, 0.6))
	kit.box(Vector3(-0.42, 0.15, 0.38), Vector3(0.18, 0.4, 0.42), BLACK)
	return [[Vector3(0, 0.975, 0), Vector3(1.0, 1.95, 0.8)]]


static func _table(kit: PropKit, v: int) -> Array:
	var xf := Transform3D.IDENTITY
	if v == 1:
		xf = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.45, -0.38))
	kit.box(Vector3(-0.9, 0.72, -0.45), Vector3(0.9, 0.76, 0.45), Color(0.5, 0.5, 0.47), xf)
	for x in [-0.8, 0.8]:
		for z in [-0.35, 0.35]:
			kit.box(Vector3(x - 0.025, 0, z - 0.025), Vector3(x + 0.025, 0.72, z + 0.025), STEEL_DARK, xf)
	if v == 1:
		return [[Vector3(0, 0.45, -0.38), Vector3(1.8, 0.9, 0.1)]]
	return [[Vector3(0, 0.38, 0), Vector3(1.8, 0.76, 0.9)]]


static func _chair(kit: PropKit, v: int) -> Array:
	var xf := Transform3D.IDENTITY
	if v == 1:
		xf = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.22, 0.45))
	var c := Color(0.25, 0.30, 0.33)
	kit.box(Vector3(-0.22, 0.44, -0.22), Vector3(0.22, 0.48, 0.22), c, xf)
	kit.box(Vector3(-0.22, 0.48, -0.24), Vector3(0.22, 0.9, -0.2), c, xf)
	for x in [-0.19, 0.19]:
		for z in [-0.19, 0.19]:
			kit.box(Vector3(x - 0.015, 0, z - 0.015), Vector3(x + 0.015, 0.44, z + 0.015), STEEL_DARK, xf)
	return []


## Office desk with a CRT, keyboard and paper. variant 1 = drawers pulled out and dumped.
static func _desk(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	var c := Color(0.46, 0.46, 0.43)
	kit.box(Vector3(-0.8, 0.72, -0.4), Vector3(0.8, 0.76, 0.4), c)
	kit.box(Vector3(0.3, 0.0, -0.38), Vector3(0.78, 0.72, 0.38), c.darkened(0.15))
	kit.box(Vector3(-0.78, 0.0, -0.38), Vector3(-0.74, 0.72, 0.38), c.darkened(0.15))
	for i in 3:
		var y := 0.08 + i * 0.22
		var out := 0.0 if v == 0 else rng.randf_range(0.1, 0.35)
		kit.box(Vector3(0.33, y, 0.38 + out - 0.02), Vector3(0.75, y + 0.18, 0.4 + out), c.lightened(0.05))
	# CRT
	kit.box(Vector3(-0.45, 0.76, -0.35), Vector3(0.05, 1.18, 0.05), Color(0.58, 0.56, 0.5))
	kit.box(Vector3(-0.4, 0.82, 0.05), Vector3(0.0, 1.12, 0.08), GLASS)
	kit.box(Vector3(-0.45, 0.76, 0.1), Vector3(0.05, 0.79, 0.3), Color(0.5, 0.49, 0.44))
	for i in 3:
		kit.obox(Vector3(rng.randf_range(0.1, 0.6), 0.765, rng.randf_range(-0.2, 0.3)), Vector3(0.21, 0.004, 0.3), Color(0.82, 0.8, 0.72), Basis(Vector3.UP, rng.randf() * 3.0))
	if v == 1:
		for i in 6:
			kit.obox(Vector3(rng.randf_range(-0.6, 1.2), 0.004, rng.randf_range(0.5, 1.4)), Vector3(0.21, 0.004, 0.3), Color(0.8, 0.78, 0.7), Basis(Vector3.UP, rng.randf() * 3.0))
	return [[Vector3(0, 0.38, 0), Vector3(1.6, 0.76, 0.8)]]


## Wall board with the yard map: container rows as blocks, crane runways, YARD B.
static func _board(kit: PropKit, t: String, rng: RandomNumberGenerator) -> Array:
	kit.box(Vector3(-1.3, 1.0, 0.0), Vector3(1.3, 2.5, 0.05), Color(0.82, 0.82, 0.78))
	kit.box(Vector3(-1.35, 0.95, 0.0), Vector3(1.35, 1.0, 0.07), STEEL_DARK)
	kit.box(Vector3(-1.35, 2.5, 0.0), Vector3(1.35, 2.55, 0.07), STEEL_DARK)
	for r in 6:
		for c in 3:
			if rng.randf() < 0.8:
				var x := -1.1 + c * 0.55
				var y := 1.15 + r * 0.17
				kit.box(Vector3(x, y, 0.05), Vector3(x + 0.45, y + 0.1, 0.055), [OPERATOR, Color(0.2, 0.25, 0.4), OLIVE][(r + c) % 3])
	kit.box(Vector3(0.6, 1.1, 0.05), Vector3(0.63, 2.2, 0.055), FIRE_RED)
	kit.box(Vector3(0.9, 1.1, 0.05), Vector3(0.93, 2.2, 0.055), FIRE_RED)
	Hub2PieceBuild.paint_text(kit, t if t != "" else "YARD B", Vector3(-1.2, 2.3, 0.056), Vector3.RIGHT, Vector3.UP, 0.035, BLACK)
	# torn sheet
	kit.tri(Vector3(0.7, 2.45, 0.058), Vector3(1.25, 2.45, 0.058), Vector3(1.2, 1.7, 0.058), Color(0.9, 0.88, 0.8))
	return []


static func _bedroll(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	var c: Color = [Color(0.25, 0.30, 0.22), Color(0.35, 0.22, 0.16), Color(0.2, 0.25, 0.32)][v % 3]
	kit.box(Vector3(-0.35, 0, -1.0), Vector3(0.35, 0.05, 1.0), c.darkened(0.3))
	kit.blob(Vector3(0, 0.08, 0.2), Vector3(0.33, 0.07, 0.75), c, rng, Transform3D.IDENTITY, 2, 6)
	kit.blob(Vector3(0, 0.08, -0.8), Vector3(0.25, 0.08, 0.15), c.lightened(0.2), rng, Transform3D.IDENTITY, 2, 6)
	return []


## Scavenger fire: stone ring, charred logs, ash; lit = ember glow.
static func _campfire(kit: PropKit, p: bool, rng: RandomNumberGenerator) -> Array:
	for i in 9:
		var a := TAU * i / 9.0
		kit.blob(Vector3(cos(a) * 0.55, 0.08, sin(a) * 0.55), Vector3(0.14, 0.1, 0.12), Color(0.35, 0.34, 0.32).darkened(rng.randf() * 0.3), rng, Transform3D.IDENTITY, 2, 5)
	kit.box(Vector3(-0.45, 0, -0.45), Vector3(0.45, 0.02, 0.45), Color(0.18, 0.17, 0.16))
	for i in 4:
		var a := TAU * i / 4.0 + 0.3
		kit.tube(Vector3(cos(a) * 0.4, 0.04, sin(a) * 0.4), Vector3(cos(a) * 0.05, 0.22, sin(a) * 0.05), 0.05, CHAR, 5)
	if p:
		kit.blob(Vector3(0, 0.08, 0), Vector3(0.2, 0.08, 0.2), Color.WHITE, rng, Transform3D.IDENTITY, 2, 6)
		var sst := _glow(kit, Color(1.0, 0.45, 0.12))
		kit.box(Vector3(-0.15, 0.03, -0.15), Vector3(0.15, 0.12, 0.15), Color.WHITE, Transform3D(Basis(Vector3.UP, 0.7)), false, sst)
		kit.box(Vector3(-0.08, 0.1, -0.08), Vector3(0.08, 0.32, 0.08), Color.WHITE, Transform3D(Basis(Vector3.UP, 0.2)), false, _glow(kit, Color(1.0, 0.7, 0.25)))
	return []


## A string of bulbs sagging `size.y` along X for `size.x`; lit = warm bulbs, a few dead.
static func _string_light(kit: PropKit, sz: Vector3, p: bool, rng: RandomNumberGenerator) -> Array:
	var n := maxi(int(sz.x / 0.8), 2)
	var prev := Vector3.ZERO
	for i in n + 1:
		var u := float(i) / n
		var pt := Vector3(u * sz.x, -sz.y * 4.0 * u * (1.0 - u), 0)
		if i > 0:
			kit.tube(prev, pt, 0.008, BLACK, 3, Transform3D.IDENTITY, false)
			var bulb := (prev + pt) * 0.5 + Vector3(0, -0.08, 0)
			if p and rng.randf() < 0.8:
				kit.box(bulb - Vector3(0.04, 0.05, 0.04), bulb + Vector3(0.04, 0.03, 0.04), Color.WHITE, Transform3D.IDENTITY, false, _glow(kit, WARM))
			else:
				kit.box(bulb - Vector3(0.035, 0.05, 0.035), bulb + Vector3(0.035, 0.02, 0.035), Color(0.3, 0.28, 0.22))
		prev = pt
	return []


static func _chemlight(kit: PropKit, p: bool) -> Array:
	if p:
		kit.tube(Vector3(-0.08, 0.015, 0), Vector3(0.08, 0.015, 0.02), 0.013, Color.WHITE, 5, Transform3D.IDENTITY, true, _glow(kit, Color(0.35, 1.0, 0.4)))
	else:
		kit.tube(Vector3(-0.08, 0.015, 0), Vector3(0.08, 0.015, 0.02), 0.013, Color(0.2, 0.35, 0.22), 5)
	return []


## Diesel generator set on a skid: radiator end at -X, control panel at +X, exhaust stack.
static func _generator(kit: PropKit, rng: RandomNumberGenerator) -> Array:
	var c := Color(0.32, 0.38, 0.30)
	kit.cell = 1.0
	kit.box(Vector3(-2.6, 0, -1.0), Vector3(2.6, 0.25, 1.0), STEEL_DARK)
	kit.box(Vector3(-2.4, 0.25, -0.9), Vector3(2.0, 2.3, 0.9), c)
	for i in 8:
		var y := 0.45 + i * 0.22
		kit.box(Vector3(-2.43, y, -0.75), Vector3(-2.4, y + 0.1, 0.75), BLACK)
	for i in 6:
		var x := -1.6 + i * 0.55
		kit.box(Vector3(x, 0.6, 0.9), Vector3(x + 0.35, 1.9, 0.92), c.darkened(0.15))
	kit.box(Vector3(2.0, 0.25, -0.6), Vector3(2.5, 2.0, 0.6), STEEL_DARK)
	kit.box(Vector3(2.5, 1.2, -0.4), Vector3(2.52, 1.8, 0.4), GLASS)
	kit.tube(Vector3(-1.0, 2.3, 0.4), Vector3(-1.0, 3.6, 0.4), 0.14, Color(0.25, 0.18, 0.12), 6)
	kit.tube(Vector3(-1.0, 3.6, 0.4), Vector3(-1.4, 3.8, 0.4), 0.14, Color(0.25, 0.18, 0.12), 6)
	Hub2PieceBuild.paint_text(kit, "GEN-2  500KVA", Vector3(-1.4, 2.0, 0.925), Vector3.RIGHT, Vector3.UP, 0.05, Color(0.85, 0.85, 0.8))
	Hub2PieceBuild.paint_text(kit, "DANGER", Vector3(2.08, 1.85, 0.6), Vector3.RIGHT, Vector3.UP, 0.03, SAFETY_YELLOW)
	if rng.randf() < 2.0:
		kit.box(Vector3(-0.3, 0.25, 0.92), Vector3(0.3, 0.9, 0.95), BLACK)   # access panel ripped off
	return [[Vector3(0, 1.15, 0), Vector3(5.2, 2.3, 1.9)]]


## Horizontal fuel tank on saddles, 5 m, with a ladder and a stencil.
static func _fuel_tank(kit: PropKit, t: String) -> Array:
	var c := Color(0.52, 0.48, 0.36)
	kit.cell = 1.0
	kit.tube(Vector3(-2.5, 1.35, 0), Vector3(2.5, 1.35, 0), 1.0, c, 10)
	for x in [-1.6, 1.6]:
		kit.box(Vector3(x - 0.2, 0, -0.9), Vector3(x + 0.2, 0.9, 0.9), STEEL_DARK)
	kit.tube(Vector3(0.8, 2.35, 0), Vector3(0.8, 2.6, 0), 0.25, STEEL_DARK, 6)
	Hub2PieceBuild.paint_text(kit, t if t != "" else "DIESEL", Vector3(-1.0, 1.25, 1.0), Vector3.RIGHT, Vector3.UP, 0.09, Color(0.15, 0.12, 0.1))
	return [[Vector3(0, 1.17, 0), Vector3(5.0, 2.35, 2.0)]]


## Oil drum. variant = colour; state 1 tipped on its side, 2 burn barrel (lit = embers).
static func _drum(kit: PropKit, v: int, st: int, p: bool, rng: RandomNumberGenerator) -> Array:
	var c: Color = [Color(0.18, 0.28, 0.45), Color(0.55, 0.14, 0.10), Color(0.30, 0.34, 0.22), Color(0.38, 0.24, 0.15), Color(0.50, 0.50, 0.48)][v % 5]
	var xf := Transform3D.IDENTITY
	if st == 1:
		xf = Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, rng.randf() * 3.0), Vector3(0.44, 0.29, 0))
	if st == 2:
		c = Color(0.2, 0.15, 0.11)
	kit.tube(Vector3(0, 0, 0), Vector3(0, 0.88, 0), 0.29, c, 8, xf, st != 2)
	for y in [0.3, 0.58]:
		kit.tube(Vector3(0, y, 0), Vector3(0, y + 0.03, 0), 0.3, c.darkened(0.2), 8, xf)
	if st == 2:
		kit.tube(Vector3(0, 0.0, 0), Vector3(0, 0.6, 0), 0.27, CHAR, 8, xf, true)
		for i in 5:
			var a := TAU * i / 5.0
			kit.box(Vector3(cos(a) * 0.29 - 0.05, 0.15, sin(a) * 0.29 - 0.05), Vector3(cos(a) * 0.29 + 0.05, 0.25, sin(a) * 0.29 + 0.05), BLACK, xf)
		if p:
			kit.box(Vector3(-0.15, 0.6, -0.15), Vector3(0.15, 0.68, 0.15), Color.WHITE, Transform3D.IDENTITY, false, _glow(kit, Color(1.0, 0.45, 0.12)))
	if st == 1:
		return [[Vector3(0.44, 0.29, 0), Vector3(0.88, 0.58, 0.58)]]
	return [[Vector3(0, 0.44, 0), Vector3(0.58, 0.88, 0.58)]]


## Pump skid: motor + volute on a baseplate. Pipe hookups (local): suction (-1.15, 0.65, 0) facing -X,
## discharge (0.35, 1.7, 0) facing up. variant 1 = motor pulled off and lying beside it.
static func _pump(kit: PropKit, v: int) -> Array:
	var c := Color(0.22, 0.34, 0.45)
	kit.box(Vector3(-1.3, 0, -0.55), Vector3(1.3, 0.2, 0.55), STEEL_DARK)
	kit.tube(Vector3(-1.0, 0.65, 0), Vector3(-1.15, 0.65, 0), 0.2, STEEL_DARK, 8)
	kit.tube(Vector3(-0.9, 0.65, 0), Vector3(-0.3, 0.65, 0), 0.4, c, 10)          # volute
	kit.tube(Vector3(0.35, 0.65, 0), Vector3(0.35, 1.7, 0), 0.14, c, 8)            # discharge riser
	kit.tube(Vector3(0.35, 1.6, 0), Vector3(0.35, 1.7, 0), 0.22, STEEL_DARK, 8)
	var mxf := Transform3D.IDENTITY
	if v == 1:
		mxf = Transform3D(Basis(Vector3.UP, 0.5), Vector3(0.6, -0.45, 1.2))
	kit.tube(Vector3(-0.2, 0.65, 0), Vector3(1.2, 0.65, 0), 0.38, Color(0.30, 0.36, 0.32), 10, mxf)  # motor
	for i in 6:
		var x := -0.05 + i * 0.2
		kit.tube(Vector3(x, 0.65, 0), Vector3(x + 0.05, 0.65, 0), 0.42, Color(0.26, 0.3, 0.28), 10, mxf)
	return [[Vector3(0, 0.55, 0), Vector3(2.6, 1.1, 1.1)]]


## Vertical process tank: radius size.x, height size.y, on four legs, ladder, nozzles, label.
static func _tank_v(kit: PropKit, sz: Vector3, t: String) -> Array:
	var r := sz.x
	var h := sz.y
	var c := Color(0.58, 0.58, 0.55)
	kit.cell = 1.2
	kit.tube(Vector3(0, 1.0, 0), Vector3(0, 1.0 + h, 0), r, c, 12)
	kit.tube(Vector3(0, 1.0 + h, 0), Vector3(0, 1.3 + h, 0), r * 0.85, c.darkened(0.08), 12, Transform3D.IDENTITY, true, null, r * 0.3)
	for a in 4:
		var d := Vector3(cos(a * PI * 0.5 + PI * 0.25), 0, sin(a * PI * 0.5 + PI * 0.25)) * r * 0.8
		kit.box(d + Vector3(-0.12, 0, -0.12), d + Vector3(0.12, 1.2, 0.12), STEEL_DARK)
	# ladder up the +X side
	for x in [-0.25, 0.25]:
		kit.box(Vector3(r + 0.25, 1.0, x - 0.03), Vector3(r + 0.3, 1.3 + h, x + 0.03), STEEL_DARK)
	for i in int(h / 0.35):
		kit.box(Vector3(r + 0.25, 1.2 + i * 0.35, -0.25), Vector3(r + 0.3, 1.23 + i * 0.35, 0.25), STEEL_DARK)
	# nozzles (pipe hookups): side at y 1.6 facing -X, top centre facing up
	kit.tube(Vector3(-r, 1.6, 0), Vector3(-r - 0.4, 1.6, 0), 0.18, STEEL_DARK, 8)
	kit.tube(Vector3(0, 1.3 + h, 0), Vector3(0, 1.7 + h, 0), 0.16, STEEL_DARK, 8)
	Hub2PieceBuild.paint_text(kit, t if t != "" else "T-1", Vector3(-0.4, 1.0 + h * 0.6, r + 0.01), Vector3.RIGHT, Vector3.UP, 0.12, Color(0.15, 0.15, 0.14))
	# rust run down from the top
	for i in 3:
		var a := 0.4 + i * 0.9
		var d := Vector3(cos(a), 0, sin(a)) * (r + 0.005)
		kit.box(d + Vector3(-0.05, 1.0 + h * 0.4, -0.05), d + Vector3(0.05, 1.0 + h, 0.05), Color(0.38, 0.2, 0.1))
	return [[Vector3(0, (1.3 + h) * 0.5, 0), Vector3(r * 1.6, 1.3 + h, r * 1.6)]]


## Roof cooling fan: square housing, grille, blades (one missing).
static func _vent_fan(kit: PropKit, rng: RandomNumberGenerator) -> Array:
	var c := Color(0.48, 0.5, 0.5)
	kit.box(Vector3(-1.2, 0, -1.2), Vector3(1.2, 1.3, 1.2), c)
	kit.tube(Vector3(0, 1.3, 0), Vector3(0, 1.6, 0), 1.05, c.darkened(0.1), 12, Transform3D.IDENTITY, false)
	kit.tube(Vector3(0, 1.55, 0), Vector3(0, 1.6, 0), 0.25, STEEL_DARK, 8)
	var skip := rng.randi() % 5
	for i in 5:
		if i == skip:
			continue
		var a := TAU * i / 5.0
		kit.obox(Vector3(cos(a) * 0.55, 1.55, sin(a) * 0.55), Vector3(0.75, 0.03, 0.22), BLACK, Basis(Vector3.UP, -a) * Basis(Vector3.RIGHT, 0.3))
	for i in 7:
		var x := -0.9 + i * 0.3
		kit.box(Vector3(x - 0.015, 1.62, -1.0), Vector3(x + 0.015, 1.65, 1.0), STEEL_DARK)
	return [[Vector3(0, 0.8, 0), Vector3(2.4, 1.6, 2.4)]]


## Wall rack of empty rifle slots, cut chain hanging.
static func _weapon_rack(kit: PropKit) -> Array:
	kit.box(Vector3(-1.2, 0.3, -0.12), Vector3(1.2, 2.0, 0.0), STEEL_DARK)
	kit.box(Vector3(-1.2, 0.3, 0.0), Vector3(1.2, 0.45, 0.35), Color(0.3, 0.31, 0.3))
	for i in 8:
		var x := -1.05 + i * 0.3
		kit.box(Vector3(x - 0.04, 0.45, 0.0), Vector3(x + 0.04, 0.55, 0.3), BLACK)
		kit.box(Vector3(x - 0.05, 1.6, 0.0), Vector3(x + 0.05, 1.75, 0.15), Color(0.3, 0.31, 0.3))
	for i in 6:
		kit.box(Vector3(1.1, 1.7 - i * 0.12, 0.05), Vector3(1.16, 1.78 - i * 0.12, 0.08), STEEL)
	Hub2PieceBuild.paint_text(kit, "ARMS", Vector3(-0.3, 1.85, 0.005), Vector3.RIGHT, Vector3.UP, 0.04, SAFETY_YELLOW)
	return [[Vector3(0, 1.15, 0.0), Vector3(2.4, 1.7, 0.4)]]


## Body scanner gate, 3 m wide opening, dead emitter strips. Opening along Z.
static func _scanner_arch(kit: PropKit) -> Array:
	var c := Color(0.62, 0.62, 0.6)
	for x in [-1.9, 1.5]:
		kit.box(Vector3(x, 0, -0.5), Vector3(x + 0.4, 3.0, 0.5), c)
		kit.box(Vector3(x + (0.38 if x < 0 else -0.01), 0.3, -0.35), Vector3(x + (0.41 if x < 0 else 0.02), 2.7, 0.35), Color(0.15, 0.2, 0.25))
	kit.box(Vector3(-1.9, 3.0, -0.5), Vector3(1.9, 3.5, 0.5), c)
	kit.box(Vector3(-1.5, 0, -0.6), Vector3(1.5, 0.04, 0.6), Color(0.25, 0.25, 0.26))
	Hub2PieceBuild.paint_text(kit, "SCAN", Vector3(-0.3, 3.15, 0.51), Vector3.RIGHT, Vector3.UP, 0.05, Color(0.2, 0.2, 0.2))
	kit.box(Vector3(-0.6, 3.05, 0.5), Vector3(0.6, 3.1, 0.52), Color(0.5, 0.15, 0.1))
	return [[Vector3(-1.7, 1.75, 0), Vector3(0.4, 3.5, 1.0)], [Vector3(1.7, 1.75, 0), Vector3(0.4, 3.5, 1.0)], [Vector3(0, 3.25, 0), Vector3(3.8, 0.5, 1.0)]]


## Guard booth 2.6 x 2.6 x 2.8: windows on three sides (some broken), door gap at the back (-Z), counter.
static func _booth(kit: PropKit, rng: RandomNumberGenerator) -> Array:
	var c := Color(0.6, 0.6, 0.57)
	var h := 2.8
	kit.box(Vector3(-1.3, 0, -1.3), Vector3(1.3, 0.15, 1.3), STEEL_DARK)
	kit.box(Vector3(-1.4, h, -1.4), Vector3(1.4, h + 0.2, 1.4), c.darkened(0.1))
	# corner posts
	for x in [-1.3, 1.2]:
		for z in [-1.3, 1.2]:
			kit.box(Vector3(x, 0.15, z), Vector3(x + 0.1, h, z + 0.1), c)
	# lower walls + windows on +Z, -X, +X
	var sides := [[Vector3(-1.2, 0, 1.2), Vector3(1.2, 0, 1.3)], [Vector3(-1.3, 0, -1.2), Vector3(-1.2, 0, 1.2)], [Vector3(1.2, 0, -1.2), Vector3(1.3, 0, 1.2)]]
	for s: Array in sides:
		var lo: Vector3 = s[0]
		var hi: Vector3 = s[1]
		kit.box(lo + Vector3(0, 0.15, 0), hi + Vector3(0, 1.1, 0), c)
		kit.box(lo + Vector3(0, 2.4, 0), hi + Vector3(0, h, 0), c)
		if rng.randf() < 0.6:
			kit.box(Vector3(lo.x, 1.1, lo.z), Vector3(hi.x, 2.4, hi.z), GLASS.lerp(Color(0.2, 0.25, 0.28), 0.4))
	# back wall with a door gap
	kit.box(Vector3(-1.2, 0.15, -1.3), Vector3(-0.4, h, -1.2), c)
	kit.box(Vector3(0.5, 0.15, -1.3), Vector3(1.2, h, -1.2), c)
	kit.box(Vector3(-0.4, 2.2, -1.3), Vector3(0.5, h, -1.2), c)
	kit.box(Vector3(-1.2, 0.9, 0.7), Vector3(1.2, 0.95, 1.2), c.darkened(0.2))   # counter
	Hub2PieceBuild.paint_text(kit, "SECURITY", Vector3(-0.62, h + 0.03, 1.405), Vector3.RIGHT, Vector3.UP, 0.04, Color(0.85, 0.85, 0.8))
	return [[Vector3(0, 0.075, 0), Vector3(2.6, 0.15, 2.6)], [Vector3(0, h + 0.1, 0), Vector3(2.8, 0.2, 2.8)],
		[Vector3(0, 0.6, 1.25), Vector3(2.6, 1.2, 0.12)], [Vector3(-1.25, 0.6, 0), Vector3(0.12, 1.2, 2.6)], [Vector3(1.25, 0.6, 0), Vector3(0.12, 1.2, 2.6)],
		[Vector3(-0.8, h * 0.5, -1.25), Vector3(0.8, h, 0.12)], [Vector3(0.85, h * 0.5, -1.25), Vector3(0.7, h, 0.12)]]


## Inspection table: roller conveyor top, side lamp arm (dead), a cut-open case on it.
static func _inspect_table(kit: PropKit) -> Array:
	kit.box(Vector3(-1.5, 0.85, -0.6), Vector3(1.5, 0.9, 0.6), STEEL)
	for i in 14:
		var x := -1.4 + i * 0.2
		kit.tube(Vector3(x, 0.93, -0.55), Vector3(x, 0.93, 0.55), 0.035, STEEL_DARK, 5)
	for x in [-1.4, 1.4]:
		for z in [-0.5, 0.5]:
			kit.box(Vector3(x - 0.04, 0, z - 0.04), Vector3(x + 0.04, 0.85, z + 0.04), STEEL_DARK)
	kit.tube(Vector3(1.4, 0.9, -0.55), Vector3(1.4, 2.0, -0.55), 0.03, STEEL_DARK, 4)
	kit.tube(Vector3(1.4, 2.0, -0.55), Vector3(0.6, 1.9, -0.2), 0.03, STEEL_DARK, 4)
	kit.box(Vector3(0.45, 1.75, -0.35), Vector3(0.75, 1.9, -0.05), Color(0.3, 0.3, 0.3))
	kit.box(Vector3(-0.8, 0.97, -0.35), Vector3(0.2, 1.17, 0.35), OLIVE)
	kit.obox(Vector3(-0.3, 1.25, -0.42), Vector3(1.0, 0.04, 0.5), OLIVE.darkened(0.1), Basis(Vector3.RIGHT, -1.1))
	return [[Vector3(0, 0.47, 0), Vector3(3.0, 0.95, 1.2)]]


## Two-post vehicle lift; variant 1 holds a loader body up at 1.6 m.
static func _vehicle_lift(kit: PropKit, v: int) -> Array:
	var c := Color(0.25, 0.35, 0.55)
	for x in [-1.7, 1.7]:
		kit.box(Vector3(x - 0.2, 0, -0.25), Vector3(x + 0.2, 3.8, 0.25), c)
		kit.box(Vector3(x - 0.35, 0, -0.4), Vector3(x + 0.35, 0.05, 0.4), STEEL_DARK)
	kit.box(Vector3(-1.9, 3.8, -0.2), Vector3(1.9, 4.0, 0.2), c)
	var ay := 1.6 if v == 1 else 0.3
	for x in [-1.5, 1.5]:
		for z in [-1.0, 1.0]:
			kit.box(Vector3(x - 0.06, ay, minf(0.0, z)), Vector3(x + 0.06, ay + 0.1, maxf(0.0, z)), STEEL_DARK)
	if v == 1:
		kit.box(Vector3(-1.3, ay + 0.1, -1.0), Vector3(1.3, ay + 0.8, 1.0), Color(0.72, 0.38, 0.13))
		kit.box(Vector3(-0.6, ay + 0.8, -0.5), Vector3(0.6, ay + 1.2, 0.5), Color(0.2, 0.2, 0.2))
	return [[Vector3(-1.7, 1.9, 0), Vector3(0.4, 3.8, 0.5)], [Vector3(1.7, 1.9, 0), Vector3(0.4, 3.8, 0.5)]] + ([[Vector3(0, ay + 0.45, 0), Vector3(2.6, 0.7, 2.0)]] if v == 1 else [])


## Pegboard tool wall: painted tool outlines, most tools gone.
static func _tool_wall(kit: PropKit, rng: RandomNumberGenerator) -> Array:
	kit.box(Vector3(-1.5, 0.9, 0.0), Vector3(1.5, 2.6, 0.03), Color(0.55, 0.45, 0.3))
	for i in 10:
		var x := -1.3 + (i % 5) * 0.6
		var y := 1.2 + floori(i / 5.0) * 0.75
		var outline := Color(0.15, 0.13, 0.1)
		var s := Vector3(0.12, rng.randf_range(0.3, 0.55), 0.004)
		kit.box(Vector3(x, y, 0.03), Vector3(x + s.x, y + s.y, 0.034), outline)
		if rng.randf() < 0.3:
			kit.box(Vector3(x - 0.02, y, 0.035), Vector3(x + s.x + 0.02, y + s.y, 0.07), STEEL)
	kit.box(Vector3(-1.6, 0.85, -0.05), Vector3(1.6, 0.9, 0.7), STEEL_DARK)
	return []


## A scavenger who did not leave: slumped sitting against the wall, legs toward +Z, coat, pack beside.
static func _body(kit: PropKit, rng: RandomNumberGenerator) -> Array:
	var skin := Color(0.35, 0.3, 0.26)
	# legs
	for x in [-0.14, 0.14]:
		kit.obox(Vector3(x, 0.1, 0.35), Vector3(0.15, 0.15, 0.55), Color(0.2, 0.22, 0.2), Basis(Vector3.UP, x * 0.8))
		kit.obox(Vector3(x * 1.3, 0.08, 0.8), Vector3(0.14, 0.14, 0.45), Color(0.2, 0.22, 0.2), Basis(Vector3.UP, x * 1.5))
		kit.box(Vector3(x * 1.4 - 0.07, 0.0, 1.0), Vector3(x * 1.4 + 0.07, 0.15, 1.15), BLACK)
	# torso leaning back on the wall
	var tb := Basis(Vector3.RIGHT, -0.35)
	kit.obox(Vector3(0, 0.45, 0.05), Vector3(0.48, 0.65, 0.28), COAT, tb)
	kit.obox(Vector3(0, 0.15, 0.2), Vector3(0.55, 0.25, 0.5), COAT.darkened(0.1))    # coat skirt
	# arms
	kit.obox(Vector3(-0.3, 0.35, 0.25), Vector3(0.12, 0.12, 0.5), COAT, Basis(Vector3.UP, 0.2))
	kit.obox(Vector3(0.32, 0.2, 0.3), Vector3(0.12, 0.12, 0.5), COAT, Basis(Vector3.UP, -0.4))
	# head bowed, wrapped
	kit.obox(Vector3(0.05, 0.85, 0.12), Vector3(0.22, 0.24, 0.24), skin.darkened(0.3), Basis(Vector3.RIGHT, 0.5) * Basis(Vector3.FORWARD, 0.2))
	kit.obox(Vector3(0.05, 0.82, 0.14), Vector3(0.26, 0.12, 0.26), CLOTH, Basis(Vector3.RIGHT, 0.5))
	# pack beside him
	kit.obox(Vector3(0.65, 0.25, 0.1), Vector3(0.45, 0.5, 0.3), Color(0.3, 0.33, 0.22), Basis(Vector3.FORWARD, 0.3))
	kit.box(Vector3(-0.9, 0.0, 0.3), Vector3(-0.6, 0.02, 0.6), Color(0.15, 0.12, 0.1))   # stain
	if rng.randf() < 0.5:
		kit.tube(Vector3(-0.7, 0.03, 0.9), Vector3(-0.55, 0.03, 1.0), 0.04, Color(0.25, 0.3, 0.3), 6)   # canteen
	return []


## Dead holo-sign emitter ring: on a floor pedestal (variant 0) or a wall bracket (1, back at -Z).
static func _holo_ring(kit: PropKit, v: int) -> Array:
	var c := Color(0.35, 0.37, 0.38)
	var centre := Vector3(0, 2.4, 0) if v == 0 else Vector3(0, 0, 0.5)
	if v == 0:
		kit.box(Vector3(-0.3, 0, -0.3), Vector3(0.3, 0.15, 0.3), STEEL_DARK)
		kit.box(Vector3(-0.07, 0.15, -0.07), Vector3(0.07, 1.7, 0.07), c)
	else:
		kit.box(Vector3(-0.2, -0.2, 0.0), Vector3(0.2, 0.2, 0.1), STEEL_DARK)
		kit.box(Vector3(-0.05, -0.05, 0.1), Vector3(0.05, 0.05, 0.4), c)
	var n := 12
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := centre + Vector3(cos(a0), sin(a0), 0) * 0.7
		var p1 := centre + Vector3(cos(a1), sin(a1), 0) * 0.7
		kit.tube(p0, p1, 0.06, c, 5)
	for i in 3:
		var a := TAU * i / 3.0
		kit.box(centre + Vector3(cos(a), sin(a), 0) * 0.7 - Vector3(0.06, 0.06, 0.08), centre + Vector3(cos(a), sin(a), 0) * 0.7 + Vector3(0.06, 0.06, 0.08), Color(0.12, 0.18, 0.22))
	if v == 0:
		kit.tube(Vector3(0, 1.7, 0), centre + Vector3(0, -0.7, 0), 0.05, c, 5)
		return [[Vector3(0, 0.85, 0), Vector3(0.3, 1.7, 0.3)]]
	return []


static func _cone(kit: PropKit, v: int) -> Array:
	var xf := Transform3D.IDENTITY if v == 0 else Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0.17, 0))
	kit.box(Vector3(-0.2, 0, -0.2), Vector3(0.2, 0.04, 0.2), Color(0.7, 0.32, 0.1), xf)
	kit.tube(Vector3(0, 0.04, 0), Vector3(0, 0.7, 0), 0.16, Color(0.78, 0.36, 0.12), 6, xf, true, null, 0.03)
	kit.tube(Vector3(0, 0.35, 0), Vector3(0, 0.45, 0), 0.115, Color(0.8, 0.8, 0.78), 6, xf, false, null, 0.095)
	return []


static func _bollard(kit: PropKit) -> Array:
	kit.tube(Vector3(0, 0, 0), Vector3(0, 1.0, 0), 0.11, SAFETY_YELLOW.darkened(0.15), 8)
	kit.tube(Vector3(0, 0.75, 0), Vector3(0, 0.85, 0), 0.115, BLACK, 8)
	return [[Vector3(0, 0.5, 0), Vector3(0.22, 1.0, 0.22)]]


static func _papers(kit: PropKit, sz: Vector3, rng: RandomNumberGenerator) -> Array:
	var n := int(clampf(sz.x * sz.z * 4.0, 4.0, 18.0))
	for i in n:
		var p := Vector3(rng.randf_range(-0.5, 0.5) * sz.x, 0.004 + i * 0.001, rng.randf_range(-0.5, 0.5) * sz.z)
		kit.obox(p, Vector3(0.21, 0.002, 0.3), Color(0.78, 0.76, 0.68).darkened(rng.randf() * 0.35), Basis(Vector3.UP, rng.randf() * 3.0), Transform3D.IDENTITY, false)
	return []


static func _cans(kit: PropKit, rng: RandomNumberGenerator) -> Array:
	for i in 6:
		var p := Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
		var c: Color = [Color(0.5, 0.15, 0.1), Color(0.6, 0.6, 0.58), Color(0.2, 0.35, 0.2), Color(0.3, 0.25, 0.15)][i % 4]
		if rng.randf() < 0.5:
			kit.tube(p, p + Vector3(0, 0.12, 0), 0.035, c, 6)
		else:
			var d := Vector3(cos(rng.randf() * 6.0), 0, sin(rng.randf() * 6.0)) * 0.12
			kit.tube(p + Vector3(0, 0.035, 0), p + d + Vector3(0, 0.035, 0), 0.035, c, 6)
	return []


## Tarp lean-to: a sheet from a line `size.y` up down to the floor `size.z` out, `size.x` long, pegged.
static func _tarp(kit: PropKit, sz: Vector3, v: int) -> Array:
	var c: Color = [Color(0.22, 0.30, 0.36), Color(0.30, 0.32, 0.22), Color(0.45, 0.30, 0.18)][v % 3]
	var hx := sz.x * 0.5
	kit.quad(Vector3(-hx, sz.y, 0), Vector3(hx, sz.y, 0), Vector3(hx, 0.05, sz.z), Vector3(-hx, 0.05, sz.z), c)
	kit.quad(Vector3(hx, sz.y, 0), Vector3(-hx, sz.y, 0), Vector3(-hx, 0.05, sz.z), Vector3(hx, 0.05, sz.z), c.darkened(0.35))
	kit.tube(Vector3(-hx - 0.3, sz.y + 0.02, 0), Vector3(hx + 0.3, sz.y + 0.02, 0), 0.01, BLACK, 3)
	for x in [-hx, hx]:
		kit.tube(Vector3(x, 0, -0.05), Vector3(x, sz.y + 0.1, 0), 0.03, WOOD, 4)
	return []


# -- signage + light --------------------------------------------------------------------------

## Wall paint text facing +Z: `text`, font pixel = size.x, colour by variant (white, yellow, black, red).
## Origin = bottom-left of the text.
static func _stencil(kit: PropKit, t: String, sz: Vector3, v: int) -> Array:
	var c: Color = [Color(0.80, 0.78, 0.72), SAFETY_YELLOW.darkened(0.1), Color(0.1, 0.1, 0.1), FIRE_RED][v % 4]
	Hub2PieceBuild.paint_text(kit, t, Vector3.ZERO, Vector3.RIGHT, Vector3.UP, maxf(sz.x, 0.02), c)
	return []


## Spray tags facing +Z, origin centre. variant: 0 arrow (pointing +X), 1 X, 2 skull, 3 tally (state
## marks), 4 circle-dot camp mark, 5 text. state = colour. size.x = scale (1 = ~1 m).
static func _tag(kit: PropKit, v: int, st: int, sz: Vector3, t: String, rng: RandomNumberGenerator) -> Array:
	var c: Color = SPRAY[st % SPRAY.size()]
	var s := maxf(sz.x, 0.1)
	var w := 0.09 * s
	var stroke := func(a: Vector2, b: Vector2) -> void:
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x) * w * 0.5
		var a3 := Vector3(a.x + nrm.x, a.y + nrm.y, 0.006) * s
		var b3 := Vector3(b.x + nrm.x, b.y + nrm.y, 0.006) * s
		var c3 := Vector3(b.x - nrm.x, b.y - nrm.y, 0.006) * s
		var d3 := Vector3(a.x - nrm.x, a.y - nrm.y, 0.006) * s
		kit.quad(d3, c3, b3, a3, c, Transform3D.IDENTITY, false)
		# a drip now and then
		if rng.randf() < 0.3:
			var dp := Vector3(b.x, b.y, 0.007) * s
			kit.quad(dp + Vector3(-0.008, -0.12 * s, 0), dp + Vector3(0.008, -0.12 * s, 0), dp + Vector3(0.008, 0, 0), dp + Vector3(-0.008, 0, 0), c, Transform3D.IDENTITY, false)
	match v:
		0:
			stroke.call(Vector2(-0.5, 0), Vector2(0.45, 0))
			stroke.call(Vector2(0.2, 0.25), Vector2(0.5, 0))
			stroke.call(Vector2(0.2, -0.25), Vector2(0.5, 0))
		1:
			stroke.call(Vector2(-0.35, -0.35), Vector2(0.35, 0.35))
			stroke.call(Vector2(-0.35, 0.35), Vector2(0.35, -0.35))
		2:
			var n := 10
			for i in n:
				var a0 := TAU * i / n
				var a1 := TAU * (i + 1) / n
				stroke.call(Vector2(cos(a0) * 0.3, 0.1 + sin(a0) * 0.3), Vector2(cos(a1) * 0.3, 0.1 + sin(a1) * 0.3))
			stroke.call(Vector2(-0.14, 0.12), Vector2(-0.06, 0.12))
			stroke.call(Vector2(0.06, 0.12), Vector2(0.14, 0.12))
			stroke.call(Vector2(-0.12, -0.2), Vector2(-0.12, -0.38))
			stroke.call(Vector2(0.0, -0.2), Vector2(0.0, -0.38))
			stroke.call(Vector2(0.12, -0.2), Vector2(0.12, -0.38))
			stroke.call(Vector2(-0.4, -0.5), Vector2(0.4, -0.75))
			stroke.call(Vector2(0.4, -0.5), Vector2(-0.4, -0.75))
		3:
			var marks := maxi(st, 1) + 3
			for i in marks:
				var x := -0.4 + (i % 5) * 0.16 + floori(i / 5.0) * 0.9
				if i % 5 == 4:
					stroke.call(Vector2(x - 0.7, -0.25), Vector2(x - 0.05, 0.25))
				else:
					stroke.call(Vector2(x, -0.3), Vector2(x + 0.02, 0.3))
		4:
			var n2 := 10
			for i in n2:
				var a0 := TAU * i / n2
				var a1 := TAU * (i + 1) / n2
				stroke.call(Vector2(cos(a0) * 0.4, sin(a0) * 0.4), Vector2(cos(a1) * 0.4, sin(a1) * 0.4))
			stroke.call(Vector2(-0.05, 0), Vector2(0.05, 0))
		5:
			Hub2PieceBuild.paint_text(kit, t, Vector3(-Hub2PieceBuild.text_width(t, 0.06 * s) * 0.5, -0.15 * s, 0.0), Vector3.RIGHT, Vector3.UP, 0.06 * s, c)
	return []


## Bay number on the floor (facing up, reads from +Z). Lit = a projected number in cold cyan (glow).
static func _bay_number(kit: PropKit, t: String, sz: Vector3, p: bool) -> Array:
	var px := maxf(sz.x, 0.1)
	var w := Hub2PieceBuild.text_width(t, px)
	var origin := Vector3(-w * 0.5, 0.012, px * 2.5)
	if p:
		var sst := _glow(kit, Color(0.35, 0.85, 1.0))
		var o := origin
		var cx := 0.0
		for ch in t.to_upper():
			var g: Array = Hub2PieceBuild.FONT.get(ch, Hub2PieceBuild.FONT[" "])
			for row in 5:
				var line: String = g[row]
				for ci in 3:
					if line[ci] == "#":
						var a := o + Vector3(cx + ci * px, 0, -(4 - row) * px)
						kit.quad(a, a + Vector3(px * 0.9, 0, 0), a + Vector3(px * 0.9, 0, -px * 0.9), a + Vector3(0, 0, -px * 0.9), Color.WHITE, Transform3D.IDENTITY, false, sst)
			cx += 4.0 * px
	else:
		Hub2PieceBuild.paint_text(kit, t, origin, Vector3.RIGHT, Vector3.FORWARD, px, SAFETY_YELLOW.darkened(0.35))
	return []


## LED strip `size.x` long along X on a wall/ceiling (faces +Z); lit = some segments glow, some dead.
static func _led_strip(kit: PropKit, sz: Vector3, p: bool, rng: RandomNumberGenerator) -> Array:
	var n := maxi(int(sz.x / 0.6), 1)
	kit.box(Vector3(-sz.x * 0.5, -0.06, 0.0), Vector3(sz.x * 0.5, 0.06, 0.04), STEEL_DARK)
	for i in n:
		var x0 := -sz.x * 0.5 + i * (sz.x / n) + 0.03
		var x1 := x0 + sz.x / n - 0.06
		if p and rng.randf() < 0.55:
			kit.box(Vector3(x0, -0.035, 0.04), Vector3(x1, 0.035, 0.06), Color.WHITE, Transform3D.IDENTITY, false, _glow(kit, Color(0.8, 0.92, 1.0)))
		else:
			kit.box(Vector3(x0, -0.035, 0.04), Vector3(x1, 0.035, 0.05), Color(0.25, 0.27, 0.28))
	return []


## Door keypad (faces +Z), variant 0 dark, 1 smashed with wires out.
static func _keypad(kit: PropKit, v: int) -> Array:
	kit.box(Vector3(-0.09, -0.15, 0), Vector3(0.09, 0.15, 0.05), Color(0.28, 0.29, 0.3))
	kit.box(Vector3(-0.07, 0.05, 0.05), Vector3(0.07, 0.12, 0.055), GLASS)
	if v == 0:
		for r in 4:
			for c in 3:
				kit.box(Vector3(-0.06 + c * 0.045, -0.12 + r * 0.04, 0.05), Vector3(-0.03 + c * 0.045, -0.095 + r * 0.04, 0.06), Color(0.15, 0.15, 0.15))
	else:
		kit.box(Vector3(-0.08, -0.14, 0.02), Vector3(0.08, 0.02, 0.03), BLACK)
		for i in 3:
			kit.tube(Vector3(-0.03 + i * 0.03, -0.05, 0.03), Vector3(-0.08 + i * 0.06, -0.3, 0.12), 0.006, [FIRE_RED, SAFETY_YELLOW, Color(0.1, 0.3, 0.6)][i], 3)
	return []


## Emergency lamp on its battery circuit, wall-mounted, faces +Z. variant 0 red caged, 1 amber caged,
## 2 red beacon dome, 3 amber beacon dome. Lit = glowing lens.
static func _emergency_lamp(kit: PropKit, v: int, p: bool) -> Array:
	var col := Color(1.0, 0.12, 0.06) if v % 2 == 0 else Color(1.0, 0.55, 0.1)
	var dead := col.darkened(0.75)
	kit.box(Vector3(-0.18, -0.18, 0), Vector3(0.18, 0.18, 0.08), STEEL_DARK)
	if v < 2:
		if p:
			kit.box(Vector3(-0.13, -0.1, 0.08), Vector3(0.13, 0.1, 0.2), Color.WHITE, Transform3D.IDENTITY, false, _glow(kit, col))
		else:
			kit.box(Vector3(-0.13, -0.1, 0.08), Vector3(0.13, 0.1, 0.18), dead)
		for i in 3:
			var x := -0.12 + i * 0.12
			kit.box(Vector3(x - 0.01, -0.12, 0.08), Vector3(x + 0.01, 0.12, 0.23), STEEL_DARK)
	else:
		kit.box(Vector3(-0.1, -0.1, 0.08), Vector3(0.1, 0.1, 0.12), STEEL_DARK)
		if p:
			kit.tube(Vector3(0, 0, 0.12), Vector3(0, 0, 0.32), 0.1, Color.WHITE, 8, Transform3D.IDENTITY, true, _glow(kit, col), 0.06)
		else:
			kit.tube(Vector3(0, 0, 0.12), Vector3(0, 0, 0.3), 0.1, dead, 8, Transform3D.IDENTITY, true, null, 0.06)
	return []


## Standing water: an irregular dark sheen size.x x size.z, a hair above the floor.
static func _puddle(kit: PropKit, sz: Vector3, rng: RandomNumberGenerator) -> Array:
	var n := 10
	var pts: Array[Vector3] = []
	for i in n:
		var a := TAU * i / n
		var r := rng.randf_range(0.7, 1.0)
		pts.append(Vector3(cos(a) * sz.x * 0.5 * r, 0.008, sin(a) * sz.z * 0.5 * r))
	var c := Vector3(0, 0.008, 0)
	for i in n:
		var j := (i + 1) % n
		kit.quad(c, pts[j], pts[j] * 1.06 + Vector3(0, 0.0005, 0), c, WATER.lerp(Color(0.2, 0.24, 0.26), 0.2), Transform3D.IDENTITY, false)
		kit.tri(c, pts[i], pts[j], WATER, Transform3D.IDENTITY)
	return []


## Water stain running down a wall (faces +Z), size.x wide, size.y tall, from the origin down.
static func _stain(kit: PropKit, sz: Vector3, rng: RandomNumberGenerator) -> Array:
	var n := maxi(int(sz.x / 0.25), 1)
	for i in n:
		var x := -sz.x * 0.5 + (i + 0.5) * (sz.x / n)
		var ln := sz.y * rng.randf_range(0.4, 1.0)
		var w := rng.randf_range(0.08, 0.22)
		kit.quad(Vector3(x - w, -ln, 0.004), Vector3(x + w, -ln, 0.004), Vector3(x + w * 1.4, 0, 0.004), Vector3(x - w * 1.4, 0, 0.004),
			Color(0.16, 0.15, 0.13).lerp(Color(0.3, 0.18, 0.1), rng.randf() * 0.5), Transform3D.IDENTITY, false)
	return []


# -- structure --------------------------------------------------------------------------------

## Guard rail `size.x` long along X, 1.1 m high, posts every ~1.5 m. variant 1 = a bent / missing
## section in the middle (no collision there).
static func _railing(kit: PropKit, sz: Vector3, v: int, rng: RandomNumberGenerator) -> Array:
	var half := sz.x * 0.5
	var c := SAFETY_YELLOW.darkened(0.2)
	var gap_a := INF
	var gap_b := -INF
	if v == 1:
		var m := rng.randf_range(-half * 0.4, half * 0.4)
		gap_a = m - 1.2
		gap_b = m + 1.2
	var n := maxi(int(sz.x / 1.5), 1)
	for i in n + 1:
		var x := -half + i * (sz.x / n)
		if x > gap_a and x < gap_b:
			continue
		kit.box(Vector3(x - 0.04, 0, -0.04), Vector3(x + 0.04, 1.1, 0.04), c)
	for y in [0.55, 1.07]:
		if v == 1:
			kit.box(Vector3(-half, y - 0.03, -0.03), Vector3(gap_a, y + 0.03, 0.03), c)
			kit.box(Vector3(gap_b, y - 0.03, -0.03), Vector3(half, y + 0.03, 0.03), c)
			# the bent end hanging down
			kit.tube(Vector3(gap_a, y, 0), Vector3(gap_a + 0.8, y - 0.9, 0.3), 0.03, c, 4)
		else:
			kit.box(Vector3(-half, y - 0.03, -0.03), Vector3(half, y + 0.03, 0.03), c)
	kit.box(Vector3(-half, 0.0, -0.02), Vector3(half if v == 0 else gap_a, 0.12, 0.02), c.darkened(0.2))
	if v == 1:
		kit.box(Vector3(gap_b, 0.0, -0.02), Vector3(half, 0.12, 0.02), c.darkened(0.2))
		return [[Vector3((-half + gap_a) * 0.5, 0.6, 0), Vector3(gap_a + half, 1.2, 0.12)], [Vector3((gap_b + half) * 0.5, 0.6, 0), Vector3(half - gap_b, 1.2, 0.12)]]
	return [[Vector3(0, 0.6, 0), Vector3(sz.x, 1.2, 0.12)]]


## Steel stair: `size.x` wide, rising `size.y` over `size.z` toward +Z from the origin (bottom front
## centre). Stringers, treads, handrails both sides. Collision: one sloped box + rails.
static func _stair(kit: PropKit, sz: Vector3) -> Array:
	var hw := sz.x * 0.5
	var steps := maxi(int(sz.y / 0.2), 1)
	var rise := sz.y / steps
	var run := sz.z / steps
	var c := Color(0.30, 0.31, 0.32)
	var slope := atan2(sz.y, sz.z)
	var ln := Vector2(sz.z, sz.y).length()
	for side in [-1.0, 1.0]:
		var x: float = hw * side
		kit.obox(Vector3(x, sz.y * 0.5 - 0.1, sz.z * 0.5), Vector3(0.08, 0.3, ln), c, Basis(Vector3.RIGHT, -slope))
		# handrail + posts
		kit.obox(Vector3(x, sz.y * 0.5 + 1.0, sz.z * 0.5), Vector3(0.05, 0.05, ln), SAFETY_YELLOW.darkened(0.25), Basis(Vector3.RIGHT, -slope))
		for i in 4:
			var t := (i + 0.5) / 4.0
			kit.box(Vector3(x - 0.025, sz.y * t, sz.z * t - 0.025), Vector3(x + 0.025, sz.y * t + 1.0, sz.z * t + 0.025), SAFETY_YELLOW.darkened(0.25))
	for i in steps:
		var y := (i + 1) * rise
		var z := i * run
		kit.box(Vector3(-hw, y - 0.04, z), Vector3(hw, y, z + run + 0.02), c.lightened(0.1))
		kit.box(Vector3(-hw, y - 0.04, z), Vector3(hw, y - 0.01, z + 0.03), SAFETY_YELLOW.darkened(0.3))
	var mid := Vector3(0, sz.y * 0.5 - 0.15, sz.z * 0.5)
	var b := Basis(Vector3.RIGHT, -slope)
	return [[mid, Vector3(sz.x, 0.3, ln), b],
		[Vector3(-hw - 0.05, sz.y * 0.5 + 0.6, sz.z * 0.5), Vector3(0.1, 1.2, ln), b],
		[Vector3(hw + 0.05, sz.y * 0.5 + 0.6, sz.z * 0.5), Vector3(0.1, 1.2, ln), b]]


## Grated steel deck size.x x size.z, top at size.y above the origin, on legs, with a kick plate.
static func _deck(kit: PropKit, sz: Vector3) -> Array:
	var hx := sz.x * 0.5
	var hz := sz.z * 0.5
	var c := Color(0.30, 0.31, 0.32)
	kit.box(Vector3(-hx, sz.y - 0.12, -hz), Vector3(hx, sz.y, hz), c)
	var n := int(sz.x / 0.3)
	for i in n:
		var x := -hx + i * 0.3 + 0.1
		kit.box(Vector3(x, sz.y, -hz), Vector3(x + 0.04, sz.y + 0.005, hz), c.darkened(0.3))
	for x in [-hx + 0.1, hx - 0.1]:
		for z in [-hz + 0.1, hz - 0.1]:
			kit.box(Vector3(x - 0.08, 0, z - 0.08), Vector3(x + 0.08, sz.y - 0.12, z + 0.08), STEEL_DARK)
	return [[Vector3(0, sz.y - 0.06, 0), Vector3(sz.x, 0.12, sz.z)]]


## Prefab site cabin 6.0 x 2.5 x 2.9 (along X, front +Z), walk-in. variant: 0 office (door left,
## two windows), 1 locker/break (door centre, one window), 2 store (no window). state 1 = window
## glass gone. The door itself is a separate Hub2Door in the gap (x -1.6..-0.6 or -0.5..0.5).
static func _cabin(kit: PropKit, v: int, st: int, rng: RandomNumberGenerator) -> Array:
	var c: Color = [Color(0.62, 0.62, 0.58), Color(0.45, 0.52, 0.55), Color(0.55, 0.5, 0.38)][v % 3]
	var L := 3.0
	var W := 1.25
	var H := 2.9
	kit.cell = 0.9
	var door := Vector2(-1.7, -0.5) if v == 0 else Vector2(-0.6, 0.6)
	kit.box(Vector3(-L, 0, -W), Vector3(L, 0.2, W), STEEL_DARK)                        # skid floor
	kit.box(Vector3(-L + 0.05, 0.2, -W + 0.05), Vector3(L - 0.05, 0.22, W - 0.05), Color(0.3, 0.28, 0.25))
	kit.box(Vector3(-L, H - 0.15, -W), Vector3(L, H, W), c.darkened(0.15))             # roof
	kit.box(Vector3(-L, 0.2, -W), Vector3(L, H - 0.15, -W + 0.08), c)                    # back
	kit.box(Vector3(-L, 0.2, -W), Vector3(-L + 0.08, H - 0.15, W), c)                    # ends
	kit.box(Vector3(L - 0.08, 0.2, -W), Vector3(L, H - 0.15, W), c)
	# front wall with the door gap and windows
	var wins: Array = []
	if v == 0:
		wins = [Vector2(0.0, 1.2), Vector2(1.6, 2.6)]
	elif v == 1:
		wins = [Vector2(1.2, 2.2)]
	kit.box(Vector3(-L, 0.2, W - 0.08), Vector3(door.x, H - 0.15, W), c)
	kit.box(Vector3(door.x, 2.3, W - 0.08), Vector3(door.y, H - 0.15, W), c)
	# right of the door: wall broken by windows
	var cursor := door.y
	for wv: Vector2 in wins:
		kit.box(Vector3(cursor, 0.2, W - 0.08), Vector3(wv.x, H - 0.15, W), c)
		kit.box(Vector3(wv.x, 0.2, W - 0.08), Vector3(wv.y, 1.1, W), c)
		kit.box(Vector3(wv.x, 2.1, W - 0.08), Vector3(wv.y, H - 0.15, W), c)
		if st != 1 and rng.randf() < 0.7:
			kit.box(Vector3(wv.x, 1.1, W - 0.05), Vector3(wv.y, 2.1, W - 0.03), GLASS.lerp(Color(0.25, 0.3, 0.32), 0.3))
		else:
			kit.tri(Vector3(wv.x, 1.1, W - 0.04), Vector3(wv.x + 0.4, 1.1, W - 0.04), Vector3(wv.x, 1.6, W - 0.04), Color(0.3, 0.36, 0.38))
		cursor = wv.y
	kit.box(Vector3(cursor, 0.2, W - 0.08), Vector3(L, H - 0.15, W), c)
	# trim + stencil
	kit.box(Vector3(-L, H - 0.35, W), Vector3(L, H - 0.3, W + 0.02), c.darkened(0.3))
	var label: String = ["SITE OFFICE", "CREW", "STORE"][v % 3]
	Hub2PieceBuild.paint_text(kit, label, Vector3(-L + 0.3, H - 0.65, W + 0.01), Vector3.RIGHT, Vector3.UP, 0.05, Color(0.15, 0.15, 0.15))
	Hub2PieceBuild.paint_text(kit, "KADE", Vector3(L - 1.1, H - 0.65, W + 0.01), Vector3.RIGHT, Vector3.UP, 0.05, OPERATOR)
	var boxes: Array = [
		[Vector3(0, 0.1, 0), Vector3(2 * L, 0.2, 2 * W)], [Vector3(0, H - 0.075, 0), Vector3(2 * L, 0.15, 2 * W)],
		[Vector3(0, H * 0.5, -W + 0.04), Vector3(2 * L, H, 0.08)],
		[Vector3(-L + 0.04, H * 0.5, 0), Vector3(0.08, H, 2 * W)], [Vector3(L - 0.04, H * 0.5, 0), Vector3(0.08, H, 2 * W)],
		[Vector3((-L + door.x) * 0.5, H * 0.5, W - 0.04), Vector3(door.x + L, H, 0.08)],
		[Vector3((door.y + L) * 0.5, H * 0.5, W - 0.04), Vector3(L - door.y, H, 0.08)],
		[Vector3((door.x + door.y) * 0.5, (2.3 + H) * 0.5, W - 0.04), Vector3(door.y - door.x, H - 2.3, 0.08)],
	]
	return boxes


## Open steel shed: four posts + a corrugated roof `size.x` x `size.z` at `size.y`, a back sheet wall (-Z).
static func _shed(kit: PropKit, sz: Vector3) -> Array:
	var hx := sz.x * 0.5
	var hz := sz.z * 0.5
	var c := Color(0.38, 0.40, 0.42)
	for x in [-hx, hx - 0.25]:
		for z in [-hz, hz - 0.25]:
			kit.box(Vector3(x, 0, z), Vector3(x + 0.25, sz.y, z + 0.25), SAFETY_YELLOW.darkened(0.35))
	kit.box(Vector3(-hx - 0.3, sz.y, -hz - 0.3), Vector3(hx + 0.3, sz.y + 0.15, hz + 0.3), c)
	var n := int(sz.x / 0.3)
	for i in n:
		var x := -hx + i * 0.3
		kit.box(Vector3(x, 0.3, -hz), Vector3(x + 0.3, sz.y, -hz + 0.05 + (0.03 if i % 2 == 0 else 0.0)), c.darkened(0.08 * (i % 2)))
	return [[Vector3(0, sz.y + 0.075, 0), Vector3(sz.x + 0.6, 0.15, sz.z + 0.6)], [Vector3(0, sz.y * 0.5, -hz + 0.05), Vector3(sz.x, sz.y, 0.1)],
		[Vector3(-hx + 0.125, sz.y * 0.5, hz - 0.125), Vector3(0.25, sz.y, 0.25)], [Vector3(hx - 0.125, sz.y * 0.5, hz - 0.125), Vector3(0.25, sz.y, 0.25)]]


## Mesh fence panel `size.x` long, 2.4 m high. variant 1 = a gate frame in the middle (2 m opening).
static func _fence(kit: PropKit, sz: Vector3, v: int) -> Array:
	var half := sz.x * 0.5
	var c := Color(0.36, 0.38, 0.38)
	var h := 2.4
	var gap := Vector2(INF, -INF) if v == 0 else Vector2(-1.0, 1.0)
	var n := maxi(int(sz.x / 2.5), 1)
	for i in n + 1:
		var x := -half + i * (sz.x / n)
		kit.box(Vector3(x - 0.04, 0, -0.04), Vector3(x + 0.04, h, 0.04), c)
	for y in [0.05, h - 0.05]:
		kit.box(Vector3(-half, y - 0.03, -0.02), Vector3(half, y + 0.03, 0.02), c)
	# mesh as a diagonal lattice of thin strips
	var m := int(sz.x / 0.3)
	for i in m:
		var x := -half + i * 0.3
		if x > gap.x - 0.2 and x < gap.y:
			continue
		kit.quad(Vector3(x, 0.05, 0.005), Vector3(x + 0.025, 0.05, 0.005), Vector3(x + 0.3 + 0.025, h - 0.05, 0.005), Vector3(x + 0.3, h - 0.05, 0.005), c.darkened(0.25), Transform3D.IDENTITY, false)
		kit.quad(Vector3(x + 0.3, 0.05, -0.005), Vector3(x + 0.325, 0.05, -0.005), Vector3(x + 0.025, h - 0.05, -0.005), Vector3(x, h - 0.05, -0.005), c.darkened(0.25), Transform3D.IDENTITY, false)
	if v == 1:
		for x in [gap.x, gap.y]:
			kit.box(Vector3(x - 0.06, 0, -0.06), Vector3(x + 0.06, h + 0.2, 0.06), c)
		kit.box(Vector3(gap.x, h + 0.1, -0.04), Vector3(gap.y, h + 0.2, 0.04), c)
		return [[Vector3((-half + gap.x) * 0.5, h * 0.5, 0), Vector3(gap.x + half, h, 0.1)], [Vector3((gap.y + half) * 0.5, h * 0.5, 0), Vector3(half - gap.y, h, 0.1)]]
	return [[Vector3(0, h * 0.5, 0), Vector3(sz.x, h, 0.1)]]


## Roll-up shutter `size.x` wide x `size.y` high set in a frame (faces +Z, origin bottom centre on the
## wall face). state 0 closed, 1 buckled (bowed out, one corner torn up), 2 half open (dark behind).
static func _shutter(kit: PropKit, sz: Vector3, st: int, t: String, _rng: RandomNumberGenerator) -> Array:
	var hw := sz.x * 0.5
	var h := sz.y
	var c := Color(0.48, 0.50, 0.50)
	kit.cell = 1.0
	kit.box(Vector3(-hw - 0.4, 0, -0.1), Vector3(-hw, h + 0.6, 0.25), SAFETY_YELLOW.darkened(0.3))
	kit.box(Vector3(hw, 0, -0.1), Vector3(hw + 0.4, h + 0.6, 0.25), SAFETY_YELLOW.darkened(0.3))
	kit.box(Vector3(-hw - 0.4, h, -0.1), Vector3(hw + 0.4, h + 0.9, 0.5), STEEL_DARK)   # roll box
	var bottom := 0.0 if st != 2 else h * 0.5
	kit.box(Vector3(-hw, 0, -0.1), Vector3(hw, h, -0.05), BLACK)                           # dark behind
	var slats := int((h - bottom) / 0.25)
	for i in slats:
		var y := bottom + i * 0.25
		var bow := 0.0
		if st == 1:
			bow = sin(PI * clampf(y / h, 0.0, 1.0)) * 0.35
		var x0 := -hw
		if st == 1 and y < 1.2:
			x0 = -hw + (1.2 - y) * 1.4    # torn up corner
		kit.box(Vector3(x0, y, bow), Vector3(hw, y + 0.23, bow + 0.06), c if i % 2 == 0 else c.darkened(0.08))
	kit.box(Vector3(-hw, bottom, 0.02), Vector3(hw, bottom + 0.12, 0.12), SAFETY_YELLOW.darkened(0.2))
	if t != "":
		Hub2PieceBuild.paint_text(kit, t, Vector3(-Hub2PieceBuild.text_width(t, 0.12) * 0.5, h * 0.62, 0.07), Vector3.RIGHT, Vector3.UP, 0.12, Color(0.85, 0.85, 0.8))
	var boxes: Array = [[Vector3(0, (bottom + h) * 0.5, 0.0), Vector3(sz.x, h - bottom, 0.2)]]
	if st == 1:
		boxes = [[Vector3(0.6, (1.2 + h) * 0.5, 0.0), Vector3(sz.x - 1.2, h - 1.2, 0.2)]]
	return boxes


## A wall that fills a corridor opening `size.x` wide x `size.y` high (faces +Z, 0.3 thick, origin
## bottom centre), with a doorway `size.z` metres off-centre. variant: 0 personnel door (1.2 x 2.3),
## 1 shutter (4.2 x 4.4), 2 blast door frame (width - 1.6 x height - 1.0, hazard stripes),
## 3 sealed (welded plates, no opening). The door itself is a Hub2Door.
static func _bulkhead(kit: PropKit, sz: Vector3, v: int, t: String) -> Array:
	var hw := sz.x * 0.5
	var h := sz.y
	var c := Color(0.40, 0.42, 0.43)
	kit.cell = 1.0
	var dw: float = [1.2, 4.2, sz.x - 1.6, 0.0][v % 4]
	var dh: float = [2.3, 4.4, h - 1.0, 0.0][v % 4]
	dh = minf(dh, h - 0.4)
	var cx := sz.z
	var dl := cx - dw * 0.5
	var dr := cx + dw * 0.5
	var boxes: Array = []
	if v == 3:
		kit.box(Vector3(-hw, 0, -0.15), Vector3(hw, h, 0.15), c.darkened(0.1))
		for i in int(sz.x / 1.5):
			var x := -hw + i * 1.5
			kit.box(Vector3(x, 0, 0.15), Vector3(x + 0.06, h, 0.19), Color(0.3, 0.22, 0.15))   # weld seams
		boxes.append([Vector3(0, h * 0.5, 0), Vector3(sz.x, h, 0.3)])
	else:
		kit.box(Vector3(-hw, 0, -0.15), Vector3(dl, h, 0.15), c)
		kit.box(Vector3(dr, 0, -0.15), Vector3(hw, h, 0.15), c)
		kit.box(Vector3(dl, dh, -0.15), Vector3(dr, h, 0.15), c)
		boxes.append([Vector3((-hw + dl) * 0.5, h * 0.5, 0), Vector3(dl + hw, h, 0.3)])
		boxes.append([Vector3((dr + hw) * 0.5, h * 0.5, 0), Vector3(hw - dr, h, 0.3)])
		boxes.append([Vector3(cx, (dh + h) * 0.5, 0), Vector3(dw, h - dh, 0.3)])
		# frame trim
		var trim := STEEL_DARK if v != 2 else SAFETY_YELLOW.darkened(0.15)
		for side in [-1.0, 1.0]:
			kit.box(Vector3(dl - 0.15, 0, 0.15 * side - 0.05), Vector3(dl, dh + 0.15, 0.15 * side + 0.05), trim)
			kit.box(Vector3(dr, 0, 0.15 * side - 0.05), Vector3(dr + 0.15, dh + 0.15, 0.15 * side + 0.05), trim)
			kit.box(Vector3(dl - 0.15, dh, 0.15 * side - 0.05), Vector3(dr + 0.15, dh + 0.15, 0.15 * side + 0.05), trim)
		if v == 2:
			# hazard chevrons along the lintel
			var n := int((dw + 0.3) / 0.6)
			for i in n:
				var x := dl - 0.15 + i * 0.6
				kit.quad(Vector3(x, dh + 0.15, 0.2), Vector3(x + 0.3, dh + 0.15, 0.2), Vector3(x + 0.6, dh + 0.75, 0.2), Vector3(x + 0.3, dh + 0.75, 0.2), BLACK, Transform3D.IDENTITY, false)
	# panel seams + label
	for i in int(sz.x / 2.0) + 1:
		var x := -hw + i * 2.0
		if x > dl - 0.2 and x < dr + 0.2:
			continue
		kit.box(Vector3(x - 0.02, 0, 0.15), Vector3(x + 0.02, h, 0.17), c.darkened(0.25))
	if t != "":
		var px := 0.08
		Hub2PieceBuild.paint_text(kit, t, Vector3(cx - Hub2PieceBuild.text_width(t, px) * 0.5, minf(dh + 0.4, h - 0.6), 0.16), Vector3.RIGHT, Vector3.UP, px, Color(0.85, 0.83, 0.75))
	return boxes


## Wall ladder `size.y` high with a safety cage above 2.5 m (faces +Z, origin bottom centre on the wall).
static func _ladder(kit: PropKit, sz: Vector3) -> Array:
	var h := sz.y
	var c := SAFETY_YELLOW.darkened(0.3)
	for x in [-0.25, 0.25]:
		kit.box(Vector3(x - 0.03, 0, 0.12), Vector3(x + 0.03, h + 1.0, 0.18), c)
	for i in int(h / 0.3):
		kit.box(Vector3(-0.25, 0.3 + i * 0.3, 0.13), Vector3(0.25, 0.33 + i * 0.3, 0.17), c)
	var y := 2.5
	while y < h + 1.0:
		var n := 7
		for j in n:
			var a0 := PI * j / n
			var a1 := PI * (j + 1) / n
			kit.tube(Vector3(cos(a0) * 0.4, y, 0.15 + sin(a0) * 0.7), Vector3(cos(a1) * 0.4, y, 0.15 + sin(a1) * 0.7), 0.02, c, 3)
		y += 1.2
	return []


## Walk-in cold store built into a wall recess: insulated white panels `size.x` x `size.y` x `size.z`
## (front +Z), doorway 1.4 m left of centre, plastic strip curtain mostly torn down, a reefer unit on
## the roof. Origin bottom centre.
static func _cold_cage(kit: PropKit, sz: Vector3, rng: RandomNumberGenerator) -> Array:
	var hx := sz.x * 0.5
	var hz := sz.z * 0.5
	var h := sz.y
	var c := Color(0.72, 0.73, 0.70)
	kit.cell = 1.0
	var d0 := -1.4 - 0.9
	var d1 := -1.4 + 0.9
	kit.box(Vector3(-hx, 0, -hz), Vector3(hx, 0.15, hz), Color(0.4, 0.42, 0.42))
	kit.box(Vector3(-hx, h, -hz), Vector3(hx, h + 0.2, hz), c)
	kit.box(Vector3(-hx, 0.15, -hz), Vector3(hx, h, -hz + 0.15), c)
	kit.box(Vector3(-hx, 0.15, -hz), Vector3(-hx + 0.15, h, hz), c)
	kit.box(Vector3(hx - 0.15, 0.15, -hz), Vector3(hx, h, hz), c)
	kit.box(Vector3(-hx, 0.15, hz - 0.15), Vector3(d0, h, hz), c)
	kit.box(Vector3(d1, 0.15, hz - 0.15), Vector3(hx, h, hz), c)
	kit.box(Vector3(d0, 2.6, hz - 0.15), Vector3(d1, h, hz), c)
	for i in 6:
		var x := d0 + 0.1 + i * 0.3
		if rng.randf() < 0.4:
			kit.box(Vector3(x, rng.randf_range(0.6, 1.8), hz - 0.05), Vector3(x + 0.22, 2.6, hz - 0.04), Color(0.55, 0.6, 0.55))
	# frost streaks inside, dark interior floor
	kit.box(Vector3(-hx + 0.15, 0.15, -hz + 0.15), Vector3(hx - 0.15, 0.16, hz - 0.15), Color(0.22, 0.23, 0.24))
	kit.box(Vector3(-1.5, h + 0.2, -hz + 0.5), Vector3(1.5, h + 1.4, -hz + 2.0), Color(0.6, 0.62, 0.6))
	for i in 5:
		kit.box(Vector3(-1.3 + i * 0.6, h + 0.4, -hz + 2.0), Vector3(-1.0 + i * 0.6, h + 1.2, -hz + 2.02), STEEL_DARK)
	Hub2PieceBuild.paint_text(kit, "COLD STORE", Vector3(d1 + 0.3, 2.2, hz + 0.01), Vector3.RIGHT, Vector3.UP, 0.06, Color(0.2, 0.3, 0.5))
	return [[Vector3(0, 0.075, 0), Vector3(sz.x, 0.15, sz.z)], [Vector3(0, h + 0.1, 0), Vector3(sz.x, 0.2, sz.z)],
		[Vector3(0, h * 0.5, -hz + 0.075), Vector3(sz.x, h, 0.15)], [Vector3(-hx + 0.075, h * 0.5, 0), Vector3(0.15, h, sz.z)],
		[Vector3(hx - 0.075, h * 0.5, 0), Vector3(0.15, h, sz.z)], [Vector3((-hx + d0) * 0.5, h * 0.5, hz - 0.075), Vector3(d0 + hx, h, 0.15)],
		[Vector3((d1 + hx) * 0.5, h * 0.5, hz - 0.075), Vector3(hx - d1, h, 0.15)], [Vector3((d0 + d1) * 0.5, (2.6 + h) * 0.5, hz - 0.075), Vector3(d1 - d0, h - 2.6, 0.15)]]


## Broken skylight seen from below: a frame grid `size.x` x `size.z` hung at the ceiling (origin =
## ceiling point), most panes gone; lit = pale daylight panes + three stepped light-shaft cards down
## `size.y` metres.
static func _skylight(kit: PropKit, sz: Vector3, p: bool, rng: RandomNumberGenerator) -> Array:
	var hx := sz.x * 0.5
	var hz := sz.z * 0.5
	var c := STEEL_DARK
	for i in int(sz.x / 2.0) + 1:
		var x := -hx + i * 2.0
		kit.box(Vector3(x - 0.08, -0.3, -hz), Vector3(x + 0.08, 0.0, hz), c)
	for i in int(sz.z / 2.0) + 1:
		var z := -hz + i * 2.0
		kit.box(Vector3(-hx, -0.3, z - 0.08), Vector3(hx, 0.0, z + 0.08), c)
	for i in int(sz.x / 2.0):
		for j in int(sz.z / 2.0):
			if rng.randf() < 0.25:
				var x := -hx + i * 2.0 + 0.1
				var z := -hz + j * 2.0 + 0.1
				kit.box(Vector3(x, -0.05, z), Vector3(x + 1.8, -0.02, z + 1.8), Color(0.3, 0.34, 0.36))
	if p:
		var sst := kit.extra_surface(_shaft_material())
		for k in 3:
			var y0 := -0.3 - k * sz.y / 3.0
			var y1 := y0 - sz.y / 3.0
			var s0 := 1.0 + k * 0.08
			var s1 := 1.0 + (k + 1) * 0.08
			for side in [[Vector3(-1, 0, 0), Vector3(0, 0, 1)], [Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, 0, -1), Vector3(-1, 0, 0)], [Vector3(0, 0, 1), Vector3(1, 0, 0)]]:
				var nrm: Vector3 = side[0]
				var along: Vector3 = side[1]
				var ext0 := Vector3(hx, 0, hz) * s0
				var ext1 := Vector3(hx, 0, hz) * s1
				var a := Vector3(nrm.x * ext0.x, y0, nrm.z * ext0.z) - along * (absf(along.x) * ext0.x + absf(along.z) * ext0.z)
				var b2 := Vector3(nrm.x * ext0.x, y0, nrm.z * ext0.z) + along * (absf(along.x) * ext0.x + absf(along.z) * ext0.z)
				var c2 := Vector3(nrm.x * ext1.x, y1, nrm.z * ext1.z) + along * (absf(along.x) * ext1.x + absf(along.z) * ext1.z)
				var d := Vector3(nrm.x * ext1.x, y1, nrm.z * ext1.z) - along * (absf(along.x) * ext1.x + absf(along.z) * ext1.z)
				var shade := Color(1, 1, 1, 0.10 - k * 0.025)
				for q in [[a, b2, c2, d], [b2, a, d, c2]]:
					sst.set_color(shade)
					sst.set_normal(Vector3.UP)
					for idx in [0, 2, 1, 0, 3, 2]:
						sst.set_color(shade)
						sst.add_vertex(q[idx])
	return []


static var _shaft_mat: StandardMaterial3D

static func _shaft_material() -> StandardMaterial3D:
	if _shaft_mat == null:
		_shaft_mat = StandardMaterial3D.new()
		_shaft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shaft_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shaft_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_shaft_mat.vertex_color_use_as_albedo = true
		_shaft_mat.albedo_color = Color(0.75, 0.82, 0.95)
		_shaft_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shaft_mat.no_depth_test = false
	return _shaft_mat


## A big header pipe that fell from its hangers: `size.x` long along X, radius 0.45, lying on two
## bent bracket stands so its top is ~1.0 m up; one end burst open, flange on the other. Vaultable.
static func _pipe_fallen(kit: PropKit, sz: Vector3, rng: RandomNumberGenerator) -> Array:
	var half := sz.x * 0.5
	var r := 0.42
	var y := 1.0 - r
	var c := Color(0.36, 0.44, 0.38)
	kit.tube(Vector3(-half, y, 0), Vector3(half - 0.4, y, 0), r, c, 8)
	kit.tube(Vector3(-half - 0.05, y, 0), Vector3(-half + 0.1, y, 0), r + 0.1, STEEL_DARK, 8)
	# burst end: torn petals
	for i in 5:
		var a := TAU * i / 5.0 + rng.randf() * 0.4
		var o := Vector3(0, cos(a), sin(a)) * r
		kit.tri(Vector3(half - 0.4, y, 0) + o, Vector3(half - 0.4, y, 0) + o.rotated(Vector3.RIGHT, 0.6), Vector3(half + rng.randf_range(0.1, 0.5), y, 0) + o * 1.5, c.darkened(0.2))
		kit.tri(Vector3(half - 0.4, y, 0) + o.rotated(Vector3.RIGHT, 0.6), Vector3(half - 0.4, y, 0) + o, Vector3(half + rng.randf_range(0.1, 0.5), y, 0) + o * 1.5, c.darkened(0.3))
	for x in [-half * 0.55, half * 0.45]:
		kit.box(Vector3(x - 0.08, 0, -0.5), Vector3(x + 0.08, y - r * 0.6, 0.5), STEEL_DARK, Transform3D(Basis(Vector3.RIGHT, rng.randf_range(-0.15, 0.15)), Vector3.ZERO))
		kit.box(Vector3(x - 0.08, y - r * 0.7, -r), Vector3(x + 0.08, y - r * 0.5, r), STEEL_DARK)
	return [[Vector3(0, 0.5, 0), Vector3(sz.x, 1.0, r * 2.0)]]
