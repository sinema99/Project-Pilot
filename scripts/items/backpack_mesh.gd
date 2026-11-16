## The backpack's mesh, built in code: a faceted PS1 rucksack after the user's reference (olive
## canvas, drawstring top under a rounded flap with a leather trim and one strap + buckle, three
## front pockets with leather tabs and buckles, side pockets, a grab loop). Flat shaded, one surface
## per colour. See docs/specs/pilot9-backpack.md.
##
## Pack space: metres, origin at the bottom of the face that lies against his back, +Y up the pack,
## +Z out away from him, X across.
extends RefCounted

## Surface indices: one material each.
const CANVAS := 0
const SEAM := 1
const LEATHER := 2
const METAL := 3
## The glowing flat bottom of each floater.
const THRUSTER := 4
const SURFACES := 5

## Main bag body, bottom to top: [y, width, depth, chamfer]. The drawstring gather is the last.
const BODY_RINGS := [
	[0.0, 0.34, 0.12, 0.05],
	[0.04, 0.40, 0.18, 0.06],
	[0.22, 0.41, 0.19, 0.06],
	[0.36, 0.38, 0.17, 0.05],
	[0.46, 0.30, 0.12, 0.04],
	[0.50, 0.18, 0.06, 0.03],
]

var _st: Array[SurfaceTool] = []


static func build() -> ArrayMesh:
	var b := new()
	b._shape()
	var mesh := ArrayMesh.new()
	for st in b._st:
		mesh = st.commit(mesh)
	return mesh


## One single-surface mesh per colour (CANVAS, SEAM, LEATHER, METAL), each to wear its own
## material_override - the looks recolour material_override, not per-surface overrides.
static func build_parts() -> Array[ArrayMesh]:
	var b := new()
	b._shape()
	var out: Array[ArrayMesh] = []
	for st in b._st:
		out.append(st.commit())
	return out


## The colour per surface, in surface order.
const COLOURS := [Color(0.42, 0.40, 0.22), Color(0.33, 0.31, 0.16), Color(0.30, 0.17, 0.09),
	Color(0.52, 0.52, 0.5), Color(0.35, 0.88, 1.0)]
const PART_NAMES := [&"Canvas", &"Seam", &"Leather", &"Metal", &"Thruster"]


## A Node3D holding the four parts, each in `materials[i]` (one per surface).
static func build_node(materials: Array) -> Node3D:
	var root := Node3D.new()
	var parts := build_parts()
	for i in parts.size():
		var mi := MeshInstance3D.new()
		mi.name = PART_NAMES[i]
		mi.mesh = parts[i]
		mi.material_override = materials[i]
		root.add_child(mi)
	return root


func _shape() -> void:
	for i in SURFACES:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st.append(st)
	_body()
	_flap()
	_pockets()
	_side_pockets()
	_grab_loop()
	_floaters()


# --- shapes -------------------------------------------------------------------------------------

func _body() -> void:
	var rings: Array = []
	for r: Array in BODY_RINGS:
		rings.append(_ring(r[0], r[1], r[2], r[3]))
	_loft(CANVAS, rings, true, true)


## The top flap: a thin slab from the gathered top down over the front, rounded at the bottom,
## with a leather trim round its edge, a leather patch and the strap + buckle down the middle.
func _flap() -> void:
	# Stations from the top down: [y, z, half width, bottom rounding drop].
	var stations := [
		[0.515, 0.02, 0.12, 0.0],
		[0.505, 0.085, 0.155, 0.0],
		[0.45, 0.16, 0.175, 0.0],
		[0.37, 0.19, 0.175, 0.0],
		[0.31, 0.198, 0.15, 0.035],
	]
	var outer: Array = []
	var inner: Array = []
	for s: Array in stations:
		var row := PackedVector3Array()
		var row_in := PackedVector3Array()
		for k in 5:
			var t := (k - 2) / 2.0
			var y: float = s[0] + absf(t) * absf(t) * float(s[3])
			var p := Vector3(t * float(s[2]), y, float(s[1]))
			var n := Vector3(0.0, y - 0.3, p.z - 0.04).normalized()
			row.append(p + n * 0.012)
			row_in.append(p)
		outer.append(row)
		inner.append(row_in)
	_slab(CANVAS, outer, inner, Vector3(0.0, 0.3, 0.04))
	# Trim: down the left edge, along the bottom, up the right edge.
	var edge := PackedVector3Array()
	for i in range(1, outer.size()):
		edge.append((outer[i] as PackedVector3Array)[0])
	var bottom: PackedVector3Array = outer[outer.size() - 1]
	for k in range(1, 5):
		edge.append(bottom[k])
	for i in range(outer.size() - 2, 0, -1):
		edge.append((outer[i] as PackedVector3Array)[4])
	_ribbon(LEATHER, edge, 0.018, 0.006, Vector3(0.0, 0.3, 0.0))
	# The oval patch, up and right of centre.
	_disc(LEATHER, Vector3(0.075, 0.43, 0.192), Vector3(0.0, 0.35, 1.0).normalized(), 0.032, 0.026, 0.006)
	# The strap down the middle and its buckle.
	var strap := PackedVector3Array([Vector3(0.0, 0.40, 0.2), Vector3(0.0, 0.32, 0.214),
		Vector3(0.0, 0.27, 0.198), Vector3(0.0, 0.225, 0.196)])
	_ribbon(LEATHER, strap, 0.026, 0.006, Vector3(0.0, 0.3, 0.0))
	_box(METAL, Vector3(0.0, 0.345, 0.218), Vector3(0.02, 0.011, 0.005))


