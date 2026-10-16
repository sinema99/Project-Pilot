class_name DescentTrees
extends Node3D

# Sparse tundra spruce in the descent shot (docs/specs/descent-trees.md), in three bands: a few
# close lone trees (60-200 m) with ink and a slight sway, creek-line ribbons in the mid-field
# (300 m - 1.5 km) and far 2-tone clumps (1.5-5 km). Placed from DescentShot's TREE_* tables.
#
# GENERATED like DescentLand: children have no owner, so nothing is saved into the .tscn. Sits
# below Land in the tree, so the wrecks it keeps clear of are already built. No collision: the
# Storm's roof bake ignores the trees and the snow falls through them.

const CEL_BASE := "res://resources/cel_ground.tres"
const CLUMP_SHADER := preload("res://shaders/cutscene/tree_clump.gdshader")

## Near-black spruce green (#1f2e2a) and the snow on its tiers.
const C_SPRUCE := Color(0.122, 0.18, 0.165)
const C_TIER_SNOW := Color(0.85, 0.88, 0.94)

@export var tree_seed := 23
## How far a close tree leans downwind at the most (deg); it swings between upright and this.
@export_range(0.0, 2.0, 0.01) var sway_degrees := 0.4
@export var sway_period_min := 4.0
@export var sway_period_max := 6.0
## Metres along a mid ribbon between tree slots.
@export var mid_spacing := 4.5
## Metres between tree tips along a far clump.
@export var far_spacing := 4.5

## The close lone spruces, in TREE_LONE order.
var lone: Array[MeshInstance3D] = []
## Every mid tree: {at, height, ribbon} (ribbon -1 for the strays between ribbons).
var mid_trees: Array[Dictionary] = []
## Every far clump: {at, length, tips}.
var clumps: Array[Dictionary] = []
var clump_material: ShaderMaterial

var _rng := RandomNumberGenerator.new()
var _wind := Vector3(0.94, 0.0, 0.33).normalized()
## Per close tree: {rest: Transform3D, axis: Vector3, phase: float, period: float}.
var _sway: Array[Dictionary] = []
var _materials := {}
## Screen boxes of the wrecks a tree in front of them must stay under: {x0, x1, dist, third}.
var _wreck_boxes: Array[Dictionary] = []


func _ready() -> void:
	_rng.seed = tree_seed
	var storm := get_node_or_null(^"../Storm")
	if storm != null:
		var w: Vector2 = storm.wind_direction
		_wind = Vector3(w.x, 0.0, w.y).normalized()
	_find_wrecks()
	_build_lone()
	_build_mid()
	_build_far()
	apply(0.0)


## The close trees' sway at shot time `t`: 0..sway_degrees downwind, each on its own phase.
func apply(t: float) -> void:
	for i in lone.size():
		var s: Dictionary = _sway[i]
		var amount := 0.5 + 0.5 * sin(TAU * t / s.period + s.phase)
		var rest: Transform3D = s.rest
		lone[i].transform = Transform3D(Basis(s.axis, deg_to_rad(sway_degrees) * amount) * rest.basis, rest.origin)


## How far close tree `i` leans from upright right now (deg).
func lean_degrees(i: int) -> float:
	return rad_to_deg(lone[i].transform.basis.y.angle_to(Vector3.UP))


## The horizontal direction the close trees lean toward.
func downwind() -> Vector3:
	return _wind


# --- close lone spruces ----------------------------------------------------------------------

