class_name DescentLand
extends Node3D

# Everything solid in the descent shot (docs/specs/cutscene-descent.md): the snow field, the ruined
# city and the wrecks in the field, the two mountain ranges, the cloud deck with its storm wall on
# the left, and the snow curtain under it. Generated at load from DescentShot's sketch tables,
# aimed at that one locked camera; backs are never seen.
#
# GENERATED like scripts/pipe_hall.gd: children have no owner, so nothing is saved into the
# .tscn. Builds in its own _ready, which runs before the Storm's (Land sits above it in the tree),
# so the Storm's roof bake finds the snow field and the drift has a ground.

const CEL_BASE := "res://resources/cel_ground.tres"
const DECK_SHADER := preload("res://shaders/cutscene/cloud_deck.gdshader")
const CURTAIN_SHADER := preload("res://shaders/cutscene/snow_curtain.gdshader")

const C_SNOW := Color(0.95, 0.94, 0.96)
const C_PEAK_SNOW := Color(0.85, 0.88, 0.94)
const C_ROCK := Color(0.28, 0.29, 0.33)
## The wrecks' concrete: lighter than the city's, which the fog lightens at 3-6 km.
const C_WRECK_CONCRETES: Array[Color] = [Color(0.44, 0.45, 0.50), Color(0.38, 0.39, 0.44)]

@export var ruin_seed := 11
@export var mountain_seed := 5
## A mountain triangle whose normal's y is below this is bare rock; above it, snow.
@export_range(0.0, 1.0, 0.01) var snow_threshold := 0.8

## The cloud deck's material; DescentShot pushes the lightning into it every frame.
var deck_material: ShaderMaterial
## The snow curtain's material; DescentShot pushes the bolt glows into it every frame.
var curtain_material: ShaderMaterial

var _materials := {}


func _ready() -> void:
	_build_snow_field()
	_build_ruins()
	_build_range("NearRange", DescentShot.NEAR_RIDGE, DescentShot.NEAR_RANGE_DISTANCE, 2000.0, mountain_seed)
	_build_range("FarRange", DescentShot.FAR_RIDGE, DescentShot.FAR_RANGE_DISTANCE, 3000.0, mountain_seed + 1)
	_build_deck()
	_build_curtain()


func _cel(col: Color) -> ShaderMaterial:
	if not _materials.has(col):
		var m := (load(CEL_BASE) as ShaderMaterial).duplicate() as ShaderMaterial
		m.set_shader_parameter("color", col)
		_materials[col] = m
	return _materials[col]


# --- snow field ------------------------------------------------------------------------------

func _build_snow_field() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "SnowField"
	var plane := PlaneMesh.new()
	plane.size = Vector2(40000.0, 40000.0)
	mi.mesh = plane
	mi.material_override = _cel(C_SNOW)
	# Centred well ahead, so the far edge is beyond the far range and the near edge behind the camera.
	mi.position = Vector3(0.0, 0.0, -15000.0)
	# The Storm's roof bake reads level meshes by their StaticBody3D: this gives the drift a ground.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40000.0, 1.0, 40000.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	mi.add_child(body)
	add_child(mi)


# --- ruins: one dead city ---------------------------------------------------------------------
# Abandoned 100+ years: a dense downtown left of centre (DescentShot.CITY_CORE), mid-rise sprawl
# thinning out to the right (CITY_SPRAWL) and lone outliers on the snow (CITY_OUTLIERS). Seven
# kinds of ruin, all boxes on one street grid, snow on every top, ledge, break and floor slab.
# Merged into one mesh per colour (hundreds of boxes).

const RUIN_KINDS: Array[StringName] = [&"snapped", &"skeleton", &"leaning", &"setback", &"facade", &"toppled", &"crane"]
const CORE_COUNT := 22
const SPRAWL_COUNT := 16
const RUBBLE_COUNT := 18
## Storey height (m) of the skeleton frames: wide enough to see sky through at 4 km.
const FLOOR := 15.0
const C_CONCRETES: Array[Color] = [
	Color(0.30, 0.31, 0.35), Color(0.22, 0.23, 0.27), Color(0.26, 0.26, 0.30),
]

