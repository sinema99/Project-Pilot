class_name Hub2PieceBuild
extends RefCounted

# Meshes for Hub2Piece (docs/specs/hub2-final-pass.md). PS1 low poly, vertex colour, flat normals,
# weathering in the colours via PropKit. Each builder fills `kit` and returns its collision boxes
# [[centre, size, basis?]]. Rooms / signage / structure builders are in Hub2PieceBuild2.
#
# House style: one operator, KADE FREIGHT (faded oxide red + white stencils, hex-chevron mark);
# 3-4 other lines in muted navy / olive / grey-white / faded mustard. Saturated colour is safety only.

const K := Hub2Piece.Kind

const OPERATOR := Color(0.50, 0.21, 0.14)
const NAVY := Color(0.19, 0.23, 0.31)
const OLIVE := Color(0.33, 0.35, 0.23)
const GREYWHITE := Color(0.66, 0.66, 0.62)
const MUSTARD := Color(0.60, 0.48, 0.22)
const LIVERIES := [OPERATOR, NAVY, OLIVE, GREYWHITE, MUSTARD, OPERATOR]
const LINE_CODES := ["KDFU", "NRDU", "OBRU", "TSLU", "MKAU", "KDFU"]
const STENCIL := Color(0.80, 0.78, 0.72)
const STEEL := Color(0.42, 0.44, 0.46)
const STEEL_DARK := Color(0.20, 0.21, 0.23)
const BLACK := Color(0.07, 0.07, 0.08)
const SOOT := Color(0.07, 0.06, 0.05)
const CHAR := Color(0.16, 0.12, 0.09)
const INTERIOR := Color(0.24, 0.22, 0.19)
const PLY := Color(0.36, 0.28, 0.18)
const LOADER_ORANGE := Color(0.78, 0.40, 0.13)
const SAFETY_YELLOW := Color(0.84, 0.65, 0.13)
const CONCRETE := Color(0.50, 0.50, 0.48)
const CONCRETE_DARK := Color(0.36, 0.36, 0.35)
const REBAR_COL := Color(0.33, 0.20, 0.12)
const SAND := Color(0.47, 0.41, 0.29)
const GLASS := Color(0.08, 0.10, 0.11)