## Three front pockets: a wide middle one with two tabs, a small one each side with one.
func _pockets() -> void:
	_pocket(Vector3(0.0, 0.14, 0.19), Vector2(0.10, 0.085), 0.07, 0.0, [-0.05, 0.05])
	_pocket(Vector3(-0.165, 0.135, 0.165), Vector2(0.055, 0.08), 0.06, -0.45, [0.0])
	_pocket(Vector3(0.165, 0.135, 0.165), Vector2(0.055, 0.08), 0.06, 0.45, [0.0])


## A pocket: a box standing `depth` proud of `back` (centre of its back face), half size `half`,
## turned `yaw` radians; a seam-coloured flap over its top; a leather tab + buckle at each x.
func _pocket(back: Vector3, half: Vector2, depth: float, yaw: float, tabs: Array) -> void:
	var b := Basis(Vector3.UP, yaw)
	var centre := back + b * Vector3(0.0, 0.0, depth * 0.5)
	_box(CANVAS, centre, Vector3(half.x, half.y, depth * 0.5), b)
	var flap_c := back + b * Vector3(0.0, half.y - 0.022, depth * 0.5 + 0.004)
	_box(SEAM, flap_c, Vector3(half.x + 0.006, 0.026, depth * 0.5 + 0.004), b)
	var face := depth + 0.01
	for x: float in tabs:
		var top := back + b * Vector3(x, half.y + 0.004, face)
		var tip := back + b * Vector3(x, half.y - 0.085, face)
		_tab(LEATHER, top, tip, b * Vector3.BACK, 0.013)
		_box(METAL, back + b * Vector3(x, half.y - 0.058, face + 0.004), Vector3(0.016, 0.009, 0.004), b)


func _side_pockets() -> void:
	for side in [-1.0, 1.0]:
		var c := Vector3(side * 0.225, 0.14, 0.09)
		_box(CANVAS, c, Vector3(0.025, 0.075, 0.065))
		_box(SEAM, c + Vector3(side * 0.002, 0.055, 0.0), Vector3(0.027, 0.022, 0.067))


## Two floaters (dark-green body, glowing THRUSTER cap) under the bottom corners of the pack, their bottoms tilted
## away from each other and out from his back.
func _floaters() -> void:
	for side in [-1.0, 1.0]:
		_sphere(SEAM, Vector3(side * 0.2, -0.03, 0.09), 0.06, side * deg_to_rad(25.0), deg_to_rad(25.0))


## A faceted dome over a cylinder (12 around), turned `tilt` radians about Z around the dome's
## centre. The holder squashes the pack across X by pack_width (0.85), so the shape is
## pre-stretched by 1/0.85 (after the tilt) to come out round.
func _sphere(surface: int, centre: Vector3, r: float, tilt: float = 0.0, back: float = 0.0) -> void:
	var around := 12
	var bands := 3
	var sx := 1.0 / 0.85
	# `back` swings the bottom out along +Z, away from the pilot's back.
	var rot := Basis(Vector3.BACK, tilt) * Basis(Vector3.RIGHT, -back)
	var at := func(v: Vector3) -> Vector3:
		var w: Vector3 = rot * v
		return centre + Vector3(w.x * sx, w.y, w.z)
	var drop := Vector3(0.0, -r, 0.0)
	var inside: Vector3 = at.call(drop * 0.5)
	# Lower half: a straight cylinder, as tall as the radius, with a flat bottom.
	for k in around:
		var t0 := TAU * k / around
		var t1 := TAU * (k + 1) / around
		var l0 := Vector3(cos(t0), 0.0, sin(t0)) * r
		var l1 := Vector3(cos(t1), 0.0, sin(t1)) * r
		_quad(surface, at.call(l0), at.call(l1), at.call(l1 + drop), at.call(l0 + drop), inside)
		_tri(THRUSTER, at.call(drop), at.call(l1 + drop), at.call(l0 + drop), inside)
	# Upper half: the hemisphere.
	for j in bands:
		var a0 := PI * 0.5 * j / bands
		var a1 := PI * 0.5 * (j + 1) / bands
		for k in around:
			var t0 := TAU * k / around
			var t1 := TAU * (k + 1) / around
			var p00: Vector3 = at.call(Vector3(sin(a0) * cos(t0), cos(a0), sin(a0) * sin(t0)) * r)
			var p01: Vector3 = at.call(Vector3(sin(a0) * cos(t1), cos(a0), sin(a0) * sin(t1)) * r)
			var p10: Vector3 = at.call(Vector3(sin(a1) * cos(t0), cos(a1), sin(a1) * sin(t0)) * r)
			var p11: Vector3 = at.call(Vector3(sin(a1) * cos(t1), cos(a1), sin(a1) * sin(t1)) * r)
			_quad(surface, p00, p01, p11, p10, inside)