## Every ruin, for tests: [{kind, base, height, lean_degrees}].
var ruins: Array[Dictionary] = []
## Every wreck in the open field, for tests: [{kind, at, length, lean_degrees, sink}].
var wrecks: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
## Footprints taken so far: (x, z, clear radius).
var _taken: Array[Vector3] = []
## Colour -> SurfaceTool, committed into one mesh each at the end.
var _city := {}
## The street grid's turn off the view axis.
var _grid := 0.0


func _build_ruins() -> void:
	ruins.clear()
	_taken.clear()
	_city.clear()
	_rng.seed = ruin_seed
	_grid = deg_to_rad(_rng.randf_range(10.0, 20.0))
	_build_core()
	_build_sprawl()
	for o: Vector3 in DescentShot.CITY_OUTLIERS:
		var at := _ground(o.x, o.y)
		var kind: StringName = &"skeleton" if o.z > 150.0 else &"snapped"
		_taken.append(Vector3(at.x, at.z, 40.0))
		_ruin(kind, _frame(at), _rng.randf_range(30.0, 45.0), _rng.randf_range(30.0, 45.0), o.z)
	_build_rubble()
	_build_wrecks()
	var root := Node3D.new()
	root.name = "Ruins"
	add_child(root)
	for col: Color in _city:
		var mi := MeshInstance3D.new()
		mi.mesh = (_city[col] as SurfaceTool).commit()
		mi.material_override = _cel(col)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


# Downtown: tallest at its middle, every kind but the toppled tower.
func _build_core() -> void:
	var zone := DescentShot.CITY_CORE
	var kinds: Array[StringName] = [&"crane", &"setback", &"setback", &"setback", &"facade", &"facade", &"facade"]
	while kinds.size() < CORE_COUNT - 2:  # the leaning pair is two more
		kinds.append(&"skeleton" if kinds.size() % 2 == 0 else &"snapped")
	_shuffle(kinds)
	kinds.insert(_rng.randi_range(0, kinds.size()), &"leaning")
	for kind in kinds:
		var w := _rng.randf_range(28.0, 50.0)
		var d := _rng.randf_range(28.0, 50.0)
		var radius := maxf(w, d) * (1.6 if kind == &"leaning" else 0.8) + 8.0
		var spot := _spot(zone, radius, 1.0)
		if spot == Vector3.INF:
			continue
		var centrality := 1.0 - absf(DescentShot.to_sketch(spot).x - zone.get_center().x) / (zone.size.x * 0.5)
		var h := lerpf(110.0, 300.0, clampf(centrality, 0.0, 1.0)) * _rng.randf_range(0.6, 1.0)
		if kind == &"setback":
			h = maxf(h * 1.15, 180.0)
		elif kind == &"crane":
			h = _rng.randf_range(110.0, 150.0)
		_ruin(kind, _frame(spot), w, d, h)


# The sprawl: lower, wider blocks, denser and taller next to downtown, plus the toppled tower.
func _build_sprawl() -> void:
	var zone := DescentShot.CITY_SPRAWL
	var kinds: Array[StringName] = [&"toppled"]
	var mix: Array[StringName] = [&"snapped", &"snapped", &"facade", &"skeleton"]
	while kinds.size() < SPRAWL_COUNT:
		kinds.append(mix[kinds.size() % mix.size()])
	for kind in kinds:
		var w := _rng.randf_range(45.0, 90.0)
		var d := _rng.randf_range(40.0, 70.0)
		var radius := 100.0 if kind == &"toppled" else maxf(w, d) * 0.8 + 10.0
		var spot := _spot(zone, radius, 1.7)
		if spot == Vector3.INF:
			continue
		var fx := clampf((DescentShot.to_sketch(spot).x - zone.position.x) / zone.size.x, 0.0, 1.0)
		var h := lerpf(100.0, 35.0, fx) * _rng.randf_range(0.6, 1.0)
		if kind == &"toppled":
			w = _rng.randf_range(30.0, 40.0)
			h = _rng.randf_range(150.0, 190.0)  # its length, lying down
		_ruin(kind, _frame(spot), w, d, h)


