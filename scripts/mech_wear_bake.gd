class_name MechWearBake
extends RefCounted

# Where EXIA's wear goes (docs/specs/mech-weathering.md, "Placement pass"). The shader can't see the
# body's shape, so this works it out once, offline, and writes it into each mesh as CUSTOM2:
#   x  chip distance: to the nearest convex edge (a hard crease or a tight bevel), divided by that
#      edge's weight - bottom edges count as nearer (heavier wear), top edges as farther (lighter).
#   y  seam distance: to the nearest concave crease or to another part's surface (where rust and
#      grime collect).
#   z  drop: how far below the nearest edge or crease above it a side-facing point hangs (rust streaks
#      run down from there).
#   w  corner distance: to the nearest point where two convex edges of different directions meet.
# Distances are in mesh units (metres) and capped (FAR / DROP_CAP): past the cap it's just "far".
# The mesh is subdivided first so no triangle edge is longer than MAX_EDGE, so these interpolate
# across a big flat face instead of being zero at its four corners. Every EXIA part is rigid on one
# bone, so the new vertices take the bone of the nearest corner and nothing cracks.
# CUSTOM0/1 carry the rest position and normal (= the bind-pose vertex), what the shader projects from.
#
# Run tools/bake_mech_wear.gd after a Mech_V1.glb re-export: it writes assets/mech_wear/<mesh>.res.

const MAX_EDGE := 0.1
## A crease counts as an edge if it turns at least this much...
const SHARP_MIN_DEG := 8.0
## ...and either turns 60 degrees or more at once, or is tighter than this radius (a bevel, not a sphere).
const SHARP_MAX_RADIUS := 0.15
const FAR := 0.6
const DROP_CAP := 3.0
const CELL := 0.5
const VOXEL := 0.1


## parts: mesh name -> Mesh (one surface each). Returns mesh name -> baked ArrayMesh.
static func bake_parts(parts: Dictionary) -> Dictionary:
	var prepared := {}
	var bit := 0
	for part_name: String in parts:
		var p := _prepare(parts[part_name])
		p["bit"] = 1 << bit
		bit += 1
		prepared[part_name] = p
	# Every part's surface, voxelised, tagged by part: the seam search looks for someone else's bit.
	var voxels := {}
	for part_name: String in prepared:
		var p: Dictionary = prepared[part_name]
		for v: Vector3 in (p["pos"] as PackedVector3Array):
			var k := _vkey(v)
			voxels[k] = int(voxels.get(k, 0)) | int(p["bit"])
	var offsets := _sphere_offsets(int(ceil(FAR / VOXEL)))
	var out := {}
	for part_name: String in prepared:
		out[part_name] = _finish(parts[part_name], prepared[part_name], voxels, offsets)
	return out


# -- analysis + subdivision --------------------------------------------------------------------