# 3x5 pixel font for stencils ('#' = paint), rows top to bottom.
const FONT := {
	"A": ["###", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
	"C": ["###", "#..", "#..", "#..", "###"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
	"E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
	"G": ["###", "#..", "#.#", "#.#", "###"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
	"I": ["###", ".#.", ".#.", ".#.", "###"], "J": ["..#", "..#", "..#", "#.#", "###"],
	"K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
	"M": ["#.#", "###", "###", "#.#", "#.#"], "N": ["##.", "#.#", "#.#", "#.#", "#.#"],
	"O": ["###", "#.#", "#.#", "#.#", "###"], "P": ["###", "#.#", "###", "#..", "#.."],
	"Q": ["###", "#.#", "#.#", "###", "..#"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
	"S": ["###", "#..", "###", "..#", "###"], "T": ["###", ".#.", ".#.", ".#.", ".#."],
	"U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
	"W": ["#.#", "#.#", "###", "###", "#.#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
	"Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
	"0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
	"2": ["###", "..#", "###", "#..", "###"], "3": ["###", "..#", ".##", "..#", "###"],
	"4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "###", "..#", "###"],
	"6": ["###", "#..", "###", "#.#", "###"], "7": ["###", "..#", "..#", ".#.", ".#."],
	"8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "###"],
	"-": ["...", "...", "###", "...", "..."], ".": ["...", "...", "...", "...", ".#."],
	"/": ["..#", "..#", ".#.", "#..", "#.."], "!": [".#.", ".#.", ".#.", "...", ".#."],
	">": ["#..", ".#.", "..#", ".#.", "#.."], "<": ["..#", ".#.", "#..", ".#.", "..#"],
	" ": ["...", "...", "...", "...", "..."],
}


static func build(k: int, v: int, st: int, s: int, w: float, sz: Vector3, t: String, p: bool) -> Dictionary:
	var kit := PropKit.new(w, s * 7919 + k * 31 + v * 7 + st)
	var rng := RandomNumberGenerator.new()
	rng.seed = s * 104729 + k * 613 + v * 17 + st
	var boxes: Array = []
	var deform := Callable()
	match k:
		K.BOX20, K.BOX40, K.REEFER:
			var r := _freight(kit, k, v, st, rng)
			boxes = r[0]
			deform = r[1]
		K.POD: boxes = _pod(kit, v, st, rng)
		K.LOADER: boxes = _loader(kit, v, st, rng)
		K.EXOFRAME: boxes = _exoframe(kit, v, rng)
		K.DRONE_RACK: boxes = _drone_rack(kit, v, rng)
		K.DRONE: boxes = _drone(kit, Transform3D(Basis(Vector3.FORWARD, 0.25 * (v % 3)), Vector3(0, 0.12, 0)))
		K.RAIL: boxes = _rail(kit, sz)
		K.CARRIER: boxes = _carrier(kit, v, rng)
		K.SLAB: boxes = _slab(kit, sz, rng)
		K.CEIL_PANEL: boxes = _ceil_panel(kit, sz, rng)
		K.CABLE_TRAY: boxes = _cable_tray(kit, sz, rng)
		K.DEBRIS: boxes = _debris(kit, sz, rng)
		K.SANDBAGS: boxes = _sandbags(kit, sz, rng)
		K.JERSEY: boxes = _jersey(kit, v)
		K.SHEET: boxes = _sheet(kit, sz, v)
		K.GIRDER_FALLEN: boxes = _girder_fallen(kit, sz, rng)
		K.REBAR: boxes = _rebar(kit, rng)
		_: boxes = Hub2PieceBuild2.build(kit, k, v, st, rng, sz, t, p)
	var mesh := kit.commit()
	if deform.is_valid():
		mesh = _deformed(mesh, deform)
	return {"mesh": mesh, "boxes": boxes}


## A copy of `mesh` with every vertex moved by `fn(Vector3) -> Vector3` (crushed containers).
static func _deformed(mesh: ArrayMesh, fn: Callable) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for j in verts.size():
			verts[j] = fn.call(verts[j])
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(i, mesh.surface_get_material(i))
	return out


static func glow(c: Color) -> StandardMaterial3D:
	return Hub2PropBuild.glow(c)


## Paints `t` in the pixel font onto a plane. `origin` = bottom-left of the text, `right`/`up` = the
## plane's axes (unit), `px` = one font pixel in metres. Unweathered so the paint stays crisp.
static func paint_text(kit: PropKit, t: String, origin: Vector3, right: Vector3, up: Vector3, px: float,
		col: Color, xf := Transform3D.IDENTITY) -> void:
	var n := right.cross(up).normalized()
	var o := origin + n * 0.006
	var cx := 0.0
	for ch in t.to_upper():
		var g: Array = FONT.get(ch, FONT[" "])
		for row in 5:
			var line: String = g[row]
			for col_i in 3:
				if line[col_i] == "#":
					var a := o + right * (cx + col_i * px) + up * ((4 - row) * px)
					kit.quad(a, a + right * px, a + right * px + up * px, a + up * px, col, xf, false)
		cx += 4.0 * px


static func text_width(t: String, px: float) -> float:
	return maxf(t.length() * 4.0 * px - px, 0.0)


## The KADE hex-chevron mark, `s` metres across, on a plane.
static func paint_logo(kit: PropKit, centre: Vector3, right: Vector3, up: Vector3, s: float, col: Color,
		xf := Transform3D.IDENTITY) -> void:
	var n := right.cross(up).normalized()
	var c := centre + n * 0.006
	var r := s * 0.5
	var pts: Array[Vector3] = []
	for i in 6:
		var a := TAU * i / 6.0 + PI / 6.0
		pts.append(c + right * cos(a) * r + up * sin(a) * r)
	var inner: Array[Vector3] = []
	for i in 6:
		inner.append(c + (pts[i] - c) * 0.72)
	for i in 6:
		var j := (i + 1) % 6
		kit.quad(inner[i], pts[i], pts[j], inner[j], col, xf, false)
	# chevron inside
	var cw := r * 0.45
	kit.quad(c + right * -cw + up * (cw * 0.2), c + up * (-cw * 0.45), c + up * (-cw * 0.15), c + right * -cw + up * (cw * 0.5), col, xf, false)
	kit.quad(c + up * (-cw * 0.45), c + right * cw + up * (cw * 0.2), c + right * cw + up * (cw * 0.5), c + up * (-cw * 0.15), col, xf, false)


# -- freight ----------------------------------------------------------------------------------

const BOX_W := 2.438
const BOX_H := 2.591

## A 20 / 40 ft container or a reefer. Length along X, doors at +X. state: 0 closed, 1 open (walk-in),
## 2 pried, 3 crushed, 4 burnt. variant picks the livery (0 and 5 = KADE operator).
static func _freight(kit: PropKit, k: int, v: int, st: int, rng: RandomNumberGenerator) -> Array:
	var length := 6.058 if k == K.BOX20 else 12.192
	var lx := length * 0.5
	var hz := BOX_W * 0.5
	var reefer := k == K.REEFER
	var burnt := st == 4
	var base: Color = LIVERIES[v % LIVERIES.size()]
	if reefer:
		base = Color(0.70, 0.71, 0.69)
	if burnt:
		base = CHAR
		kit.wear = 1.0
	kit.cell = 1.1
	kit.grime_height = 1.6
	var frame := base.darkened(0.35) if not burnt else SOOT
	var open := st == 1 or st == 2
	var t := 0.05   # shell thickness for walk-in boxes
	var rib := 0.3
	# Corrugated long sides: alternating strips (colour step), one quad each.
	for side in [-1.0, 1.0]:
		var z: float = hz * side
		var n := int(length / rib)
		for i in n:
			var x0 := -lx + i * rib
			var x1 := x0 + rib
			var c := base if i % 2 == 0 else base.darkened(0.12)
			var zz: float = z + (0.03 * side if i % 2 == 1 else 0.0)
			if side > 0.0:
				kit.quad(Vector3(x0, 0.15, zz), Vector3(x1, 0.15, zz), Vector3(x1, BOX_H - 0.12, zz), Vector3(x0, BOX_H - 0.12, zz), c)
			else:
				kit.quad(Vector3(x1, 0.15, zz), Vector3(x0, 0.15, zz), Vector3(x0, BOX_H - 0.12, zz), Vector3(x1, BOX_H - 0.12, zz), c)
		if open:
			# inner face, dark
			var zi: float = z - t * side
			if side > 0.0:
				kit.quad(Vector3(lx, 0.15, zi), Vector3(-lx, 0.15, zi), Vector3(-lx, BOX_H - 0.12, zi), Vector3(lx, BOX_H - 0.12, zi), INTERIOR, Transform3D.IDENTITY, false)
			else:
				kit.quad(Vector3(-lx, 0.15, zi), Vector3(lx, 0.15, zi), Vector3(lx, BOX_H - 0.12, zi), Vector3(-lx, BOX_H - 0.12, zi), INTERIOR, Transform3D.IDENTITY, false)
	# Roof (and its underside when open), floor, back end.
	kit.box(Vector3(-lx, BOX_H - 0.12, -hz), Vector3(lx, BOX_H - 0.06, hz), base.darkened(0.06))
	kit.box(Vector3(-lx, 0.0, -hz), Vector3(lx, 0.15, hz), frame)
	if open:
		kit.box(Vector3(-lx + 0.1, 0.15, -hz + t), Vector3(lx - 0.05, 0.18, hz - t), PLY)
	kit.box(Vector3(-lx, 0.15, -hz), Vector3(-lx + 0.06, BOX_H - 0.12, hz), base.darkened(0.08))
	if reefer:
		# Refrigeration unit flush in the back end: grille, fan, control box.
		kit.box(Vector3(-lx - 0.02, 0.3, -hz + 0.15), Vector3(-lx + 0.02, 2.3, hz - 0.15), Color(0.55, 0.56, 0.55))
		for i in 8:
			var y := 0.5 + i * 0.22
			kit.box(Vector3(-lx - 0.05, y, -hz + 0.25), Vector3(-lx - 0.01, y + 0.08, hz - 0.9), STEEL_DARK)
		kit.tube(Vector3(-lx - 0.05, 1.5, hz - 0.55), Vector3(-lx - 0.12, 1.5, hz - 0.55), 0.3, BLACK, 8)
		kit.box(Vector3(-lx - 0.12, 0.4, hz - 0.85), Vector3(-lx - 0.02, 0.9, hz - 0.25), Color(0.25, 0.27, 0.27))
	# Frame: corner posts, top/bottom rails, castings.
	for cx in [-lx, lx - 0.15]:
		for cz in [-hz, hz - 0.15]:
			kit.box(Vector3(cx, 0, cz), Vector3(cx + 0.15, BOX_H, cz + 0.15), frame)
			kit.box(Vector3(cx - 0.005, BOX_H - 0.12, cz - 0.005), Vector3(cx + 0.155, BOX_H, cz + 0.155), BLACK)
			kit.box(Vector3(cx - 0.005, 0.0, cz - 0.005), Vector3(cx + 0.155, 0.12, cz + 0.155), BLACK)
	for cz in [-hz, hz - 0.1]:
		kit.box(Vector3(-lx, BOX_H - 0.16, cz), Vector3(lx, BOX_H - 0.04, cz + 0.1), frame)
	# Door end at +X.
	var leaf_w := hz
	var leaves := [[-1.0, 0.0], [1.0, 0.0]]   # [side, swing angle]
	if st == 1:
		leaves = [[-1.0, deg_to_rad(rng.randf_range(95.0, 120.0))], [1.0, deg_to_rad(rng.randf_range(160.0, 265.0))]]
	elif st == 2:
		leaves = [[-1.0, deg_to_rad(rng.randf_range(35.0, 70.0))], [1.0, -1.0]]
	var door_col := base.darkened(0.05)
	for lf: Array in leaves:
		var side: float = lf[0]
		var ang: float = lf[1]
		var hinge := Vector3(lx, 0.1, hz * side)
		var xf: Transform3D
		if ang < -0.5:
			# pried off its top hinge: hangs from the bottom one, leaning out
			xf = Transform3D(Basis(Vector3.FORWARD, -0.45) * Basis(Vector3.UP, 0.15), hinge + Vector3(0.25, -0.05, 0))
		else:
			xf = Transform3D(Basis(Vector3.UP, ang * side), hinge)
		# leaf in its own frame: from the hinge toward the centre (-side in z), thin in x
		var lo := Vector3(0.0, 0.0, -leaf_w if side > 0.0 else 0.0)
		var hi := Vector3(0.05, BOX_H - 0.2, 0.0 if side > 0.0 else leaf_w)
		kit.box(lo, hi, door_col, xf)
		# lock rods + handles
		for rz in [0.3, 0.75]:
			var z: float = -rz * side
			kit.box(Vector3(0.05, 0.1, z - 0.025), Vector3(0.09, BOX_H - 0.3, z + 0.025), STEEL_DARK, xf)
			kit.box(Vector3(0.05, 1.05, z - 0.02), Vector3(0.14, 1.12, z + 0.2 * -side), STEEL_DARK, xf)
	if not open:
		kit.box(Vector3(lx - 0.02, 0.15, -hz + 0.1), Vector3(lx, BOX_H - 0.15, hz - 0.1), BLACK)   # seam behind the leaves
	else:
		# dark inside of the roof
		kit.quad(Vector3(-lx, BOX_H - 0.125, hz - t), Vector3(lx, BOX_H - 0.125, hz - t), Vector3(lx, BOX_H - 0.125, -hz + t), Vector3(-lx, BOX_H - 0.125, -hz + t), INTERIOR.darkened(0.3), Transform3D.IDENTITY, false)
	# Paint: owner code + number by the doors, and the operator mark / line name on the sides.
	if not burnt:
		var code: String = LINE_CODES[v % LINE_CODES.size()] + " " + str(rng.randi_range(100000, 999999))
		paint_text(kit, code, Vector3(lx - 0.25 - text_width(code, 0.035), BOX_H - 0.5, hz + 0.035), Vector3.RIGHT, Vector3.UP, 0.035, STENCIL)
		if v % LIVERIES.size() == 0 or v % LIVERIES.size() == 5:
			for side in [-1.0, 1.0]:
				# face-local u runs along `right` as seen from outside that face
				var right := Vector3.RIGHT if side > 0.0 else Vector3.LEFT
				var face := Vector3(0, 0, hz * side + 0.035 * side)
				paint_logo(kit, face + right * -1.5 + Vector3(0, 1.35, 0), right, Vector3.UP, 0.95, STENCIL)
				paint_text(kit, "KADE", face + right * -0.8 + Vector3(0, 0.95, 0), right, Vector3.UP, 0.16, STENCIL)
				paint_text(kit, "FREIGHT", face + right * -0.8 + Vector3(0, 0.6, 0), right, Vector3.UP, 0.05, STENCIL)
		elif not reefer:
			var names := ["", "NORDA", "OBRA", "TESSAL", "MAKAU"]
			var nm: String = names[v % 5]
			var tw2 := text_width(nm, 0.12)
			paint_text(kit, nm, Vector3(-tw2 * 0.5, 1.4, hz + 0.035), Vector3.RIGHT, Vector3.UP, 0.12, STENCIL.darkened(0.15))
	# Collision.
	var boxes: Array = []
	if open:
		boxes.append([Vector3(0, 0.09, 0), Vector3(length, 0.18, BOX_W)])
		boxes.append([Vector3(0, BOX_H - 0.09, 0), Vector3(length, 0.18, BOX_W)])
		boxes.append([Vector3(0, BOX_H * 0.5, -hz + 0.05), Vector3(length, BOX_H, 0.1)])
		boxes.append([Vector3(0, BOX_H * 0.5, hz - 0.05), Vector3(length, BOX_H, 0.1)])
		boxes.append([Vector3(-lx + 0.05, BOX_H * 0.5, 0), Vector3(0.1, BOX_H, BOX_W)])
	else:
		boxes.append([Vector3(0, BOX_H * 0.5, 0), Vector3(length, BOX_H, BOX_W)])
	var fn := Callable()
	if st == 3:
		var dent := rng.randf_range(0.35, 0.6)
		var corner := rng.randf_range(0.4, 0.8)
		fn = func(p: Vector3) -> Vector3:
			var h := clampf(p.y / BOX_H, 0.0, 1.0)
			var mid := sin(PI * clampf((p.x + lx) / length, 0.0, 1.0))
			var c := clampf((p.x - lx * 0.4) / (lx * 0.6), 0.0, 1.0) * clampf((p.z + hz) / BOX_W, 0.0, 1.0)
			var dz := 0.12 * sin(PI * h) * mid * signf(p.z)
			return Vector3(p.x, p.y - h * (dent * mid + corner * c * c), p.z + dz)
		boxes = [[Vector3(0, (BOX_H - 0.5) * 0.5, 0), Vector3(length, BOX_H - 0.5, BOX_W)]]
	return [boxes, fn]


## Sealed hard-shell cargo pod: octagonal shell along X, chamfered ends, clamp rings, skids.
## variant 1 = split open (lid hinged up, contents spilled).
static func _pod(kit: PropKit, v: int, _st: int, rng: RandomNumberGenerator) -> Array:
	var shell := GREYWHITE if v % 2 == 0 else OPERATOR
	var band := OPERATOR if v % 2 == 0 else STENCIL
	var r := 1.15
	var half := 2.6
	var cy := r + 0.35
	var split := v >= 2
	kit.cell = 0.9
	var sides := 8
	var lid_xf := Transform3D.IDENTITY
	if split:
		lid_xf = Transform3D(Basis(Vector3.RIGHT, -1.1), Vector3(0, cy, -r * 0.92)) * Transform3D(Basis.IDENTITY, Vector3(0, -cy, r * 0.92))
	for i in sides:
		var a0 := TAU * (i + 0.5) / sides
		var a1 := TAU * (i + 1.5) / sides
		var p0 := Vector3(0, cy + sin(a0) * r, cos(a0) * r)
		var p1 := Vector3(0, cy + sin(a1) * r, cos(a1) * r)
		var top := sin((a0 + a1) * 0.5) > 0.2
		var xf := lid_xf if (split and top) else Transform3D.IDENTITY
		var c := shell if i % 2 == 0 else shell.darkened(0.06)
		kit.quad(p0 + Vector3(-half, 0, 0), p0 + Vector3(half, 0, 0), p1 + Vector3(half, 0, 0), p1 + Vector3(-half, 0, 0), c, xf)
		# chamfered end caps
		for e in [-1.0, 1.0]:
			var ex: float = half * e
			var q0 := Vector3(ex + 0.45 * e, cy + sin(a0) * r * 0.62, cos(a0) * r * 0.62)
			var q1 := Vector3(ex + 0.45 * e, cy + sin(a1) * r * 0.62, cos(a1) * r * 0.62)
			if e > 0.0:
				kit.quad(p0 + Vector3(ex, -cy, 0) + Vector3(0, cy, 0), q0, q1, p1 + Vector3(ex, 0, 0), shell.darkened(0.1), xf)
				kit.tri(Vector3(ex + 0.45, cy, 0), q1, q0, shell.darkened(0.15), xf)
			else:
				kit.quad(q0, p0 + Vector3(ex, 0, 0), p1 + Vector3(ex, 0, 0), q1, shell.darkened(0.1), xf)
				kit.tri(Vector3(ex - 0.45, cy, 0), q0, q1, shell.darkened(0.15), xf)
		# clamp rings
		for cx in [-1.5, 1.5]:
			kit.quad(p0 * 1.04 + Vector3(cx - 0.12, -cy * 0.04, 0), p0 * 1.04 + Vector3(cx + 0.12, -cy * 0.04, 0),
				p1 * 1.04 + Vector3(cx + 0.12, -cy * 0.04, 0), p1 * 1.04 + Vector3(cx - 0.12, -cy * 0.04, 0), STEEL_DARK, xf)
	kit.box(Vector3(-half + 0.3, cy - 0.15, r * 0.93), Vector3(half - 0.3, cy + 0.15, r * 0.97), band)
	paint_text(kit, "KD-%03d" % rng.randi_range(1, 999), Vector3(-0.9, cy + 0.35, r * 0.95), Vector3.RIGHT, Vector3.UP, 0.08, STEEL_DARK)
	# skids
	for z in [-0.7, 0.7]:
		kit.box(Vector3(-half, 0.0, z - 0.12), Vector3(half, 0.4, z + 0.12), STEEL_DARK)
	var boxes: Array = [[Vector3(0, cy * 0.75, 0), Vector3(half * 2.0 + 0.6, cy * 1.5, r * 1.9)]]
	if split:
		# dark inside + spilled cases
		kit.box(Vector3(-half, cy - 0.2, -r * 0.8), Vector3(half, cy - 0.15, r * 0.8), INTERIOR)
		for i in 5:
			var p := Vector3(rng.randf_range(-2.0, 2.0), 0, r + 0.6 + rng.randf_range(0.0, 1.8))
			var s := Vector3(rng.randf_range(0.4, 0.7), rng.randf_range(0.25, 0.45), rng.randf_range(0.35, 0.6))
			kit.obox(p + Vector3(0, s.y * 0.5, 0), s, [OLIVE, GREYWHITE, STEEL_DARK][i % 3], Basis(Vector3.UP, rng.randf() * 3.0))
		boxes = [[Vector3(0, cy * 0.5, 0), Vector3(half * 2.0 + 0.6, cy, r * 1.9)]]
	return boxes


static func _track(kit: PropKit, x0: float, x1: float, z: float, w: float, h: float) -> void:
	kit.box(Vector3(x0 + 0.2, 0.0, z - w * 0.5), Vector3(x1 - 0.2, h, z + w * 0.5), BLACK)
	kit.tube(Vector3(x0 + 0.2, h * 0.5, z - w * 0.5), Vector3(x0 + 0.2, h * 0.5, z + w * 0.5), h * 0.5, BLACK, 6)
	kit.tube(Vector3(x1 - 0.2, h * 0.5, z - w * 0.5), Vector3(x1 - 0.2, h * 0.5, z + w * 0.5), h * 0.5, BLACK, 6)
	for i in 3:
		var x := lerpf(x0 + 0.6, x1 - 0.6, i / 2.0)
		kit.tube(Vector3(x, h * 0.4, z - w * 0.5 - 0.02), Vector3(x, h * 0.4, z + w * 0.5 + 0.02), h * 0.22, STEEL_DARK, 6)


## Tracked cargo loader (the 2329 forklift): squat body on two tracks, cab cage, mast + forks at +X.
## variant 0 forks down, 1 forks raised with a pallet, 2 burnt, 3 tipped on its side.
static func _loader(kit: PropKit, v: int, _st: int, rng: RandomNumberGenerator) -> Array:
	var body := LOADER_ORANGE if v != 2 else CHAR
	if v == 2:
		kit.wear = 1.0
	var root := Transform3D.IDENTITY
	if v == 3:
		root = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.1, 0))
	_track(kit, -1.9, 1.3, -0.85, 0.45, 0.6)
	_track(kit, -1.9, 1.3, 0.85, 0.45, 0.6)
	kit.box(Vector3(-1.8, 0.55, -0.62), Vector3(1.1, 1.25, 0.62), body, root)
	kit.box(Vector3(-2.15, 0.55, -0.75), Vector3(-1.6, 1.55, 0.75), STEEL_DARK, root)   # counterweight + battery
	paint_text(kit, "L-%02d" % rng.randi_range(1, 24), Vector3(-1.3, 0.85, 0.625), Vector3.RIGHT, Vector3.UP, 0.07, BLACK, root)
	# hazard chevrons on the counterweight
	for i in 4:
		var z := -0.6 + i * 0.32
		kit.quad(Vector3(-2.151, 0.65, z), Vector3(-2.151, 0.65, z + 0.16), Vector3(-2.151, 1.45, z + 0.32), Vector3(-2.151, 1.45, z + 0.16),
			SAFETY_YELLOW if v != 2 else SOOT, root, false)
	# cab cage
	var cage := STEEL_DARK
	for px in [-1.4, 0.3]:
		for pz in [-0.55, 0.55]:
			kit.box(Vector3(px - 0.05, 1.25, pz - 0.05), Vector3(px + 0.05, 2.75, pz + 0.05), cage, root)
	kit.box(Vector3(-1.45, 2.7, -0.6), Vector3(0.35, 2.8, 0.6), cage, root)
	for i in 4:
		var x := -1.35 + i * 0.5
		kit.box(Vector3(x - 0.02, 2.68, -0.58), Vector3(x + 0.02, 2.72, 0.58), cage, root)
	kit.box(Vector3(-1.0, 1.25, -0.4), Vector3(-0.4, 1.75, 0.4), BLACK, root)     # seat
	kit.box(Vector3(-0.9, 1.75, -0.4), Vector3(-0.8, 2.3, 0.4), BLACK, root)
	kit.box(Vector3(0.0, 1.25, -0.3), Vector3(0.3, 1.9, 0.3), STEEL_DARK, root)   # console
	# mast + forks
	var fy := 0.1 if v != 1 else 2.2
	for pz in [-0.45, 0.45]:
		kit.box(Vector3(1.15, 0.2, pz - 0.07), Vector3(1.3, 3.3, pz + 0.07), STEEL_DARK, root)
	kit.box(Vector3(1.3, fy, -0.6), Vector3(1.38, fy + 0.7, 0.6), STEEL_DARK, root)
	for pz in [-0.35, 0.35]:
		kit.box(Vector3(1.38, fy, pz - 0.07), Vector3(2.6, fy + 0.06, pz + 0.07), STEEL, root)
	if v == 1:
		Hub2PropBuild.pallet_base(kit, fy + 0.06)
		kit.box(Vector3(1.45, fy + 0.2, -0.55), Vector3(2.55, fy + 1.1, 0.55), Color(0.62, 0.48, 0.30), root)
	# beacon (dead)
	kit.tube(Vector3(-1.3, 2.8, 0.45), Vector3(-1.3, 2.95, 0.45), 0.08, Color(0.45, 0.25, 0.08), 6, root)
	if v == 3:
		return [[Vector3(-0.4, 0.6, 0), Vector3(4.5, 1.2, 2.8)]]
	return [[Vector3(-0.5, 0.75, 0), Vector3(3.3, 1.5, 2.1)], [Vector3(1.9, fy + 0.1, 0), Vector3(1.3, 0.2, 1.0)]]


## Powered loader exoframe slumped in its charging cradle (variant 0) or face down beside it (1).
static func _exoframe(kit: PropKit, v: int, _rng: RandomNumberGenerator) -> Array:
	var shell := Color(0.62, 0.60, 0.52)
	var dark := STEEL_DARK
	# cradle: back frame + charging arm
	kit.box(Vector3(-1.1, 0, -0.9), Vector3(1.1, 0.12, 0.6), dark)
	for x in [-1.0, 1.0]:
		kit.box(Vector3(x - 0.08, 0.12, -0.85), Vector3(x + 0.08, 3.3, -0.7), dark)
	kit.box(Vector3(-1.08, 3.2, -0.9), Vector3(1.08, 3.4, -0.65), dark)
	kit.box(Vector3(-0.3, 2.6, -0.7), Vector3(0.3, 3.2, -0.4), Color(0.3, 0.32, 0.3))
	kit.tube(Vector3(0, 2.9, -0.4), Vector3(0, 2.4, 0.0), 0.05, BLACK, 4)
	paint_text(kit, "CHG 3", Vector3(-0.35, 3.24, -0.649), Vector3.RIGHT, Vector3.UP, 0.04, SAFETY_YELLOW)
	var xf := Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 0.0, -0.1))
	if v == 1:
		xf = Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.6, 0.55, 1.6))
	# legs (bent), hips, torso, shoulders, arms hanging, head cage
	for sx in [-0.42, 0.42]:
		kit.box(Vector3(sx - 0.2, 0.0, -0.15), Vector3(sx + 0.2, 0.15, 0.4), dark, xf)              # foot
		kit.obox(Vector3(sx, 0.55, 0.05), Vector3(0.32, 0.85, 0.36), shell, Basis(Vector3.RIGHT, 0.35), xf)   # shin
		kit.obox(Vector3(sx, 1.2, -0.05), Vector3(0.36, 0.7, 0.4), shell.darkened(0.08), Basis(Vector3.RIGHT, -0.3), xf)   # thigh
	kit.box(Vector3(-0.6, 1.45, -0.35), Vector3(0.6, 1.75, 0.25), dark, xf)                         # hips
	kit.box(Vector3(-0.7, 1.75, -0.45), Vector3(0.7, 2.6, 0.35), shell, xf)                         # torso
	kit.box(Vector3(-0.5, 1.9, 0.35), Vector3(0.5, 2.45, 0.42), GLASS, xf)                          # chest window
	kit.box(Vector3(-0.95, 2.35, -0.45), Vector3(0.95, 2.7, 0.3), shell.darkened(0.12), xf)         # shoulders
	for sx in [-0.85, 0.85]:
		kit.box(Vector3(sx - 0.17, 1.3, -0.2), Vector3(sx + 0.17, 2.35, 0.15), shell.darkened(0.04), xf)
		kit.box(Vector3(sx - 0.2, 0.75, -0.15), Vector3(sx + 0.2, 1.3, 0.35), dark, xf)              # claw
	kit.box(Vector3(-0.25, 2.6, -0.2), Vector3(0.25, 2.95, 0.25), dark, xf)
	paint_text(kit, "EX-7", Vector3(-0.3, 2.42, 0.351), Vector3.RIGHT, Vector3.UP, 0.05, BLACK, xf)
	return [[Vector3(0, 1.6, -0.2), Vector3(2.2, 3.2, 1.3)]]


