class_name ArrivalSpire
extends Node3D

# The spire in the arrival shot (docs/specs/cutscene-arrival.md, spec R4-6/8, R4b): something
# ancient and built, about 11 km out past the base, far bigger than anything in it.
# Plainly made, but at no human scale: no windows, no doors, no rails. An uneven hexagonal shaft
# (so it is nobody's octagonal tower) tapering as it climbs off the top of the frame, cut into
# sections by ledge bands that hold snow, two long grooves down every face, all sized to read at
# that distance (R4b-4). It is lighter in steps as it climbs, so its height reads past the haze.
# Inert (R4-8): nothing on it lights or moves; the clouds stream spindrift off its ledges
# (ArrivalClouds asks for `ledges`).
#
# Its foot stands clean on the low snowfield ArrivalLand lays just above the cloud sea (SPIRE): no
# rock, no rubble (R4b-2/3), only a drift where the shaft meets the snow.
#
# GENERATED like ArrivalLand: no owner, nothing saved into the .tscn. Built after Land.

const CEL_BASE := "res://resources/cel_ground.tres"
const CREASE := "res://resources/cel_crease_material.tres"
## The shaft's tones, foot to crown: blue-black, lifting a step per band of sections.
const C_TONES := [Color(0.09, 0.1, 0.13), Color(0.12, 0.13, 0.16), Color(0.15, 0.16, 0.2), Color(0.19, 0.2, 0.25)]
const C_GROOVE := Color(0.06, 0.07, 0.09)
const C_SNOW := Color(0.86, 0.87, 0.89)
## The hexagon's corners: radius factor and angle offset (degrees) each, so no two faces match.
const CORNERS := [[1.0, 0.0], [0.88, 4.0], [1.06, -3.0], [0.9, 5.0], [0.98, -2.0], [0.84, 3.0]]

@export var spire_seed := 2329
## The hexagon's turn (degrees) about the vertical.
@export var turn_degrees := 12.0
## How far the foot sinks into the snowfield (m), the ledge bands' spacing (m), how far each section
## steps in over the ledge (fraction of its radius), and how far up it is built (fraction of the
## height at which it would come to a point; it is off the frame long before).
@export var sink := 40.0
@export var section := 200.0
@export_range(0.0, 0.2, 0.005) var ledge_in := 0.08
@export_range(0.0, 1.0, 0.01) var built_to := 0.9
## The height (m) it would come to a point at, where 0 takes it from the frame. The boss arena's bake
## sets it higher: the space elevator, a longer cone climbing out of sight.
@export var taper_height := 0.0
## Grooves: width (m) and how far they stand off the face (m).
@export var groove_width := 20.0
@export var groove_out := 2.0
## The drift where the shaft meets the snowfield: how far it reaches out (m) and how high it banks
## against the shaft (m).
@export var drift_out := 30.0
@export var drift_up := 10.0
## Ink fade (m): the default fades out long before 11 km.
@export var ink_fade_start := 14000.0
@export var ink_fade_end := 20000.0

## The spire's foot centre (world) and the height at which it would come to a point (m above it).
var foot: Vector3
var height := 0.0
## World points on the downwind rim of the ledges inside the frame, for the spindrift.
var ledges: Array[Vector3] = []

var _mats := {}


func _ready() -> void:
	var shot := get_parent() as ArrivalShot
	var land := get_node(^"../Land") as ArrivalLand
	var sp := ArrivalShot.SPIRE
	foot = land.spire_foot
	var frame_top := shot.at_distance(sp.u, 0.0, sp.distance).y
	height = taper_height if taper_height > 0.0 else (frame_top - foot.y) / (1.0 - sp.frame_top_radius / sp.radius)
	var crease := (load(CREASE) as ShaderMaterial).duplicate() as ShaderMaterial
	crease.set_shader_parameter("fade_start_m", ink_fade_start)
	crease.set_shader_parameter("fade_end_m", ink_fade_end)
	for i in C_TONES.size():
		_mats["tone%d" % i] = _cel(C_TONES[i], crease)
	_mats.groove = _cel(C_GROOVE, null)
	_mats.snow = _cel(C_SNOW, crease)
	_build_shaft(sp.radius, frame_top)
	_build_drift()


func radius_at(y: float) -> float:
	return ArrivalShot.SPIRE.radius * (1.0 - (y - foot.y) / height)