static func _prepare(mesh: Mesh) -> Dictionary:
	var arr := mesh.surface_get_arrays(0)
	var src_v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var src_n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var src_b: Variant = arr[Mesh.ARRAY_BONES]
	var src_w: Variant = arr[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(src_v.size())
		for i in src_v.size():
			idx[i] = i
	var per := 0
	if src_b != null:
		per = (src_b as PackedInt32Array).size() / src_v.size()

	# Weld by position so a hard edge (split normals) still joins its two faces.
	var weld := PackedInt32Array()
	weld.resize(src_v.size())
	var wpos := PackedVector3Array()
	var seen := {}
	for v in src_v.size():
		var key := Vector3i((src_v[v] * 10000.0).round())
		var id: int = seen.get(key, -1)
		if id < 0:
			id = wpos.size()
			seen[key] = id
			wpos.append(src_v[v])
		weld[v] = id

	var tri_count := idx.size() / 3
	var fn := PackedVector3Array()
	var fc := PackedVector3Array()
	fn.resize(tri_count)
	fc.resize(tri_count)
	var edge_faces := {}
	for t in tri_count:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		var n := (src_v[b] - src_v[a]).cross(src_v[c] - src_v[a])
		n = n.normalized() if n.length_squared() > 1e-16 else Vector3.ZERO
		if n.dot(src_n[a] + src_n[b] + src_n[c]) < 0.0:
			n = -n
		fn[t] = n
		fc[t] = (src_v[a] + src_v[b] + src_v[c]) / 3.0
		for e in 3:
			var w0 := weld[idx[t * 3 + e]]
			var w1 := weld[idx[t * 3 + (e + 1) % 3]]
			if w0 == w1:
				continue
			var key := Vector2i(mini(w0, w1), maxi(w0, w1))
			if not edge_faces.has(key):
				edge_faces[key] = []
			(edge_faces[key] as Array).append(t)

	var convex: Array = []   # [p0, p1, weight]
	var concave: Array = []  # [p0, p1]
	var dirs := {}           # welded vertex -> convex edge directions meeting there
	var min_ang := deg_to_rad(SHARP_MIN_DEG)
	for key: Vector2i in edge_faces:
		var fs: Array = edge_faces[key]
		var p0 := wpos[key.x]
		var p1 := wpos[key.y]
		if fs.size() == 1:
			# An open border: wear it like an outer edge.
			convex.append([p0, p1, _edge_weight(fn[fs[0]])])
			_note_dir(dirs, key, p1 - p0)
			continue
		if fs.size() != 2:
			continue
		var na := fn[fs[0]]
		var nb := fn[fs[1]]
		if na == Vector3.ZERO or nb == Vector3.ZERO:
			continue
		var ang := na.angle_to(nb)
		if ang < min_ang:
			continue
		if ang < deg_to_rad(60.0) and fc[fs[0]].distance_to(fc[fs[1]]) / ang > SHARP_MAX_RADIUS:
			continue
		if (fc[fs[1]] - p0).dot(na) < 0.0:
			convex.append([p0, p1, _edge_weight((na + nb).normalized())])
			_note_dir(dirs, key, p1 - p0)
		else:
			concave.append([p0, p1])

	var corners := PackedVector3Array()
	for w: int in dirs:
		var ds: Array = dirs[w]
		var found := false
		for i in ds.size():
			for j in range(i + 1, ds.size()):
				if absf((ds[i] as Vector3).dot(ds[j])) < 0.7:
					found = true
		if found:
			corners.append(wpos[w])

	# Subdivide: every source vertex is kept as is, long triangles are split into an n x n grid.
	var pos := src_v.duplicate()
	var nrm := src_n.duplicate()
	var bones := PackedInt32Array(src_b) if src_b != null else PackedInt32Array()
	var weights := PackedFloat32Array(src_w) if src_w != null else PackedFloat32Array()
	var out_idx := PackedInt32Array()
	for t in tri_count:
		var c3 := [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]
		var va: Vector3 = src_v[c3[0]]
		var vb: Vector3 = src_v[c3[1]]
		var vc: Vector3 = src_v[c3[2]]
		var longest := maxf(va.distance_to(vb), maxf(vb.distance_to(vc), vc.distance_to(va)))
		var n := clampi(int(ceil(longest / MAX_EDGE)), 1, 64)
		if n == 1:
			out_idx.append_array(PackedInt32Array(c3))
			continue
		# grid[i][j]: weight i/n on b, j/n on c.
		var grid := []
		for i in n + 1:
			var row := PackedInt32Array()
			for j in n + 1 - i:
				var u := float(i) / n
				var v := float(j) / n
				var w := 1.0 - u - v
				var id := -1
				if i == 0 and j == 0:
					id = c3[0]
				elif i == n:
					id = c3[1]
				elif j == n:
					id = c3[2]
				else:
					id = pos.size()
					pos.append(va * w + vb * u + vc * v)
					nrm.append((src_n[c3[0]] * w + src_n[c3[1]] * u + src_n[c3[2]] * v).normalized())
					if per > 0:
						var near: int = c3[0] if w >= u and w >= v else (c3[1] if u >= v else c3[2])
						for k in per:
							bones.append(bones[near * per + k])
							weights.append(weights[near * per + k])
				row.append(id)
			grid.append(row)
		for i in n:
			for j in n - i:
				out_idx.append_array(PackedInt32Array([grid[i][j], grid[i + 1][j], grid[i][j + 1]]))
				if j < n - i - 1:
					out_idx.append_array(PackedInt32Array([grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]))

	return {
		"pos": pos, "nrm": nrm, "bones": bones, "weights": weights, "index": out_idx, "per": per,
		"convex": convex, "concave": concave, "corners": corners, "src_count": src_v.size(),
	}


## Bottom edges wear more (they count as nearer), top edges less, vertical edges in between.
static func _edge_weight(outward: Vector3) -> float:
	return 1.0 + 0.6 * maxf(-outward.y, 0.0) - 0.4 * maxf(outward.y, 0.0)


static func _note_dir(dirs: Dictionary, key: Vector2i, d: Vector3) -> void:
	for w in [key.x, key.y]:
		if not dirs.has(w):
			dirs[w] = []
		(dirs[w] as Array).append(d.normalized())


# -- fields ------------------------------------------------------------------------------------

static func _finish(src: Mesh, p: Dictionary, voxels: Dictionary, offsets: Array) -> ArrayMesh:
	var pos: PackedVector3Array = p["pos"]
	var nrm: PackedVector3Array = p["nrm"]
	var convex_grid := _segment_grid(p["convex"])
	var crease_grid := _segment_grid((p["convex"] as Array) + (p["concave"] as Array))
	var concave_grid := _segment_grid(p["concave"])
	var corner_grid := {}
	for c: Vector3 in (p["corners"] as PackedVector3Array):
		var k := _ckey(c)
		if not corner_grid.has(k):
			corner_grid[k] = []
		(corner_grid[k] as Array).append(c)
	var own: int = p["bit"]
	var field := PackedFloat32Array()
	field.resize(pos.size() * 4)
	for v in pos.size():
		var x := pos[v]
		var cell := _cell(x)
		var chip := FAR
		var seam := FAR
		var corner := FAR
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var k := cell + Vector3i(dx, dy, dz)
					if convex_grid.has(k):
						for s: Array in convex_grid[k]:
							chip = minf(chip, _seg_dist(x, s[0], s[1]) / float(s[2]))
					if concave_grid.has(k):
						for s: Array in concave_grid[k]:
							seam = minf(seam, _seg_dist(x, s[0], s[1]))
					if corner_grid.has(k):
						for c: Vector3 in (corner_grid[k] as Array):
							corner = minf(corner, x.distance_to(c))
		# Another part's surface close by.
		for o: Array in offsets:
			if float(o[1]) >= seam:
				break
			var m: int = voxels.get(_vkey(x + o[0]), 0)
			if m & ~own:
				seam = float(o[1])
				break
		# Drop: only side-facing points hang below an edge.
		var drop := DROP_CAP
		if absf(nrm[v].y) < 0.6:
			for dy in range(0, int(ceil(DROP_CAP / CELL)) + 1):
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						var k := cell + Vector3i(dx, dy, dz)
						if not crease_grid.has(k):
							continue
						for s: Array in crease_grid[k]:
							var q := _seg_closest(x, s[0], s[1])
							var d := q.distance_to(x)
							if d < drop and d > 0.02 and q.y - x.y > 0.7 * d:
								drop = d
		field[v * 4] = chip
		field[v * 4 + 1] = seam
		field[v * 4 + 2] = drop
		field[v * 4 + 3] = corner

	var rest_pos := PackedFloat32Array()
	var rest_nrm := PackedFloat32Array()
	rest_pos.resize(pos.size() * 3)
	rest_nrm.resize(pos.size() * 3)
	for v in pos.size():
		for k in 3:
			rest_pos[v * 3 + k] = pos[v][k]
			rest_nrm[v * 3 + k] = nrm[v][k]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_INDEX] = p["index"]
	arrays[Mesh.ARRAY_CUSTOM0] = rest_pos
	arrays[Mesh.ARRAY_CUSTOM1] = rest_nrm
	arrays[Mesh.ARRAY_CUSTOM2] = field
	if int(p["per"]) > 0:
		arrays[Mesh.ARRAY_BONES] = p["bones"]
		arrays[Mesh.ARRAY_WEIGHTS] = p["weights"]
	var flags := (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	if int(p["per"]) == 8:
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var out := ArrayMesh.new()
	out.resource_name = src.resource_name
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	out.surface_set_material(0, src.surface_get_material(0))
	# MechPaint checks this against the live mesh: a re-export that changed the part means re-bake.
	out.set_meta(&"source_vertex_count", p["src_count"])
	return out


static func _segment_grid(segs: Array) -> Dictionary:
	var grid := {}
	for s: Array in segs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var lo := _cell(Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)))
		var hi := _cell(Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)))
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var k := Vector3i(x, y, z)
					if not grid.has(k):
						grid[k] = []
					(grid[k] as Array).append(s)
	return grid


static func _cell(p: Vector3) -> Vector3i:
	return Vector3i((p / CELL).floor())


static func _ckey(p: Vector3) -> Vector3i:
	return _cell(p)


static func _vkey(p: Vector3) -> int:
	var v := Vector3i((p / VOXEL).floor()) + Vector3i(512, 512, 512)
	return v.x | (v.y << 10) | (v.z << 20)


## [offset, distance] for every voxel within r, nearest first.
static func _sphere_offsets(r: int) -> Array:
	var out := []
	for x in range(-r, r + 1):
		for y in range(-r, r + 1):
			for z in range(-r, r + 1):
				var d := Vector3(x, y, z).length() * VOXEL
				if d <= r * VOXEL:
					out.append([Vector3(x, y, z) * VOXEL, d])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	return out


static func _seg_closest(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var l := ab.length_squared()
	if l < 1e-12:
		return a
	return a + ab * clampf((p - a).dot(ab) / l, 0.0, 1.0)


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	return p.distance_to(_seg_closest(p, a, b))