func _build_lone() -> void:
	var axis := Vector3.UP.cross(_wind).normalized()
	for i in DescentShot.TREE_LONE.size():
		var row: Array = DescentShot.TREE_LONE[i]
		var h: float = row[2]
		var green := _surface()
		var snow := _surface()
		_spruce(green, snow, Transform3D.IDENTITY, h, h * _girth(), 9,
				_rng.randi_range(7, 10), 0.5)
		var mi := MeshInstance3D.new()
		mi.name = "LoneSpruce%d" % i
		mi.mesh = _commit([green, snow], [_cel(C_SPRUCE, true), _cel(C_TIER_SNOW, true)])
		var rest := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), _ground(row[0], row[1]))
		mi.transform = rest
		add_child(mi)
		lone.append(mi)
		_sway.append({rest = rest, axis = axis, phase = _rng.randf() * TAU,
				period = _rng.randf_range(sway_period_min, sway_period_max)})


# --- mid tree lines --------------------------------------------------------------------------

func _build_mid() -> void:
	mid_trees.clear()
	var green := _surface()
	var snow := _surface()
	for r in DescentShot.TREE_RIBBONS.size():
		var row: Array = DescentShot.TREE_RIBBONS[r]
		var a := _ground(row[0], row[1])
		var b := _ground(row[2], row[3])
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var side := Vector3.UP.cross(dir)
		var bends := _rng.randf_range(1.5, 3.0)
		var bend_phase := _rng.randf() * TAU
		var amp := _rng.randf_range(6.0, 16.0)
		# One to three breaks along the line, where the creek runs bare.
		var gaps: Array[Vector2] = []
		for g in _rng.randi_range(1, 3):
			var c := _rng.randf_range(0.2, 0.8)
			var half := _rng.randf_range(0.025, 0.06)
			gaps.append(Vector2(c - half, c + half))
		# Spruce islands: the line breaks into tight overlapping clumps with open snow between, so
		# it reads as dark serrated masses at 300 m - 1.5 km instead of a picket fence of spires.
		var island_phase := _rng.randf() * TAU
		var s := _rng.randf_range(0.0, mid_spacing)
		while s < length:
			var u := s / length
			s += mid_spacing * _rng.randf_range(0.7, 1.3)
			if gaps.any(func(g: Vector2) -> bool: return u > g.x and u < g.y):
				continue
			if sin(s / 23.0 + island_phase) + 0.6 * sin(s / 9.0 + island_phase * 1.7) < -0.1:
				continue
			var taper := pow(sin(PI * u), 0.6)
			var count := roundi(float(row[4]) * taper * _rng.randf_range(0.6, 1.25))
			if count == 0 and _rng.randf() < 0.35:
				count = 1
			var centre := a + dir * (length * u) + side * (sin(u * PI * bends + bend_phase) * amp)
			for j in count:
				var across := (j - (count - 1) * 0.5) * _rng.randf_range(2.5, 4.0) + _rng.randf_range(-1.0, 1.0)
				var at := centre + side * across + dir * _rng.randf_range(-2.0, 2.0)
				_mid_tree(green, snow, at, lerpf(7.0, 17.0, taper) * _size(), r)
	# Strays and pairs out on the open snow between the lines.
	for k in 8:
		var at := _ground(_rng.randf_range(0.0, DescentShot.SKETCH_SIZE.x), _rng.randf_range(320.0, 1450.0))
		_mid_tree(green, snow, at, 12.0 * _size(), -1)
		if _rng.randf() < 0.4:
			var a2 := _rng.randf() * TAU
			_mid_tree(green, snow, at + Vector3(cos(a2), 0.0, sin(a2)) * _rng.randf_range(3.0, 6.0),
					9.0 * _size(), -1)
	var mi := MeshInstance3D.new()
	mi.name = "MidTrees"
	mi.mesh = _commit([green, snow], [_cel(C_SPRUCE, false), _cel(C_TIER_SNOW, false)])
	add_child(mi)


func _mid_tree(green: SurfaceTool, snow: SurfaceTool, at: Vector3, h: float, ribbon: int) -> void:
	if _hides_a_wreck(at, h):
		return
	var foot := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), at)
	_spruce(green, snow, foot, h, h * _girth(), 6, _rng.randi_range(4, 8), 0.3)
	mid_trees.append({at = at, height = h, ribbon = ribbon})


