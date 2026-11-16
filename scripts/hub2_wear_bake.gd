class_name Hub2WearBake
extends RefCounted

# Where hub2's wear goes (docs/specs/hub2-industrial.md). The surface shader can't see the shape, so
# this works it out once, offline, and writes it into each mesh:
#   - every triangle is cut to <= MAX_EDGE metres and un-indexed (flat faces);
#   - CUSTOM0 = signed distance, in metres, from each vertex to up to four "lines" near the triangle,
#     which the GPU interpolates exactly (a distance to a line is linear across a face);
#   - CUSTOM1 = what each line is: 0 none, 1 convex edge, 2 concave crease, 3 seam where one piece
#     of the map goes into another (the sign is arbitrary, the shader takes abs).
# A "line" is an edge of a flat patch (a region: triangles joined by edges under SMOOTH_DEG) that a
# neighbouring patch meets at a real angle, or a seam found by cutting the map's separate pieces
# against each other. Region lines are shared by every triangle of the region, so a quad split into
# two triangles gets all four of its edges on both halves and the diagonal never shows.
# The same data places the decals: scatter() drops vents, stripes, plates and so on on the flat
# faces, keeping clear of every line and of anything in front of them.
#
# Distances are metres in WORLD scale (the scene scales the Map by WORLD_SCALE); decals come out in
# the Map's own space. Run tools/bake_hub2_wear.gd after a hub2.glb re-export.

const WORLD_SCALE := 0.6
const SMOOTH_DEG := 25.0
const MAX_EDGE := 12.0
const SEAM_EDGE := 3.0
const REACH := 2.0
const CELL := 8.0
const MAX_LINES := 4

const CLS_CONVEX := 1.0
const CLS_CONCAVE := 2.0
const CLS_SEAM := 3.0

const DECAL_LIFT := 0.03
const DECAL_MARGIN := 0.18

## Surface kinds from the outward normal's y.
const KIND_WALL := 0
const KIND_FLOOR := 1
const KIND_CEIL := 2

var _meshes: Array[Dictionary] = []   # { name, mesh, xform (Map space) }
var _tris: Array[Dictionary] = []
var _lines: Array[Dictionary] = []
var _grid := {}
var _y_min := INF
var _y_max := -INF


func add_mesh(mesh_name: String, mesh: Mesh, xform: Transform3D) -> void:
	_meshes.append({"name": mesh_name, "mesh": mesh, "xform": xform})


## mesh name -> baked ArrayMesh.
func bake() -> Dictionary:
	_prepare()
	var out := {}
	for mi in _meshes.size():
		out[_meshes[mi]["name"]] = _build_mesh(mi)
	return out


# -- analysis ----------------------------------------------------------------------------------

func _metres(mi: int, v: Vector3) -> Vector3:
	return (_meshes[mi]["xform"] as Transform3D) * v * WORLD_SCALE


