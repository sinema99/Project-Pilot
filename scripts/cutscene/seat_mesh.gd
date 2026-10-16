class_name SeatMesh
extends RefCounted

# Mesh builders for the cockpit seat (scripts/cutscene/cockpit_seat.gd): boxes with rounded edges
# and shapes turned on a lathe, both with smooth analytic normals, so every edge catches a cel
# highlight and the outline hull stays closed. See docs/specs/cutscene-cockpit.md.
#
# Godot draws a triangle's front when (v1 - v0) x (v2 - v0) points AWAY from the outward normal;
# both builders wind that way.

## Box-projected UV units per metre.
const UV_SCALE := 1.5


## A box `size` with every edge rounded to `radius` (`bevel` segments per half of the 90 deg turn,
## so 2 * bevel across an edge). Options, each optional:
## - "taper": Vector2, the top face's scale in x and z (1, 1 = straight sides).
## - "shear": Vector2, the top face's offset in x and z.
## - "puff": float, how far the top face domes up at its centre (cushions).
## - "subdiv": int, extra grid lines across each face, needed for "puff" to show.
## Taper, shear and puff blend in from bottom (none) to top (full), and the normals follow them.
static func rounded_box(size: Vector3, radius: float, bevel := 2, opts := {}) -> Array:
	var h := size * 0.5
	var r := minf(radius, minf(h.x, minf(h.y, h.z)) * 0.98)
	r = maxf(r, 0.002)
	var inner := h - Vector3.ONE * r
	var subdiv: int = opts.get("subdiv", 0)
	var coords := [_axis_coords(h.x, r, bevel, subdiv), _axis_coords(h.y, r, bevel, subdiv),
			_axis_coords(h.z, r, bevel, subdiv)]
	var deform := func(p: Vector3) -> Vector3: return _deform(p, h, opts)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for axis in 3:
		var b := (axis + 1) % 3
		var c := (axis + 2) % 3
		for sgn: float in [1.0, -1.0]:
			var cb: Array = coords[b]
			var cc: Array = coords[c]
			var base := verts.size()
			for j in cc.size():
				for i in cb.size():
					var p := Vector3.ZERO
					p[axis] = h[axis] * sgn
					p[b] = cb[i]
					p[c] = cc[j]
					var q := p.clamp(-inner, inner)
					var n := (p - q).normalized()
					var rounded := q + n * r
					verts.append(deform.call(rounded))
					normals.append(_deformed_normal(deform, rounded, n))
			var w := cb.size()
			for j in cc.size() - 1:
				for i in w - 1:
					var a0 := base + j * w + i
					_quad(indices, verts, normals, a0, a0 + 1, a0 + w + 1, a0 + w)
	return _arrays(verts, normals, indices)


## A solid of revolution about local Y from a profile of (radius, y) points, bottom to top, each
## with its 2D outward normal (radial, y). `segments` around.
static func lathe(profile: PackedVector2Array, profile_normals: PackedVector2Array, segments := 20) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var ring := segments + 1
	for k in profile.size():
		for s in ring:
			var a := TAU * float(s) / segments
			var dir := Vector3(cos(a), 0.0, sin(a))
			verts.append(dir * profile[k].x + Vector3.UP * profile[k].y)
			normals.append((dir * profile_normals[k].x + Vector3.UP * profile_normals[k].y).normalized())
	for k in profile.size() - 1:
		for s in segments:
			var a0 := k * ring + s
			_quad(indices, verts, normals, a0, a0 + 1, a0 + ring + 1, a0 + ring)
	return _arrays(verts, normals, indices)


## A cylinder `height` tall along local Y, centred, with its rim edges rounded to `edge`.
## `top_radius` < 0 means the same as `radius` (a straight cylinder); otherwise a cone frustum.
static func rounded_cylinder(radius: float, height: float, edge: float, segments := 20,
		top_radius := -1.0) -> Array:
	var rt := radius if top_radius < 0.0 else top_radius
	var e := clampf(edge, 0.001, minf(minf(radius, rt), height * 0.5) * 0.98)
	var hh := height * 0.5
	var side := Vector2(height, -(rt - radius)).normalized() # outward normal of the side (radial, y)
	var prof := PackedVector2Array()
	var nrm := PackedVector2Array()
	prof.append(Vector2(0.0, -hh))
	nrm.append(Vector2(0.0, -1.0))
	# Bottom rim, from the cap normal round to the side normal.
	var c0 := Vector2(radius - e, -hh + e)
	var a_bottom := -PI * 0.5
	var a_side := atan2(side.y, side.x)
	for i in 4:
		var a := lerpf(a_bottom, a_side, float(i) / 3.0)
		prof.append(c0 + Vector2(cos(a), sin(a)) * e)
		nrm.append(Vector2(cos(a), sin(a)))
	var c1 := Vector2(rt - e, hh - e)
	for i in 4:
		var a := lerpf(a_side, PI * 0.5, float(i) / 3.0)
		prof.append(c1 + Vector2(cos(a), sin(a)) * e)
		nrm.append(Vector2(cos(a), sin(a)))
	prof.append(Vector2(0.0, hh))
	nrm.append(Vector2(0.0, 1.0))
	return lathe(prof, nrm, segments)