# The shaft: sections between ledge bands, each a hexagonal frustum stepped in over the ledge below
# it, snow on the ledge, two grooves down each face.
func _build_shaft(r0: float, frame_top: float) -> void:
	var s := {}
	for key in _mats:
		s[key] = _surface()
	var y := foot.y - sink
	var top := foot.y + height * built_to
	var k := 0
	var sections := int(ceil((top - y) / section))
	while y < top:
		var y1 := minf(y + section, top)
		var lo := _hexagon(radius_at(y) * (1.0 - ledge_in if k > 0 else 1.0))
		var hi := _hexagon(radius_at(y1))
		var tone: StringName = "tone%d" % mini(int(float(k) / sections * C_TONES.size() * 2.0), C_TONES.size() - 1)
		for i in 6:
			var j := (i + 1) % 6
			var a0 := Vector3(lo[i].x, y, lo[i].y)
			var b0 := Vector3(lo[j].x, y, lo[j].y)
			var a1 := Vector3(hi[i].x, y1, hi[i].y)
			var b1 := Vector3(hi[j].x, y1, hi[j].y)
			var out := (b0 - a0).cross(a1 - a0).normalized()
			var mid := (lo[i] + lo[j]) * 0.5 - Vector2(foot.x, foot.z)
			if out.dot(Vector3(mid.x, 0.0, mid.y)) < 0.0:
				out = -out
			_quad(s[tone], a0, b0, b1, a1, out)
			# Two grooves down the face, a third of the way in from each corner, short of the ledges.
			for t in [0.33, 0.67]:
				var g0 := a0.lerp(b0, t)
				var g1 := a1.lerp(b1, t)
				var e0 := (b0 - a0).normalized() * groove_width * 0.5
				var e1 := (b1 - a1).normalized() * groove_width * 0.5
				var off := out * groove_out
				var up := Vector3.UP * 3.0
				_quad(s.groove, g0 - e0 + off + up, g0 + e0 + off + up, g1 + e1 + off - up, g1 - e1 + off - up, out)
		if k > 0:
			# The ledge under this section: what the section below leaves showing, snowed over.
			_ring(s.snow, _hexagon(radius_at(y)), lo, y + 0.5)
			if y < frame_top:
				var c := Vector2(foot.x, foot.z) + Vector2(radius_at(y), 0.0)
				ledges.append(Vector3(c.x, y, c.y))
		y = y1
		k += 1
	_commit("Shaft", s)


# The drift banked against the shaft's foot: a snow skirt from up the shaft out onto the field, so
# the shaft meets the snow cleanly with no hard seam.
func _build_drift() -> void:
	var s := {snow = _surface()}
	var inner := _hexagon(radius_at(foot.y + drift_up))
	var outer := _hexagon(radius_at(foot.y) + drift_out)
	for i in 6:
		var j := (i + 1) % 6
		var a0 := Vector3(outer[i].x, foot.y - 1.0, outer[i].y)
		var b0 := Vector3(outer[j].x, foot.y - 1.0, outer[j].y)
		var a1 := Vector3(inner[i].x, foot.y + drift_up, inner[i].y)
		var b1 := Vector3(inner[j].x, foot.y + drift_up, inner[j].y)
		var mid := (outer[i] + outer[j]) * 0.5 - Vector2(foot.x, foot.z)
		_quad(s.snow, a0, b0, b1, a1, (Vector3(mid.x, 0.0, mid.y).normalized() + Vector3.UP).normalized())
	_commit("Drift", s)


func _hexagon(r: float) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var turn := deg_to_rad(turn_degrees)
	for i in 6:
		var corner: Array = CORNERS[i]
		var a := turn + TAU * i / 6.0 + deg_to_rad(corner[1])
		poly.append(Vector2(foot.x, foot.z) + Vector2.from_angle(a) * r * corner[0])
	return poly


func _ring(st: SurfaceTool, outer: PackedVector2Array, inner: PackedVector2Array, y: float) -> void:
	for i in outer.size():
		var j := (i + 1) % outer.size()
		_quad(st, Vector3(outer[i].x, y, outer[i].y), Vector3(outer[j].x, y, outer[j].y),
				Vector3(inner[j].x, y, inner[j].y), Vector3(inner[i].x, y, inner[i].y), Vector3.UP)


func _surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


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


# A flat quad a-b-c-d (in order round it), facing `want`.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3) -> void:
	_tri(st, a, b, c, want)
	_tri(st, a, c, d, want)


# One flat-shaded triangle, wound so its front faces `want` (Godot: clockwise from the front).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3) -> void:
	if (c - a).cross(b - a).dot(want) < 0.0:
		var swap := b
		b = c
		c = swap
	for p in [a, b, c]:
		st.set_normal(want)
		st.add_vertex(p)


func _cel(col: Color, crease: ShaderMaterial) -> ShaderMaterial:
	var m := (load(CEL_BASE) as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("color", col)
	m.next_pass = crease
	return m