static func _drone(kit: PropKit, xf: Transform3D) -> Array:
	var body := Color(0.30, 0.31, 0.30)
	kit.box(Vector3(-0.22, -0.08, -0.22), Vector3(0.22, 0.08, 0.22), body, xf)
	kit.box(Vector3(-0.1, -0.12, -0.1), Vector3(0.1, -0.08, 0.1), BLACK, xf)
	for a in 4:
		var d := Vector3(cos(PI * 0.25 + a * PI * 0.5), 0, sin(PI * 0.25 + a * PI * 0.5))
		kit.tube(d * 0.2, d * 0.5, 0.03, body.darkened(0.2), 4, xf)
		kit.tube(d * 0.5 + Vector3(0, 0.02, 0), d * 0.5 + Vector3(0, 0.06, 0), 0.17, STEEL_DARK, 6, xf)
	return []


## Wall rack of quad-drone charging slots, 3 rows x 4; some drones missing, one fallen on the floor.
static func _drone_rack(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	kit.box(Vector3(-2.2, 0.0, -0.05), Vector3(2.2, 3.2, 0.0), STEEL_DARK)
	for row in 3:
		var y := 0.5 + row * 0.95
		kit.box(Vector3(-2.2, y, 0.0), Vector3(2.2, y + 0.06, 0.75), Color(0.3, 0.31, 0.32))
		for i in 4:
			var x := -1.65 + i * 1.1
			kit.box(Vector3(x - 0.06, y + 0.06, 0.05), Vector3(x + 0.06, y + 0.12, 0.2), Color(0.12, 0.25, 0.12))   # dead charge pad
			if rng.randf() < (0.55 if v == 0 else 0.3):
				_drone(kit, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(x, y + 0.2, 0.4)))
	paint_text(kit, "DRONE BAY", Vector3(-0.7, 3.0, 0.005), Vector3.RIGHT, Vector3.UP, 0.04, SAFETY_YELLOW)
	_drone(kit, Transform3D(Basis(Vector3.FORWARD, 2.6) * Basis(Vector3.UP, 0.7), Vector3(rng.randf_range(-1.0, 1.0), 0.15, 1.2)))
	return [[Vector3(0, 1.6, 0.35), Vector3(4.4, 3.2, 0.8)]]