# Concrete mounds drifted over with snow, all through the city.
func _build_rubble() -> void:
	for i in RUBBLE_COUNT:
		var zone := DescentShot.CITY_CORE if i % 2 == 0 else DescentShot.CITY_SPRAWL
		var at := _ground(_rng.randf_range(zone.position.x, zone.end.x), _rng.randf_range(zone.position.y, zone.end.y))
		var size := Vector3(_rng.randf_range(25.0, 60.0), _rng.randf_range(6.0, 18.0), _rng.randf_range(20.0, 45.0))
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(-10.0, 10.0)))
		var frame := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * tilt, at + Vector3(0.0, size.y * 0.3, 0.0))
		_capped(size, frame, _concrete(), 3.0)


## Builds one ruin of `kind` standing on `frame` (origin at its foot, +Y up).
func _ruin(kind: StringName, frame: Transform3D, w: float, d: float, h: float) -> void:
	var lean := 0.0
	var col := _concrete()
	match kind:
		&"snapped":
			if _rng.randf() < 0.3:
				lean = _rng.randf_range(4.0, 9.0)
				frame = _tipped(frame, lean)
			_snapped(frame, w, d, h, col)
		&"skeleton":
			_skeleton(frame, w, d, h, col)
		&"leaning":
			lean = _leaning_pair(frame, w, d, h, col)
		&"setback":
			_setback(frame, w, d, h, col)
		&"facade":
			_facade(frame, w, h, col)
		&"toppled":
			_toppled(frame, w, h, col)
		&"crane":
			_crane(frame, h)
	ruins.append({kind = kind, base = frame.origin, height = h, lean_degrees = lean})


# A tower sheared off: the shaft, then two or three jagged stubs of the lost floors, and sometimes
# a broken-off section still hanging on.
func _snapped(frame: Transform3D, w: float, d: float, h: float, col: Color) -> void:
	_capped(Vector3(w, h, d), frame.translated_local(Vector3(0.0, h * 0.5, 0.0)), col)
	for i in _rng.randi_range(2, 3):
		var sw := w * _rng.randf_range(0.2, 0.45)
		var sd := d * _rng.randf_range(0.5, 1.0)
		var sh := h * _rng.randf_range(0.05, 0.16)
		var at := Vector3(_rng.randf_range(-0.5, 0.5) * (w - sw), h + sh * 0.5, _rng.randf_range(-0.5, 0.5) * (d - sd))
		_capped(Vector3(sw, sh, sd), frame.translated_local(at), col)
	if _rng.randf() < 0.4:
		var cw := w * _rng.randf_range(0.45, 0.7)
		var ch := h * _rng.randf_range(0.12, 0.22)
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var tip := Basis(Vector3.FORWARD, deg_to_rad(_rng.randf_range(20.0, 40.0)) * side)
		_capped(Vector3(cw, ch, d * 0.8), frame * Transform3D(tip, Vector3(side * w * 0.3, h + ch * 0.4, 0.0)), col)


# The cladding is gone up top: a solid base, then bare floor slabs on columns with sky between,
# the top floors half gone.
func _skeleton(frame: Transform3D, w: float, d: float, h: float, col: Color) -> void:
	var clad := FLOOR * floorf(h * _rng.randf_range(0.25, 0.5) / FLOOR)
	if clad > 0.0:
		_capped(Vector3(w, clad, d), frame.translated_local(Vector3(0.0, clad * 0.5, 0.0)), col)
	var columns := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, -1), Vector2(0, 1)]
	for c: Vector2 in columns:
		var ch := (h - clad) * _rng.randf_range(0.65, 1.0)
		var at := Vector3(c.x * (w * 0.5 - 2.5), clad + ch * 0.5, c.y * (d * 0.5 - 2.5))
		_box(Vector3(5.0, ch, 5.0), frame.translated_local(at), col)
	var y := clad + FLOOR
	while y < h:
		if _rng.randf() > 0.15:
			var top := (y - clad) / maxf(h - clad, 1.0)
			var sw := w if top < 0.6 else w * _rng.randf_range(0.35, 0.8)
			var sx := (w - sw) * 0.5 * (1.0 if _rng.randf() < 0.5 else -1.0)
			_capped(Vector3(sw, 2.5, d), frame.translated_local(Vector3(sx, y, 0.0)), col, 1.5)
		y += FLOOR