func _grab_loop() -> void:
	var loop := PackedVector3Array([Vector3(-0.045, 0.49, 0.012), Vector3(-0.04, 0.55, 0.012),
		Vector3(0.0, 0.565, 0.012), Vector3(0.04, 0.55, 0.012), Vector3(0.045, 0.49, 0.012)])
	_ribbon(LEATHER, loop, 0.022, 0.008, Vector3(0.0, 0.45, 0.012), Vector3.BACK)


# --- primitives ---------------------------------------------------------------------------------

## A chamfered rectangle at height `y`, back edge on z = 0: 8 points around.
static func _ring(y: float, w: float, d: float, c: float) -> PackedVector3Array:
	var hw := w * 0.5
	return PackedVector3Array([
		Vector3(-hw + c, y, 0.0), Vector3(hw - c, y, 0.0), Vector3(hw, y, c), Vector3(hw, y, d - c),
		Vector3(hw - c, y, d), Vector3(-hw + c, y, d), Vector3(-hw, y, d - c), Vector3(-hw, y, c),
	])


static func _centroid(pts: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in pts:
		c += p
	return c / maxf(pts.size(), 1)


## Closed rings joined side by side; optional fans close the ends.
func _loft(surface: int, rings: Array, cap_bottom: bool, cap_top: bool) -> void:
	for i in rings.size() - 1:
		var a: PackedVector3Array = rings[i]
		var b: PackedVector3Array = rings[i + 1]
		var ref := (_centroid(a) + _centroid(b)) * 0.5
		for k in a.size():
			var k2 := (k + 1) % a.size()
			_quad(surface, a[k], a[k2], b[k2], b[k], ref)
	if cap_bottom:
		var r0: PackedVector3Array = rings[0]
		_fan(surface, r0, _centroid(r0), _centroid(rings[1]))
	if cap_top:
		var rn: PackedVector3Array = rings[rings.size() - 1]
		_fan(surface, rn, _centroid(rn), _centroid(rings[rings.size() - 2]))


func _fan(surface: int, ring: PackedVector3Array, centre: Vector3, inside: Vector3) -> void:
	for k in ring.size():
		_tri(surface, centre, ring[k], ring[(k + 1) % ring.size()], inside)


## A thin open sheet given as rows of points, `outer` and `inner` layers, closed round the edges.
func _slab(surface: int, outer: Array, inner: Array, inside: Vector3) -> void:
	var rows := outer.size()
	var cols := (outer[0] as PackedVector3Array).size()
	for i in rows - 1:
		for k in cols - 1:
			var o0: PackedVector3Array = outer[i]
			var o1: PackedVector3Array = outer[i + 1]
			var i0: PackedVector3Array = inner[i]
			var i1: PackedVector3Array = inner[i + 1]
			_quad(surface, o0[k], o0[k + 1], o1[k + 1], o1[k], inside)
			# The underside faces the bag.
			var mid := (i0[k] + i1[k + 1]) * 0.5
			_quad(surface, i0[k], i0[k + 1], i1[k + 1], i1[k], mid + (mid - inside).normalized() * 0.5)
	# Edges.
	for i in rows - 1:
		for k in [0, cols - 1]:
			var a: Vector3 = (outer[i] as PackedVector3Array)[k]
			var b: Vector3 = (outer[i + 1] as PackedVector3Array)[k]
			var c: Vector3 = (inner[i + 1] as PackedVector3Array)[k]
			var d: Vector3 = (inner[i] as PackedVector3Array)[k]
			var mid := (a + b + c + d) * 0.25
			_quad(surface, a, b, c, d, mid - Vector3(signf(a.x) if k > 0 else -1.0, 0.0, 0.0) * 0.1)
	for k in cols - 1:
		var last := rows - 1
		var a: Vector3 = (outer[last] as PackedVector3Array)[k]
		var b: Vector3 = (outer[last] as PackedVector3Array)[k + 1]
		var c: Vector3 = (inner[last] as PackedVector3Array)[k + 1]
		var d: Vector3 = (inner[last] as PackedVector3Array)[k]
		_quad(surface, a, b, c, d, (a + b + c + d) * 0.25 + Vector3(0.0, 0.1, 0.0))


## A flat band along `path`, `width` wide and `thick` thick, its flat side facing away from
## `centre` (or along `facing` when given): a closed box section, so it shows from any side.
func _ribbon(surface: int, path: PackedVector3Array, width: float, thick: float, centre: Vector3,
		facing: Vector3 = Vector3.ZERO) -> void:
	var rings: Array = []
	for i in path.size():
		var p := path[i]
		var tangent := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var out := facing if facing != Vector3.ZERO else (p - centre)
		out = (out - tangent * out.dot(tangent)).normalized()
		var side := tangent.cross(out).normalized()
		var hw := side * width * 0.5
		rings.append(PackedVector3Array([p - hw, p + hw, p + hw + out * thick, p - hw + out * thick]))
	for i in rings.size() - 1:
		var a: PackedVector3Array = rings[i]
		var b: PackedVector3Array = rings[i + 1]
		var ref := (_centroid(a) + _centroid(b)) * 0.5
		for k in 4:
			_quad(surface, a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k], ref)
	var first: PackedVector3Array = rings[0]
	var last: PackedVector3Array = rings[rings.size() - 1]
	_quad(surface, first[0], first[1], first[2], first[3], _centroid(rings[mini(1, rings.size() - 1)]))
	_quad(surface, last[0], last[1], last[2], last[3], _centroid(rings[maxi(rings.size() - 2, 0)]))