## Ceiling mag-rail: a box beam `size.x` long along X hanging `size.y` below its hangers (origin = the
## ceiling point at the rail's middle), rods every 8 m, power rail strip under it.
static func _rail(kit: PropKit, sz: Vector3) -> Array:
	var half := sz.x * 0.5
	var drop := sz.y
	kit.cell = 1.5
	kit.box(Vector3(-half, -drop - 0.7, -0.45), Vector3(half, -drop, 0.45), Color(0.30, 0.31, 0.33))
	kit.box(Vector3(-half, -drop - 0.85, -0.12), Vector3(half, -drop - 0.7, 0.12), Color(0.18, 0.35, 0.40))   # power strip
	var n := int(sz.x / 8.0)
	for i in n + 1:
		var x := -half + i * (sz.x / maxf(n, 1))
		kit.box(Vector3(x - 0.08, -drop, -0.08), Vector3(x + 0.08, 0.0, 0.08), STEEL_DARK)
		kit.box(Vector3(x - 0.3, -0.12, -0.3), Vector3(x + 0.3, 0.0, 0.3), STEEL_DARK)
	return []


## Mag-rail carrier stalled on the rail: bogie on top, clamp frame, a 40 ft box held (variant 0) or
## empty clamps (1). Origin = top of the bogie = the rail's underside; it hangs down -Y, length along X.
static func _carrier(kit: PropKit, v: int, rng: RandomNumberGenerator) -> Array:
	var c := Color(0.55, 0.52, 0.42)
	kit.box(Vector3(-3.0, -0.9, -0.6), Vector3(3.0, 0.0, 0.6), c)
	kit.box(Vector3(-6.4, -1.4, -1.5), Vector3(6.4, -0.9, 1.5), c.darkened(0.15))
	for x in [-6.0, 6.0]:
		for z in [-1.3, 1.3]:
			kit.box(Vector3(x - 0.15, -4.3, z - 0.15), Vector3(x + 0.15, -1.4, z + 0.15), STEEL_DARK)
	kit.box(Vector3(-2.6, -0.85, 0.6), Vector3(-0.4, -0.25, 0.62), Color(0.7, 0.18, 0.1))
	paint_text(kit, "MC-0%d" % (rng.randi_range(1, 9)), Vector3(0.0, -0.75, 0.61), Vector3.RIGHT, Vector3.UP, 0.08, BLACK)
	if v == 0:
		var t := Transform3D(Basis.IDENTITY, Vector3(0, -1.45 - BOX_H, 0))
		kit.box(Vector3(-6.096, 0, -1.219), Vector3(6.096, BOX_H, 1.219), OPERATOR.darkened(0.1), t)
		for side in [-1.0, 1.0]:
			for i in 40:
				if i % 2 == 1:
					var x0 := -6.0 + i * 0.3
					if side > 0.0:
						kit.quad(Vector3(x0, 0.2, 1.222), Vector3(x0 + 0.3, 0.2, 1.222), Vector3(x0 + 0.3, BOX_H - 0.2, 1.222), Vector3(x0, BOX_H - 0.2, 1.222), OPERATOR.darkened(0.22), t)
					else:
						kit.quad(Vector3(x0 + 0.3, 0.2, -1.222), Vector3(x0, 0.2, -1.222), Vector3(x0, BOX_H - 0.2, -1.222), Vector3(x0 + 0.3, BOX_H - 0.2, -1.222), OPERATOR.darkened(0.22), t)
			paint_logo(kit, Vector3(-3.0 * side, 1.4, 1.225 * side), Vector3.RIGHT * side, Vector3.UP, 0.9, STENCIL, t)
	return []


