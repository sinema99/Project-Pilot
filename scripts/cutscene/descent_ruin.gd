class_name DescentRuin
extends Node3D

# The ruined room the descent shot is seen from (docs/specs/cutscene-descent.md rows 39-45): a broken
# ceiling edge over the top-left, a snapped pillar leaning in at the right edge, a ragged floor lip
# along the bottom, a torn pipe and a few sagging wires hanging from the ceiling. Near-black
# silhouettes, rimmed only while lightning fires. A child of the shot's camera, built in the
# camera's own space from sketch pixels (DescentShot.sketch_local), so the wrapper scene moving the
# shot never shifts it. Everything is placed from the tables below: retune by moving points.

const SILHOUETTE_SHADER := preload("res://shaders/cutscene/ruin_silhouette.gdshader")

## The ceiling's broken edge, left to right: [sketch x, sketch y]. The slab covers everything above.
## Ends at CEILING_END_X, where it breaks off up and out of the frame.
const CEILING_EDGE := [
	Vector2(-80, 103), Vector2(40, 98), Vector2(110, 108), Vector2(170, 94), Vector2(260, 90),
	Vector2(300, 100), Vector2(330, 126), Vector2(372, 131), Vector2(410, 109), Vector2(470, 81),
	Vector2(560, 76), Vector2(640, 67), Vector2(700, 72), Vector2(760, 59), Vector2(850, 55),
	Vector2(900, 48), Vector2(960, 51), Vector2(1030, 41), Vector2(1110, 37), Vector2(1170, 30),
	Vector2(1230, 33), Vector2(1290, 22), Vector2(1335, 26), Vector2(1370, 16),
]
## The break at the ceiling's right end, from the last edge point up out of the frame.
const CEILING_BREAK := [Vector2(1392, 8), Vector2(1380, -10), Vector2(1404, -30), Vector2(1398, -80)]
const CEILING_DEPTH := 3.0
const CEILING_THICKNESS := 0.04

## Rebar out of the ceiling's broken edge and end: [sketch px points], each a bent rod.
const CEILING_REBAR := [
	[Vector2(1352, 18), Vector2(1398, 26), Vector2(1416, 46)],
	[Vector2(1384, 6), Vector2(1426, 0)],
	[Vector2(1306, 22), Vector2(1318, 50), Vector2(1310, 66)],
	[Vector2(350, 126), Vector2(356, 152), Vector2(346, 164)],
]

## The pillar's outline (sketch px, clockwise from bottom-left), past the right and bottom edges.
const PILLAR := [
	Vector2(1770, 900), Vector2(1689, 640), Vector2(1677, 626), Vector2(1657, 560),
	Vector2(1624, 452), Vector2(1605, 396), Vector2(1620, 372), Vector2(1638, 392), Vector2(1666, 384),
	Vector2(1681, 358), Vector2(1709, 380), Vector2(1742, 370), Vector2(1779, 336), Vector2(1829, 332),
	Vector2(1990, 300), Vector2(1990, 900),
]
const PILLAR_DEPTH := 2.4
const PILLAR_THICKNESS := 0.035
const PILLAR_REBAR := [
	[Vector2(1630, 386), Vector2(1618, 346), Vector2(1596, 324)],
	[Vector2(1696, 366), Vector2(1700, 326)],
]

## The floor slab's ragged lip along the bottom of the frame (sketch px, left to right).
const FLOOR_EDGE := [
	Vector2(-80, 826), Vector2(60, 822), Vector2(150, 830), Vector2(190, 812), Vector2(240, 818),
	Vector2(330, 832), Vector2(420, 838), Vector2(520, 852), Vector2(760, 858), Vector2(880, 846),
	Vector2(960, 840), Vector2(1010, 830), Vector2(1060, 836), Vector2(1180, 842), Vector2(1300, 854),
	Vector2(1460, 850), Vector2(1560, 836), Vector2(1620, 822), Vector2(1700, 814), Vector2(1990, 812),
]
const FLOOR_DEPTH := 2.0
const FLOOR_THICKNESS := 0.025

## The torn pipe: its path in sketch px (from just inside the ceiling's edge, bent down),
## where it tore loose (its pivot), depth (m) and radius (m).
const PIPE_PATH := [
	Vector2(500, 72), Vector2(520, 90), Vector2(552, 112), Vector2(572, 168),
	Vector2(582, 220), Vector2(586, 272), Vector2(582, 318),
]
const PIPE_PIVOT := Vector2(520, 90)
const PIPE_DEPTH := 2.6
const PIPE_RADIUS := 0.032

## Sagging wires: [start px, end px, sag (px), depth (m)]. Their ends sit inside the ceiling.
const WIRES := [
	[Vector2(872, 46), Vector2(1186, 24), 96.0, 2.9],
	[Vector2(900, 42), Vector2(1150, 28), 62.0, 3.0],
	[Vector2(950, 40), Vector2(1240, 24), 132.0, 2.8],
]
## The snapped wire hanging straight down: its points from the ceiling down (sketch px), and depth.
const DANGLING_WIRE := [
	Vector2(1046, 32), Vector2(1050, 110), Vector2(1058, 180), Vector2(1066, 232), Vector2(1080, 252),
	Vector2(1088, 266),
]
const DANGLING_DEPTH := 2.9
const WIRE_RADIUS := 0.006