# Two towers, one tipped over onto the other: the leaner's top corner rests against its
# neighbour's side, below its roof. `frame` is the pair's middle. Returns the lean (degrees).
func _leaning_pair(frame: Transform3D, w: float, d: float, h: float, col: Color) -> float:
	var hb := maxf(h, 160.0)
	var ha := hb * _rng.randf_range(0.75, 0.85)
	var lean := _rng.randf_range(12.0, 18.0)
	var t := deg_to_rad(lean)
	var wa := w * 0.85
	# The gap at the foot that lets the leaner's top corner just reach the neighbour's face.
	var gap := wa * 0.5 * (cos(t) - 1.0) + ha * sin(t)
	var stand := frame.translated_local(Vector3(wa * 0.5 + gap * 0.5 + w * 0.5, 0.0, 0.0))
	var leaner := frame.translated_local(Vector3(-wa * 0.5 - gap * 0.5, 0.0, 0.0))
	_snapped(stand, w, d, hb, col)
	# Rotating -t about +Z tips the leaner's top toward +X, onto its neighbour.
	_snapped(leaner * Transform3D(Basis(Vector3.BACK, -t), Vector3.ZERO), wa, d * 0.9, ha, _concrete())
	return lean


# The old landmark: three stepped tiers and a bent antenna mast.
func _setback(frame: Transform3D, w: float, d: float, h: float, col: Color) -> void:
	var y := 0.0
	for tier: Vector2 in [Vector2(1.0, 0.5), Vector2(0.72, 0.3), Vector2(0.45, 0.2)]:
		var th := h * tier.y
		_capped(Vector3(w * tier.x, th, d * tier.x), frame.translated_local(Vector3(0.0, y + th * 0.5, 0.0)), col)
		y += th
	var top := frame.translated_local(Vector3(0.0, y, 0.0))
	_box(Vector3(4.0, 30.0, 4.0), top.translated_local(Vector3(0.0, 15.0, 0.0)), col)
	var bend := Basis(Vector3.BACK, deg_to_rad(_rng.randf_range(35.0, 60.0)) * (1.0 if _rng.randf() < 0.5 else -1.0))
	_box(Vector3(4.0, 26.0, 4.0), top.translated_local(Vector3(0.0, 30.0, 0.0)) * Transform3D(bend, bend * Vector3(0.0, 13.0, 0.0)), col)


# One wall left standing with nothing behind it: strips of ragged height, holes punched through.
func _facade(frame: Transform3D, w: float, h: float, col: Color) -> void:
	var n := _rng.randi_range(4, 6)
	var sw := w / n
	for i in n:
		var sh := h * _rng.randf_range(0.45, 1.0)
		var x := -w * 0.5 + sw * (i + 0.5)
		if _rng.randf() < 0.4 and sh > 3.0 * FLOOR:
			# A floor-high hole: the strip in two pieces.
			var hole := FLOOR * maxf(floorf(_rng.randf_range(0.3, 0.7) * sh / FLOOR), 1.0)
			_capped(Vector3(sw, hole, 4.0), frame.translated_local(Vector3(x, hole * 0.5, 0.0)), col, 1.5)
			var rest := sh - hole - FLOOR
			_capped(Vector3(sw, rest, 4.0), frame.translated_local(Vector3(x, hole + FLOOR + rest * 0.5, 0.0)), col)
		else:
			_capped(Vector3(sw, sh, 4.0), frame.translated_local(Vector3(x, sh * 0.5, 0.0)), col)


