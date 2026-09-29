@tool
class_name Rail
extends Path3D

# A grind rail: draw the Curve3D in the editor with Bezier handles, paste the node into a map
# the way bounce_pad.gd and the button/door are pasted, and pilot9 rides whatever you drew.
# See docs/specs/pilot9-rail-grind.md.
#
# THE CURVE IS THE RAIL. The tube is generated from it and has no collision at all - what he
# rides and what you see come from the same curve, so they cannot disagree, and a 16 cm curved
# trimesh floor (where CharacterBody3D jitters) never exists. Walking or rising through the tube
# clips for a moment and can never snag him, give a stray is_on_floor(), or become a wall-run
# surface.
#
# LOCAL SPACE, ALWAYS. Every question pilot9 asks this node - where is the centreline, which way
# does it run, how far along is the closest point - is answered through the rail's CURRENT
# global_transform. The grind stores an offset along the curve and never a world position, so a
# rail parented to something that moves (map #4's cables on the giant) carries him with it at no
# extra cost.
#
# Found through the `rails` group rather than a registry: a map holds a handful, and
# get_closest_offset() per rail per airborne frame is cheap.
#
# pilot9.gd never names this class - it duck-types the methods below on a plain Node, for the
# stale-global-class-cache reason bounce_pad.gd's header gives.

const GROUP := &"rails"

## The grab colour off the jump grid ruler (jump_grid.gd's COLOUR_GRAB): a rail is something
## you catch, so it borrows "what you grab" rather than claiming a new slot in the palette.
const COLOUR_RAIL := Color(0.20, 0.78, 0.92)

## The same shader every blockout box and the ruler wear - see blockout_box.gd::_material().
## Unshaded, world-space metre lines, so a rail counts its own length the way a box does.
const GRID_SHADER := "res://shaders/metre_grid.gdshader"

## The generated child, cleared by name on every rebuild so a duplicated rail never owns two.
const TUBE_NAME := "Tube"

## A freshly pasted rail with no curve gets this one: 6 m straight along -Z, level. Something
## to see and grab a handle of, not a design.
const DEFAULT_LENGTH := 6.0

## Tube radius, metres. His feet ride at centreline + this. Thicker for map #4's cables.
@export_range(0.01, 1.0, 0.01, "or_greater") var rail_radius: float = 0.08:
	set(value):
		rail_radius = maxf(value, 0.01)
		_rebuild()

## Verts per ring of the generated tube.
@export_range(3, 32, 1) var rail_sides: int = 8:
	set(value):
		rail_sides = clampi(value, 3, 64)
		_rebuild()


func _ready() -> void:
	add_to_group(GROUP)
	if curve == null:
		curve = _default_curve()
	if not curve_changed.is_connected(_rebuild):
		curve_changed.connect(_rebuild)
	_rebuild()


func _default_curve() -> Curve3D:
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO)
	c.add_point(Vector3(0.0, 0.0, -DEFAULT_LENGTH))
	return c


# --- what pilot9 asks -------------------------------------------------------------
# Offsets are curve-local metres (Curve3D's own baked length). Positions and directions come
# back in WORLD space, through the transform as it stands this frame.

## Length of the ride, metres along the curve.
func ride_length() -> float:
	return curve.get_baked_length() if curve != null else 0.0


## True when the curve closes on itself: the ride wraps and has no end. `closed` arrived on
## Curve3D in Godot 4.4; asked by name so an older curve simply reads as open.
func is_loop() -> bool:
	return curve != null and "closed" in curve and bool(curve.get("closed"))


## The rail's up, for the "above the centreline" gate and for where his feet sit. The node's
## own up rather than a per-point one: a rail tilted by its parent tilts its up with it.
func up() -> Vector3:
	return global_transform.basis.y.normalized()


## The closest point on the centreline to `world_pos`, as an offset along the curve.
func closest_offset(world_pos: Vector3) -> float:
	if curve == null:
		return 0.0
	return curve.get_closest_offset(global_transform.affine_inverse() * world_pos)


## The centreline at `offset`, in world space.
func point_at(offset: float) -> Vector3:
	if curve == null:
		return global_position
	return global_transform * curve.sample_baked(offset, true)


## Where his feet ride at `offset`: on top of the tube, centreline + rail_radius along up().
func top_at(offset: float) -> Vector3:
	return point_at(offset) + up() * rail_radius


## The world direction of increasing offset at `offset`, unit length. Central-differenced off
## the baked curve rather than read off sample_baked_with_rotation()'s basis, whose forward axis
## convention is one sign flip away from sending him backwards.
func tangent_at(offset: float) -> Vector3:
	if curve == null:
		return -global_transform.basis.z.normalized()
	var length := ride_length()
	var h := minf(0.05, maxf(length * 0.25, 0.001))
	var a := offset - h
	var b := offset + h
	if not is_loop():
		a = clampf(a, 0.0, length)
		b = clampf(b, 0.0, length)
	var local := curve.sample_baked(b, true) - curve.sample_baked(a, true)
	var world := global_transform.basis * local
	return world.normalized() if world.length() > 0.00001 else Vector3.FORWARD