# -- rubble -----------------------------------------------------------------------------------

## Broken concrete slab chunk: a jagged prism (size.x x size.z footprint, size.y thick) with rebar
## stubs out of the broken edges. Origin bottom centre; tilt it in the node transform.
static func _slab(kit: PropKit, sz: Vector3, rng: RandomNumberGenerator) -> Array:
	var n := 7
	var top: Array[Vector3] = []
	var bot: Array[Vector3] = []
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(0.75, 1.0)
		var p := Vector3(cos(a) * sz.x * 0.5 * r, 0, sin(a) * sz.z * 0.5 * r)
		bot.append(p)
		top.append(p * rng.randf_range(0.9, 1.0) + Vector3(0, sz.y * rng.randf_range(0.85, 1.1), 0))
	var ct := Vector3(0, sz.y, 0)
	for i in n:
		var j := (i + 1) % n
		var c := CONCRETE.lerp(CONCRETE_DARK, rng.randf() * 0.5)
		kit.tri_out(top[i], top[j], ct, c.lightened(0.05), Vector3(0, -10, 0))
		kit.tri_out(bot[i], bot[j], Vector3.ZERO, c.darkened(0.2), Vector3(0, 10, 0))
		kit.tri_out(bot[i], bot[j], top[j], c, Vector3(0, sz.y * 0.5, 0))
		kit.tri_out(bot[i], top[j], top[i], c, Vector3(0, sz.y * 0.5, 0))
	for i in rng.randi_range(2, 5):
		var k := rng.randi() % n
		var p := (bot[k] + top[k]) * 0.5
		var out := Vector3(p.x, 0, p.z).normalized()
		var end := p + out * rng.randf_range(0.3, 0.9) + Vector3(0, rng.randf_range(-0.2, 0.4), 0)
		kit.tube(p - out * 0.1, end, 0.02, REBAR_COL, 4)
	return [[Vector3(0, sz.y * 0.5, 0), Vector3(sz.x * 0.8, sz.y, sz.z * 0.8)]]


