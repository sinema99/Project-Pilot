class_name Hub2RoofClip
extends RefCounted

# Cuts a rectangular hole (world XZ) out of the flat triangles that lie in a thin horizontal band,
# so hub2's roof really has a gap in it (docs/specs/hub2-roof-door.md). Works on mesh arrays and on
# collision faces; every per-vertex attribute (normal, colour, uv, the wear bake's CUSTOM0/1) is
# interpolated along the cut, so the baked wear stays continuous.
#
# Only meshes that are not indexed (the wear bake's are flat-shaded, one vertex per corner) and carry
# no bones. A triangle that is cut keeps its slot for its first piece; further pieces are appended; a
# triangle fully inside the hole collapses to a zero-area sliver. Nothing else is touched.


## `mesh` with `hole` (world XZ) cut out of every flat triangle whose three corners sit between world
## heights y_lo and y_hi. `to_world` is the mesh's transform. Null when nothing was cut.
static func cut_mesh(mesh: Mesh, to_world: Transform3D, hole: Rect2, y_lo: float, y_hi: float) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var out := ArrayMesh.new()
	var changed := false
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var fmt: int = mesh.surface_get_format(s)
		if cut_arrays(arrays, to_world, hole, y_lo, y_hi):
			changed = true
		var flags := 0
		for n in 4:
			flags |= fmt & (7 << (Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT + 3 * n))
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays, [], {}, flags)
		out.surface_set_material(s, mesh.surface_get_material(s))
	if not changed:
		return null
	for k in mesh.get_meta_list():
		out.set_meta(k, mesh.get_meta(k))
	return out


## Collision faces (a ConcavePolygonShape3D's data) with the same hole cut.
static func cut_faces(faces: PackedVector3Array, to_world: Transform3D, hole: Rect2, y_lo: float, y_hi: float) -> PackedVector3Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	if cut_arrays(arrays, to_world, hole, y_lo, y_hi):
		return arrays[Mesh.ARRAY_VERTEX]
	return faces


## Cuts `arrays` (a surface's arrays) in place. True when anything changed.
static func cut_arrays(arrays: Array, to_world: Transform3D, hole: Rect2, y_lo: float, y_hi: float) -> bool:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: Variant = arrays[Mesh.ARRAY_INDEX]
	if index != null and (index as PackedInt32Array).size() > 0:
		push_warning("Hub2RoofClip: indexed mesh, not cut.")
		return false
	if arrays[Mesh.ARRAY_BONES] != null or arrays[Mesh.ARRAY_WEIGHTS] != null:
		push_warning("Hub2RoofClip: skinned mesh, not cut.")
		return false
	var n := verts.size()
	if n < 3:
		return false

	# Which triangles can touch the hole: tested in the mesh's own space so the scan is plain compares.
	var box := AABB(Vector3(hole.position.x, y_lo, hole.position.y), Vector3(hole.size.x, y_hi - y_lo, hole.size.y))
	var local_box := to_world.affine_inverse() * box
	var lo := local_box.position
	var hi := local_box.end
	var hits := PackedInt32Array()
	var i := 0
	while i < n:
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		if maxf(a.x, maxf(b.x, c.x)) >= lo.x and minf(a.x, minf(b.x, c.x)) <= hi.x \
				and maxf(a.z, maxf(b.z, c.z)) >= lo.z and minf(a.z, minf(b.z, c.z)) <= hi.z \
				and maxf(a.y, maxf(b.y, c.y)) >= lo.y and minf(a.y, minf(b.y, c.y)) <= hi.y:
			hits.append(i)
		i += 3
	if hits.is_empty():
		return false

	# Attribute layout: the vertex position first, then every other per-vertex array.
	var slots: Array[int] = []
	var strides: Array[int] = []
	for s in Mesh.ARRAY_MAX:
		if s == Mesh.ARRAY_VERTEX or s == Mesh.ARRAY_INDEX:
			continue
		var a: Variant = arrays[s]
		if a == null:
			continue
		if a.size() == 0:
			continue
		var stride := 0
		match typeof(a):
			TYPE_PACKED_VECTOR3_ARRAY:
				stride = 3
			TYPE_PACKED_VECTOR2_ARRAY:
				stride = 2
			TYPE_PACKED_COLOR_ARRAY:
				stride = 4
			TYPE_PACKED_FLOAT32_ARRAY:
				stride = int((a as PackedFloat32Array).size() / float(n))
			_:
				push_warning("Hub2RoofClip: attribute %d has an unsupported type; mesh not cut." % s)
				return false
		slots.append(s)
		strides.append(stride)
	var work: Array = []
	for s in slots:
		work.append(arrays[s])

	var changed := false
	for t in hits:
		var tri: Array = [_record(verts, work, strides, t), _record(verts, work, strides, t + 1), _record(verts, work, strides, t + 2)]
		var ok := true
		for r in tri:
			var wy := (to_world * Vector3(r[0], r[1], r[2])).y
			if wy < y_lo or wy > y_hi:
				ok = false
		if not ok:
			continue
		var pieces := _subtract(tri, to_world, hole)
		var kept := 0.0
		for p in pieces:
			kept += _area_xz(p, to_world)
		if absf(kept - _area_xz(tri, to_world)) < 1e-6:
			continue    # bounding boxes met but the triangle is clear of the hole
		changed = true
		var out_tris: Array = []
		for p in pieces:
			for k in range(1, p.size() - 1):
				out_tris.append([p[0], p[k], p[k + 1]])
		var first := true
		for ot in out_tris:
			if first:
				for k in 3:
					_store(verts, work, strides, t + k, ot[k])
				first = false
			else:
				for k in 3:
					_store(verts, work, strides, -1, ot[k])
		if first:
			# Gone entirely: collapse onto the first corner.
			var v0 := verts[t]
			verts[t + 1] = v0
			verts[t + 2] = v0
	if not changed:
		return false
	arrays[Mesh.ARRAY_VERTEX] = verts
	for k in slots.size():
		arrays[slots[k]] = work[k]
	return true


