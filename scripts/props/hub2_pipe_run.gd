@tool
class_name Hub2PipeRun
extends Node3D

# One pipe of a hub2 pipe bundle (docs/specs/hub2-pipe-routing.md): a polyline of low-poly tubes with
# flanges, a chamfered elbow (collars both sides) at every bend, brackets back to the surface it hangs
# from, and now and then a valve wheel or a gauge. Each end is capped: WALL = it goes into a surface
# (square sleeve plate on walls / ceilings, round flange on floors, the tube carries on 0.3 m inside),
# TEE = it joins another pipe (a collar around the host pipe). `sag` drops the middle of the longest
# segment off its brackets. Visual only, no collision (it runs along wall / ceiling corners).

enum Service { STEEL, FIRE, GAS, WATER }
enum End { OPEN, WALL, TEE }

const COLOURS := {
	Service.STEEL: Color(0.46, 0.47, 0.48),
	Service.FIRE: Color(0.33, 0.17, 0.15),
	Service.GAS: Color(0.42, 0.37, 0.24),
	Service.WATER: Color(0.36, 0.44, 0.38),
}

@export var points := PackedVector3Array():
	set(v):
		points = v
		_queue()
@export var radius := 0.2:
	set(v):
		radius = v
		_queue()
@export var service: Service = Service.STEEL:
	set(v):
		service = v
		_queue()
## Local direction from the pipe to the surface its brackets fix to (used where `mount_dirs` has no entry).
@export var mount_dir := Vector3.UP:
	set(v):
		mount_dir = v
		_queue()
## Per segment (points[i] -> points[i + 1]): direction to the surface that segment's brackets fix to.
@export var mount_dirs := PackedVector3Array():
	set(v):
		mount_dirs = v
		_queue()
## Distance from the pipe centre to that surface.
@export var mount_gap := 0.4:
	set(v):
		mount_gap = v
		_queue()
@export var sag := false:
	set(v):
		sag = v
		_queue()
## How the first / last point ends (see End).
@export var end_a: End = End.OPEN:
	set(v):
		end_a = v
		_queue()
@export var end_b: End = End.OPEN:
	set(v):
		end_b = v
		_queue()
## WALL: the surface normal (out of the surface) at that end. TEE: the host pipe's direction.
@export var end_a_normal := Vector3.ZERO:
	set(v):
		end_a_normal = v
		_queue()
@export var end_b_normal := Vector3.ZERO:
	set(v):
		end_b_normal = v
		_queue()
## Radius of the host pipe a TEE end joins.
@export var tee_radius := 0.3:
	set(v):
		tee_radius = v
		_queue()
@export var fittings_seed := 0:
	set(v):
		fittings_seed = v
		_queue()
@export var wear := 0.8:
	set(v):
		wear = v
		_queue()
@export var view_range := 130.0:
	set(v):
		view_range = v
		_queue()

const BRACKET := Color(0.22, 0.23, 0.25)
const BRACKET_PITCH := 3.0
## How far a WALL end carries on inside the surface (hides the cut).
const INTO_WALL := 0.3

var _built := false


func _ready() -> void:
	_built = true
	_rebuild()


func _queue() -> void:
	if _built:
		_rebuild()


func _rebuild() -> void:
	for child in get_children():
		if child.has_meta(&"prop_part"):
			child.free()
	if points.size() < 2:
		return
	var key := [points, radius, int(service), mount_dir, mount_dirs, mount_gap, sag, int(end_a), int(end_b),
		end_a_normal, end_b_normal, tee_radius, fittings_seed, wear]
	var made := PropMeshCache.fetch("pipe4", key, func() -> Dictionary: return {"mesh": _build_mesh(), "boxes": []})
	var mi := MeshInstance3D.new()
	mi.name = "Visual"
	mi.mesh = made["mesh"]
	mi.visibility_range_end = view_range
	mi.set_meta(&"prop_part", true)
	add_child(mi)


## Bend radius at a corner for this pipe (thin pipes bend tighter).
func bend_radius() -> float:
	return radius * 1.5


## Where the drawn elbow at interior point i of `pts` passes closest to the corner, and its direction
## there: [point, tangent]. (Same trim rule as _build_mesh; a tee onto a bend goes here.)
static func elbow_mid(pts: PackedVector3Array, i: int, r: float) -> Array:
	var din := (pts[i] - pts[i - 1]).normalized()
	var dout := (pts[i + 1] - pts[i]).normalized()
	var ang := din.angle_to(dout)
	if ang < deg_to_rad(4.0):
		return [pts[i], din]
	var t := minf(r * 1.5 * tan(ang * 0.5), 0.45 * minf(pts[i].distance_to(pts[i - 1]), pts[i].distance_to(pts[i + 1])))
	return [pts[i] + (dout - din) * t * 0.25, (din + dout).normalized()]