## Fallen ceiling panel: a bent metal sheet (two planes) with hanger wires and a light trough.
static func _ceil_panel(kit: PropKit, sz: Vector3, rng: RandomNumberGenerator) -> Array:
	var hx := sz.x * 0.5
	var hz := sz.z * 0.5
	var bend := rng.randf_range(0.25, 0.6)
	var col := Color(0.58, 0.58, 0.56)
	var mid := Vector3(rng.randf_range(-0.3, 0.3) * hx, bend, 0)
	kit.box(Vector3(-hx, 0, -hz), Vector3(mid.x, 0.04, hz), col, Transform3D(Basis(Vector3.BACK, atan2(bend, hx + mid.x)), Vector3(-hx, 0, 0)) * Transform3D(Basis.IDENTITY, Vector3(hx, 0, 0)))
	kit.box(Vector3(mid.x, 0, -hz), Vector3(hx, 0.04, hz), col.darkened(0.1), Transform3D(Basis(Vector3.BACK, -atan2(bend, hx - mid.x)), Vector3(hx, 0, 0)) * Transform3D(Basis.IDENTITY, Vector3(-hx, 0, 0)))
	for i in 3:
		var p := Vector3(rng.randf_range(-hx, hx), 0.1, rng.randf_range(-hz, hz))
		kit.tube(p, p + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.4, 1.2), rng.randf_range(-0.5, 0.5)), 0.01, STEEL_DARK, 3, Transform3D.IDENTITY, false)
	return [[Vector3(0, bend * 0.5 + 0.05, 0), Vector3(sz.x, bend + 0.1, sz.z)]]


