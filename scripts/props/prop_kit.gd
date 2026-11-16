class_name PropKit
extends RefCounted

# Shared mesh kit for hub2's code-built PS1 props (docs/specs/hub2-storage.md).
#
# Everything is vertex colour + flat normals, no textures or UVs, drawn with a plain vertex-colour
# StandardMaterial3D that AIRFRAME swaps for its PS1 surface material (pixels, snap, stepped light).
# Weathering lives in the vertex colours: faces are cut into cells no bigger than `cell` so the
# colour can change across them, and each vertex is darkened toward the bottom of the prop (grime),
# tinted rust near box edges and in hashed blotches, and faded toward grey. `wear` 0 = clean.
#
# Colours are given in sRGB and written as linear (what StandardMaterial3D and the PS1 shader read).

const RUST := Color(0.36, 0.17, 0.08)
const GRIME := Color(0.10, 0.09, 0.08)
const FADE := Color(0.55, 0.55, 0.53)

var st := SurfaceTool.new()
var wear := 0.0
## Grime runs from `floor_y` (darkest) up `grime_height` metres.
var floor_y := 0.0
var grime_height := 1.2
## Max face cell size (m) when wear > 0: where the colour may change.
var cell := 0.6
var seed_offset := Vector3.ZERO
## Extra surfaces: [material, SurfaceTool] for glows and screens.
var _extra: Array = []

static var _material: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 1.0
		_material.metallic_specular = 0.0
	return _material


static func glow_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _init(p_wear := 0.0, p_seed := 0) -> void:
	wear = p_wear
	var r := RandomNumberGenerator.new()
	r.seed = p_seed
	seed_offset = Vector3(r.randf() * 100.0, r.randf() * 100.0, r.randf() * 100.0)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func commit() -> ArrayMesh:
	var mesh := st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, material())
	for e: Array in _extra:
		var sst: SurfaceTool = e[1]
		sst.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, e[0])
	return mesh


## A second surface (glowing bulbs, CRT glass) with its own material. Returns its SurfaceTool.
func extra_surface(mat: Material) -> SurfaceTool:
	for e: Array in _extra:
		if e[0] == mat:
			return e[1]
	var sst := SurfaceTool.new()
	sst.begin(Mesh.PRIMITIVE_TRIANGLES)
	_extra.append([mat, sst])
	return sst


# -- weathering -------------------------------------------------------------------------------

static func hash3(p: Vector3) -> float:
	var h := sin(p.dot(Vector3(127.1, 311.7, 74.7))) * 43758.5453
	return h - floor(h)


## Smooth value noise, 0..1.
static func noise3(p: Vector3) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector3.ONE * 3.0 - f * 2.0)
	var n := 0.0
	for dx in 2:
		for dy in 2:
			for dz in 2:
				var w := (f.x if dx == 1 else 1.0 - f.x) * (f.y if dy == 1 else 1.0 - f.y) * (f.z if dz == 1 else 1.0 - f.z)
				n += w * hash3(i + Vector3(dx, dy, dz))
	return n


## The weathered sRGB colour of `base` at local point `p`; `edge` 0..1 = how near a box edge.
func weather(base: Color, p: Vector3, edge: float) -> Color:
	if wear <= 0.0:
		return base
	var q := p + seed_offset
	var c := base.lerp(FADE, 0.25 * wear * noise3(q * 0.35))
	var blot := noise3(q * 1.3)
	var rust := clampf((blot - 0.62) * 4.0, 0.0, 1.0) * 0.7 + edge * clampf(noise3(q * 3.1) - 0.25, 0.0, 1.0) * 0.9
	c = c.lerp(RUST.lerp(RUST.lightened(0.25), noise3(q * 5.0)), clampf(rust * wear, 0.0, 0.85))
	var g := clampf(1.0 - (p.y - floor_y) / grime_height, 0.0, 1.0)
	c = c.lerp(GRIME, g * g * 0.55 * wear)
	return c


# -- primitives -------------------------------------------------------------------------------

func _emit(sst: SurfaceTool, p: Vector3, n: Vector3, c: Color) -> void:
	sst.set_color(c.srgb_to_linear())
	sst.set_normal(n)
	sst.add_vertex(p)


## A quad a,b,c,d (counter-clockwise seen from the front), cut into cells when weathered.
## `xf` places it; `edge_fn` is unused-null or a Callable(local Vector2 uv) -> edge 0..1.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, xf := Transform3D.IDENTITY,
		weathered := true, sst: SurfaceTool = null) -> void:
	var s := st if sst == null else sst
	var wa := xf * a
	var wb := xf * b
	var wc := xf * c
	var wd := xf * d
	var n := (wb - wa).cross(wc - wa)
	if n.length_squared() < 1e-12:
		n = (wc - wa).cross(wd - wa)
	n = n.normalized()
	var nu := 1
	var nv := 1
	if weathered and wear > 0.0 and sst == null:
		nu = clampi(int(ceil(wa.distance_to(wb) / cell)), 1, 24)
		nv = clampi(int(ceil(wa.distance_to(wd) / cell)), 1, 24)
	for i in nu:
		for j in nv:
			var u0 := float(i) / nu
			var u1 := float(i + 1) / nu
			var v0 := float(j) / nv
			var v1 := float(j + 1) / nv
			var pts := [_bil(wa, wb, wc, wd, u0, v0), _bil(wa, wb, wc, wd, u1, v0),
				_bil(wa, wb, wc, wd, u1, v1), _bil(wa, wb, wc, wd, u0, v1)]
			var uvs := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
			var cols: Array[Color] = []
			for k in 4:
				if weathered and sst == null:
					var uv: Vector2 = uvs[k]
					var e := 1.0 - minf(minf(uv.x, 1.0 - uv.x) * wa.distance_to(wb), minf(uv.y, 1.0 - uv.y) * wa.distance_to(wd)) / 0.35
					cols.append(weather(col, pts[k], clampf(e, 0.0, 1.0)))
				else:
					cols.append(col)
			for k in [0, 2, 1, 0, 3, 2]:
				_emit(s, pts[k], n, cols[k])


