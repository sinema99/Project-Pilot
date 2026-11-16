## Paints the revolver's chunky PS1 texture in code (docs/specs/pilot9-revolver-texture.md).
##
## assets/revolver.glb has no usable UVs (the body's collapse onto one line) and the grip is fused into
## the body mesh. So each mesh is re-built with box-projected UVs (every triangle goes to the X, Y or Z
## face cell of one shared atlas by its facing, at a uniform texel density), then rasterised: every
## texel finds the 3D point it sits on (barycentric across its triangle), and that point - in the
## GLB's own space - decides steel / wood / hammer / bore.
## Deterministic: same seed, same pixels.
extends RefCounted

const W := 64        ## atlas texels; the 4.3 unit gun is 64 across, about 100 texels per metre on the 0.6 m gun
const H := 80
const BLOCK := 4     ## the image is blown up with nearest sampling so the cel shader's linear filter stays chunky
## The GLB-space box every part sits in; its sides set the three cells' sizes at one density.
const BOX_MIN := Vector3(-4.05, -0.15, -0.5)
const BOX_SIZE := Vector3(4.4, 2.0, 1.0)

const STEEL := Color(0.27, 0.27, 0.30)
const STEEL_DARK := Color(0.17, 0.17, 0.20)
const STEEL_LIGHT := Color(0.70, 0.70, 0.74)
const CYLINDER := Color(0.20, 0.21, 0.26)
const HAMMER := Color(0.80, 0.78, 0.70)
const WOOD := Color(0.62, 0.31, 0.10)
const WOOD_DARK := Color(0.42, 0.19, 0.06)
const WOOD_PALE := Color(0.90, 0.62, 0.38)

## Where the grip starts, in the GLB's own space (muzzle -X, top +Y): behind the cylinder, below the frame.
const GRIP_MIN_X := -0.55
const GRIP_MAX_Y := 1.3
const MUZZLE_X := -3.99


## Atlas rects in texels (x, y, w, h): side faces (+-Z) see x by y; top and bottom (+-Y) x by z; the
## ends (+-X) a turned z by y.
static func _cell(axis: int) -> Rect2:
	match axis:
		2: return Rect2(0, 0, 64, 29)
		1: return Rect2(0, 30, 64, 15)
		_: return Rect2(0, 46, 29, 15)


static func _project(p: Vector3, axis: int) -> Vector2:
	var q := (p - BOX_MIN) / BOX_SIZE
	var r := _cell(axis)
	var f := Vector2.ZERO
	match axis:
		2: f = Vector2(q.x, 1.0 - q.y)
		1: f = Vector2(q.x, q.z)
		_: f = Vector2(1.0 - q.y, q.z)
	# Half a texel in from the cell's edge so neighbouring cells do not bleed.
	var inset := Vector2(0.5, 0.5) / r.size
	f = f.clamp(inset, Vector2.ONE - inset)
	return (r.position + f * r.size) / Vector2(W, H)