## Ladder-type cable tray, `size.x` long, bent down at a kink, with a cable bundle spilling out.
static func _cable_tray(kit: PropKit, sz: Vector3, rng: RandomNumberGenerator) -> Array:
	var half := sz.x * 0.5
	var kink := rng.randf_range(-0.2, 0.2) * sz.x
	var drop := rng.randf_range(0.5, 1.1)
	var segs := [[Vector3(-half, drop, 0), Vector3(kink, 0.1, 0)], [Vector3(kink, 0.1, 0), Vector3(half, 0.0, 0)]]
	for sg: Array in segs:
		var a: Vector3 = sg[0]
		var b: Vector3 = sg[1]
		for z in [-0.3, 0.3]:
			kit.tube(a + Vector3(0, 0, z), b + Vector3(0, 0, z), 0.04, STEEL, 4)
		var n := int(a.distance_to(b) / 0.5)
		for i in n:
			var p := a.lerp(b, (i + 0.5) / n)
			kit.box(p + Vector3(-0.02, -0.02, -0.3), p + Vector3(0.02, 0.02, 0.3), STEEL_DARK)
		for c in 4:
			var o := Vector3(0, 0.06, -0.15 + c * 0.1)
			kit.tube(a + o, b + o + Vector3(0, rng.randf_range(-0.05, 0.05), 0), 0.035, [BLACK, Color(0.35, 0.1, 0.08), Color(0.15, 0.2, 0.35)][c % 3], 4)
	return [[Vector3(0, drop * 0.35 + 0.1, 0), Vector3(sz.x, drop * 0.7 + 0.2, 0.7)]]


## Loose debris: chunks, bits of panel and a few rebar ends in a low pile, size.x x size.z. No collision.
static func _debris(kit: PropKit, sz: Vector3, rng: RandomNumberGenerator) -> Array:
	var n := int(clampf(sz.x * sz.z * 3.0, 6.0, 30.0))
	for i in n:
		var p := Vector3(rng.randf_range(-0.5, 0.5) * sz.x, 0, rng.randf_range(-0.5, 0.5) * sz.z)
		var falloff := 1.0 - (absf(p.x) / (sz.x * 0.5) + absf(p.z) / (sz.z * 0.5)) * 0.5
		var s := Vector3(rng.randf_range(0.08, 0.35), rng.randf_range(0.05, 0.25), rng.randf_range(0.08, 0.35)) * (0.5 + falloff)
		var col := CONCRETE.lerp(CONCRETE_DARK, rng.randf())
		if rng.randf() < 0.2:
			col = STEEL.darkened(rng.randf() * 0.4)
		kit.obox(p + Vector3(0, s.y * 0.4, 0), s, col, Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * 0.8))
	for i in 3:
		var p := Vector3(rng.randf_range(-0.4, 0.4) * sz.x, 0.05, rng.randf_range(-0.4, 0.4) * sz.z)
		kit.tube(p, p + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.0, 0.3), rng.randf_range(-0.8, 0.8)), 0.015, REBAR_COL, 4)
	return []


## Sandbag wall `size.x` long, `size.y` high (rows of 0.18 m bags, staggered).
static func _sandbags(kit: PropKit, sz: Vector3, rng: RandomNumberGenerator) -> Array:
	var rows := maxi(int(sz.y / 0.18), 1)
	var bag_l := 0.62
	for r in rows:
		var n := int(sz.x / bag_l) + 1
		var off := (bag_l * 0.5) if r % 2 == 1 else 0.0
		for i in n:
			var x := -sz.x * 0.5 + off + i * bag_l
			if x + bag_l * 0.5 > sz.x * 0.5 + 0.2 or (r == rows - 1 and rng.randf() < 0.15):
				continue
			var c := SAND.lerp(SAND.darkened(0.3), rng.randf()).lerp(Color(0.3, 0.32, 0.22), 0.3 if rng.randf() < 0.3 else 0.0)
			var bc := Vector3(x, r * 0.18 + 0.085, rng.randf_range(-0.03, 0.03))
			var bb := Basis(Vector3.UP, rng.randf_range(-0.08, 0.08))
			kit.obox(bc, Vector3(bag_l - 0.04, 0.15, 0.42), c, bb)
			kit.obox(bc + Vector3(0, 0.06, 0), Vector3(bag_l - 0.14, 0.06, 0.32), c.lightened(0.06), bb)
			kit.obox(bc + Vector3(bag_l * 0.5 - 0.03, 0.0, 0), Vector3(0.06, 0.1, 0.3), c.darkened(0.15), bb)
	return [[Vector3(0, rows * 0.09, 0), Vector3(sz.x, rows * 0.18, 0.5)]]


