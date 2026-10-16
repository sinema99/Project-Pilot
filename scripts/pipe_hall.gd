@tool
class_name PipeHall
extends Node3D

# The pipe hall: a dark industrial chasm of giant pipes, steel catwalks and caged lamps, built
# from a reference painting. See docs/specs/pipe-hall.md.
#
# GENERATED, like scripts/jump_grid.gd, and for the same reason: every child is added WITHOUT an
# `owner`, so none of it is serialised into scenes/trial.tscn. The .tscn stores one instanced
# node and a transform; moving the hall is dragging that node, and a rebuild can never leave
# stale geometry behind. @tool so the editor viewport shows what the game will.
#
# LOCAL SPACE. The origin is the centre of the hall's floor, the walking surface is y = 0 (the
# same height as the jump grid's slab, so the causeway lines up with it), the hall runs along X
# and the door is in the -Z wall. Nothing below reads a world position.
#
# What is solid and what is not: floors, decks, ramps, the big pipes and the columns have
# colliders; railings, braces, cables, ribs, bands and lamps are dressing and have none, so a
# jump off a catwalk is never snagged by a rail and a wall-run is never spoiled by a bolt.
#
# The look is the project's cel shader (resources/cel_ground.tres, colour swapped per part) with
# the darkness coming from a local ambient: a ReflectionProbe over the whole hall that replaces
# the scene's bright sky ambient inside it.

const RAIL_SCRIPT := preload("res://scripts/rail.gd")
const CEL_BASE := "res://resources/cel_ground.tres"

# --- the shell -------------------------------------------------------------
const HALF_X := 48.0
const HALF_Z := 28.0
const HEIGHT := 46.0
## The ceiling lamps' spotlights and light shafts. Off since 2026-09-30: something lit half of pilot's
## body at floor level and the ceiling lights were the suspect. The fixtures stay, unlit.
const CEILING_LIGHTS_ON := false
const DOOR_HALF := 5.0
const DOOR_HEIGHT := 10.0
## The walkway from the jump grid's +Z edge to the door. It starts a metre inside the slab so
## the two are one surface rather than two edges a pixel apart.
const CAUSEWAY_LENGTH := 32.0
const CAUSEWAY_WIDTH := 8.0

# --- the palette: cold blue steel, one warm accent ---------------------------
const C_FLOOR := Color(0.085, 0.105, 0.150)
const C_WALL := Color(0.075, 0.095, 0.145)
const C_STEEL := Color(0.135, 0.170, 0.245)
const C_PIPE := Color(0.190, 0.255, 0.365)
const C_PIPE_DARK := Color(0.120, 0.160, 0.235)
const C_BAND := Color(0.250, 0.320, 0.430)
const C_DECK := Color(0.220, 0.245, 0.290)
const C_CABLE := Color(0.055, 0.070, 0.110)
const C_YELLOW := Color(0.78, 0.60, 0.16)
const C_LAMP_WARM := Color(1.0, 0.62, 0.22)
const C_LAMP_COOL := Color(0.62, 0.80, 1.0)

@export_tool_button("Rebuild") var rebuild_action: Callable = _build
## Seeds the cable tangle, and nothing else.
@export var cable_seed := 7

var _hull: StaticBody3D
var _vis: Node3D
var _lit: Node3D
var _mats: Dictionary = {}
var _bolts: Array[Transform3D] = []

const GENERATED := ["Hull", "Visual", "Lights", "GrindRail", "GrindRail2", "Ambient"]


func _ready() -> void:
	_build()


func _build() -> void:
	if not is_inside_tree():
		return
	_clear()
	_mats.clear()
	_bolts.clear()

	_hull = StaticBody3D.new()
	_hull.name = "Hull"
	add_child(_hull)
	_vis = Node3D.new()
	_vis.name = "Visual"
	add_child(_vis)
	_lit = Node3D.new()
	_lit.name = "Lights"
	add_child(_lit)

	_shell()
	_pipes()
	_columns()
	_walkways()
	_ceiling()
	_ceiling_lamps()
	_far_wall()
	_grind_rails()
	_ambient()
	_flush_bolts()