## `xf` takes the mesh's own vertices into the GLB's space (the node chain above the mesh). Replaces the
## instance's mesh with the re-projected one and returns the texture for it.
static func paint(mi: MeshInstance3D, xf: Transform3D, kind: StringName, seed_value: int, wear: float) -> ImageTexture:
	var src := mi.mesh
	var out := ArrayMesh.new()
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	# Base: blotchy steel everywhere so any texel no triangle covers is still plausible.
	for y in H:
		for x in W:
			img.set_pixel(x, y, _shade(kind, Vector3.ZERO, Vector3.UP, x, y, 1.0, seed_value, wear, true))
	for surf in src.get_surface_count():
		var arr := src.surface_get_arrays(surf)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx = PackedInt32Array(range(verts.size()))
		var nv := PackedVector3Array()
		var nn := PackedVector3Array()
		var nu := PackedVector2Array()
		var world := PackedVector3Array()
		var wnorm := PackedVector3Array()
		for t in range(0, idx.size() - 2, 3):
			var a := xf * verts[idx[t]]
			var b := xf * verts[idx[t + 1]]
			var c := xf * verts[idx[t + 2]]
			var fn := (b - a).cross(c - a)
			var axis := 2
			var fa := fn.abs()
			if fa.x > fa.y and fa.x > fa.z:
				axis = 0
			elif fa.y > fa.z:
				axis = 1
			for k in 3:
				var vi := idx[t + k]
				var wp := xf * verts[vi]
				nv.append(verts[vi])
				nn.append(norms[vi])
				nu.append(_project(wp, axis))
				world.append(wp)
				wnorm.append((xf.basis * norms[vi]).normalized())
		var na: Array = []
		na.resize(Mesh.ARRAY_MAX)
		na[Mesh.ARRAY_VERTEX] = nv
		na[Mesh.ARRAY_NORMAL] = nn
		na[Mesh.ARRAY_TEX_UV] = nu
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
		for t in range(0, nv.size() - 2, 3):
			_raster(img, world, wnorm, nu, t, kind, seed_value, wear)
	mi.mesh = out
	img.resize(W * BLOCK, H * BLOCK, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


static func _raster(img: Image, world: PackedVector3Array, wnorm: PackedVector3Array, uvs: PackedVector2Array,
		t: int, kind: StringName, seed_value: int, wear: float) -> void:
	var sz := Vector2(W, H)
	var ua := uvs[t] * sz
	var ub := uvs[t + 1] * sz
	var uc := uvs[t + 2] * sz
	var den := (ub.y - uc.y) * (ua.x - uc.x) + (uc.x - ub.x) * (ua.y - uc.y)
	if absf(den) < 0.0001:
		return
	var lo := Vector2(minf(ua.x, minf(ub.x, uc.x)), minf(ua.y, minf(ub.y, uc.y)))
	var hi := Vector2(maxf(ua.x, maxf(ub.x, uc.x)), maxf(ua.y, maxf(ub.y, uc.y)))
	for y in range(maxi(int(floorf(lo.y)) - 1, 0), mini(int(ceilf(hi.y)) + 1, H)):
		for x in range(maxi(int(floorf(lo.x)) - 1, 0), mini(int(ceilf(hi.x)) + 1, W)):
			var p := Vector2(x + 0.5, y + 0.5)
			var w0 := ((ub.y - uc.y) * (p.x - uc.x) + (uc.x - ub.x) * (p.y - uc.y)) / den
			var w1 := ((uc.y - ua.y) * (p.x - uc.x) + (ua.x - uc.x) * (p.y - uc.y)) / den
			var w2 := 1.0 - w0 - w1
			# A little slack so edge texels are covered (the bleed that stops seam lines).
			if minf(w0, minf(w1, w2)) < -0.12:
				continue
			var edge := clampf(minf(w0, minf(w1, w2)), 0.0, 1.0)
			var pos := world[t] * w0 + world[t + 1] * w1 + world[t + 2] * w2
			var nrm := (wnorm[t] * w0 + wnorm[t + 1] * w1 + wnorm[t + 2] * w2).normalized()
			img.set_pixel(x, y, _shade(kind, pos, nrm, x, y, edge, seed_value, wear, false))


static func _hash(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177 & 0x7fffffff
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0


## Blotches: cells of `cell` texels, hashed and blended, so it clumps like the reference's noise.
static func _blotch(x: int, y: int, cell: int, s: int) -> float:
	return _hash(x / cell, y / cell, s)


static func _shade(kind: StringName, pos: Vector3, nrm: Vector3, x: int, y: int, edge: float, s: int, wear: float, base_only: bool) -> Color:
	var blot := _blotch(x, y, 3, s) * 0.5 + _blotch(x, y, 1, s + 7) * 0.5
	if kind == &"hammer":
		return HAMMER.darkened(0.25 * blot)
	var is_grip := kind == &"body" and not base_only and pos.x > GRIP_MIN_X and pos.y < GRIP_MAX_Y
	if is_grip:
		return _wood(pos, x, y, edge, s, wear)
	# Steel. Streak highlights run along the barrel (constant in x): a band per slice of the
	# cross-section, bright or dark by hash - the long painted glints of the reference.
	var col := STEEL.lerp(STEEL_DARK, blot * 0.6)
	if kind == &"cylinder":
		col = CYLINDER.lerp(STEEL_DARK, blot * 0.5)
	if not base_only:
		var band := int(floorf(pos.y * 14.0 + pos.z * 19.0))
		var bh := _hash(band, 3, s)
		var along := _hash(int(floorf(pos.x * 9.0)), band, s + 3)
		var streak_gain := 0.45 if kind == &"cylinder" else 0.3
		if bh > 0.72 and along > 0.25:
			col = col.lerp(STEEL_LIGHT, streak_gain + 0.3 * along)
		elif bh < 0.22:
			col = col.lerp(Color(0.07, 0.07, 0.09), 0.6)
		# Bore: the muzzle face is a black ring.
		if kind == &"body" and pos.x < MUZZLE_X + 0.08 and nrm.x < -0.7:
			col = Color(0.03, 0.03, 0.04)
		# Edge scuffs: texels hugging a triangle edge go pale, the steel showing through the bluing.
		if edge < 0.07 and _hash(x, y, s + 11) < 0.35 + wear * 0.5:
			col = col.lerp(STEEL_LIGHT, 0.55)
		# Cylinder flutes: pale scratches around the drum.
		if kind == &"cylinder" and _hash(x, y, s + 23) > 0.96:
			col = col.lerp(STEEL_LIGHT, 0.6)
	return col


static func _wood(pos: Vector3, x: int, y: int, edge: float, s: int, wear: float) -> Color:
	# Grain runs down the grip, which leans about 25 degrees off vertical in the GLB.
	var along := pos.y * 0.9 + pos.x * 0.45
	var gband := int(floorf(along * 26.0 + pos.z * 9.0))
	var grain := _hash(gband, 5, s)
	var col := WOOD.lerp(WOOD_DARK, grain * 0.7)
	col = col.lerp(WOOD_DARK, _blotch(x, y, 3, s + 31) * 0.28)
	# Dark flecks and a few pale scuffs at the heel and edges.
	if _hash(x, y, s + 41) > 0.94:
		col = col.lerp(WOOD_DARK, 0.8)
	if edge < 0.08 and _hash(x, y, s + 47) < 0.25 + wear * 0.5:
		col = col.lerp(WOOD_PALE, 0.7)
	elif _hash(x, y, s + 53) > 0.975:
		col = col.lerp(WOOD_PALE, 0.6)
	return col