# --- the tube ---------------------------------------------------------------------

func _rebuild() -> void:
	# Setters fire while the scene file is still being read, before there is a tree to add
	# children to. _ready() runs this again once there is - blockout_box.gd's rule.
	if not is_inside_tree():
		return
	var old := get_node_or_null(TUBE_NAME)
	if old:
		remove_child(old)
		old.queue_free()
	if curve == null or curve.point_count < 2:
		return
	var mesh := tube_mesh(curve.get_baked_points(), rail_radius, rail_sides, is_loop())
	if mesh == null:
		return
	var tube := MeshInstance3D.new()
	tube.name = TUBE_NAME
	tube.mesh = mesh
	tube.material_override = _material()
	# Unshaded, so a shadow on it could not be seen; the same call the boxes make.
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# No owner: the .tscn stores the curve and the two numbers, never the geometry.
	add_child(tube)


func _material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = load(GRID_SHADER) as Shader
	mat.set_shader_parameter("base_color", COLOUR_RAIL)
	return mat


## A ring of `sides` verts swept along `points` at `radius`, in the points' own space. Frames
## are parallel-transported rather than built off a fixed up, so a rail that goes vertical does
## not pinch or spin its rings. Open tubes get flat end caps; a loop joins its last ring to its
## first. Null for fewer than two distinct points. Static so the tests can sweep a known line.
static func tube_mesh(points: PackedVector3Array, radius: float, sides: int,
		closed: bool) -> ArrayMesh:
	var pts := PackedVector3Array()
	for p in points:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 0.0001:
			pts.append(p)
	if closed and pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < 0.01:
		pts.remove_at(pts.size() - 1)
	var n := pts.size()
	if n < 2:
		return null
	sides = maxi(sides, 3)

	var tangents: Array[Vector3] = []
	for i in n:
		var prev := pts[i - 1] if (i > 0 or closed) else pts[i]
		var next := pts[(i + 1) % n] if (i < n - 1 or closed) else pts[i]
		var t := next - prev
		tangents.append(t.normalized() if t.length() > 0.00001 else Vector3.FORWARD)

	# Seed the first frame off world up, or off X for a rail that starts vertical.
	var start_up := Vector3.UP if absf(tangents[0].dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var normal := (start_up - tangents[0] * start_up.dot(tangents[0])).normalized()
	var rings: Array[PackedVector3Array] = []
	var ring_normals: Array[PackedVector3Array] = []
	for i in n:
		var t := tangents[i]
		normal = (normal - t * normal.dot(t))
		normal = normal.normalized() if normal.length() > 0.00001 else t.cross(Vector3.RIGHT).normalized()
		var binormal := t.cross(normal).normalized()
		var ring := PackedVector3Array()
		var nrm := PackedVector3Array()
		for s in sides:
			var a := TAU * float(s) / float(sides)
			var dir := normal * cos(a) + binormal * sin(a)
			ring.append(pts[i] + dir * radius)
			nrm.append(dir)
		rings.append(ring)
		ring_normals.append(nrm)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := n if closed else n - 1
	for i in segments:
		var j := (i + 1) % n
		for s in sides:
			var s2 := (s + 1) % sides
			_tri(st, rings[i][s], ring_normals[i][s], rings[j][s], ring_normals[j][s],
				rings[j][s2], ring_normals[j][s2])
			_tri(st, rings[i][s], ring_normals[i][s], rings[j][s2], ring_normals[j][s2],
				rings[i][s2], ring_normals[i][s2])
	if not closed:
		_cap(st, pts[0], rings[0], -tangents[0], false)
		_cap(st, pts[n - 1], rings[n - 1], tangents[n - 1], true)
	return st.commit()


# Godot's front faces are clockwise as seen by the viewer. Along-then-around is
# (b - a) x (c - a) = t x around = -outward, i.e. clockwise seen from OUTSIDE, which is the
# side cull_back must keep. The caps below are wound by the same rule.
static func _tri(st: SurfaceTool, a: Vector3, na: Vector3, b: Vector3, nb: Vector3,
		c: Vector3, nc: Vector3) -> void:
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


static func _cap(st: SurfaceTool, centre: Vector3, ring: PackedVector3Array, facing: Vector3,
		at_end: bool) -> void:
	var count := ring.size()
	for s in count:
		var a := ring[s]
		var b := ring[(s + 1) % count]
		st.set_normal(facing)
		st.add_vertex(centre)
		if at_end:
			st.set_normal(facing)
			st.add_vertex(b)
			st.set_normal(facing)
			st.add_vertex(a)
		else:
			st.set_normal(facing)
			st.add_vertex(a)
			st.set_normal(facing)
			st.add_vertex(b)