func _clear() -> void:
	for nm in GENERATED:
		var child := get_node_or_null(NodePath(nm))
		if child:
			remove_child(child)
			child.queue_free()


# --- materials ---------------------------------------------------------------

func _cel(col: Color) -> Material:
	var key := col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := (load(CEL_BASE) as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("color", col)
	_mats[key] = m
	return m


func _glow(col: Color) -> Material:
	var key := "glow" + col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	_mats[key] = m
	return m


# The visible shaft of a lamp's light: a soft additive cone (shaders/light_shaft.gdshader) that
# fades at its edge and where it meets a surface, so it reads as haze rather than as geometry.
func _beam_material(col: Color, height: float) -> Material:
	var key := "beam" + col.to_html() + str(height)
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/light_shaft.gdshader")
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("height", height)
	_mats[key] = m
	return m


# --- primitives --------------------------------------------------------------

## One box. `orient` tilts it (ramps, braces); the collider gets the same transform and size, so
## what is drawn and what is stood on cannot drift apart.
func _box(pos: Vector3, size: Vector3, col: Color, collide := true,
		orient := Basis.IDENTITY, shadow := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _cel(col)
	mi.transform = Transform3D(orient, pos)
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.transform = Transform3D(orient, pos)
		_hull.add_child(cs)


## A straight square beam between two points, for braces and struts. Never solid.
func _beam(a: Vector3, b: Vector3, thickness: float, col: Color) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return
	_box((a + b) * 0.5, Vector3(thickness, length, thickness), col, false,
		_align_y(b - a), false)


func _ring(pos: Vector3, axis: Vector3, radius: float, height: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 24
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _cel(col)
	mi.transform = Transform3D(_align_y(axis), pos)
	_vis.add_child(mi)


## A basis whose +Y runs along `dir`. Orthonormal and right-handed.
static func _align_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


## `corners` with every interior corner rounded to a circular arc of `radius`. The corners must
## be far enough apart that two arcs never overlap.
static func _fillet(corners: Array[Vector3], radius: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.append(corners[0])
	for i in range(1, corners.size() - 1):
		var p := corners[i]
		var d0 := (p - corners[i - 1]).normalized()
		var d1 := (corners[i + 1] - p).normalized()
		var turn := acos(clampf(d0.dot(d1), -1.0, 1.0))
		if turn < 0.01:
			out.append(p)
			continue
		var tangent_len := radius * tan(turn * 0.5)
		var n := (d1 - d0 * d0.dot(d1)).normalized()
		var centre := p - d0 * tangent_len + n * radius
		var steps := maxi(int(ceil(turn / (PI / 16.0))), 4)
		for k in range(steps + 1):
			var phi := turn * float(k) / float(steps)
			out.append(centre - n * radius * cos(phi) + d0 * radius * sin(phi))
	out.append(corners[corners.size() - 1])
	return out


# --- pipes -------------------------------------------------------------------

## A pipe along `points`: the swept tube, a seam band every `band_every` metres, a bolted flange
## at each end, and (when `collide`) a cylinder collider per segment.
func _pipe(points: PackedVector3Array, radius: float, col: Color, collide := true,
		band_every := 6.0) -> void:
	var mesh := RAIL_SCRIPT.tube_mesh(points, radius, 24, false) as ArrayMesh
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _cel(col)
	_vis.add_child(mi)

	var travelled := 0.0
	var next_at := band_every * 0.5
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.01:
			continue
		if collide:
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = radius
			cyl.height = seg
			cs.shape = cyl
			cs.transform = Transform3D(_align_y(b - a), (a + b) * 0.5)
			_hull.add_child(cs)
		while next_at <= travelled + seg:
			var t := (next_at - travelled) / seg
			_ring(a.lerp(b, t), b - a, radius * 1.035, 0.32, C_BAND)
			next_at += band_every
		travelled += seg

	var last := points.size() - 1
	_flange(points[0], (points[1] - points[0]).normalized(), radius)
	_flange(points[last], (points[last - 1] - points[last]).normalized(), radius)


# A collar at a pipe's end. `inward` points from the end along the pipe. The bolts sit on the
# collar's inner face, where they can be seen, and are batched into one MultiMesh at the end.
func _flange(end: Vector3, inward: Vector3, radius: float) -> void:
	_ring(end + inward * 0.45, inward, radius * 1.16, 0.9, C_PIPE_DARK)
	var count := clampi(int(radius * 5.0), 10, 28)
	var frame := _align_y(inward)
	var perp := frame.x
	var perp2 := frame.z
	for k in count:
		var a := TAU * float(k) / float(count)
		var off := (perp * cos(a) + perp2 * sin(a)) * radius * 1.09
		_bolts.append(Transform3D(frame, end + inward * 0.92 + off))


func _flush_bolts() -> void:
	if _bolts.is_empty():
		return
	var cm := CylinderMesh.new()
	cm.top_radius = 0.14
	cm.bottom_radius = 0.14
	cm.height = 0.22
	cm.radial_segments = 6
	cm.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cm
	mm.instance_count = _bolts.size()
	for i in _bolts.size():
		mm.set_instance_transform(i, _bolts[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _cel(C_STEEL)
	_vis.add_child(mmi)


# --- the shell ---------------------------------------------------------------

func _shell() -> void:
	# Floor, and the causeway that joins it to the jump grid.
	_box(Vector3(0, -0.5, 0), Vector3(HALF_X * 2.0, 1.0, HALF_Z * 2.0), C_FLOOR)
	_box(Vector3(0, -0.5, -HALF_Z - CAUSEWAY_LENGTH * 0.5),
		Vector3(CAUSEWAY_WIDTH, 1.0, CAUSEWAY_LENGTH), C_FLOOR)
	# Hazard edge lines down the causeway: two thin strips, not solid.
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(sx * (CAUSEWAY_WIDTH * 0.5 - 0.3), 0.012, -HALF_Z - CAUSEWAY_LENGTH * 0.5),
			Vector3(0.25, 0.02, CAUSEWAY_LENGTH), C_YELLOW, false, Basis.IDENTITY, false)

	# Four walls and a roof, one metre thick, outside the playable box.
	var wall_len := HALF_X * 2.0 + 2.0
	_box(Vector3(0, HEIGHT * 0.5, HALF_Z + 0.5), Vector3(wall_len, HEIGHT, 1.0), C_WALL)
	_box(Vector3(HALF_X + 0.5, HEIGHT * 0.5, 0), Vector3(1.0, HEIGHT, HALF_Z * 2.0), C_WALL)
	_box(Vector3(-HALF_X - 0.5, HEIGHT * 0.5, 0), Vector3(1.0, HEIGHT, HALF_Z * 2.0), C_WALL)
	_box(Vector3(0, HEIGHT + 0.5, 0), Vector3(wall_len, 1.0, HALF_Z * 2.0 + 2.0), C_WALL)
	# The -Z wall, with the door cut out of it.
	var side_w := HALF_X + 1.0 - DOOR_HALF
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(sx * (DOOR_HALF + side_w * 0.5), HEIGHT * 0.5, -HALF_Z - 0.5),
			Vector3(side_w, HEIGHT, 1.0), C_WALL)
	_box(Vector3(0, (DOOR_HEIGHT + HEIGHT) * 0.5, -HALF_Z - 0.5),
		Vector3(DOOR_HALF * 2.0, HEIGHT - DOOR_HEIGHT, 1.0), C_WALL)
	# The doorframe and the two lamps either side of it.
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(sx * (DOOR_HALF + 0.3), DOOR_HEIGHT * 0.5, -HALF_Z + 0.2),
			Vector3(0.6, DOOR_HEIGHT, 0.9), C_STEEL, false)
		_warm_lamp(Vector3(sx * (DOOR_HALF + 1.4), 5.0, -HALF_Z + 0.6), 1.6, 12.0)
	_box(Vector3(0, DOOR_HEIGHT + 0.3, -HALF_Z + 0.2),
		Vector3(DOOR_HALF * 2.0 + 1.2, 0.6, 0.9), C_YELLOW, false)

	# Wall ribs and belts: dressing that gives a flat wall scale.
	for x in range(-40, 41, 8):
		_box(Vector3(x, HEIGHT * 0.5, HALF_Z - 0.3), Vector3(0.8, HEIGHT, 0.6), C_STEEL, false)
		if absi(x) > 7:
			_box(Vector3(x, HEIGHT * 0.5, -HALF_Z + 0.3), Vector3(0.8, HEIGHT, 0.6), C_STEEL, false)
	for z in range(-24, 25, 8):
		_box(Vector3(HALF_X - 0.3, HEIGHT * 0.5, z), Vector3(0.6, HEIGHT, 0.8), C_STEEL, false)
		_box(Vector3(-HALF_X + 0.3, HEIGHT * 0.5, z), Vector3(0.6, HEIGHT, 0.8), C_STEEL, false)
	for y: float in [12.0, 24.0, 36.0]:
		_box(Vector3(0, y, HALF_Z - 0.3), Vector3(HALF_X * 2.0, 0.5, 0.6), C_STEEL, false)
		_box(Vector3(HALF_X - 0.3, y, 0), Vector3(0.6, 0.5, HALF_Z * 2.0), C_STEEL, false)
		_box(Vector3(-HALF_X + 0.3, y, 0), Vector3(0.6, 0.5, HALF_Z * 2.0), C_STEEL, false)

	# Lamps down the causeway, both sides.
	for zi in 4:
		var z := -HALF_Z - 4.0 - float(zi) * 8.0
		for sx: float in [-1.0, 1.0]:
			var p := Vector3(sx * (CAUSEWAY_WIDTH * 0.5 - 0.15), 0, z)
			_box(p + Vector3(0, 1.4, 0), Vector3(0.14, 2.8, 0.14), C_STEEL, false)
			_warm_lamp(p + Vector3(0, 3.0, 0), 1.4, 9.0)


func _pipes() -> void:
	# The big pipe lying along the floor: the foreground mass of the painting, and a surface you
	# can run across the top of.
	var main := PackedVector3Array([Vector3(-HALF_X, 5.0, 19.0), Vector3(HALF_X, 5.0, 19.0)])
	_pipe(main, 5.0, C_PIPE)
	for x: float in [-36.0, -12.0, 12.0, 36.0]:
		for sz: float in [-1.0, 1.0]:
			_box(Vector3(x, 1.25, 19.0 + sz * 5.4), Vector3(3.0, 2.5, 1.4), C_STEEL)

	# The left elbow: straight up from the floor, over at the top, across the hall into the far
	# wall. The vertical run is a wall-run surface.
	var left: Array[Vector3] = [
		Vector3(-41.0, 0.0, -22.0), Vector3(-41.0, 34.0, -22.0), Vector3(-41.0, 34.0, HALF_Z + 0.5)]
	_pipe(_fillet(left, 10.0), 4.2, C_PIPE)

	# The right elbow: up the east side and out through the east wall.
	var right: Array[Vector3] = [
		Vector3(38.0, 0.0, -22.0), Vector3(38.0, 30.0, -22.0), Vector3(HALF_X + 0.5, 30.0, -22.0)]
	_pipe(_fillet(right, 8.0), 3.6, C_PIPE)

	# A pair of slimmer risers against the west wall, close enough to wall-run between.
	for z: float in [-8.0, -1.0]:
		_pipe(PackedVector3Array([Vector3(-44.5, 0, z), Vector3(-44.5, HEIGHT, z)]), 2.2, C_PIPE_DARK)
	# A run across the back wall at mid height.
	_pipe(PackedVector3Array(
		[Vector3(-HALF_X, 26.0, HALF_Z - 2.2), Vector3(HALF_X, 26.0, HALF_Z - 2.2)]), 2.2, C_PIPE_DARK)
	# Three overhead runs, too high to touch; they are here for the silhouette.
	for z: float in [-22.0, -18.5, -15.0]:
		_pipe(PackedVector3Array([Vector3(-HALF_X, 37.5, z), Vector3(HALF_X, 37.5, z)]),
			1.6, C_PIPE_DARK, false, 7.0)


func _columns() -> void:
	# The two main supports, either side of the central catwalk.
	for x: float in [-14.0, 18.0]:
		_pipe(PackedVector3Array([Vector3(x, 0, -3.0), Vector3(x, HEIGHT, -3.0)]), 2.5, C_PIPE, true, 7.0)


# --- catwalks ----------------------------------------------------------------

func _walkways() -> void:
	# A: the long central span.
	_walkway(Vector3(-34.0, 14.0, 3.0), Vector3(26.0, 14.0, 3.0), 4.0, 10.0)
	_struts(Vector3(-34.0, 14.0, 3.0), Vector3(26.0, 14.0, 3.0), 4.0, 12.0)
	# B: the lower deck on the west side.
	_walkway(Vector3(-34.0, 7.0, -14.0), Vector3(-10.0, 7.0, -14.0), 3.5, 12.0)
	_struts(Vector3(-34.0, 7.0, -14.0), Vector3(-10.0, 7.0, -14.0), 3.5, 12.0)
	# C: the upper platform on the east side.
	_platform(Vector3(40.0, 20.0, -1.5), Vector3(8.0, 0.4, 17.0))

	# Ramps: floor up to B, B up to A, A up to C.
	_ramp(Vector3(2.12, 0.0, -14.0), Vector3(-10.0, 7.0, -14.0), 3.0)
	_ramp(Vector3(-28.0, 7.0, -12.25), Vector3(-28.0, 14.0, 1.0), 3.0)
	_ramp(Vector3(26.0, 14.0, 3.0), Vector3(36.4, 20.0, 3.0), 3.0)


## An axis-aligned catwalk between `a` and `b`, `a.y` being the walking surface: solid deck,
## railings, a toe plate, two beams underneath and a warm lamp every `lamp_every` metres.
func _walkway(a: Vector3, b: Vector3, width: float, lamp_every: float) -> void:
	var length := a.distance_to(b)
	var d := (b - a).normalized()
	var mid := (a + b) * 0.5
	var along_x := absf(d.x) > 0.5
	var deck := Vector3(length, 0.4, width) if along_x else Vector3(width, 0.4, length)
	_box(mid + Vector3(0, -0.2, 0), deck, C_DECK)
	var side := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var bar := Vector3(length, 0.09, 0.09) if along_x else Vector3(0.09, 0.09, length)
	var plate := Vector3(length, 0.22, 0.05) if along_x else Vector3(0.05, 0.22, length)
	var beam := Vector3(length, 0.5, 0.3) if along_x else Vector3(0.3, 0.5, length)
	for s: float in [-1.0, 1.0]:
		var edge: Vector3 = side * (width * 0.5 - 0.06) * s
		_box(mid + edge + Vector3(0, 1.1, 0), bar, C_YELLOW, false, Basis.IDENTITY, false)
		_box(mid + edge + Vector3(0, 0.55, 0), bar, C_STEEL, false, Basis.IDENTITY, false)
		_box(mid + edge + Vector3(0, 0.11, 0), plate, C_STEEL, false, Basis.IDENTITY, false)
		_box(mid + side * (width * 0.5 - 0.3) * s + Vector3(0, -0.65, 0), beam, C_STEEL, false)
		var posts := int(length / 2.5)
		for i in posts + 1:
			var p := a + d * (length * float(i) / float(posts)) + edge
			_box(p + Vector3(0, 0.55, 0), Vector3(0.08, 1.1, 0.08), C_STEEL, false,
				Basis.IDENTITY, false)
	var lamps := int(length / lamp_every)
	for i in lamps:
		var p := a + d * (lamp_every * (float(i) + 0.5)) + side * (width * 0.5 - 0.06)
		_warm_lamp(p + Vector3(0, 1.55, 0), 1.5, 10.0)


## Diagonal braces from under a catwalk to the floor, in pairs every `every` metres.
func _struts(a: Vector3, b: Vector3, width: float, every: float) -> void:
	var length := a.distance_to(b)
	var d := (b - a).normalized()
	var along_x := absf(d.x) > 0.5
	var side := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var count := int(length / every)
	for i in count:
		var p := a + d * (every * (float(i) + 0.5)) + Vector3(0, -0.5, 0)
		for s: float in [-1.0, 1.0]:
			var top: Vector3 = p + side * (width * 0.5 - 0.3) * s
			_beam(top, Vector3(top.x + d.x * 5.0, 0.0, top.z + d.z * 5.0), 0.35, C_STEEL)
			_beam(top, Vector3(top.x - d.x * 5.0, 0.0, top.z - d.z * 5.0), 0.35, C_STEEL)


## A solid slab standing on the ground at `centre` (its y is the walking surface).
func _platform(centre: Vector3, size: Vector3) -> void:
	_box(centre + Vector3(0, -size.y * 0.5, 0), size, C_DECK)
	# Two legs down to the floor.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(centre.x + sx * (size.x * 0.5 - 0.6), 0.0, centre.z + sz * (size.z * 0.5 - 0.6))
			_box(Vector3(p.x, (centre.y - size.y) * 0.5, p.z), Vector3(0.6, centre.y - size.y, 0.6),
				C_STEEL, true)
	# Railings on the three open sides (the ramp comes in on the west).
	var top := centre.y
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(centre.x, top + 1.1, centre.z + sz * (hz - 0.06)),
			Vector3(size.x, 0.09, 0.09), C_YELLOW, false, Basis.IDENTITY, false)
	_box(Vector3(centre.x + hx - 0.06, top + 1.1, centre.z),
		Vector3(0.09, 0.09, size.z), C_YELLOW, false, Basis.IDENTITY, false)
	_warm_lamp(Vector3(centre.x + hx - 0.5, top + 1.6, centre.z - hz + 0.5), 1.6, 11.0)
	_warm_lamp(Vector3(centre.x + hx - 0.5, top + 1.6, centre.z + hz - 0.5), 1.6, 11.0)


## A ramp from `bottom` to `top`, the walking surface running exactly through both points.
func _ramp(bottom: Vector3, top: Vector3, width: float) -> void:
	var x := (top - bottom).normalized()
	var z := x.cross(Vector3.UP).normalized()
	var y := z.cross(x)
	var frame := Basis(x, y, z)
	var length := bottom.distance_to(top)
	var mid := (bottom + top) * 0.5
	_box(mid - y * 0.2, Vector3(length, 0.4, width), C_DECK, true, frame)
	for s: float in [-1.0, 1.0]:
		var edge := z * (width * 0.5 - 0.06) * s
		_box(mid + edge + y * 1.0, Vector3(length, 0.09, 0.09), C_YELLOW, false, frame, false)
		_box(mid + edge + y * 0.5, Vector3(length, 0.09, 0.09), C_STEEL, false, frame, false)


# --- overhead ----------------------------------------------------------------

func _ceiling() -> void:
	# Girders across the hall and along it.
	for x in range(-44, 45, 11):
		_box(Vector3(x, HEIGHT - 1.4, 0), Vector3(0.9, 1.6, HALF_Z * 2.0), C_STEEL, false)
	for z: float in [-14.0, 0.0, 14.0]:
		_box(Vector3(0, HEIGHT - 2.4, z), Vector3(HALF_X * 2.0, 0.9, 0.9), C_STEEL, false)

	# The cable tangle: bundles of three, swung between two points with a parabolic sag.
	var rng := RandomNumberGenerator.new()
	rng.seed = cable_seed
	for i in 18:
		var a := Vector3(rng.randf_range(-44.0, 44.0), rng.randf_range(40.5, 43.5), rng.randf_range(-24.0, 24.0))
		var b := a + Vector3(rng.randf_range(-24.0, 24.0), rng.randf_range(-2.0, 1.0), rng.randf_range(-12.0, 12.0))
		b.x = clampf(b.x, -46.0, 46.0)
		b.z = clampf(b.z, -26.0, 26.0)
		var sag := rng.randf_range(2.0, 7.5)
		var radius := rng.randf_range(0.12, 0.22)
		var perp := (b - a).cross(Vector3.UP).normalized()
		for k in 3:
			var off := perp * (float(k) - 1.0) * 0.42 + Vector3(0, float(k % 2) * 0.3, 0)
			var pts := PackedVector3Array()
			for s in 17:
				var t := float(s) / 16.0
				var p := a.lerp(b, t) + off
				p.y -= sag * 4.0 * t * (1.0 - t)
				pts.append(p)
			var mesh := RAIL_SCRIPT.tube_mesh(pts, radius, 6, false) as ArrayMesh
			if mesh:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.material_override = _cel(C_CABLE)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_vis.add_child(mi)


func _ceiling_lamps() -> void:
	var spots := [
		Vector3(-26.0, 40.0, -6.0), Vector3(-4.0, 40.0, 10.0), Vector3(12.0, 40.0, -10.0),
		Vector3(30.0, 40.0, 8.0), Vector3(-34.0, 40.0, 14.0)]
	for p: Vector3 in spots:
		_ceiling_lamp(p)


# A hanging shade, its bulb, a cool spotlight and the faint shaft it throws.
func _ceiling_lamp(pos: Vector3) -> void:
	_box(pos + Vector3(0, (HEIGHT - pos.y) * 0.5 + 0.55, 0),
		Vector3(0.12, HEIGHT - pos.y - 1.1, 0.12), C_STEEL, false, Basis.IDENTITY, false)
	var shade := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.3
	cone.bottom_radius = 1.3
	cone.height = 1.1
	cone.radial_segments = 20
	shade.mesh = cone
	shade.material_override = _cel(C_STEEL)
	shade.position = pos
	_vis.add_child(shade)
	var bulb := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.08
	bulb.mesh = disc
	bulb.material_override = _glow(C_LAMP_COOL) if CEILING_LIGHTS_ON else _cel(C_STEEL)
	bulb.position = pos + Vector3(0, -0.52, 0)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(bulb)

	if not CEILING_LIGHTS_ON:
		return
	var spot := SpotLight3D.new()
	spot.position = pos + Vector3(0, -0.6, 0)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.light_color = C_LAMP_COOL
	spot.light_energy = 40.0
	spot.spot_range = pos.y + 10.0
	spot.spot_angle = 40.0
	spot.spot_attenuation = 0.5
	spot.spot_angle_attenuation = 2.5
	spot.shadow_enabled = true
	_lit.add_child(spot)

	var reach := pos.y - 0.6
	var shaft := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.6
	sm.bottom_radius = reach * tan(deg_to_rad(40.0))
	sm.height = reach
	sm.radial_segments = 28
	sm.rings = 1
	shaft.mesh = sm
	shaft.material_override = _beam_material(C_LAMP_COOL, reach)
	shaft.position = Vector3(pos.x, reach * 0.5, pos.z)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(shaft)


## A caged warm lamp: a glowing bulb in a steel cup, and an omni to go with it. No shadows, so a
## couple of dozen of them cost almost nothing.
func _warm_lamp(pos: Vector3, energy: float, reach: float) -> void:
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	sphere.radial_segments = 12
	sphere.rings = 6
	bulb.mesh = sphere
	bulb.material_override = _glow(C_LAMP_WARM)
	bulb.position = pos
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(bulb)
	var cup := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.28
	cm.bottom_radius = 0.12
	cm.height = 0.18
	cm.radial_segments = 10
	cup.mesh = cm
	cup.material_override = _cel(C_STEEL)
	cup.position = pos + Vector3(0, -0.22, 0)
	cup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(cup)
	var omni := OmniLight3D.new()
	omni.position = pos
	omni.light_color = C_LAMP_WARM
	omni.light_energy = energy
	omni.omni_range = reach
	omni.omni_attenuation = 1.4
	_lit.add_child(omni)


func _far_wall() -> void:
	# A sealed blast door at the east end: frame, panel, and ribs across it.
	var x := HALF_X - 0.45
	_box(Vector3(x, 10.0, 0), Vector3(0.9, 20.0, 26.0), C_STEEL, false)
	_box(Vector3(x - 0.25, 10.0, 0), Vector3(0.6, 18.0, 23.0), C_PIPE_DARK, false)
	for y in range(3, 18, 3):
		_box(Vector3(x - 0.6, float(y), 0), Vector3(0.3, 0.35, 23.0), C_STEEL, false)
	for z: float in [-8.0, 0.0, 8.0]:
		_box(Vector3(x - 0.6, 10.0, z), Vector3(0.3, 18.0, 0.35), C_STEEL, false)
	_box(Vector3(x - 0.5, 20.2, 0), Vector3(1.0, 0.5, 26.0), C_YELLOW, false)
	for z: float in [-14.0, 14.0]:
		_warm_lamp(Vector3(x - 1.0, 7.0, z), 1.8, 12.0)


# --- grind rails ---------------------------------------------------------------

func _grind_rails() -> void:
	# From the upper platform down across the hall to catwalk A: a long, gentle ride.
	_rail("GrindRail", [
		Vector3(42.0, 20.8, 6.0), Vector3(42.0, 19.0, 15.0), Vector3(22.0, 17.0, 17.0),
		Vector3(8.0, 15.0, 4.5)], [Vector3(42.0, 19.0, 15.0), Vector3(22.0, 17.0, 17.0)])


func _rail(nm: String, pts: Array[Vector3], hangers: Array[Vector3]) -> void:
	var curve := Curve3D.new()
	for i in pts.size():
		var prev := pts[maxi(i - 1, 0)]
		var next := pts[mini(i + 1, pts.size() - 1)]
		var tangent := (next - prev) / 6.0
		curve.add_point(pts[i], -tangent, tangent)
	var rail := RAIL_SCRIPT.new() as Path3D
	rail.name = nm
	rail.curve = curve
	add_child(rail)
	for h in hangers:
		_beam(Vector3(h.x, HEIGHT - 0.5, h.z), h + Vector3(0, 0.1, 0), 0.12, C_STEEL)


# --- ambient ----------------------------------------------------------------------

# Replaces the scene's bright sky ambient inside the hall with a dark blue of its own. Without
# this the sky's light reaches every surface through the open sky dome and the place reads as a
# pale room rather than a cavern.
func _ambient() -> void:
	var probe := ReflectionProbe.new()
	probe.name = "Ambient"
	# Padded well past the floor and walls: a probe blends out toward the scene's pale sky ambient
	# at its edge, and with the floor AT the edge that glow crept up everything standing on it.
	var pad := 12.0
	probe.position = Vector3(0, HEIGHT * 0.5, 0)
	probe.size = Vector3(HALF_X * 2.0 + pad * 2.0, HEIGHT + pad * 2.0, HALF_Z * 2.0 + pad * 2.0)
	probe.interior = true
	probe.box_projection = false
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.055, 0.080, 0.145)
	probe.ambient_color_energy = 1.0
	probe.intensity = 0.0
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.cull_mask = 0
	add_child(probe)