## A basis whose local Y points along `dir`: stands a lathe shape on a face.
static func facing(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var helper := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# Grid positions along one axis of half-extent h: the bevel samples (spaced so the rounded corner
# comes out in even angle steps), the face interior, then the other bevel.
static func _axis_coords(h: float, r: float, bevel: int, subdiv: int) -> Array:
	var inner := h - r
	var out: Array = []
	for k in range(bevel, -1, -1):
		out.append(-inner - r * tan(float(k) / bevel * PI * 0.25))
	for k in range(1, subdiv + 1):
		out.append(lerpf(-inner, inner, float(k) / (subdiv + 1)))
	for k in range(0, bevel + 1):
		out.append(inner + r * tan(float(k) / bevel * PI * 0.25))
	return out


static func _deform(p: Vector3, h: Vector3, opts: Dictionary) -> Vector3:
	var t := clampf((p.y + h.y) / (2.0 * h.y), 0.0, 1.0)
	var taper: Vector2 = opts.get("taper", Vector2.ONE)
	var shear: Vector2 = opts.get("shear", Vector2.ZERO)
	var puff: float = opts.get("puff", 0.0)
	var out := Vector3(p.x * lerpf(1.0, taper.x, t) + shear.x * t, p.y,
			p.z * lerpf(1.0, taper.y, t) + shear.y * t)
	if puff != 0.0:
		var u := clampf(p.x / h.x, -1.0, 1.0)
		var v := clampf(p.z / h.z, -1.0, 1.0)
		out.y += puff * (1.0 - u * u) * (1.0 - v * v) * t * t
	return out


# The normal carried through the deformation: the inverse transpose of its Jacobian, taken by
# central differences.
static func _deformed_normal(deform: Callable, p: Vector3, n: Vector3) -> Vector3:
	const E := 1e-4
	var dx: Vector3 = (deform.call(p + Vector3(E, 0, 0)) - deform.call(p - Vector3(E, 0, 0))) / (2.0 * E)
	var dy: Vector3 = (deform.call(p + Vector3(0, E, 0)) - deform.call(p - Vector3(0, E, 0))) / (2.0 * E)
	var dz: Vector3 = (deform.call(p + Vector3(0, 0, E)) - deform.call(p - Vector3(0, 0, E))) / (2.0 * E)
	var j := Basis(dx, dy, dz)
	if absf(j.determinant()) < 1e-8:
		return n
	return (j.inverse().transposed() * n).normalized()


# Two triangles over a, b, c, d (in either order round the quad), each wound to face its vertex
# normals.
static func _quad(indices: PackedInt32Array, verts: PackedVector3Array, normals: PackedVector3Array,
		a: int, b: int, c: int, d: int) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var v0 := verts[tri[0]]
		var cross := (verts[tri[1]] - v0).cross(verts[tri[2]] - v0)
		var avg := normals[tri[0]] + normals[tri[1]] + normals[tri[2]]
		if cross.dot(avg) > 0.0:
			tri = [tri[0], tri[2], tri[1]]
		indices.append_array(PackedInt32Array(tri))


static func _arrays(verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	# Box-projected UVs for the cel material's painted patches (docs/specs/painted-shading.md).
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	for i in verts.size():
		var p := verts[i] * UV_SCALE
		var a := normals[i].abs()
		if a.x >= a.y and a.x >= a.z:
			uvs[i] = Vector2(p.z, p.y)
		elif a.y >= a.z:
			uvs[i] = Vector2(p.x, p.z)
		else:
			uvs[i] = Vector2(p.x, p.y)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	return arrays