func _prepare() -> void:
	_tris.clear()
	_lines.clear()
	_grid.clear()
	var weld_base := 0
	var edge_faces := {}   # Vector3i(mesh, a, b) -> [tri]
	for mi in _meshes.size():
		var mesh: Mesh = _meshes[mi]["mesh"]
		var arr := mesh.surface_get_arrays(0)
		var src_v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var src_n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var xf: Transform3D = _meshes[mi]["xform"]
		var nbasis := xf.basis.inverse().transposed()
		var weld := PackedInt32Array()
		weld.resize(src_v.size())
		var seen := {}
		for v in src_v.size():
			var m := _metres(mi, src_v[v])
			_y_min = minf(_y_min, m.y)
			_y_max = maxf(_y_max, m.y)
			var key := Vector3i((m * 1000.0).round())
			if not seen.has(key):
				seen[key] = seen.size()
			weld[v] = weld_base + int(seen[key])
		weld_base += seen.size()
		for t in idx.size() / 3:
			var i0 := idx[t * 3]
			var i1 := idx[t * 3 + 1]
			var i2 := idx[t * 3 + 2]
			var lv: Array[Vector3] = [src_v[i0], src_v[i1], src_v[i2]]
			var mv: Array[Vector3] = [_metres(mi, lv[0]), _metres(mi, lv[1]), _metres(mi, lv[2])]
			var nm := (mv[1] - mv[0]).cross(mv[2] - mv[0])
			if nm.length_squared() < 1e-10:
				continue
			nm = nm.normalized()
			var src_avg := nbasis * (src_n[i0] + src_n[i1] + src_n[i2])
			if nm.dot(src_avg) < 0.0:
				nm = -nm
			var nl := (lv[1] - lv[0]).cross(lv[2] - lv[0]).normalized()
			if nl.dot(src_n[i0] + src_n[i1] + src_n[i2]) < 0.0:
				nl = -nl
			_tris.append({"mesh": mi, "lv": lv, "mv": mv, "nm": nm, "nl": nl,
				"w": [weld[i0], weld[i1], weld[i2]], "region": -1, "comp": -1, "lines": []})
	for ti in _tris.size():
		var w: Array = _tris[ti]["w"]
		for e in 3:
			var a: int = w[e]
			var b: int = w[(e + 1) % 3]
			if a == b:
				continue
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not edge_faces.has(key):
				edge_faces[key] = []
			(edge_faces[key] as Array).append([ti, e])

	# Classify each shared edge.
	var smooth := deg_to_rad(SMOOTH_DEG)
	var edge_class := {}
	for key: Vector2i in edge_faces:
		var fs: Array = edge_faces[key]
		var cls := 0.0
		if fs.size() != 2:
			cls = CLS_CONVEX
		else:
			var ta: Dictionary = _tris[fs[0][0]]
			var tb: Dictionary = _tris[fs[1][0]]
			var na: Vector3 = ta["nm"]
			var nb: Vector3 = tb["nm"]
			if na.angle_to(nb) >= smooth:
				var pa: Vector3 = ta["mv"][fs[0][1]]
				var cb := ((tb["mv"][0] as Vector3) + (tb["mv"][1] as Vector3) + (tb["mv"][2] as Vector3)) / 3.0
				cls = CLS_CONVEX if (cb - pa).dot(na) < 0.0 else CLS_CONCAVE
		edge_class[key] = cls

	# Regions: flood across smooth edges. Components: flood across every edge.
	var parent_r := PackedInt32Array()
	parent_r.resize(_tris.size())
	var parent_c := PackedInt32Array()
	parent_c.resize(_tris.size())
	for i in _tris.size():
		parent_r[i] = i
		parent_c[i] = i
	for key: Vector2i in edge_faces:
		var fs: Array = edge_faces[key]
		for k in range(1, fs.size()):
			_union(parent_c, fs[0][0], fs[k][0])
			if edge_class[key] == 0.0:
				_union(parent_r, fs[0][0], fs[k][0])
	for i in _tris.size():
		_tris[i]["region"] = _find(parent_r, i)
		_tris[i]["comp"] = _find(parent_c, i)

	# Region lines.
	for key: Vector2i in edge_faces:
		var cls: float = edge_class[key]
		if cls == 0.0:
			continue
		for f: Array in edge_faces[key]:
			var t: Dictionary = _tris[f[0]]
			var e: int = f[1]
			var a: Vector3 = t["mv"][e]
			var b: Vector3 = t["mv"][(e + 1) % 3]
			var dir := b - a
			if dir.length() < 1e-4:
				continue
			var cen := ((t["mv"][0] as Vector3) + (t["mv"][1] as Vector3) + (t["mv"][2] as Vector3)) / 3.0
			var inward := (cen - a) - dir.normalized() * (cen - a).dot(dir.normalized())
			if inward.length() < 1e-5:
				continue
			_add_line(a, b, inward.normalized(), cls, t["region"], -1)

	# Seams where separate pieces cut into each other.
	var comp_tris := {}
	var comp_box := {}
	for ti in _tris.size():
		var c: int = _tris[ti]["comp"]
		if not comp_tris.has(c):
			comp_tris[c] = []
			comp_box[c] = AABB(_tris[ti]["mv"][0], Vector3.ZERO)
		(comp_tris[c] as Array).append(ti)
		var bx: AABB = comp_box[c]
		for p: Vector3 in _tris[ti]["mv"]:
			bx = bx.expand(p)
		comp_box[c] = bx
	var comps: Array = comp_tris.keys()
	var seam_count := 0
	for i in comps.size():
		for j in range(i + 1, comps.size()):
			var ba: AABB = (comp_box[comps[i]] as AABB).grow(0.05)
			var bb: AABB = (comp_box[comps[j]] as AABB).grow(0.05)
			if not ba.intersects(bb):
				continue
			var ta_list: Array = _tris_in(comp_tris[comps[i]], bb)
			var tb_list: Array = _tris_in(comp_tris[comps[j]], ba)
			for a_idx: int in ta_list:
				var ta: Dictionary = _tris[a_idx]
				var abox := _tri_box(ta)
				for b_idx: int in tb_list:
					var tb: Dictionary = _tris[b_idx]
					if not abox.intersects(_tri_box(tb)):
						continue
					var seg := _tri_tri(ta["mv"], tb["mv"])
					if seg.is_empty():
						continue
					_add_seam(a_idx, seg[0], seg[1])
					_add_seam(b_idx, seg[0], seg[1])
					seam_count += 1
	print("hub2 bake: %d tris, %d lines (%d seams)" % [_tris.size(), _lines.size(), seam_count])