# -- polygon work -------------------------------------------------------------------------------

## The parts of the convex polygon `poly` outside `hole`, as convex polygons.
static func _subtract(poly: Array, to_world: Transform3D, hole: Rect2) -> Array:
	var pieces: Array = []
	var rest := poly
	for step in 4:
		var axis := 0 if step < 2 else 2
		var limit := hole.position.x if step == 0 else (hole.end.x if step == 1 else (hole.position.y if step == 2 else hole.end.y))
		var outside_low := step == 0 or step == 2
		var outside := _clip(rest, to_world, axis, limit, outside_low)
		if outside.size() >= 3 and _area_xz(outside, to_world) > 1e-7:
			pieces.append(outside)
		rest = _clip(rest, to_world, axis, limit, not outside_low)
		if rest.size() < 3:
			break
	return pieces


## `poly` kept where the world coordinate on `axis` (0 = x, 2 = z) is <= limit (keep_low) or >= limit.
static func _clip(poly: Array, to_world: Transform3D, axis: int, limit: float, keep_low: bool) -> Array:
	var out: Array = []
	var count := poly.size()
	for i in count:
		var a: PackedFloat32Array = poly[i]
		var b: PackedFloat32Array = poly[(i + 1) % count]
		var da := _coord(a, to_world, axis) - limit
		var db := _coord(b, to_world, axis) - limit
		if not keep_low:
			da = -da
			db = -db
		var in_a := da <= 0.0
		var in_b := db <= 0.0
		if in_a:
			out.append(a)
		if in_a != in_b:
			var t := da / (da - db)
			var m := PackedFloat32Array()
			m.resize(a.size())
			for k in a.size():
				m[k] = lerpf(a[k], b[k], t)
			out.append(m)
	return out


static func _coord(r: PackedFloat32Array, to_world: Transform3D, axis: int) -> float:
	var w := to_world * Vector3(r[0], r[1], r[2])
	return w.x if axis == 0 else w.z


static func _area_xz(poly: Array, to_world: Transform3D) -> float:
	var sum := 0.0
	var count := poly.size()
	for i in count:
		var a := to_world * Vector3(poly[i][0], poly[i][1], poly[i][2])
		var j := (i + 1) % count
		var b := to_world * Vector3(poly[j][0], poly[j][1], poly[j][2])
		sum += a.x * b.z - b.x * a.z
	return absf(sum) * 0.5


# -- vertex records: position + every attribute as one float run --------------------------------

static func _record(verts: PackedVector3Array, work: Array, strides: Array[int], i: int) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	var v := verts[i]
	r.append(v.x)
	r.append(v.y)
	r.append(v.z)
	for k in work.size():
		var a: Variant = work[k]
		match typeof(a):
			TYPE_PACKED_VECTOR3_ARRAY:
				var q: Vector3 = a[i]
				r.append(q.x)
				r.append(q.y)
				r.append(q.z)
			TYPE_PACKED_VECTOR2_ARRAY:
				var q: Vector2 = a[i]
				r.append(q.x)
				r.append(q.y)
			TYPE_PACKED_COLOR_ARRAY:
				var q: Color = a[i]
				r.append(q.r)
				r.append(q.g)
				r.append(q.b)
				r.append(q.a)
			_:
				for j in strides[k]:
					r.append(a[i * strides[k] + j])
	return r


## Writes `r` over vertex `i`, or appends it when i < 0.
static func _store(verts: PackedVector3Array, work: Array, strides: Array[int], i: int, r: PackedFloat32Array) -> void:
	var v := Vector3(r[0], r[1], r[2])
	if i < 0:
		verts.append(v)
	else:
		verts[i] = v
	var o := 3
	for k in work.size():
		match typeof(work[k]):
			TYPE_PACKED_VECTOR3_ARRAY:
				var a3: PackedVector3Array = work[k]
				var q3 := Vector3(r[o], r[o + 1], r[o + 2])
				o += 3
				if i < 0:
					a3.append(q3)
				else:
					a3[i] = q3
				work[k] = a3
			TYPE_PACKED_VECTOR2_ARRAY:
				var a2: PackedVector2Array = work[k]
				var q2 := Vector2(r[o], r[o + 1])
				o += 2
				if i < 0:
					a2.append(q2)
				else:
					a2[i] = q2
				work[k] = a2
			TYPE_PACKED_COLOR_ARRAY:
				var ac: PackedColorArray = work[k]
				var qc := Color(r[o], r[o + 1], r[o + 2], r[o + 3])
				o += 4
				if i < 0:
					ac.append(qc)
				else:
					ac[i] = qc
				work[k] = ac
			_:
				var af: PackedFloat32Array = work[k]
				for j in strides[k]:
					if i < 0:
						af.append(r[o + j])
					else:
						af[i * strides[k] + j] = r[o + j]
				o += strides[k]
				work[k] = af