## A box: centre, half extents, turned by `basis`.
func _box(surface: int, centre: Vector3, half: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var c: Array[Vector3] = []
	for z in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for x in [-1.0, 1.0]:
				c.append(centre + basis * Vector3(x * half.x, y * half.y, z * half.z))
	for f in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
		_quad(surface, c[f[0]], c[f[1]], c[f[2]], c[f[3]], centre)


## A pointed leather tab hanging from `top` to `tip`, lying flat on a face whose normal is
## `normal`: a pentagon slab, `half_w` across.
func _tab(surface: int, top: Vector3, tip: Vector3, normal: Vector3, half_w: float) -> void:
	var down := (tip - top)
	var across := down.normalized().cross(normal).normalized() * half_w
	var shoulder := top + down * 0.72
	var front := PackedVector3Array([top - across, top + across, shoulder + across, tip, shoulder - across])
	var t := normal * 0.006
	var back := PackedVector3Array()
	for p in front:
		back.append(p - t)
	_prism(surface, front, back)


## An oval disc (8 sides) of half sizes `a` (across) x `b` (up), facing `normal`.
func _disc(surface: int, centre: Vector3, normal: Vector3, a: float, b: float, thick: float) -> void:
	var across := Vector3.UP.cross(normal).normalized()
	var up := normal.cross(across).normalized()
	var front := PackedVector3Array()
	var back := PackedVector3Array()
	for k in 8:
		var ang := TAU * k / 8.0
		var p := centre + across * cos(ang) * a + up * sin(ang) * b
		front.append(p + normal * thick)
		back.append(p)
	_prism(surface, front, back)


## A flat polygon `front` and its copy `back`, joined round the edge.
func _prism(surface: int, front: PackedVector3Array, back: PackedVector3Array) -> void:
	var cf := _centroid(front)
	var cb := _centroid(back)
	_fan(surface, front, cf, cb)
	_fan(surface, back, cb, cf)
	var mid := (cf + cb) * 0.5
	for k in front.size():
		var k2 := (k + 1) % front.size()
		_quad(surface, front[k], front[k2], back[k2], back[k], mid)


func _quad(surface: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3) -> void:
	_tri(surface, a, b, c, inside)
	_tri(surface, a, c, d, inside)


## One flat-shaded triangle, wound to face away from `inside`.
func _tri(surface: int, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		n = -n
		var t := b
		b = c
		c = t
	var st := _st[surface]
	# Godot's front faces wind clockwise: (a, c, b) against the counter-clockwise (a, b, c).
	for p in [a, c, b]:
		st.set_normal(n)
		st.add_vertex(p)


## The shoulder strap's band along `path` (any space), thick side away from `centre`. Used by
## backpack_holder.gd for the straps.
static func build_strap(path: PackedVector3Array, centre: Vector3, width: float = 0.045,
		thick: float = 0.008) -> ArrayMesh:
	var b := new()
	for i in SURFACES:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		b._st.append(st)
	b._ribbon(LEATHER, path, width, thick, centre)
	return b._st[LEATHER].commit()