static func _find(parent: PackedInt32Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra


func _tris_in(list: Array, box: AABB) -> Array:
	var out: Array = []
	for ti: int in list:
		if _tri_box(_tris[ti]).intersects(box):
			out.append(ti)
	return out


static func _tri_box(t: Dictionary) -> AABB:
	var mv: Array = t["mv"]
	return AABB(mv[0], Vector3.ZERO).expand(mv[1]).expand(mv[2]).grow(0.02)


## The segment where two triangles cross, or [].
static func _tri_tri(a: Array, b: Array) -> Array:
	var pts: Array[Vector3] = []
	for e in 3:
		var r: Variant = Geometry3D.segment_intersects_triangle(a[e], a[(e + 1) % 3], b[0], b[1], b[2])
		if r != null:
			pts.append(r)
		var q: Variant = Geometry3D.segment_intersects_triangle(b[e], b[(e + 1) % 3], a[0], a[1], a[2])
		if q != null:
			pts.append(q)
	var best := 0.0
	var pair: Array = []
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var d := pts[i].distance_to(pts[j])
			if d > best:
				best = d
				pair = [pts[i], pts[j]]
	return pair if best > 0.05 else []


func _add_seam(tri: int, p: Vector3, q: Vector3) -> void:
	var n: Vector3 = _tris[tri]["nm"]
	var dir := (q - p).normalized()
	var perp := n.cross(dir)
	if perp.length() < 1e-5:
		return
	_add_line(p, q, perp.normalized(), CLS_SEAM, -1, tri)


func _add_line(a: Vector3, b: Vector3, nrm: Vector3, cls: float, region: int, owner: int) -> void:
	var li := _lines.size()
	_lines.append({"a": a, "b": b, "n": nrm, "cls": cls, "region": region, "owner": owner,
		"dir": (b - a).normalized(), "len": a.distance_to(b)})
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)) - Vector3.ONE * 0.1
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)) + Vector3.ONE * 0.1
	var c0 := Vector3i((lo / CELL).floor())
	var c1 := Vector3i((hi / CELL).floor())
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			for z in range(c0.z, c1.z + 1):
				var k := Vector3i(x, y, z)
				if not _grid.has(k):
					_grid[k] = []
				(_grid[k] as Array).append(li)


# -- mesh -------------------------------------------------------------------------------------