## Snow sifting off the ceiling's edge: [shot time, sketch x].
const SIFTS := [[1.8, 640.0], [5.0, 230.0], [8.3, 1060.0], [11.5, 470.0], [15.1, 840.0], [18.0, 150.0]]

@export var ink := Color("#0a0d12")
@export var rim_color := Color(0.4, 0.55, 0.6)
## How bright the rim gets at a full flash.
@export var rim_energy := 0.45
@export_group("Motion")
## Wire sway: degrees about each wire's chord, and seconds per swing.
@export var wire_sway := 10.0
@export var wire_period := 5.5
## The pipe's swing (degrees) and period (s), and the dangling wire's.
@export var pipe_swing := 1.5
@export var pipe_period := 7.0
@export var dangle_swing := 3.0
@export var dangle_period := 4.2

var material: ShaderMaterial
var sift: CPUParticles3D
## Swinging parts: [node, pivot (camera space), axis, amplitude (deg), period (s), phase].
var _swings: Array = []
var _last_t := -1.0


func _ready() -> void:
	build()


## Builds every piece (idempotent).
func build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_swings.clear()
	material = ShaderMaterial.new()
	material.shader = SILHOUETTE_SHADER
	material.set_shader_parameter(&"ink", ink)
	material.set_shader_parameter(&"rim_color", rim_color)
	material.set_shader_parameter(&"rim_energy", rim_energy)

	var outline := PackedVector2Array()
	for p in CEILING_EDGE:
		outline.append(p)
	for p in CEILING_BREAK:
		outline.append(p)
	outline.append(Vector2(-80, -80))
	_add_mesh("Ceiling", _slab(outline, CEILING_DEPTH, CEILING_THICKNESS))
	_add_mesh("CeilingRebar", _rods(CEILING_REBAR, CEILING_DEPTH, 0.009))

	_add_mesh("Pillar", _slab(PackedVector2Array(PILLAR), PILLAR_DEPTH, PILLAR_THICKNESS))
	_add_mesh("PillarRebar", _rods(PILLAR_REBAR, PILLAR_DEPTH, 0.011))

	var floor_line := PackedVector2Array(FLOOR_EDGE)
	floor_line.append(Vector2(1990, 900))
	floor_line.append(Vector2(-80, 900))
	_add_mesh("Floor", _slab(floor_line, FLOOR_DEPTH, FLOOR_THICKNESS))

	var pipe := _add_mesh("Pipe", _pipe())
	_swing(pipe, _at(PIPE_PIVOT, PIPE_DEPTH), Vector3.BACK, pipe_swing, pipe_period, 0.0)

	for i in WIRES.size():
		var w: Array = WIRES[i]
		var pts := PackedVector3Array()
		for k in 25:
			var u := k / 24.0
			var px: Vector2 = (w[0] as Vector2).lerp(w[1], u) + Vector2(0.0, 4.0 * w[2] * u * (1.0 - u))
			pts.append(_at(px, w[3]))
		var node := _add_mesh("Wire%d" % i, _tube(pts, WIRE_RADIUS, 5))
		var a := _at(w[0], w[3])
		var b := _at(w[1], w[3])
		_swing(node, (a + b) * 0.5, (b - a).normalized(), wire_sway, wire_period * (1.0 + 0.17 * i), 1.9 * i)
	var dangle := PackedVector3Array()
	for p in DANGLING_WIRE:
		dangle.append(_at(p, DANGLING_DEPTH))
	var dnode := _add_mesh("DanglingWire", _tube(_smooth(dangle, 4), WIRE_RADIUS, 5))
	_swing(dnode, dangle[0], Vector3.BACK, dangle_swing, dangle_period, 0.7)

	sift = _make_sift()
	add_child(sift)


## Per frame: shot time `t` and how lit the storm is (0..~1.5).
func apply(t: float, flash: float) -> void:
	material.set_shader_parameter(&"flash", flash)
	for s: Array in _swings:
		var angle := deg_to_rad(s[3]) * sin(TAU * t / s[4] + s[5])
		var pivot: Vector3 = s[1]
		var rot := Transform3D(Basis(s[2], angle), Vector3.ZERO)
		(s[0] as Node3D).transform = Transform3D(Basis.IDENTITY, pivot) * rot * Transform3D(Basis.IDENTITY, -pivot)
	if t < _last_t:
		_last_t = t - 1e-3
	for row: Array in SIFTS:
		if row[0] > _last_t and row[0] <= t and t - row[0] < 0.5:
			sift.position = _at(Vector2(row[1], edge_y(row[1]) + 4.0), CEILING_DEPTH - 0.05)
			sift.restart()
	_last_t = t


## The ceiling's edge at sketch x (sketch px y).
static func edge_y(x: float) -> float:
	return DescentShot.polyline_y(CEILING_EDGE, x)


