## pilot9's cowboy hat, modelled in code: a classic cattleman. See docs/specs/pilot9-cowboy-hat.md.
##
## Hat space: y up, +Z the front, origin at the centre of the headband opening (the brim's
## underside at the crown). One closed surface of revolution - a profile swept round an ellipse -
## bent per angle for the brim curl, the front dip, the crease and the two front pinches. The band
## is a second mesh hugging the bottom of the crown.
##
## Every profile segment is its own smooth group, so the brim edge and the crown/brim join stay
## hard under the cel bands while the crown's top edge rounds off.
extends RefCounted

const SEGMENTS := 64

## Brim: half-widths across (x) and front to back (z). Sized to his head, not a real one: his head
## is ~0.25 m across, so the brim is ~0.5 m front to back.
const BRIM_X := 0.235
const BRIM_Z := 0.25
const BRIM_THICKNESS := 0.01
## How far the sides curl up at the edge, and how far the front and back dip.
const BRIM_CURL := 0.075
const BRIM_DIP := 0.016

## Crown half-widths at the brim and at the top - tapered (user, 2026-10-22: top not so wide).
const CROWN_BASE := Vector2(0.128, 0.122)
const CROWN_TOP := Vector2(0.09, 0.088)
## Crown height at the back; the front is CROWN_FRONT_DROP lower.
const CROWN_HEIGHT := 0.155
const CROWN_FRONT_DROP := 0.016
## The centre crease: depth at its deepest, half-width across.
const CREASE_DEPTH := 0.065
const CREASE_WIDTH := 0.045
## The front pinches: how far in, at which angle either side of the front, how wide.
const PINCH_DEPTH := 0.045
const PINCH_ANGLE := 0.65
const PINCH_WIDTH := 0.32

## Band: from BAND_LOW to BAND_HIGH of the way up the crown, standing BAND_PROUD off it.
const BAND_LOW := 0.04
const BAND_HIGH := 0.22
const BAND_PROUD := 0.005


## Two meshes, so each can carry its own material_override: apply_stylized.gd re-derives the
## surface materials of anything under his skeleton, but leaves an override alone.
static func build_felt() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_commit(mesh, _felt_strips())
	return mesh


static func build_band() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_commit(mesh, _band_strips())
	return mesh


## -- shape ---------------------------------------------------------------------------------

static func _crown_height(theta: float) -> float:
	return CROWN_HEIGHT - CROWN_FRONT_DROP * cos(theta)


## Radial pull-in of the crown at angle `theta`, `k` of the way up it (0 brim, 1 top).
static func _pinch(theta: float, k: float) -> float:
	var a := wrapf(theta, -PI, PI)
	var g := exp(-pow((a - PINCH_ANGLE) / PINCH_WIDTH, 2.0)) \
		+ exp(-pow((a + PINCH_ANGLE) / PINCH_WIDTH, 2.0))
	return PINCH_DEPTH * k * k * g


## A point on the crown wall, `k` of the way up, pushed `proud` metres out.
static func _wall(theta: float, k: float, proud: float = 0.0) -> Vector3:
	var r := CROWN_BASE.lerp(CROWN_TOP, k)
	var dir := Vector3(sin(theta), 0.0, cos(theta))
	var p := Vector3(r.x * dir.x, 0.0, r.y * dir.z)
	var out := p.normalized() if p.length() > 0.0 else dir
	p += out * (proud - _pinch(theta, k))
	p.y = BRIM_THICKNESS + k * (_crown_height(theta) - BRIM_THICKNESS)
	return p


## A point on the crown top, `v` of the way from the centre (0) to the edge (1).
static func _top(theta: float, v: float) -> Vector3:
	var edge := _wall(theta, 1.0)
	var p := Vector3(edge.x * v, 0.0, edge.z * v)
	var crease := CREASE_DEPTH * exp(-pow(p.x / CREASE_WIDTH, 2.0)) * (1.0 - pow(v, 6.0))
	p.y = _crown_height(theta) - crease
	return p


## The brim's curl at `u` of the way out (0 crown, 1 edge): sides up, front and back down.
static func _curl(theta: float, u: float) -> float:
	var s := sin(theta)
	var c := cos(theta)
	return BRIM_CURL * pow(u, 2.5) * s * s - BRIM_DIP * u * u * c * c