static func _bil(a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: float, v: float) -> Vector3:
	return a.lerp(b, u).lerp(d.lerp(c, u), v)


## Axis-aligned box lo..hi in the frame `xf`. `faces` bitmask skips faces (1 +X,2 -X,4 +Y,8 -Y,16 +Z,32 -Z).
func box(lo: Vector3, hi: Vector3, col: Color, xf := Transform3D.IDENTITY, weathered := true,
		sst: SurfaceTool = null, skip := 0) -> void:
	var p := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	var faces := [[5, 1, 2, 6, 1], [0, 4, 7, 3, 2], [7, 6, 2, 3, 4], [0, 1, 5, 4, 8], [4, 5, 6, 7, 16], [1, 0, 3, 2, 32]]
	for f in faces:
		if skip & int(f[4]):
			continue
		quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], col, xf, weathered, sst)


## Box of `size` centred on `centre`, rotated by basis `b` (the frame is xf * [b, centre]).
func obox(centre: Vector3, size: Vector3, col: Color, b := Basis.IDENTITY, xf := Transform3D.IDENTITY,
		weathered := true, sst: SurfaceTool = null) -> void:
	box(-size * 0.5, size * 0.5, col, xf * Transform3D(b, centre), weathered, sst)


## A tube from a to b, `sides`-gon (PS1 low poly), radius r, capped.
func tube(a: Vector3, b: Vector3, r: float, col: Color, sides := 6, xf := Transform3D.IDENTITY,
		caps := true, sst: SurfaceTool = null, r_b := -1.0) -> void:
	var rb := r if r_b < 0.0 else r_b
	var axis := b - a
	var length := axis.length()
	if length < 1e-5:
		return
	var dir := axis / length
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(dir).normalized()
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	for i in sides:
		var t := TAU * (float(i) + 0.5) / sides
		var o := side * cos(t) + up * sin(t)
		ring_a.append(a + o * r)
		ring_b.append(b + o * rb)
	var segs := 1 if wear <= 0.0 or sst != null else clampi(int(ceil(length / (cell * 1.5))), 1, 30)
	for i in sides:
		var j := (i + 1) % sides
		for s in segs:
			var t0 := float(s) / segs
			var t1 := float(s + 1) / segs
			quad(ring_a[j].lerp(ring_b[j], t0), ring_a[i].lerp(ring_b[i], t0),
				ring_a[i].lerp(ring_b[i], t1), ring_a[j].lerp(ring_b[j], t1), col, xf, true, sst)
	if caps:
		for i in sides:
			var j := (i + 1) % sides
			_tri(xf * a, xf * ring_a[j], xf * ring_a[i], col, sst)
			_tri(xf * b, xf * ring_b[i], xf * ring_b[j], col, sst)


func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color, sst: SurfaceTool = null) -> void:
	var s := st if sst == null else sst
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = -n.normalized()
	for p in [a, b, c]:
		_emit(s, p, n, weather(col, p, 0.0) if sst == null else col)


## A triangle in frame xf, a,b,c counter-clockwise seen from the front.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, xf := Transform3D.IDENTITY, sst: SurfaceTool = null) -> void:
	_tri(xf * a, xf * c, xf * b, col, sst)


## A lumpy low-poly blob (bush, leaf clump, moss mound): an octahedron-ish hull with jittered points.
func blob(centre: Vector3, radii: Vector3, col: Color, rng: RandomNumberGenerator, xf := Transform3D.IDENTITY,
		rings := 3, sides := 6) -> void:
	var pts: Array = []
	for i in rings + 1:
		var lat := PI * float(i) / rings - PI * 0.5
		var row: Array[Vector3] = []
		for j in sides:
			var lon := TAU * float(j) / sides + (0.5 if i % 2 == 1 else 0.0) * TAU / sides
			var k := 1.0 if i == 0 or i == rings else rng.randf_range(0.8, 1.15)
			row.append(centre + Vector3(cos(lat) * cos(lon) * radii.x, sin(lat) * radii.y, cos(lat) * sin(lon) * radii.z) * k)
		pts.append(row)
	for i in rings:
		var ra: Array = pts[i]
		var rb: Array = pts[i + 1]
		for j in sides:
			var jn := (j + 1) % sides
			var shade := col.darkened(0.25 * (1.0 - float(i) / rings)).lightened(rng.randf() * 0.06)
			tri_out(xf * (ra[j] as Vector3), xf * (rb[jn] as Vector3), xf * (rb[j] as Vector3), shade, xf * centre)
			tri_out(xf * (ra[j] as Vector3), xf * (ra[jn] as Vector3), xf * (rb[jn] as Vector3), shade, xf * centre)


## A triangle (already in mesh space) facing away from `inside`.
func tri_out(a: Vector3, b: Vector3, c: Vector3, col: Color, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		_tri(a, b, c, col)
	else:
		_tri(a, c, b, col)


## A screen quad a,b,c,d (counter-clockwise from the front, a bottom-left) with 0..1 UVs, into `sst`.
func screen_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, sst: SurfaceTool) -> void:
	var n := (b - a).cross(c - a).normalized()
	var pts := [a, b, c, d]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for k in [0, 2, 1, 0, 3, 2]:
		sst.set_color(Color.WHITE)
		sst.set_normal(n)
		sst.set_uv(uvs[k])
		sst.add_vertex(pts[k])