func _mount(i: int) -> Vector3:
	var m := mount_dirs[i] if i < mount_dirs.size() else mount_dir
	return m.normalized() if m.length_squared() > 1e-6 else Vector3.UP


func _build_mesh() -> ArrayMesh:
	var kit := PropKit.new(wear, fittings_seed)
	kit.cell = 1.2
	kit.floor_y = -1000.0
	var rng := RandomNumberGenerator.new()
	rng.seed = fittings_seed
	var col: Color = COLOURS[service]
	var sides := 6 if radius < 0.3 else 8
	var n := points.size()
	# Per-segment direction and length; the tangent trim at each interior point (the elbow's reach).
	var dirs: Array[Vector3] = []
	var lens: Array[float] = []
	for i in n - 1:
		var d := points[i + 1] - points[i]
		lens.append(d.length())
		dirs.append(d / maxf(d.length(), 0.0001))
	var trim: Array[float] = []
	trim.resize(n)
	trim.fill(0.0)
	for i in range(1, n - 1):
		var ang := dirs[i - 1].angle_to(dirs[i])
		if ang < deg_to_rad(4.0):
			continue
		var t := bend_radius() * tan(ang * 0.5)
		trim[i] = minf(t, 0.45 * minf(lens[i - 1], lens[i]))
	var longest := -1
	if sag:
		var bl := -1.0
		for i in n - 1:
			if lens[i] > bl and absf(dirs[i].y) < 0.3:
				bl = lens[i]
				longest = i
	for i in n - 1:
		var a := points[i] + dirs[i] * trim[i]
		var b := points[i + 1] - dirs[i] * trim[i + 1]
		if i == 0 and end_a == End.WALL:
			a -= dirs[i] * INTO_WALL
		if i == n - 2 and end_b == End.WALL:
			b += dirs[i] * INTO_WALL
		var md := _mount(i)
		if i == longest:
			# The sagging span: dropped off its brackets, dipping down.
			var drop := Vector3.DOWN * minf(2.5, lens[i] * 0.12)
			var dip := [a, a.lerp(b, 0.3) + drop * 0.7, a.lerp(b, 0.5) + drop, a.lerp(b, 0.7) + drop * 0.7, b]
			for k in 4:
				kit.tube(dip[k], dip[k + 1], radius, col, sides, Transform3D.IDENTITY, false)
			continue
		kit.tube(a, b, radius, col, sides, Transform3D.IDENTITY, false)
		var span := a.distance_to(b)
		var dir := dirs[i]
		# Flanges every ~6 m and brackets every BRACKET_PITCH.
		var s := 1.0
		while s < span - 0.5:
			var p := a + dir * s
			if fmod(s, 6.0) < BRACKET_PITCH * 0.5:
				kit.tube(p - dir * 0.05, p + dir * 0.05, radius * 1.35, col.darkened(0.15), sides, Transform3D.IDENTITY, false)
			_bracket(kit, p, md)
			s += BRACKET_PITCH
		# A valve wheel or a gauge on some segments.
		if span > 4.0 and rng.randf() < 0.35:
			var at := a + dir * span * rng.randf_range(0.3, 0.7)
			if rng.randf() < 0.6:
				_valve(kit, at, dir, -md, col)
			else:
				_gauge(kit, at, -md)
	# Elbows: a short bezier from tangent point to tangent point, a collar at each end.
	for i in range(1, n - 1):
		if trim[i] <= 0.0:
			if i > 0:
				kit.tube(points[i] - dirs[i] * radius * 0.6, points[i] + dirs[i] * radius * 0.6, radius * 1.2, col.darkened(0.1), sides, Transform3D.IDENTITY, false)
			continue
		var p0 := points[i] - dirs[i - 1] * trim[i]
		var p2 := points[i] + dirs[i] * trim[i]
		var prev := p0
		for k in range(1, 5):
			var t := k / 4.0
			var q := p0.lerp(points[i], t).lerp(points[i].lerp(p2, t), t)
			kit.tube(prev, q, radius, col, sides, Transform3D.IDENTITY, true)
			prev = q
		var dark := col.darkened(0.1)
		kit.tube(p0 - dirs[i - 1] * radius * 0.35, p0 + dirs[i - 1] * radius * 0.35, radius * 1.2, dark, sides, Transform3D.IDENTITY, true)
		kit.tube(p2 - dirs[i] * radius * 0.35, p2 + dirs[i] * radius * 0.35, radius * 1.2, dark, sides, Transform3D.IDENTITY, true)
	_cap(kit, end_a, points[0], -dirs[0], end_a_normal, col, sides)
	_cap(kit, end_b, points[n - 1], dirs[n - 2], end_b_normal, col, sides)
	return kit.commit()