## A point on the brim, `u` of the way out, on its top (true) or underside.
static func _brim(theta: float, u: float, top: bool) -> Vector3:
	var hx := lerpf(CROWN_BASE.x, BRIM_X, u)
	var hz := lerpf(CROWN_BASE.y, BRIM_Z, u)
	var y := _curl(theta, u) + (BRIM_THICKNESS if top else 0.0)
	return Vector3(hx * sin(theta), y, hz * cos(theta))


## -- strips: each is one smooth group, an Array of row Callables (theta -> Vector3) ----------

static func _felt_strips() -> Array:
	var underside := [func(t: float) -> Vector3: return Vector3.ZERO]
	for u in [0.0, 0.25, 0.5, 0.75, 1.0]:
		underside.append(_brim_row(u, false))
	var rim := [_brim_row(1.0, false), _brim_row(1.0, true)]
	var brim_top := []
	for u in [1.0, 0.75, 0.5, 0.25, 0.0]:
		brim_top.append(_brim_row(u, true))
	var crown := []
	for k in [0.0, 0.25, 0.5, 0.75, 0.92]:
		crown.append(_wall_row(k, 0.0))
	crown.append(func(t: float) -> Vector3:
		var p := _top(t, 0.97)
		p.y -= 0.004
		return p)
	for v in [0.85, 0.65, 0.45, 0.25, 0.1, 0.0]:
		crown.append(_top_row(v))
	return [underside, rim, brim_top, crown]


static func _band_strips() -> Array:
	return [
		[_wall_row(BAND_LOW, 0.0), _wall_row(BAND_LOW, BAND_PROUD)],
		[_wall_row(BAND_LOW, BAND_PROUD), _wall_row(BAND_HIGH, BAND_PROUD)],
		[_wall_row(BAND_HIGH, BAND_PROUD), _wall_row(BAND_HIGH, 0.0)],
	]


static func _brim_row(u: float, top: bool) -> Callable:
	return func(t: float) -> Vector3: return _brim(t, u, top)


static func _wall_row(k: float, proud: float) -> Callable:
	return func(t: float) -> Vector3: return _wall(t, k, proud)


static func _top_row(v: float) -> Callable:
	return func(t: float) -> Vector3: return _top(t, v)


## -- assembly ------------------------------------------------------------------------------

## Sweeps every strip round the hat into one surface. Rows run outward-and-up along the profile
## and theta runs toward +x from the front, which winds every quad clockwise seen from outside -
## Godot's front face - so generate_normals() points them out.
static func _commit(mesh: ArrayMesh, strips: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var total_rows := 0
	for strip: Array in strips:
		total_rows += strip.size()
	var row_index := 0
	for g in strips.size():
		var strip: Array = strips[g]
		st.set_smooth_group(g)
		for r in strip.size() - 1:
			var a: Callable = strip[r]
			var b: Callable = strip[r + 1]
			var va := float(row_index + r) / float(total_rows)
			var vb := float(row_index + r + 1) / float(total_rows)
			for i in SEGMENTS:
				var t0 := TAU * float(i) / float(SEGMENTS)
				var t1 := TAU * float(i + 1) / float(SEGMENTS)
				var u0 := float(i) / float(SEGMENTS)
				var u1 := float(i + 1) / float(SEGMENTS)
				var a0: Vector3 = a.call(t0)
				var a1: Vector3 = a.call(t1)
				var b0: Vector3 = b.call(t0)
				var b1: Vector3 = b.call(t1)
				_tri(st, [a0, b0, b1], [Vector2(u0, va), Vector2(u0, vb), Vector2(u1, vb)])
				_tri(st, [a0, b1, a1], [Vector2(u0, va), Vector2(u1, vb), Vector2(u1, va)])
		row_index += strip.size()
	st.generate_normals()
	st.index()
	st.commit(mesh)


static func _tri(st: SurfaceTool, points: Array, uvs: Array) -> void:
	# Skip the slivers at the poles, where two corners are the same point.
	if (points[0] as Vector3).is_equal_approx(points[1]) or (points[1] as Vector3).is_equal_approx(points[2]) \
			or (points[0] as Vector3).is_equal_approx(points[2]):
		return
	for i in 3:
		st.set_uv(uvs[i])
		st.add_vertex(points[i])