func _build_mesh(mi: int) -> ArrayMesh:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var src: Mesh = _meshes[mi]["mesh"]
	for ti in _tris.size():
		var t: Dictionary = _tris[ti]
		if t["mesh"] != mi:
			continue
		var cand := _candidates(ti, REACH + 0.5)
		var limit := MAX_EDGE
		for li: int in cand:
			if _lines[li]["owner"] == ti:
				limit = SEAM_EDGE
				break
		var pieces: Array = []
		_subdivide(ti, [t["lv"][0], t["lv"][1], t["lv"][2]], [t["mv"][0], t["mv"][1], t["mv"][2]], limit, cand, pieces, 0)
		for piece: Array in pieces:
			var lv: Array = piece[0]
			var picks: Array = piece[2]
			for k in 3:
				pos.append(lv[k])
				nrm.append(t["nl"])
				for s in MAX_LINES:
					if s < picks.size():
						c0.append((picks[s][2] as Array)[k])
						c1.append(picks[s][1])
					else:
						c0.append(99.0)
						c1.append(0.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_CUSTOM0] = c0
	arrays[Mesh.ARRAY_CUSTOM1] = c1
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var out := ArrayMesh.new()
	out.resource_name = src.resource_name
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	# Hub2Wear checks this against the live mesh: a re-export that changed the map means re-bake.
	out.set_meta(&"source_vertex_count", (src.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	out.set_meta(&"y_min", _y_min)
	out.set_meta(&"y_max", _y_max)
	print("%s: %d -> %d verts" % [_meshes[mi]["name"], (src.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), pos.size()])
	return out


## Lines that can matter to triangle `ti` (its region's lines and its own seams) within `reach`.
func _candidates(ti: int, reach: float) -> Array:
	var t: Dictionary = _tris[ti]
	var box := _tri_box(t).grow(reach)
	return _lines_in(box, t["region"], ti)


func _lines_in(box: AABB, region: int, owner: int) -> Array:
	var c0 := Vector3i((box.position / CELL).floor())
	var c1 := Vector3i((box.end / CELL).floor())
	var seen := {}
	var out: Array = []
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			for z in range(c0.z, c1.z + 1):
				for li: int in _grid.get(Vector3i(x, y, z), []):
					if seen.has(li):
						continue
					seen[li] = true
					var L: Dictionary = _lines[li]
					if L["owner"] >= 0:
						if L["owner"] != owner:
							continue
					elif L["region"] != region:
						continue
					var a: Vector3 = L["a"]
					var b: Vector3 = L["b"]
					if not box.intersects(AABB(a.min(b), Vector3.ZERO).expand(a.max(b)).grow(0.05)):
						continue
					out.append(li)
	return out


## Cuts a triangle into pieces of at most `limit` metres where a line is near, and leaves it whole
## where none is (the map has kilometre-wide faces; cutting those everywhere would be millions of
## triangles). Each piece comes out as [local verts, metre verts, picked lines].
func _subdivide(ti: int, lv: Array, mv: Array, limit: float, near: Array, out: Array, depth: int) -> void:
	var picks := _pick_lines(ti, mv, near)
	var worst := 0
	var longest := 0.0
	for e in 3:
		var d: float = (mv[e] as Vector3).distance_to(mv[(e + 1) % 3])
		if d > longest:
			longest = d
			worst = e
	if picks.is_empty() or longest <= limit or depth >= 24:
		out.append([lv, mv, picks])
		return
	var e1 := (worst + 1) % 3
	var e2 := (worst + 2) % 3
	var ml: Vector3 = ((lv[worst] as Vector3) + (lv[e1] as Vector3)) * 0.5
	var mm: Vector3 = ((mv[worst] as Vector3) + (mv[e1] as Vector3)) * 0.5
	_subdivide(ti, [lv[worst], ml, lv[e2]], [mv[worst], mm, mv[e2]], limit, near, out, depth + 1)
	_subdivide(ti, [ml, lv[e1], lv[e2]], [mm, mv[e1], mv[e2]], limit, near, out, depth + 1)


## The up-to-four lines nearest a (sub)triangle, as [score, class, [d at v0, v1, v2]].
func _pick_lines(_ti: int, mv: Array, near: Array) -> Array:
	var cands: Array = []
	for li: int in near:
		var L: Dictionary = _lines[li]
		var ln: Vector3 = L["n"]
		var la: Vector3 = L["a"]
		var d: Array = [((mv[0] as Vector3) - la).dot(ln), ((mv[1] as Vector3) - la).dot(ln), ((mv[2] as Vector3) - la).dot(ln)]
		var score: float
		if L["cls"] == CLS_SEAM:
			var signs_differ := signf(d[0]) != signf(d[1]) or signf(d[1]) != signf(d[2])
			score = 0.0 if signs_differ else minf(absf(d[0]), minf(absf(d[1]), absf(d[2])))
		else:
			if maxf(d[0], maxf(d[1], d[2])) < -0.2:
				continue
			score = maxf(0.0, minf(d[0], minf(d[1], d[2])))
		if score > REACH:
			continue
		var dir: Vector3 = L["dir"]
		var t0: float = ((mv[0] as Vector3) - la).dot(dir)
		var t1: float = ((mv[1] as Vector3) - la).dot(dir)
		var t2: float = ((mv[2] as Vector3) - la).dot(dir)
		var seg_len: float = L["len"]
		if maxf(t0, maxf(t1, t2)) < -REACH or minf(t0, minf(t1, t2)) > seg_len + REACH:
			continue
		cands.append([score, L["cls"], d])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return cands.slice(0, MAX_LINES)


# -- decals -----------------------------------------------------------------------------------
# Placed by rule, not by area (docs/specs/hub2-industrial.md, pass 2): vents in one even row, plates
# and section codes at eye height on the same grid, hazard stripes only along drop edges, pipes only
# along wall / ceiling joints, floor chevrons and labels on the walkable blocks, and a short list of
# hand-placed key spots. Nothing goes where he can't get near.

const REF_SCALE := 0.75       # the scale the hand-tuned numbers below were measured at
const K := WORLD_SCALE / REF_SCALE   # ... and what they are multiplied by now
const ROW_PERIOD := 36.0        # wall rows repeat every 36 m of height
const ROW_PLATE_Y := 38.5       # eye height on the spawn platform (floor 36.3)
const ROW_VENT_Y := 47.0
const GRID_U := 30.0            # spacing along a wall
const REACH_FULL := 15.0        # a wall within this of somewhere he can stand gets decals
const REACH_NONE := 45.0
const SPAWN := Vector3(0.02, 36.3, 102.5)
const SECTION_LABELS: Array[String] = ["text_0", "text_1", "text_2", "text_3", "text_16"]
const MAX_EDGE_STRIPES := 100
const MAX_PIPES := 0   # 3D pipe runs replaced the flat pipe decals (docs/specs/hub2-storage.md)
const MAX_FLOOR_LABELS := 24
const MAX_SCUFFS := 120

## Hand-placed: a ray from `from` along `dir` hits a wall or floor; the decal goes where it lands.
## { from, dir, sprite, scale }
const KEY_SPOTS: Array[Dictionary] = [
	# Spawn platform, flanking the drop edge (z ~ 12): left GATE 5 + amber lamps, right DANGER + red
	# lamps, and a warning triangle a little back from the ledge.
	{"from": Vector3(0, 40.4, 15), "dir": Vector3(-1, 0, 0), "sprite": "text_7", "scale": 2.0},
	{"from": Vector3(0, 48.0, 15), "dir": Vector3(-1, 0, 0), "sprite": "lamps_amber", "scale": 1.5},
	{"from": Vector3(0, 40.4, 15), "dir": Vector3(1, 0, 0), "sprite": "text_9", "scale": 2.0},
	{"from": Vector3(0, 38.0, 23), "dir": Vector3(1, 0, 0), "sprite": "warn_tri", "scale": 2.0},
	{"from": Vector3(0, 48.0, 15), "dir": Vector3(1, 0, 0), "sprite": "lamps_red", "scale": 1.5},
]


func _reach_weights() -> PackedFloat32Array:
	var floor_cells := {}
	for t in _tris:
		if (t["nm"] as Vector3).y > 0.6:
			var mv: Array = t["mv"]
			var fc: Vector3 = ((mv[0] as Vector3) + (mv[1] as Vector3) + (mv[2] as Vector3)) / 3.0
			var fk := Vector3i((fc / 40.0).floor())
			if not floor_cells.has(fk):
				floor_cells[fk] = []
			(floor_cells[fk] as Array).append(fc)
	var weights := PackedFloat32Array()
	weights.resize(_tris.size())
	for ti in _tris.size():
		var wt: Dictionary = _tris[ti]
		var wmv: Array = wt["mv"]
		var wc: Vector3 = ((wmv[0] as Vector3) + (wmv[1] as Vector3) + (wmv[2] as Vector3)) / 3.0
		if (wt["nm"] as Vector3).y > 0.6:
			weights[ti] = 1.0
			continue
		var best := INF
		var base := Vector3i((wc / 40.0).floor())
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				for dz in range(-2, 3):
					for fc2: Vector3 in floor_cells.get(base + Vector3i(dx, dy, dz), []):
						best = minf(best, wc.distance_to(fc2))
		weights[ti] = clampf(1.0 - (best - REACH_FULL) / (REACH_NONE - REACH_FULL), 0.0, 1.0)
	return weights


## Drops the decals. Returns { mesh: ArrayMesh, count: int }; the mesh is in Map space.
func scatter(atlas: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7771113
	var faces := PackedVector3Array()
	for t in _tris:
		for p: Vector3 in t["mv"]:
			faces.append(p)
	var tmesh := TriangleMesh.new()
	tmesh.create_from_faces(faces)
	var sprites: Array = atlas["sprites"]
	var out := {"placed": [], "verts": PackedVector3Array(), "norms": PackedVector3Array(),
		"uvs": PackedVector2Array(), "cols": PackedColorArray(), "by": {}}
	var weights := _reach_weights()
	var region_tri := {}   # region -> [its biggest triangle, area]
	var region_area := {}
	for ti in _tris.size():
		var tmv: Array = _tris[ti]["mv"]
		var ar: float = 0.5 * ((tmv[1] as Vector3) - tmv[0]).cross((tmv[2] as Vector3) - tmv[0]).length()
		var rg: int = _tris[ti]["region"]
		region_area[rg] = float(region_area.get(rg, 0.0)) + ar
		if not region_tri.has(rg) or ar > float(region_tri[rg][1]):
			region_tri[rg] = [ti, ar]
	_scatter_keys(sprites, tmesh, rng, out)   # first, so the rules make room for them
	_scatter_walls(sprites, weights, tmesh, rng, out)
	_scatter_edges(sprites, region_tri, tmesh, rng, out)
	_scatter_pipes(sprites, region_tri, weights, tmesh, rng, out)
	_scatter_floors(sprites, region_tri, region_area, tmesh, rng, out)
	var placed: Array = out["placed"]
	print("decals: %d placed %s" % [placed.size(), out["by"]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out["verts"]
	arrays[Mesh.ARRAY_NORMAL] = out["norms"]
	arrays[Mesh.ARRAY_TEX_UV] = out["uvs"]
	arrays[Mesh.ARRAY_COLOR] = out["cols"]
	var mesh := ArrayMesh.new()
	if (out["verts"] as PackedVector3Array).size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "count": placed.size()}


## Puts `sp` down if it fits; returns whether it did.
func _put_decal(sp: Dictionary, p: Vector3, n: Vector3, kind: int, ti: int, tmesh: TriangleMesh,
		rng: RandomNumberGenerator, out: Dictionary, keep_up := false, up_in := Vector3.ZERO, scale := 1.0) -> bool:
	if sp.is_empty():
		return false
	var placed: Array = out["placed"]
	var q := _try_place(sp, p, n, kind, ti, tmesh, placed, rng, keep_up, up_in, scale)
	if q.is_empty():
		return false
	placed.append([p, q["radius"], n])
	_emit(q, out["verts"], out["norms"], out["uvs"], out["cols"], rng)
	var by: Dictionary = out["by"]
	by[sp["name"]] = int(by.get(sp["name"], 0)) + 1
	return true


## Vents and plates on one world grid, so a wall reads as a rhythm and a split quad never doubles up.
func _scatter_walls(sprites: Array, weights: PackedFloat32Array, tmesh: TriangleMesh,
		rng: RandomNumberGenerator, out: Dictionary) -> void:
	for ti in _tris.size():
		var t: Dictionary = _tris[ti]
		var n: Vector3 = t["nm"]
		if absf(n.y) > 0.3 or weights[ti] < 0.5:
			continue
		var h := Vector3(n.x, 0.0, n.z)
		if h.length() < 0.5:
			continue
		h = h.normalized()
		var tang := Vector3.UP.cross(h).normalized()
		var mv: Array = t["mv"]
		var ua := INF
		var ub := -INF
		var ya := INF
		var yb := -INF
		for p: Vector3 in mv:
			ua = minf(ua, p.dot(tang))
			ub = maxf(ub, p.dot(tang))
			ya = minf(ya, p.y)
			yb = maxf(yb, p.y)
		var nh := n.dot(h)
		var a0: Vector3 = mv[0]
		for row in 2:
			var base_y := (ROW_PLATE_Y if row == 0 else ROW_VENT_Y) * K
			var k := ceili((ya - base_y) / (ROW_PERIOD * K))
			while base_y + k * ROW_PERIOD * K <= yb:
				var y := base_y + k * ROW_PERIOD * K
				k += 1
				var c := ceili((ua - GRID_U * 0.5) / GRID_U)
				while GRID_U * 0.5 + c * GRID_U <= ub:
					var u := GRID_U * 0.5 + c * GRID_U
					c += 1
					var d := (n.dot(a0) - y * n.y) / nh
					var pt := h * d + tang * u + Vector3.UP * y
					if not _in_tri(pt, mv):
						continue
					var cell := int(floor(u / GRID_U)) + int(floor(y / (ROW_PERIOD * K))) * 3
					var sprite_name := ""
					if row == 1:
						sprite_name = "vent_a" if posmod(cell, 2) == 0 else "vent_wide"
					else:
						match posmod(cell, 4):
							0: sprite_name = "plate"
							1: sprite_name = SECTION_LABELS[posmod(cell, SECTION_LABELS.size())]
							_: continue
					var sp := _find_sprite(sprites, sprite_name)
					# A nudge along the wall if a seam is in the way.
					for off: float in [0.0, 1.5, -1.5, 3.0, -3.0]:
						var pp := pt + tang * off
						if not _in_tri(pp, mv):
							continue
						if _put_decal(sp, pp, n, KIND_WALL, ti, tmesh, rng, out):
							if row == 1:
								var streak := _find_sprite(sprites, "streak_a" if posmod(cell, 3) != 0 else "streak_b")
								var below := pp - Vector3.UP * (float(sp["h"]) / Hub2DecalAtlas.TEXELS_PER_METRE * 0.5 + float(streak["h"]) / 32.0)
								_put_decal(streak, below, n, KIND_WALL, ti, tmesh, rng, out, true, Vector3.UP)
							break


## Hazard stripes along convex floor edges: the ledges you can drop from.
func _scatter_edges(sprites: Array, region_tri: Dictionary, tmesh: TriangleMesh,
		rng: RandomNumberGenerator, out: Dictionary) -> void:
	var cands: Array = []
	for li in _lines.size():
		var L: Dictionary = _lines[li]
		if L["cls"] != CLS_CONVEX or absf((L["dir"] as Vector3).y) > 0.05 or float(L["len"]) < 4.0:
			continue
		if not region_tri.has(L["region"]):
			continue
		var ti: int = region_tri[L["region"]][0]
		if (_tris[ti]["nm"] as Vector3).y < 0.7:
			continue
		var mid: Vector3 = ((L["a"] as Vector3) + (L["b"] as Vector3)) * 0.5
		cands.append([mid.distance_to(SPAWN * K), li, ti])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var stripe := _find_sprite(sprites, "hazard_h")
	var count := 0
	for c in cands:
		if count >= MAX_EDGE_STRIPES:
			break
		var L: Dictionary = _lines[c[1]]
		var inward: Vector3 = L["n"]
		var s := 2.0
		var on_line := 0
		while s < float(L["len"]) - 2.0 and on_line < 14 and count < MAX_EDGE_STRIPES:
			var p: Vector3 = (L["a"] as Vector3) + (L["dir"] as Vector3) * s + inward * 0.5
			if _put_decal(stripe, p, Vector3.UP, KIND_FLOOR, c[2], tmesh, rng, out, true, inward):
				count += 1
				on_line += 1
			s += 4.0


## One pipe run along each wall / ceiling joint.
func _scatter_pipes(sprites: Array, region_tri: Dictionary, weights: PackedFloat32Array,
		tmesh: TriangleMesh, rng: RandomNumberGenerator, out: Dictionary) -> void:
	var cands: Array = []
	for li in _lines.size():
		var L: Dictionary = _lines[li]
		if L["cls"] != CLS_CONCAVE or absf((L["dir"] as Vector3).y) > 0.05 or float(L["len"]) < 8.0:
			continue
		if (L["n"] as Vector3).y > -0.7 or not region_tri.has(L["region"]):
			continue
		var ti: int = region_tri[L["region"]][0]
		var tn: Vector3 = _tris[ti]["nm"]
		if absf(tn.y) > 0.3 or weights[ti] < 0.5:
			continue
		var mid: Vector3 = ((L["a"] as Vector3) + (L["b"] as Vector3)) * 0.5
		cands.append([mid.distance_to(SPAWN * K), li, ti, tn])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var pipe := _find_sprite(sprites, "pipe_b")
	var count := 0
	for c in cands:
		if count >= MAX_PIPES:
			break
		var L: Dictionary = _lines[c[1]]
		var s := 3.5
		var on_line := 0
		while s < float(L["len"]) - 3.5 and on_line < 12 and count < MAX_PIPES:
			var p: Vector3 = (L["a"] as Vector3) + (L["dir"] as Vector3) * s + (L["n"] as Vector3) * 0.5
			if _put_decal(pipe, p, c[3], KIND_WALL, c[2], tmesh, rng, out, true, Vector3.UP):
				count += 1
				on_line += 1
			s += 6.0


## Floor chevrons down the spawn platform, a big code on each walkable block, a few scuffs.
func _scatter_floors(sprites: Array, region_tri: Dictionary, region_area: Dictionary,
		tmesh: TriangleMesh, rng: RandomNumberGenerator, out: Dictionary) -> void:
	var arrow := _find_sprite(sprites, "arrow")
	# Chevrons point the way he travels: down the platform toward the drop.
	var z := 96.0 * K
	while z > 28.0 * K:
		var r := tmesh.intersect_ray(Vector3(0.0, (SPAWN.y + 3.0) * K, z), Vector3.DOWN)
		if not r.is_empty():
			var ti: int = r["face_index"]
			_put_decal(arrow, r["position"], Vector3.UP, KIND_FLOOR, ti, tmesh, rng, out, true, Vector3(0, 0, -1), 2.0)
		z -= 10.0
	# One code per block.
	var blocks: Array = []
	for rg: int in region_tri:
		var ti: int = region_tri[rg][0]
		if (_tris[ti]["nm"] as Vector3).y < 0.9 or float(region_area[rg]) < 150.0:
			continue
		var mv: Array = _tris[ti]["mv"]
		var cen: Vector3 = ((mv[0] as Vector3) + (mv[1] as Vector3) + (mv[2] as Vector3)) / 3.0
		blocks.append([cen.distance_to(SPAWN * K), ti, cen])
	blocks.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var codes := ["text_0", "text_1", "text_2", "text_3", "text_16", "text_13", "text_17", "text_19"]
	var i := 0
	for b in blocks:
		if i >= MAX_FLOOR_LABELS:
			break
		var sp := _find_sprite(sprites, codes[i % codes.size()])
		if _put_decal(sp, b[2], Vector3.UP, KIND_FLOOR, b[1], tmesh, rng, out, true, Vector3(0, 0, -1), 3.0):
			i += 1
	# A few scuffs, only on floors.
	var scuffs := 0
	for ti in _tris.size():
		if scuffs >= MAX_SCUFFS:
			break
		var t: Dictionary = _tris[ti]
		if (t["nm"] as Vector3).y < 0.9:
			continue
		var mv: Array = t["mv"]
		var area: float = 0.5 * ((mv[1] as Vector3) - mv[0]).cross((mv[2] as Vector3) - mv[0]).length()
		var want := area * 0.12 / 100.0
		var count := int(floor(want)) + (1 if rng.randf() < want - floor(want) else 0)
		for _i in count:
			var u := rng.randf()
			var v := rng.randf()
			if u + v > 1.0:
				u = 1.0 - u
				v = 1.0 - v
			var p: Vector3 = (mv[0] as Vector3) + ((mv[1] as Vector3) - mv[0]) * u + ((mv[2] as Vector3) - mv[0]) * v
			var sp := _find_sprite(sprites, "scuff_a" if rng.randf() < 0.6 else "scuff_b")
			if _put_decal(sp, p, t["nm"], KIND_FLOOR, ti, tmesh, rng, out):
				scuffs += 1


func _scatter_keys(sprites: Array, tmesh: TriangleMesh, rng: RandomNumberGenerator, out: Dictionary) -> void:
	for ks: Dictionary in KEY_SPOTS:
		var dir: Vector3 = (ks["dir"] as Vector3).normalized()
		var r := tmesh.intersect_ray((ks["from"] as Vector3) * K, dir)
		if r.is_empty():
			push_warning("hub2 key spot %s missed" % ks["sprite"])
			continue
		var n: Vector3 = r["normal"]
		if n.dot(dir) > 0.0:
			n = -n
		var kind := KIND_WALL if absf(n.y) < 0.5 else KIND_FLOOR
		if not _put_decal(_find_sprite(sprites, ks["sprite"]), r["position"], n, kind, r["face_index"], tmesh,
				rng, out, false, Vector3.ZERO, float(ks.get("scale", 1.0))):
			push_warning("hub2 key spot %s did not fit" % ks["sprite"])


static func _in_tri(p: Vector3, mv: Array) -> bool:
	var a: Vector3 = mv[0]
	var v0: Vector3 = (mv[1] as Vector3) - a
	var v1: Vector3 = (mv[2] as Vector3) - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var den := d00 * d11 - d01 * d01
	if absf(den) < 1e-9:
		return false
	var bv := (d11 * d20 - d01 * d21) / den
	var bw := (d00 * d21 - d01 * d20) / den
	return bv >= 0.0 and bw >= 0.0 and bv + bw <= 1.0


static func _find_sprite(sprites: Array, sprite_name: String) -> Dictionary:
	for s: Dictionary in sprites:
		if s["name"] == sprite_name:
			return s
	return {}


## A decal at `p` on a face with outward normal `n`, or {} when it doesn't fit.
func _try_place(sp: Dictionary, p: Vector3, n: Vector3, kind: int, ti: int, tmesh: TriangleMesh,
		placed: Array, rng: RandomNumberGenerator, keep_up := false, up_in := Vector3.ZERO, scale := 1.0) -> Dictionary:
	var up: Vector3
	if keep_up:
		up = up_in
	elif kind == KIND_WALL:
		up = Vector3.UP
	else:
		var turns := rng.randi_range(0, 3)
		up = Basis(n, turns * PI * 0.5) * (Vector3.RIGHT if absf(n.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD)
	up = (up - n * up.dot(n)).normalized()
	var right := up.cross(n).normalized()
	var w: float = float(sp["w"]) / Hub2DecalAtlas.TEXELS_PER_METRE * scale
	var h: float = float(sp["h"]) / Hub2DecalAtlas.TEXELS_PER_METRE * scale
	if sp["rot_ok"] and not keep_up and rng.randf() < 0.5:
		var tmp := up
		up = right
		right = -tmp
	var half := Vector2(w * 0.5, h * 0.5)
	var radius := half.length()
	var corners: Array[Vector3] = [
		p + right * half.x + up * half.y, p - right * half.x + up * half.y,
		p - right * half.x - up * half.y, p + right * half.x - up * half.y]
	# Clear of every line, inside the face.
	var region: int = _tris[ti]["region"]
	for li: int in _lines_in(AABB(p, Vector3.ZERO).grow(radius + DECAL_MARGIN + 0.1), region, ti):
		var L: Dictionary = _lines[li]
		var la: Vector3 = L["a"]
		var dir: Vector3 = L["dir"]
		var along := clampf((p - la).dot(dir), 0.0, L["len"])
		if p.distance_to(la + dir * along) > radius + DECAL_MARGIN:
			continue
		var ln: Vector3 = L["n"]
		var neg := false
		var pos := false
		for c in corners:
			var d := (c - la).dot(ln)
			if L["cls"] == CLS_SEAM:
				if absf(d) < DECAL_MARGIN:
					return {}
				neg = neg or d < 0.0
				pos = pos or d > 0.0
			elif d < DECAL_MARGIN:
				return {}
		if neg and pos:
			return {}
	# Nothing in front of it.
	for c in [p] + corners:
		var from: Vector3 = c + n * DECAL_LIFT
		if not tmesh.intersect_segment(from, from + n * 0.6).is_empty():
			return {}
	# Not on top of another decal (a streak under its vent may touch it).
	var skip := 1 if keep_up else 0
	for oi in placed.size() - skip:
		var o: Array = placed[oi]
		if p.distance_to(o[0]) < radius + float(o[1]) + 0.1 and n.dot(o[2]) > 0.9:
			return {}
	return {"sp": sp, "centre": p + n * DECAL_LIFT, "n": n, "up": up, "right": right,
		"half": half, "radius": radius}


func _emit(q: Dictionary, verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		cols: PackedColorArray, rng: RandomNumberGenerator) -> void:
	var sp: Dictionary = q["sp"]
	var rect: Rect2i = sp["rect"]
	var c: Vector3 = q["centre"]
	var right: Vector3 = q["right"]
	var up: Vector3 = q["up"]
	var half: Vector2 = q["half"]
	var n: Vector3 = q["n"]
	var sz := Hub2DecalAtlas.SIZE
	# UV corners follow the sprite's own up/right; the sprite may have been rotated a quarter turn
	# (half is swapped then), so the UV rect always maps the image's top edge to `up`.
	var u0 := float(rect.position.x) / sz
	var u1 := float(rect.position.x + rect.size.x) / sz
	var v0 := float(rect.position.y) / sz
	var v1 := float(rect.position.y + rect.size.y) / sz
	var tl := c - right * half.x + up * half.y
	var tr := c + right * half.x + up * half.y
	var bl := c - right * half.x - up * half.y
	var br := c + right * half.x - up * half.y
	var s := 1.0 / WORLD_SCALE
	var shade := rng.randf_range(0.8, 1.08)
	var col := Color(shade, shade, shade, 1.0)
	# Winding: cull is off in the decal shader, so either way shows; the normal is the face's.
	for corner in [[tl, Vector2(u0, v0)], [tr, Vector2(u1, v0)], [br, Vector2(u1, v1)],
			[tl, Vector2(u0, v0)], [br, Vector2(u1, v1)], [bl, Vector2(u0, v1)]]:
		verts.append((corner[0] as Vector3) * s)
		norms.append(n)
		uvs.append(corner[1])
		cols.append(col)