## Camera-space point on the ray through sketch px `px`, `depth` metres in front of the lens.
static func _at(px: Vector2, depth: float) -> Vector3:
	return DescentShot.sketch_local(px) * depth


func _add_mesh(n: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _swing(node: Node3D, pivot: Vector3, axis: Vector3, amp: float, period: float, phase: float) -> void:
	_swings.append([node, pivot, axis, amp, period, phase])


# --- geometry ---------------------------------------------------------------------------------

## Adds triangle a b c facing `n` (Godot's front faces wind clockwise on screen).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tmp := b
		b = c
		c = tmp
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## A flat shape: the outline (sketch px) on the plane `depth` in front of the lens, pushed
## `thickness` straight back (camera -Z) so its sides show as thin slivers for the rim.
static func _slab(outline: PackedVector2Array, depth: float, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front := PackedVector3Array()
	for p in outline:
		front.append(_at(p, depth))
	var back := Vector3(0.0, 0.0, -thickness)
	var idx := Geometry2D.triangulate_polygon(outline)
	for i in range(0, idx.size(), 3):
		_tri(st, front[idx[i]], front[idx[i + 1]], front[idx[i + 2]], Vector3.BACK)
	# Sides, outward: which way is out follows the outline's winding on screen.
	var cw := _signed_area(front) < 0.0
	for i in front.size():
		var a := front[i]
		var b := front[(i + 1) % front.size()]
		var along := b - a
		var n := Vector3(along.y, -along.x, 0.0).normalized()  # outward for a counter-clockwise outline
		if cw:
			n = -n
		_tri(st, a, b, b + back, n)
		_tri(st, a, b + back, a + back, n)
	return st.commit()


static func _signed_area(pts: PackedVector3Array) -> float:
	var s := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## Bent rods (rebar): each row a list of sketch px points at `depth`.
static func _rods(rows: Array, depth: float, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: Array in rows:
		var pts := PackedVector3Array()
		for p in row:
			pts.append(_at(p, depth))
		_tube_into(st, pts, radius, 5)
	return st.commit()


static func _tube(pts: PackedVector3Array, radius: float, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube_into(st, pts, radius, sides)
	return st.commit()


## A tube of `sides` facets along `pts`, capped at the far end.
static func _tube_into(st: SurfaceTool, pts: PackedVector3Array, radius: float, sides: int) -> void:
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var up := Vector3.BACK
	for i in pts.size():
		var dir := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := dir.cross(up)
		if side.length() < 1e-3:
			side = dir.cross(Vector3.UP)
		side = side.normalized()
		var up2 := side.cross(dir).normalized()
		var ring := PackedVector3Array()
		var nr := PackedVector3Array()
		for k in sides:
			var a := TAU * k / sides
			var n := side * cos(a) + up2 * sin(a)
			ring.append(pts[i] + n * radius)
			nr.append(n)
		rings.append(ring)
		normals.append(nr)
	for i in pts.size() - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			var n := (normals[i][k] + normals[i][k2] + normals[i + 1][k] + normals[i + 1][k2]).normalized()
			_tri(st, rings[i][k], rings[i][k2], rings[i + 1][k2], n)
			_tri(st, rings[i][k], rings[i + 1][k2], rings[i + 1][k], n)
	var last := pts.size() - 1
	var cap_n := (pts[last] - pts[last - 1]).normalized()
	for k in sides:
		_tri(st, pts[last], rings[last][k], rings[last][(k + 1) % sides], cap_n)


## Catmull-Rom through `pts`, `steps` samples per span.
static func _smooth(pts: PackedVector3Array, steps: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in pts.size() - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		for s in steps:
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[pts.size() - 1])
	return out


## The torn pipe: a smooth bent tube with a coupling collar near its open end.
func _pipe() -> ArrayMesh:
	var raw := PackedVector3Array()
	for p in PIPE_PATH:
		raw.append(_at(p, PIPE_DEPTH))
	var pts := _smooth(raw, 5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube_into(st, pts, PIPE_RADIUS, 10)
	# A coupling a little above the torn end, and a ragged flare at the end itself.
	var n := pts.size()
	var dir := (pts[n - 1] - pts[n - 4]).normalized()
	var collar := pts[n - 1] - dir * 0.16
	_tube_into(st, PackedVector3Array([collar, collar + dir * 0.07]), PIPE_RADIUS * 1.3, 10)
	_tube_into(st, PackedVector3Array([pts[n - 1] - dir * 0.015, pts[n - 1] + dir * 0.01]), PIPE_RADIUS * 1.12, 7)
	return st.commit()


func _make_sift() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "SnowSift"
	p.emitting = false
	p.one_shot = true
	p.amount = 60
	p.lifetime = 3.0
	p.explosiveness = 0.0
	p.local_coords = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.14, 0.01, 0.08)
	p.direction = Vector3.DOWN
	p.spread = 12.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.2
	p.gravity = Vector3(0.12, -0.45, 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.006, 0.006)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.86, 0.9, 0.97)
	m.disable_fog = true
	quad.material = m
	p.mesh = quad
	return p