# A tower lying across the snow in three broken pieces, half buried. `length` along frame X.
func _toppled(frame: Transform3D, w: float, length: float, col: Color) -> void:
	var seg := length / 3.0 - 8.0
	var x := -length * 0.5
	for i in 3:
		var twist := Basis(Vector3.UP, deg_to_rad(_rng.randf_range(-8.0, 8.0))) * Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(-6.0, 6.0)))
		_capped(Vector3(seg, w * 0.8, w), frame * Transform3D(twist, Vector3(x + seg * 0.5, w * 0.25, 0.0)), col)
		x += seg + 8.0


# A tower crane: mast, a jib snapped and hanging, a counter-jib with its weight.
func _crane(frame: Transform3D, h: float) -> void:
	var col := C_CONCRETES[1]
	_box(Vector3(5.0, h, 5.0), frame.translated_local(Vector3(0.0, h * 0.5, 0.0)), col)
	var top := frame.translated_local(Vector3(0.0, h, 0.0))
	_capped(Vector3(45.0, 4.0, 4.0), top.translated_local(Vector3(22.5, 0.0, 0.0)), col, 1.0)
	var droop := Basis(Vector3.BACK, deg_to_rad(-_rng.randf_range(30.0, 50.0)))
	_box(Vector3(35.0, 4.0, 4.0), top.translated_local(Vector3(45.0, 0.0, 0.0)) * Transform3D(droop, droop * Vector3(17.5, 0.0, 0.0)), col)
	_capped(Vector3(22.0, 4.0, 4.0), top.translated_local(Vector3(-11.0, 0.0, 0.0)), col, 1.0)
	_capped(Vector3(8.0, 8.0, 6.0), top.translated_local(Vector3(-19.0, -5.0, 0.0)), col)


# --- wrecks in the open field ----------------------------------------------------------------
# DescentShot.FIELD_WRECKS: lone blocks between the camera and the city, sunk into the snow and
# tilted each a different way, a snow drift banked against the side they lean toward.

func _build_wrecks() -> void:
	wrecks.clear()
	var n := DescentShot.FIELD_WRECKS.size()
	for i in n:
		var row: Array = DescentShot.FIELD_WRECKS[i]
		var at := _ground(row[0], row[1])
		var length: float = row[2]
		var kind: StringName = row[3]
		var lean: float = row[4]
		var sink: float = row[5]
		var w: float = row[6]
		var col: Color = C_WRECK_CONCRETES[i % C_WRECK_CONCRETES.size()]
		# Lean mostly across the view (left / right in turn) so the slant reads, each a different
		# amount toward or away from the camera.
		var view := (at - DescentShot.CAMERA_POSITION) * Vector3(1, 0, 1)
		var away := atan2(view.x, -view.z)
		var a := away + (0.0 if i % 2 == 0 else PI) + _rng.randf_range(-0.5, 0.5)
		var axis := Vector3(sin(a), 0.0, -cos(a))
		var rot := Basis(axis, deg_to_rad(lean)) * Basis(Vector3.UP, _rng.randf() * TAU)
		var frame := Transform3D(rot, at - rot.y * length * sink)
		match kind:
			&"skeleton":
				_skeleton(frame, w, w * 0.9, length, col)
			_:
				_snapped(frame, w, w * _rng.randf_range(0.8, 1.0), length, col)
		var low := Vector3(-axis.z, 0.0, axis.x)  # where the top leans: UP turned about `axis`
		_drift(at, low, w, length)
		wrecks.append({kind = kind, at = at, length = length, lean_degrees = lean, sink = sink, foot = frame.origin})


# A drift banked against a wreck's low side: a snow slab, high at the wreck and sloping away.
func _drift(at: Vector3, low: Vector3, w: float, length: float) -> void:
	var size := Vector3(w * 1.6, maxf(length * 0.16, 5.0), maxf(length * 0.55, w * 1.2))
	var b := Basis.looking_at(low, Vector3.UP) * Basis(Vector3.RIGHT, deg_to_rad(-12.0))
	_box(size, Transform3D(b, at + low * size.z * 0.35), C_SNOW)


# --- ruin helpers -------------------------------------------------------------------------------