# --- far clumps ------------------------------------------------------------------------------

func _build_far() -> void:
	clumps.clear()
	var st := _surface()
	for row: Array in DescentShot.TREE_FAR_LINES:
		var a := _ground(row[0], row[1])
		var b := _ground(row[2], row[3])
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var side := Vector3.UP.cross(dir)
		var bend_phase := _rng.randf() * TAU
		var s := _rng.randf_range(0.0, 80.0)
		while s < length:
			var clump := _rng.randf_range(60.0, 240.0)
			var mid := a + dir * (s + clump * 0.5)
			# Thinner the further out: the gaps between clumps grow with distance.
			var far := Vector2(mid.x, mid.z).length() / 1500.0
			var tips := 0
			var t := 0.0
			while t < clump and s + t < length:
				var v := t / clump
				var taper := sin(PI * v)
				var centre := a + dir * (s + t) + side * (sin((s + t) / 90.0 + bend_phase) * 20.0)
				var deep := maxi(1, roundi(_rng.randf_range(1.0, 3.2) * taper))
				for j in deep:
					var at := centre + side * ((j - (deep - 1) * 0.5) * 4.0 + _rng.randf_range(-1.5, 1.5))
					var h := _rng.randf_range(6.0, 20.0) * lerpf(0.5, 1.0, taper)
					if not _hides_a_wreck(at, h):
						_tip(st, at, h, h * _rng.randf_range(0.15, 0.32))
						tips += 1
				t += far_spacing * _rng.randf_range(0.7, 1.3)
			if tips > 0:
				clumps.append({at = mid, length = clump, tips = tips})
			s += clump + _rng.randf_range(40.0, 200.0) * far
	clump_material = ShaderMaterial.new()
	clump_material.shader = CLUMP_SHADER
	var sun := get_node_or_null(^"../Sun") as DirectionalLight3D
	if sun != null:
		clump_material.set_shader_parameter(&"to_light", sun.global_transform.basis.z)
	var mi := MeshInstance3D.new()
	mi.name = "FarClumps"
	mi.mesh = _commit([st], [clump_material])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## One tree tip in a far clump: a five-sided pyramid. Many overlapping make the scalloped mound.
func _tip(st: SurfaceTool, at: Vector3, h: float, r: float) -> void:
	var apex := at + Vector3(_rng.randf_range(-0.4, 0.4), h, _rng.randf_range(-0.4, 0.4))
	var a0 := _rng.randf() * TAU
	var ring: Array[Vector3] = []
	for k in 5:
		var a := a0 + TAU * k / 5.0
		ring.append(at + Vector3(cos(a), -0.5, sin(a)) * Vector3(r, 1.0, r))
	for k in 5:
		var p: Vector3 = ring[k]
		var q: Vector3 = ring[(k + 1) % 5]
		_tri(st, apex, p, q, (p + q) * 0.5 - at)


## A tree's width-to-height ratio: a mix of pencil-thin black spruce, ordinary ones and a few full,
## bushy old ones, so neighbours never match.
func _girth() -> float:
	var roll := _rng.randf()
	if roll < 0.35:
		return _rng.randf_range(0.055, 0.08)
	if roll < 0.8:
		return _rng.randf_range(0.09, 0.12)
	return _rng.randf_range(0.13, 0.19)


## A height multiplier: mostly 0.6-1.25, with some saplings well under half size.
func _size() -> float:
	return _rng.randf_range(0.25, 0.45) if _rng.randf() < 0.15 else _rng.randf_range(0.6, 1.25)


# --- the spruce ------------------------------------------------------------------------------