## Concrete jersey barrier, 2 m. variant 1 = cracked and chipped, 2 = painted hazard stripes.
static func _jersey(kit: PropKit, v: int) -> Array:
	var c := CONCRETE.lightened(0.05)
	for x0 in [-1.0]:
		kit.quad(Vector3(x0, 0, 0.3), Vector3(x0 + 2, 0, 0.3), Vector3(x0 + 2, 0.3, 0.3), Vector3(x0, 0.3, 0.3), c)
		kit.quad(Vector3(x0, 0.3, 0.3), Vector3(x0 + 2, 0.3, 0.3), Vector3(x0 + 2, 0.82, 0.1), Vector3(x0, 0.82, 0.1), c.darkened(0.05))
		kit.quad(Vector3(x0 + 2, 0, -0.3), Vector3(x0, 0, -0.3), Vector3(x0, 0.3, -0.3), Vector3(x0 + 2, 0.3, -0.3), c)
		kit.quad(Vector3(x0 + 2, 0.3, -0.3), Vector3(x0, 0.3, -0.3), Vector3(x0, 0.82, -0.1), Vector3(x0 + 2, 0.82, -0.1), c.darkened(0.05))
		kit.box(Vector3(x0, 0.82, -0.1), Vector3(x0 + 2, 0.86, 0.1), c)
		for e in [x0, x0 + 2.0]:
			var s := 1.0 if e > x0 else -1.0
			var pts := [Vector3(e, 0, -0.3), Vector3(e, 0.3, -0.3), Vector3(e, 0.86, -0.1), Vector3(e, 0.86, 0.1), Vector3(e, 0.3, 0.3), Vector3(e, 0, 0.3)]
			for i in range(1, 5):
				if s > 0:
					kit.tri(pts[0], pts[i], pts[i + 1], c.darkened(0.1))
				else:
					kit.tri(pts[0], pts[i + 1], pts[i], c.darkened(0.1))
	if v == 2:
		for i in 5:
			var x := -0.9 + i * 0.4
			kit.quad(Vector3(x, 0.32, 0.297), Vector3(x + 0.2, 0.32, 0.297), Vector3(x + 0.3, 0.8, 0.107), Vector3(x + 0.1, 0.8, 0.107), SAFETY_YELLOW.darkened(0.2), Transform3D.IDENTITY, false)
	return [[Vector3(0, 0.43, 0), Vector3(2.0, 0.86, 0.6)]]


## Corrugated metal sheet, size.x x size.z, lying flat (tilt it in the transform). variant 1 = rusted.
static func _sheet(kit: PropKit, sz: Vector3, v: int) -> Array:
	var col := Color(0.50, 0.52, 0.52) if v == 0 else Color(0.40, 0.26, 0.16)
	var n := int(sz.z / 0.15)
	for i in n:
		var z0 := -sz.z * 0.5 + i * 0.15
		var y0 := 0.03 if i % 2 == 0 else 0.0
		var y1 := 0.0 if i % 2 == 0 else 0.03
		kit.quad(Vector3(-sz.x * 0.5, y0, z0 + 0.15), Vector3(sz.x * 0.5, y0, z0 + 0.15), Vector3(sz.x * 0.5, y1, z0), Vector3(-sz.x * 0.5, y1, z0), col if i % 2 == 0 else col.darkened(0.1))
		kit.quad(Vector3(-sz.x * 0.5, y1, z0), Vector3(sz.x * 0.5, y1, z0), Vector3(sz.x * 0.5, y0, z0 + 0.15), Vector3(-sz.x * 0.5, y0, z0 + 0.15), col.darkened(0.3))
	return [[Vector3(0, 0.02, 0), Vector3(sz.x, 0.06, sz.z)]]


## A crane bridge girder that fell: yellow box girder `size.x` long, one end torn (jagged plates),
## lying on the floor along X. Collision is the girder body.
static func _girder_fallen(kit: PropKit, sz: Vector3, rng: RandomNumberGenerator) -> Array:
	var half := sz.x * 0.5
	var h := 2.2
	var w := 1.6
	var col := Color(0.70, 0.55, 0.14)
	kit.cell = 1.4
	kit.box(Vector3(-half, 0, -w * 0.5), Vector3(half - 1.0, h, w * 0.5), col)
	# web stiffener stripes
	for i in int(sz.x / 2.5):
		var x := -half + 1.0 + i * 2.5
		kit.box(Vector3(x, 0.05, w * 0.5), Vector3(x + 0.12, h - 0.05, w * 0.5 + 0.04), col.darkened(0.2))
		kit.box(Vector3(x, 0.05, -w * 0.5 - 0.04), Vector3(x + 0.12, h - 0.05, -w * 0.5), col.darkened(0.2))
	# torn end: bent plates
	for i in 4:
		var y := rng.randf_range(0.1, h - 0.3)
		kit.obox(Vector3(half - 0.5, y, rng.randf_range(-0.6, 0.6)), Vector3(1.4, 0.06, rng.randf_range(0.4, 1.2)), col.darkened(0.3),
			Basis(Vector3.BACK, rng.randf_range(-0.6, 0.6)) * Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5)))
	# rail wheel truck at the far end
	kit.box(Vector3(-half - 0.6, 0.5, -1.2), Vector3(-half, 1.8, 1.2), STEEL_DARK)
	paint_text(kit, "SWL 40T", Vector3(-half + 2.0, 0.7, w * 0.5 + 0.045), Vector3.RIGHT, Vector3.UP, 0.12, BLACK)
	return [[Vector3(-0.5, h * 0.5, 0), Vector3(sz.x - 1.0, h, w)]]


## Loose bundle of bent rebar lying on the floor.
static func _rebar(kit: PropKit, rng: RandomNumberGenerator) -> Array:
	for i in 6:
		var a := Vector3(rng.randf_range(-1.5, -0.8), 0.03 + i * 0.01, rng.randf_range(-0.3, 0.3))
		var m := Vector3(rng.randf_range(-0.3, 0.3), 0.04, rng.randf_range(-0.3, 0.3))
		var b := Vector3(rng.randf_range(0.8, 1.6), rng.randf_range(0.03, 0.4), rng.randf_range(-0.5, 0.5))
		kit.tube(a, m, 0.016, REBAR_COL, 4)
		kit.tube(m, b, 0.016, REBAR_COL, 4)
	return []