## Ground point on the ray through sketch x at the horizon, `distance` m out.
func _ground(sketch_x: float, distance: float) -> Vector3:
	var p := DescentShot.sketch_point(Vector2(sketch_x, DescentShot.HORIZON_PX), distance)
	return Vector3(p.x, 0.0, p.z)


## A ruin's frame on the street grid, a few degrees off true.
func _frame(at: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _grid + deg_to_rad(_rng.randf_range(-4.0, 4.0))), at)


## `frame` tipped `degrees` over on its foot, about a random horizontal axis.
func _tipped(frame: Transform3D, degrees: float) -> Transform3D:
	var a := _rng.randf() * TAU
	return Transform3D(Basis(Vector3(cos(a), 0.0, sin(a)), deg_to_rad(degrees)) * frame.basis, frame.origin)


## A free spot in `zone` at least `radius` clear of every ruin so far, or Vector3.INF. `bias` > 1
## crowds the spots toward the zone's left side.
func _spot(zone: Rect2, radius: float, bias: float) -> Vector3:
	for attempt in 60:
		var x := zone.position.x + zone.size.x * pow(_rng.randf(), bias)
		var p := _ground(x, _rng.randf_range(zone.position.y, zone.end.y))
		var clear := true
		for t: Vector3 in _taken:
			if Vector2(p.x - t.x, p.z - t.y).length() < radius + t.z:
				clear = false
				break
		if clear:
			_taken.append(Vector3(p.x, p.z, radius))
			return p
	return Vector3.INF


func _concrete() -> Color:
	return C_CONCRETES[_rng.randi() % C_CONCRETES.size()]


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp


## A box with snow on top: a thin white slab just over its top face.
func _capped(size: Vector3, xform: Transform3D, col: Color, snow := 3.0) -> void:
	_box(size, xform, col)
	var cap := Vector3(size.x * 1.03, snow, size.z * 1.03)
	_box(cap, xform.translated_local(Vector3(0.0, size.y * 0.5 + snow * 0.4, 0.0)), C_PEAK_SNOW)


## A `size` box centred on `xform`, appended to its colour's merged mesh.
func _box(size: Vector3, xform: Transform3D, col: Color) -> void:
	var st: SurfaceTool = _city.get(col)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_city[col] = st
	var rot := xform.basis.orthonormalized()
	var half := size * 0.5
	for axis in 3:
		for sgn: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := n.cross(u)
			# Clockwise seen from outside: Godot's front face.
			var corners := [n - u - v, n + u + v, n + u - v, n - u - v, n - u + v, n + u + v]
			var uvs := [Vector2(0, 0), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)]
			for k in 6:
				st.set_normal(rot * n)
				st.set_uv(uvs[k])
				st.add_vertex(xform * ((corners[k] as Vector3) * half))


# --- mountains -------------------------------------------------------------------------------

## Ridge height (m) at horizontal `distance` along each ridge point's ray, as [azimuth, height]
## pairs sorted by azimuth (radians, atan2(x, -z): right is positive).
static func ridge_profile(ridge: Array, distance: float) -> Array:
	var out := []
	for px: Vector2 in ridge:
		var p := DescentShot.sketch_point(px, distance)
		out.append(Vector2(atan2(p.x, -p.z), p.y))
	return out


static func _profile_at(profile: Array, az: float) -> float:
	if az <= profile[0].x:
		return profile[0].y
	for i in range(1, profile.size()):
		if az <= profile[i].x:
			return lerpf(profile[i - 1].y, profile[i].y, (az - profile[i - 1].x) / (profile[i].x - profile[i - 1].x))
	return profile[profile.size() - 1].y