## A northern spruce `h` tall and `r` wide at its lowest tier, standing at `foot`: a thin trunk,
## `tiers` drooping branch skirts with snow on the top `snow_frac` of each, and a clumpy spire.
## Every skirt is a closed wedge, so the low camera looking up sees green undersides.
func _spruce(green: SurfaceTool, snow: SurfaceTool, foot: Transform3D, h: float, r: float,
		segs: int, tiers: int, snow_frac: float) -> void:
	var trunk_r := maxf(0.12, r * 0.1)
	var bare := h * (_rng.randf_range(0.06, 0.15) if _rng.randf() < 0.6 else 0.03)
	_cone(green, foot, Vector3(0.0, -0.4, 0.0), trunk_r, h * 0.9, 0.0, 5)
	# Uneven tier heights, sorted, from the top of the bare trunk to just under the spire.
	var crown := h * 0.84 - bare
	var ys: Array[float] = []
	for i in tiers:
		ys.append(bare + crown * clampf((i + _rng.randf_range(-0.3, 0.3)) / tiers, 0.0, 0.97))
	ys.sort()
	var tier_h := crown / tiers * _rng.randf_range(1.5, 1.9)
	# Some trees are thin on one side (wind, or a neighbour that shaded it out).
	var thin_at := _rng.randf() * TAU if _rng.randf() < 0.45 else INF
	for y in ys:
		var rb := maxf(r * pow(1.0 - y / h, 0.85) * _rng.randf_range(0.8, 1.1), 0.35)
		_skirt(green, snow, foot, Vector3(_rng.randf_range(-0.1, 0.1), 0.0, _rng.randf_range(-0.1, 0.1)),
				y, tier_h * _rng.randf_range(0.85, 1.15), rb, trunk_r, segs, snow_frac, thin_at)
	# The spire: one slim cone, and a clump or two of short tufts hugging it.
	_cone(green, foot, Vector3(0.0, h * 0.8, 0.0), r * 0.13, h * 0.2, 0.0, 5)
	for k in _rng.randi_range(1, 2):
		var off := Vector3(_rng.randf_range(-0.25, 0.25), 0.0, _rng.randf_range(-0.25, 0.25))
		_skirt(green, snow, foot, off, h * _rng.randf_range(0.78, 0.88), h * 0.06, r * 0.22, trunk_r,
				maxi(segs - 2, 5), snow_frac, INF)


## One drooping branch skirt: top ring at the trunk, a ragged snow line, a ragged drooped rim, and
## an underside back to the trunk.
func _skirt(green: SurfaceTool, snow: SurfaceTool, foot: Transform3D, centre: Vector3, y: float,
		th: float, rb: float, trunk_r: float, segs: int, snow_frac: float, thin_at: float) -> void:
	var top := centre + Vector3(0.0, y + th, 0.0)
	var rim: Array[Vector3] = []
	var line: Array[Vector3] = []
	var under: Array[Vector3] = []
	var a0 := _rng.randf() * TAU
	for k in segs:
		var a := a0 + TAU * (k + _rng.randf_range(-0.2, 0.2)) / segs
		var rr := rb * _rng.randf_range(0.7, 1.1)
		if thin_at != INF and absf(angle_difference(a, thin_at)) < 0.8:
			rr *= 0.45
		var out := Vector3(cos(a), 0.0, sin(a))
		var p := centre + out * rr + Vector3(0.0, y - th * _rng.randf_range(0.1, 0.35), 0.0)
		rim.append(p)
		line.append(top.lerp(p, clampf(snow_frac + _rng.randf_range(-0.1, 0.1), 0.05, 0.95)))
		under.append(centre + out * trunk_r + Vector3(0.0, y + th * 0.35, 0.0))
	for k in segs:
		var k1 := (k + 1) % segs
		var out := ((rim[k] + rim[k1]) * 0.5 - centre) * Vector3(1, 0, 1)
		var up_out := out.normalized() + Vector3.UP
		var t0 := foot * top
		_tri(snow, t0, foot * line[k], foot * line[k1], foot.basis * up_out)
		_quad(green, foot * line[k], foot * line[k1], foot * rim[k1], foot * rim[k], foot.basis * up_out)
		_quad(green, foot * rim[k], foot * rim[k1], foot * under[k1], foot * under[k], foot.basis * Vector3.DOWN)