## The fitting at an end: `p` is the end point, `out` the pipe's direction leaving through it.
func _cap(kit: PropKit, kind: End, p: Vector3, out: Vector3, nrm: Vector3, col: Color, sides: int) -> void:
	match kind:
		End.WALL:
			var nn := nrm.normalized() if nrm.length_squared() > 1e-6 else -out
			# Sleeve collar just outside the surface, then the plate on it.
			kit.tube(p + nn * 0.02, p + nn * 0.2, radius * 1.25, col.darkened(0.2), sides, Transform3D.IDENTITY, true)
			var b := _basis_facing(nn)
			if nn.y > 0.7:
				kit.tube(p, p + nn * 0.06, radius * 1.9 + 0.08, BRACKET, 8, Transform3D.IDENTITY, true)
			else:
				var w := radius * 2.6 + 0.2
				kit.obox(p + nn * 0.03, Vector3(w, w, 0.06), BRACKET, b, Transform3D.IDENTITY, false)
				for k in 4:
					var c := (b.x * (1 if k % 2 == 0 else -1) + b.y * (1 if k < 2 else -1)) * (w * 0.5 - 0.06)
					kit.obox(p + nn * 0.07 + c, Vector3(0.05, 0.05, 0.03), col.darkened(0.4), b, Transform3D.IDENTITY, false)
		End.TEE:
			var hd := nrm.normalized() if nrm.length_squared() > 1e-6 else Vector3.RIGHT
			var hr := maxf(tee_radius, radius)
			kit.tube(p - hd * hr * 1.3, p + hd * hr * 1.3, hr * 1.18, col.darkened(0.2), 8, Transform3D.IDENTITY, true)
			kit.tube(p - out * (hr * 1.1), p - out * (hr * 1.1 + radius * 0.6), radius * 1.25, col.darkened(0.2), sides, Transform3D.IDENTITY, true)


## A basis whose +Z is `n` (a plate lying on the surface with that normal).
static func _basis_facing(n: Vector3) -> Basis:
	var z := n.normalized()
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	return Basis(x, z.cross(x), z)


func _bracket(kit: PropKit, p: Vector3, md: Vector3) -> void:
	var to := p + md * mount_gap
	kit.tube(p + md * radius, to, 0.03, BRACKET, 4, Transform3D.IDENTITY, false)
	var side := md.cross(Vector3.UP if absf(md.y) < 0.9 else Vector3.RIGHT).normalized()
	kit.tube(p - side * (radius + 0.04) + md * radius * 0.2, p + side * (radius + 0.04) + md * radius * 0.2, 0.025, BRACKET, 4, Transform3D.IDENTITY, false)
	kit.obox(to, Vector3(0.18, 0.18, 0.18), BRACKET, Basis.IDENTITY, Transform3D.IDENTITY, false)


func _valve(kit: PropKit, at: Vector3, dir: Vector3, out: Vector3, col: Color) -> void:
	kit.tube(at - dir * radius * 0.8, at + dir * radius * 0.8, radius * 1.3, col.darkened(0.2), 6, Transform3D.IDENTITY, false)
	var stem := at + out * (radius + 0.25)
	kit.tube(at + out * radius, stem, 0.03, Color(0.2, 0.2, 0.2), 4, Transform3D.IDENTITY, false)
	var u := dir
	var v := out.cross(dir).normalized()
	var r := 0.2
	for k in 8:
		var a0 := TAU * k / 8.0
		var a1 := TAU * (k + 1) / 8.0
		kit.tube(stem + (u * cos(a0) + v * sin(a0)) * r, stem + (u * cos(a1) + v * sin(a1)) * r, 0.025, Color(0.34, 0.16, 0.14), 4, Transform3D.IDENTITY, false)
	kit.tube(stem - u * r, stem + u * r, 0.02, Color(0.34, 0.16, 0.14), 4, Transform3D.IDENTITY, false)


func _gauge(kit: PropKit, at: Vector3, out: Vector3) -> void:
	var g := at + out * (radius + 0.15)
	kit.tube(at + out * radius, g, 0.03, Color(0.3, 0.3, 0.3), 4, Transform3D.IDENTITY, false)
	kit.tube(g, g + out * 0.06, 0.12, Color(0.25, 0.25, 0.25), 8, Transform3D.IDENTITY, true)
	kit.tube(g + out * 0.06, g + out * 0.065, 0.1, Color(0.85, 0.85, 0.8), 8, Transform3D.IDENTITY, true)