# A polar heightfield around the camera: across azimuth from the ridge table, across radius a hump
# peaking at `distance` (half-width `spread`), scaled so its silhouette from the camera is the
# ridge. Ridged noise cuts gullies into it; steep triangles are rock, the rest snow.
func _build_range(node_name: String, ridge: Array, distance: float, spread: float, seed_: int) -> void:
	var profile := ridge_profile(ridge, distance)
	var az0: float = profile[0].x
	var az1: float = profile[profile.size() - 1].x
	var na := 420
	var nr := 56
	var noise := FastNoiseLite.new()
	noise.seed = seed_
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = 4
	noise.frequency = 1.0 / (distance * 0.16)
	var cam := DescentShot.CAMERA_POSITION
	var pos := PackedVector3Array()
	pos.resize(na * nr)
	for i in na:
		var az := lerpf(az0, az1, float(i) / float(na - 1))
		var dir := Vector3(sin(az), 0.0, -cos(az))
		var ridge_h := _profile_at(profile, az)
		# The hump's tallest angle from the camera, at unit height: scale so it hits the ridge.
		var best := 0.0
		for k in nr:
			var x := lerpf(-1.0, 1.0, float(k) / float(nr - 1))
			best = maxf(best, _hump(x) / (distance + x * spread))
		var ridge_scale := (ridge_h - cam.y) / (distance * best) if best > 0.0 else 0.0
		for k in nr:
			var x := lerpf(-1.0, 1.0, float(k) / float(nr - 1))
			var r := distance + x * spread
			var p := cam * Vector3(1, 0, 1) + dir * r
			var hump := _hump(x)
			var n := noise.get_noise_2d(p.x, p.z)
			p.y = maxf(0.0, ridge_scale * hump * (0.9 + 0.18 * n))
			pos[i * nr + k] = p
	var normals := PackedVector3Array()
	normals.resize(pos.size())
	for i in na:
		for k in nr:
			var l := pos[maxi(i - 1, 0) * nr + k]
			var rr := pos[mini(i + 1, na - 1) * nr + k]
			var f := pos[i * nr + maxi(k - 1, 0)]
			var b := pos[i * nr + mini(k + 1, nr - 1)]
			var nrm := (rr - l).cross(b - f).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			normals[i * nr + k] = nrm
	var snow := SurfaceTool.new()
	var rock := SurfaceTool.new()
	snow.begin(Mesh.PRIMITIVE_TRIANGLES)
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in na - 1:
		for k in nr - 1:
			var a := i * nr + k
			var b := (i + 1) * nr + k
			var c := (i + 1) * nr + k + 1
			var d := i * nr + k + 1
			for tri in [[a, c, b], [a, d, c]]:
				var ny := (normals[tri[0]].y + normals[tri[1]].y + normals[tri[2]].y) / 3.0
				var st := snow if ny >= snow_threshold else rock
				for v: int in tri:
					st.set_normal(normals[v])
					st.add_vertex(pos[v])
	var mesh := ArrayMesh.new()
	snow.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, _cel(C_PEAK_SNOW))
	rock.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, _cel(C_ROCK))
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# Cross-section of a range, x = -1 (front foot) .. 1 (back foot), peak 1 at 0.
static func _hump(x: float) -> float:
	return pow(maxf(0.0, 1.0 - x * x), 1.3)


# --- cloud deck ------------------------------------------------------------------------------

## Deck vertices fan from its front edge (DescentShot.deck_edge_point: the cloud line on the deck
## base, or the storm wall's lip on the left) back toward the camera, over the top of the frame.
## Rows along the edge x columns toward the camera.
const DECK_ALONG := 440
const DECK_BACK := 160
## How far toward the camera the deck reaches, as a fraction of each edge point's distance.
const DECK_REACH := 0.8
## Fraction of each storm-wall band given to its riser (the step that faces the camera).
const SHELF_RISER := 0.45