## A `sides`-sided cone (or prism if `r_top` > 0) from `base` up `height`, at `foot`.
func _cone(st: SurfaceTool, foot: Transform3D, base: Vector3, r: float, height: float, r_top: float,
		sides: int) -> void:
	var apex := base + Vector3(0.0, height, 0.0)
	for k in sides:
		var a := TAU * k / sides
		var b := TAU * (k + 1) / sides
		var p := base + Vector3(cos(a), 0.0, sin(a)) * r
		var q := base + Vector3(cos(b), 0.0, sin(b)) * r
		var want := foot.basis * Vector3(cos((a + b) * 0.5), 0.0, sin((a + b) * 0.5))
		if r_top > 0.0:
			_quad(st, foot * p, foot * q, foot * (apex + (q - base) * r_top / r),
					foot * (apex + (p - base) * r_top / r), want)
		else:
			_tri(st, foot * apex, foot * p, foot * q, want)


# --- helpers ---------------------------------------------------------------------------------

## A flat-shaded triangle facing `want`: Godot's front face is clockwise seen from outside.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	if n.dot(want) > 0.0:
		var tmp := b
		b = c
		c = tmp
		n = -n
	n = -n.normalized()
	for p: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(p.x, p.y))
		st.add_vertex(p)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3) -> void:
	_tri(st, a, b, c, want)
	_tri(st, a, c, d, want)


func _surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _commit(tools: Array, materials: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for i in tools.size():
		(tools[i] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[i])
	return mesh


## The shot's cel material in `col`; `ink` keeps its crease + outline passes.
func _cel(col: Color, ink: bool) -> ShaderMaterial:
	var key := "%s|%s" % [col, ink]
	if not _materials.has(key):
		var m := (load(CEL_BASE) as ShaderMaterial).duplicate() as ShaderMaterial
		m.set_shader_parameter("color", col)
		if not ink:
			m.next_pass = null
		_materials[key] = m
	return _materials[key]


## Ground point on the ray through sketch x at the horizon, `distance` m out.
func _ground(sketch_x: float, distance: float) -> Vector3:
	var p := DescentShot.sketch_point(Vector2(sketch_x, DescentShot.HORIZON_PX), distance)
	return Vector3(p.x, 0.0, p.z)


func _find_wrecks() -> void:
	_wreck_boxes.clear()
	var land := get_node_or_null(^"../Land") as DescentLand
	if land == null:
		return
	for w: Dictionary in land.wrecks:
		var at: Vector3 = w.at
		var dist := Vector2(at.x, at.z).length()
		var standing: float = float(w.length) * (1.0 - w.sink) * cos(deg_to_rad(w.lean_degrees))
		var x := DescentShot.to_sketch(at).x
		var half: float = w.length * 0.6 / dist * DescentShot.SKETCH_SIZE.x / (2.0 * tan(deg_to_rad(DescentShot.FOV) * 0.5) * DescentShot.ASPECT)
		var foot_y := DescentShot.to_sketch(at).y
		var top_y := DescentShot.to_sketch(at + Vector3.UP * standing).y
		_wreck_boxes.append({x0 = x - half, x1 = x + half, dist = dist, third = foot_y - (foot_y - top_y) / 3.0})


## True if a tree `h` tall at `at` stands in front of a wreck and reaches above its lower third.
func _hides_a_wreck(at: Vector3, h: float) -> bool:
	var dist := Vector2(at.x, at.z).length()
	var top := DescentShot.to_sketch(at + Vector3.UP * h)
	for box: Dictionary in _wreck_boxes:
		if dist < box.dist and top.x > box.x0 and top.x < box.x1 and top.y < box.third:
			return true
	return false