func _build_deck() -> void:
	var line: Array = DescentShot.CLOUD_LINE
	var x0: float = line[0].x
	var x1: float = line[line.size() - 1].x
	var cam := DescentShot.CAMERA_POSITION
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	for i in DECK_ALONG:
		var x := lerpf(x0, x1, float(i) / float(DECK_ALONG - 1))
		var edge := DescentShot.deck_edge_point(x)
		var edge_r := Vector2(edge.x - cam.x, edge.z - cam.z).length()
		var flat := DescentShot.sketch_at_height(Vector2(x, DescentShot.polyline_y(line, x)), DescentShot.DECK_BASE)
		# The wall climbs from its lip to the deck base by where the flat deck's edge would be.
		var inner_r := Vector2(flat.x - cam.x, flat.z - cam.z).length() * 0.9
		var k := DescentShot.shelf_amount(x)
		for j in DECK_BACK:
			var w := float(j) / float(DECK_BACK - 1)
			# Denser toward the edge, where the billows meet the sky.
			var f := 1.0 - DECK_REACH * w * w
			var r := edge_r * f
			var s := clampf((edge_r - r) / maxf(edge_r - inner_r, 1.0), 0.0, 1.0)
			var stair := shelf_stair(s)
			var h := lerpf(edge.y, DescentShot.DECK_BASE, stair.x)
			verts.append(Vector3(cam.x + (edge.x - cam.x) * f, h, cam.z + (edge.z - cam.z) * f))
			uvs.append(Vector2(float(i) / float(DECK_ALONG - 1), w))
			# r = how much storm wall, g = riser (0..1), b = how near a band's lip.
			var on_wall := 1.0 if s < 1.0 and edge.y < DescentShot.DECK_BASE - 1.0 else 0.0
			colors.append(Color(k, stair.y * on_wall, stair.z * on_wall, 1.0))
	var idx := PackedInt32Array()
	for i in DECK_ALONG - 1:
		for j in DECK_BACK - 1:
			var a := i * DECK_BACK + j
			var b := (i + 1) * DECK_BACK + j
			idx.append_array([a, b, b + 1, a, b + 1, a + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader pulls billows down: never cull on the flat bounds.
	mesh.custom_aabb = AABB(Vector3(-20000, 0, -20000), Vector3(40000, 1000, 40000))
	deck_material = ShaderMaterial.new()
	deck_material.shader = DECK_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "CloudDeck"
	mi.mesh = mesh
	mi.material_override = deck_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The storm wall's stepped climb at `s` (0 = its lip, 1 = the deck base): x = height fraction,
## y = 1 on a riser, z = 1 at a band's lip fading up its riser. Each band starts with its riser,
## so the lip itself is a step facing the camera.
static func shelf_stair(s: float) -> Vector3:
	var n := float(DescentShot.SHELF_BANDS)
	var q := minf(s * n, n - 0.0001)
	var band := floorf(q)
	var fr := q - band
	var rise := smoothstep(0.0, SHELF_RISER, fr)
	var riser := 1.0 if fr < SHELF_RISER else 0.0
	return Vector3((band + rise) / n if s < 1.0 else 1.0, riser, (1.0 - fr / SHELF_RISER) * riser)


# --- snow curtain ----------------------------------------------------------------------------
# A dark sheet of falling snow under the storm wall, behind the city: a strip CURTAIN_DISTANCE out
# from the left edge of the frame to CURTAIN_END_X, from the ground up past the wall's lip (the
# deck hides the top). The shader thins it toward the centre.

const CURTAIN_COLUMNS := 96


func _build_curtain() -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var x0 := -400.0
	var x1 := DescentShot.CURTAIN_END_X + 100.0
	for i in CURTAIN_COLUMNS:
		var x := lerpf(x0, x1, float(i) / float(CURTAIN_COLUMNS - 1))
		var foot := DescentShot.sketch_point(Vector2(x, DescentShot.HORIZON_PX), DescentShot.CURTAIN_DISTANCE)
		var top := DescentShot.sketch_point(Vector2(x, DescentShot.lip_y(x) - 60.0), DescentShot.CURTAIN_DISTANCE)
		var u := x / DescentShot.SKETCH_SIZE.x
		verts.append(Vector3(foot.x, maxf(top.y, 50.0), foot.z))
		uvs.append(Vector2(u, 0.0))
		verts.append(Vector3(foot.x, 0.0, foot.z))
		uvs.append(Vector2(u, 1.0))
	var idx := PackedInt32Array()
	for i in CURTAIN_COLUMNS - 1:
		var a := i * 2
		idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	curtain_material = ShaderMaterial.new()
	curtain_material.shader = CURTAIN_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "SnowCurtain"
	mi.mesh = mesh
	mi.material_override = curtain_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
