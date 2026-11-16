## pilot9's trench coat as geometry: a low-poly, faceted coat modelled in his skeleton's REST pose
## (model space: +X his left, +Y up, +Z his front) and skinned to his bones plus the coat's own
## chain bones. Built once by scripts/items/trench_coat.gd. See docs/specs/pilot9-trench-coat.md.
##
## Every triangle owns its three vertices and carries its face normal, so the coat shades as flat
## planes in every look. Two surfaces: LEATHER (outside) and LINING (inside faces, cuff mouths).
## Only the left half is written down; the right is its mirror.
##
## Fitted to the body by tests/_probe_coat_body.gd: his vest is +-0.21 wide and +-0.20 deep at the
## chest, his shoulder pads reach x 0.25 / y 1.59 / z +-0.155, his hip pouch reaches z -0.233, his
## legs +-0.215, and his helmet starts at y 1.55.
##
## The fitted cut (2026-11-11): from the hips up the coat sits ON those numbers, not outside them,
## because what it covers is cut out of his body while it is on (scripts/items/trench_coat_body.gd).
## Only the front panels still clear his chest (about 2 cm): the chest is still there.
##
## The flat back (2026-11-11): the back from the waist up sits on his VEST line (~-0.16), not on
## the backpack's -0.20 - the pack and hip pouch are cut away with the rest of his back, so making
## room for them was only bulk. Straight, no waist pinch; hips and skirt untouched.
##
## The slim cut (2026-11-11): the rows are fitted to the user's red line, drawn over the back
## probe shot and measured in metres by projecting it through the probe camera. Shoulder row and
## hips come in (the skirt now flares from the waist, not the hip), the collar is a short stand
## ring close round the neck, epaulettes 2/3 size inside the shoulder line, slimmer sleeves.
## Chest, waist, knee and hem already sat on the line. Each row is pinched all the way round.
## Played: "nothing changed" (the line was close to the old coat). Then "way tighter everywhere":
## below the waist the floor is his legs (+-0.215 the whole way down, whole and never cut), so the
## skirt is a near-straight column just outside them (hem 0.335 -> 0.255) and leans on the leg push
## in a stride; above it his trunk is cut away, so the coat sits inside his old outline.
## The low top (2026-11-12, user's red lines on a front shot): everything from the chest row up is
## squashed into a lower band, so his red scarf shows above the collar (clipping accepted). First
## y' = 1.34 + (y - 1.34) * 0.638 (collar top ~1.55); user: halfway back, so the factor is 0.819
## (collar top ~1.61, between the original 1.67 and 1.55).
## Long sleeves (2026-11-12): the cuff's rim reaches his hand (0.315 -> 0.36 down the forearm; the
## hand starts at 0.364), so no wrist shows - only his hands come out of the sleeves.
extends RefCounted

const LEATHER := 0
const LINING := 1
const SURFACES := 2

## Chains per side: front panel, side, back, vent edge. Left 0..3, right 4..7.
const SIDE_CHAINS := 4
const CHAINS := SIDE_CHAINS * 2

## How far the lining sits inside the leather.
const LINING_INSET := 0.006

# Columns down the left half, front to back: F (front edge), FC (front corner), S (side),
# BC (back corner), B (back centre; BV, the vent edge, below the waist). [x, z] per column.
const ROW_TOP_Y := [1.573, 1.563, 1.553, 1.563, 1.573]
const ROW_TOP := [[0.075, 0.13], [0.17, 0.11], [0.195, 0.0], [0.17, -0.12], [0.0, -0.135]]
const ROW_ARM_Y := 1.471
const ROW_ARM := [[0.07, 0.20], [0.19, 0.16], [0.215, 0.0], [0.19, -0.135], [0.0, -0.135]]
const ROW_CHEST_Y := 1.34
const ROW_CHEST := [[0.085, 0.235], [0.185, 0.20], [0.20, 0.0], [0.17, -0.135], [0.0, -0.135]]
const ROW_WAIST_Y := 1.12
const ROW_WAIST := [[0.105, 0.215], [0.17, 0.19], [0.20, 0.0], [0.17, -0.135], [0.0, -0.135]]
const ROW_HIP_Y := 0.95
## Front edge + front pushed out onto the waist-knee line (2026-11-16): was 0.17 / 0.15, a dent.
const ROW_HIP := [[0.12, 0.206], [0.21, 0.183],[0.24, 0.0], [0.215, -0.17], [0.012, -0.18]]
const ROW_KNEE_Y := 0.64
const ROW_KNEE := [[0.15, 0.19], [0.215, 0.17], [0.245, 0.0], [0.215, -0.17], [0.012, -0.19]]
const ROW_HEM_Y := 0.30
const ROW_HEM := [[0.17, 0.20], [0.23, 0.18], [0.255, 0.0], [0.23, -0.18], [0.012, -0.20]]
## Which chain a skirt column hangs from (F and FC share the front panel's).
const COLUMN_CHAIN := [0, 0, 1, 2, 3]
## Row points 0 (front edge) and 1 (front): rigid from the chest down to the hip row.
const FRONT_POINTS := 2
## The belly bones (left; the right is its mirror): children of Hips at the waist row's front
## edge, moved each tick by trench_coat.gd so the waist row sits on the straight line from the
## posed chest row down to the hip row - the front hangs over the hollow of his belly.
## One per row: [0] the waist row, [1] the mid row (half-way to the chest). Translation only, so
## a point weighted between two of them lands exactly between their targets.
const BELLY_BONES := ["LeftCoatBelly0", "LeftCoatBelly1"]
const BELLY_BONES_R := ["RightCoatBelly0", "RightCoatBelly1"]
const ROW_MID_Y := (ROW_WAIST_Y + ROW_CHEST_Y) * 0.5

# The collar: its foot on the yoke and its flared top edge. [x, y, z], front tip to back centre.
const COLLAR_FOOT := [[0.09, 1.579, 0.10], [0.12, 1.573, 0.0], [0.09, 1.579, -0.10], [0.0, 1.582, -0.13]]
const COLLAR_TOP := [[0.11, 1.602, 0.12], [0.155, 1.610, 0.0], [0.12, 1.614, -0.135], [0.0, 1.616, -0.17]]

# A lapel: the inner edge runs down the front edge, the outer edge is the notch and the peak.
const LAPEL_INNER := [[0.078, 1.553, 0.142], [0.07, 1.471, 0.207], [0.085, 1.34, 0.242], [0.098, 1.20, 0.229]]
const LAPEL_OUTER := [[0.17, 1.508, 0.175], [0.155, 1.446, 0.19]]

# An epaulette: a strap from the collar to the shoulder edge. Inner and outer end [x, top y].
const EPAULETTE := [[0.14, 1.590], [0.195, 1.573]]
const EPAULETTE_HALF_WIDTH := 0.02
const EPAULETTE_DEPTH := 0.028

# A sleeve: rings along the arm. [distance along the upper arm or forearm in metres, radius].
const SLEEVE_SIDES := 6
## The rounded sleeve head (2026-11-12): the first rings start inside his shoulder (negative =
## back past the joint, toward his neck) and grow from a small dome, so the sleeve rounds up into
## the coat's shoulder instead of standing as a square open top beside it. The head rings ride
## his shoulder bone as much as his upper arm, so a hanging arm doesn't swing the dome up.
const SLEEVE_UPPER := [[-0.035, 0.03], [-0.01, 0.06], [0.03, 0.077], [0.18, 0.073]]
## The dome's tip, closing the head, and how much of the head rides the shoulder bone.
const SLEEVE_HEAD_TIP := -0.05
const SLEEVE_HEAD_SHOULDER := 0.5
const SLEEVE_ELBOW_RADIUS := 0.076
## Rings flanking the elbow: [distance from the joint, radius, share on the forearm bone].
const SLEEVE_ELBOW_UPPER := [[0.09, 0.07, 0.2], [0.04, 0.069, 0.35]]
const SLEEVE_ELBOW_LOWER := [[0.04, 0.066, 0.65], [0.09, 0.064, 0.8]]
const SLEEVE_LOWER := [[0.33, 0.062], [0.36, 0.08]]
## The dark disc that closes the cuff's mouth, this far back from the rim.
const CUFF_MOUTH_BACK := 0.012


## The left chains' points in rest model space: per chain [waist pivot, knee joint, hem tip].
static func chain_points() -> Array:
	var out := []
	for c in SIDE_CHAINS:
		var rows := []
		for row: Array in [[ROW_WAIST, ROW_WAIST_Y], [ROW_KNEE, ROW_KNEE_Y], [ROW_HEM, ROW_HEM_Y]]:
			var sum := Vector3.ZERO
			var n := 0
			for col in COLUMN_CHAIN.size():
				if COLUMN_CHAIN[col] == c:
					sum += Vector3(row[0][col][0], row[1], row[0][col][1])
					n += 1
			rows.append(sum / float(n))
		out.append(rows)
	# The vent chain hangs from a little off the back centre, not from the seam itself.
	out[3][0].x = 0.04
	return out


## Half the width of the coat's opening at height `y`: the front edge's x, from the rows.
static func front_edge_x(y: float) -> float:
	var ys := [ROW_HIP_Y, ROW_WAIST_Y, ROW_CHEST_Y, ROW_ARM_Y, ROW_TOP_Y[0]]
	var xs := [ROW_HIP[0][0], ROW_WAIST[0][0], ROW_CHEST[0][0], ROW_ARM[0][0], ROW_TOP[0][0]]
	if y <= ys[0]:
		return xs[0]
	for i in ys.size() - 1:
		if y <= ys[i + 1]:
			return lerpf(xs[i], xs[i + 1], (y - float(ys[i])) / (float(ys[i + 1]) - float(ys[i])))
	return xs[xs.size() - 1]


static func upper_bone_name(chain: int) -> String:
	return "CoatU%d" % chain


static func lower_bone_name(chain: int) -> String:
	return "CoatL%d" % chain


## Builds the coat. `skeleton` must already have the chain bones. The bone indices written are
## skeleton bone indices: skin it with one bind per bone, in bone order.
static func build(skeleton: Skeleton3D, leather: Material, lining: Material) -> ArrayMesh:
	var b := _Builder.new(skeleton)
	b.torso()
	b.skirt()
	b.yoke()
	b.collar()
	b.lapel()
	b.epaulette()
	b.sleeve()
	return b.commit([leather, lining])


## The left belly line in rest model space: [[belly bones' rest points (waist, mid)], hip front
## edge, chest front edge, the chest point's [bones, weights]] - what trench_coat.gd drives them by.
static func belly_line(skeleton: Skeleton3D) -> Array:
	var w := Vector3(ROW_WAIST[0][0], ROW_WAIST_Y, ROW_WAIST[0][1])
	var h := Vector3(ROW_HIP[0][0], ROW_HIP_Y, ROW_HIP[0][1])
	var c := Vector3(ROW_CHEST[0][0], ROW_CHEST_Y, ROW_CHEST[0][1])
	var t: Array = _Builder.new(skeleton).trunk(c)
	return [[w, (w + c) * 0.5], h, c, t[1], t[2]]


class _Builder:
	var skeleton: Skeleton3D
	var verts: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var bones: Array[PackedInt32Array] = []
	var weights: Array[PackedFloat32Array] = []
	var mirror := {}
	var spine_bones := PackedInt32Array()
	var spine_heights := PackedFloat32Array()

	func _init(skel: Skeleton3D) -> void:
		skeleton = skel
		for s in SURFACES:
			verts.append(PackedVector3Array())
			normals.append(PackedVector3Array())
			bones.append(PackedInt32Array())
			weights.append(PackedFloat32Array())
		for i in skel.get_bone_count():
			var n := skel.get_bone_name(i)
			var other := n
			if n.begins_with("Left"):
				other = "Right" + n.substr(4)
			elif n.begins_with("Right"):
				other = "Left" + n.substr(5)
			elif n.begins_with("CoatU") or n.begins_with("CoatL"):
				other = n.substr(0, 5) + str((int(n.substr(5)) + SIDE_CHAINS) % CHAINS)
			var j := skel.find_bone(other)
			mirror[i] = j if j >= 0 else i
		for n: String in ["Hips", "Spine", "Chest", "UpperChest", "Neck"]:
			spine_bones.append(skel.find_bone(n))
			spine_heights.append(skel.get_bone_global_rest(skel.find_bone(n)).origin.y)

	func bone(n: String) -> int:
		return skeleton.find_bone(n)

	func rest(n: String) -> Vector3:
		return skeleton.get_bone_global_rest(bone(n)).origin

	# -- vertices: [position, [bones], [weights]] ----------------------------------------------

	## On the trunk: the two nearest spine bones by height, giving way to the shoulder bone out
	## over the shoulder.
	func trunk(p: Vector3) -> Array:
		var bs := []
		var ws := []
		var last := spine_bones.size() - 1
		if p.y <= spine_heights[0]:
			bs = [spine_bones[0]]
			ws = [1.0]
		elif p.y >= spine_heights[last]:
			bs = [spine_bones[last]]
			ws = [1.0]
		else:
			for i in last:
				if p.y <= spine_heights[i + 1]:
					var f := (p.y - spine_heights[i]) / (spine_heights[i + 1] - spine_heights[i])
					bs = [spine_bones[i], spine_bones[i + 1]]
					ws = [1.0 - f, f]
					break
		var shoulder := smoothstep(0.14, 0.26, absf(p.x)) * smoothstep(1.42, 1.50, p.y) * 0.5
		if shoulder > 0.0:
			for i in ws.size():
				ws[i] *= 1.0 - shoulder
			bs.append(bone("LeftShoulder"))
			ws.append(shoulder)
		return [p, bs, ws]

	## The waist row (2026-11-12): on his pelvis, like the skirt's chain bones under it. It used to
	## ride the trunk blend (mostly Spine at 1.12), so a strafe clip twisting his spine against
	## his hips turned the coat's flat back round onto his hip's side corner, and the top of his
	## thigh came through right under the seam. The torso above takes the twist instead.
	func waist(p: Vector3) -> Array:
		return on(p, spine_bones[0])

	## The front panels' belly (2026-11-16, the front-crease fix). The waist row's front rides the
	## belly bone; from there up to the chest row the weights are a straight lerp of belly bone and
	## chest (trunk blend) by height, so the mid row + lapel tip land on the line between them.
	## History: pass 1 put the waist + hip rows on his pelvis and lerped up from the waist: the
	## run's chest lean (~20 deg over upright hips) folded the front into the hollow of his belly
	## (posed z chest 0.345 / waist 0.269 / hip 0.292), the V the user circled. Pass 2 lerped from
	## the knee row: chest weight on low points swings them BACK about the chest's high pivot (hip
	## row z 0.221, into his thighs) - weights alone can't drape it, hence the driven bone.
	func front_torso(p: Vector3) -> Array:
		if p.y >= ROW_CHEST_Y:
			return trunk(p)
		var b0 := belly_bone(0)
		var b1 := belly_bone(1)
		if p.y <= ROW_WAIST_Y:
			return on(p, b0)
		if p.y <= ROW_MID_Y:
			return on2(p, b0, b1, (p.y - ROW_WAIST_Y) / (ROW_MID_Y - ROW_WAIST_Y))
		var chest := trunk(Vector3(p.x, ROW_CHEST_Y, p.z))
		var f := (p.y - ROW_MID_Y) / (ROW_CHEST_Y - ROW_MID_Y)
		var bs: Array = [b1]
		var ws: Array = [1.0 - f]
		for k in (chest[1] as Array).size():
			bs.append(chest[1][k])
			ws.append(f * float(chest[2][k]))
		return [p, bs, ws]

	func belly_bone(k: int) -> int:
		var b := bone(BELLY_BONES[k])
		return b if b >= 0 else spine_bones[0]

	## The waist row: front points on the belly blend, the rest on his pelvis.
	func front_waist(p: Vector3, i: int) -> Array:
		return front_torso(p) if i < FRONT_POINTS else waist(p)

	func on(p: Vector3, bone_index: int) -> Array:
		return [p, [bone_index], [1.0]]

	func on2(p: Vector3, a: int, b: int, share_b: float) -> Array:
		return [p, [a, b], [1.0 - share_b, share_b]]

	func row(points: Array, y: Variant, weigh: Callable) -> Array:
		var out := []
		for i in points.size():
			var py: float = y[i] if y is Array else y
			out.append(weigh.call(Vector3(points[i][0], py, points[i][1]), i))
		return out

	# -- triangles -----------------------------------------------------------------------------

	## One flat triangle and its mirror. `outward` is any vector on its front side.
	func tri(surface: int, a: Array, b: Array, c: Array, outward: Vector3, lined := false) -> void:
		for side in 2:
			var pa: Vector3 = a[0]
			var pb: Vector3 = b[0]
			var pc: Vector3 = c[0]
			var out := outward
			if side == 1:
				pa.x = -pa.x
				pb.x = -pb.x
				pc.x = -pc.x
				out.x = -out.x
			# Godot's front face is clockwise: its normal is (c - a) x (b - a).
			var n := (pc - pa).cross(pb - pa)
			if n.length_squared() < 1e-12:
				continue
			n = n.normalized()
			var order := [a, b, c]
			var points := [pa, pb, pc]
			if n.dot(out) < 0.0:
				n = -n
				order = [a, c, b]
				points = [pa, pc, pb]
			for k in 3:
				_vertex(surface, points[k], n, order[k], side == 1)
			if lined:
				for k in [0, 2, 1]:
					_vertex(LINING, points[k] - n * LINING_INSET, -n, order[k], side == 1)

	func quad(surface: int, a: Array, b: Array, c: Array, d: Array, outward: Vector3, lined := false) -> void:
		tri(surface, a, b, c, outward, lined)
		tri(surface, a, c, d, outward, lined)

	func _vertex(surface: int, p: Vector3, n: Vector3, v: Array, mirrored: bool) -> void:
		verts[surface].append(p)
		normals[surface].append(n)
		var bs: Array = v[1]
		var ws: Array = v[2]
		var total := 0.0
		for w: float in ws:
			total += w
		for j in 4:
			if j < bs.size():
				bones[surface].append(mirror[bs[j]] if mirrored else bs[j])
				weights[surface].append(ws[j] / total)
			else:
				bones[surface].append(0)
				weights[surface].append(0.0)

	func commit(materials: Array) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		mesh.resource_name = "TrenchCoat"
		for s in SURFACES:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts[s]
			arrays[Mesh.ARRAY_NORMAL] = normals[s]
			arrays[Mesh.ARRAY_BONES] = bones[s]
			arrays[Mesh.ARRAY_WEIGHTS] = weights[s]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_name(s, ["Leather", "Lining"][s])
			mesh.surface_set_material(s, materials[s])
		return mesh

	static func _out(a: Array, b: Array) -> Vector3:
		var mid: Vector3 = ((a[0] as Vector3) + (b[0] as Vector3)) * 0.5
		return Vector3(mid.x, 0.0, mid.z)

	# -- the parts -----------------------------------------------------------------------------

	## Waist to shoulder top: three bands of four panels a side.
	func torso() -> void:
		var weigh := func(p: Vector3, _i: int) -> Array: return trunk(p)
		# A middle row between the pelvis-ridden waist and the spine-ridden chest: when his spine
		# twists against his hips (run left / right) the one tall back quad folded into a crease
		# and let the body through; two quads, the middle one half on each, take the twist smoothly.
		var mid_pts := []
		for i in ROW_WAIST.size():
			mid_pts.append([(ROW_WAIST[i][0] + ROW_CHEST[i][0]) * 0.5, (ROW_WAIST[i][1] + ROW_CHEST[i][1]) * 0.5])
		# The front edge + front columns (FRONT_POINTS) take the straight belly blend instead.
		var mid := row(mid_pts, ROW_MID_Y,
			func(p: Vector3, i: int) -> Array:
				return front_torso(p) if i < FRONT_POINTS else on2(p, spine_bones[0], spine_bones[1], 0.5))
		var rows := [row(ROW_WAIST, ROW_WAIST_Y, front_waist),
			mid, row(ROW_CHEST, ROW_CHEST_Y, weigh),
			row(ROW_ARM, ROW_ARM_Y, weigh), row(ROW_TOP, ROW_TOP_Y, weigh)]
		for r in rows.size() - 1:
			for i in 4:
				quad(LEATHER, rows[r][i], rows[r][i + 1], rows[r + 1][i + 1], rows[r + 1][i],
					_out(rows[r][i], rows[r][i + 1]), true)

	## Waist to hem: the waist row rides the trunk, the hip and knee rows a chain's upper bone,
	## the hem its lower bone - so each panel hinges at the knee row.
	func skirt() -> void:
		var upper := func(p: Vector3, i: int) -> Array:
			return on(p, bone("CoatU%d" % COLUMN_CHAIN[i]))
		var lower := func(p: Vector3, i: int) -> Array:
			return on(p, bone("CoatL%d" % COLUMN_CHAIN[i]))
		# The front's hip row is on his pelvis (2026-11-16): the front swings from the knee row
		# down, so the belly panel above it no longer shears against the leg-pushed chain.
		var hip := func(p: Vector3, i: int) -> Array:
			return waist(p) if i < FRONT_POINTS else upper.call(p, i)
		var rows := [row(ROW_WAIST, ROW_WAIST_Y, front_waist),
			row(ROW_HIP, ROW_HIP_Y, hip), row(ROW_KNEE, ROW_KNEE_Y, upper), row(ROW_HEM, ROW_HEM_Y, lower)]
		for r in rows.size() - 1:
			for i in 4:
				quad(LEATHER, rows[r][i], rows[r][i + 1], rows[r + 1][i + 1], rows[r + 1][i],
					_out(rows[r + 1][i], rows[r + 1][i + 1]), true)

	## The shoulder top, from the torso's top edge in to the collar's foot.
	func yoke() -> void:
		var weigh := func(p: Vector3, _i: int) -> Array: return trunk(p)
		var top := row(ROW_TOP, ROW_TOP_Y, weigh)
		var foot := _collar_row(COLLAR_FOOT)
		tri(LEATHER, top[0], top[1], foot[0], Vector3.UP)
		for i in 3:
			quad(LEATHER, top[i + 1], top[i + 2], foot[i + 1], foot[i], Vector3.UP)

	func _collar_row(points: Array) -> Array:
		var chest := bone("UpperChest")
		var neck := bone("Neck")
		var out := []
		for p: Array in points:
			out.append(on2(Vector3(p[0], p[1], p[2]), chest, neck, 0.25))
		return out

	## Turned up and flared, open at the front.
	func collar() -> void:
		var foot := _collar_row(COLLAR_FOOT)
		var top := _collar_row(COLLAR_TOP)
		for i in 3:
			# Lined: its inside faces his head and shows.
			quad(LEATHER, foot[i], foot[i + 1], top[i + 1], top[i], _out(top[i], top[i + 1]), true)

	## Lies on the front panel, standing a little proud of it at the notch and the peak.
	func lapel() -> void:
		var inner := []
		for p: Array in LAPEL_INNER:
			inner.append(front_torso(Vector3(p[0], p[1], p[2])))
		var outer := []
		for p: Array in LAPEL_OUTER:
			outer.append(front_torso(Vector3(p[0], p[1], p[2])))
		var front := Vector3(0.3, 0.0, 1.0)
		tri(LEATHER, inner[0], outer[0], inner[1], front)
		tri(LEATHER, inner[1], outer[0], outer[1], front)
		tri(LEATHER, inner[1], outer[1], inner[2], front)
		tri(LEATHER, inner[2], outer[1], inner[3], front)

	func epaulette() -> void:
		var corners := []
		for end: Array in EPAULETTE:
			for z: float in [EPAULETTE_HALF_WIDTH, -EPAULETTE_HALF_WIDTH]:
				for drop: float in [0.0, EPAULETTE_DEPTH]:
					corners.append(trunk(Vector3(end[0], end[1] - drop, z)))
		# corners: inner (front top, front bottom, back top, back bottom), then outer the same.
		quad(LEATHER, corners[0], corners[4], corners[6], corners[2], Vector3.UP)
		quad(LEATHER, corners[0], corners[1], corners[5], corners[4], Vector3.BACK)
		quad(LEATHER, corners[2], corners[6], corners[7], corners[3], Vector3.FORWARD)
		quad(LEATHER, corners[4], corners[5], corners[7], corners[6], Vector3.RIGHT)
		quad(LEATHER, corners[0], corners[2], corners[3], corners[1], Vector3.LEFT)

	## Shoulder to cuff. The elbow ring is shared between the two arm bones.
	func sleeve() -> void:
		var upper_arm := bone("LeftUpperArm")
		var lower_arm := bone("LeftLowerArm")
		var shoulder := rest("LeftUpperArm")
		var elbow := rest("LeftLowerArm")
		var wrist := rest("LeftHand")
		var a1 := (elbow - shoulder).normalized()
		var a2 := (wrist - elbow).normalized()
		var rings := []
		var centres := PackedVector3Array()
		var clavicle := bone("LeftShoulder")
		var head := func(p: Vector3) -> Array:
			var t := (p - shoulder).dot(a1)
			var share := SLEEVE_HEAD_SHOULDER * clampf(1.0 - t / 0.03, 0.0, 1.0)
			return on2(p, upper_arm, clavicle, share)
		for s: Array in SLEEVE_UPPER:
			var c: Vector3 = shoulder + a1 * float(s[0])
			rings.append(_ring(c, a1, s[1], head))
			centres.append(c)
		# The dome's tip closes the head.
		var tip: Array = head.call(shoulder + a1 * SLEEVE_HEAD_TIP)
		for i in SLEEVE_SIDES:
			var j := (i + 1) % SLEEVE_SIDES
			tri(LEATHER, tip, rings[0][i], rings[0][j], ((rings[0][i][0] as Vector3) - shoulder) - a1 * 0.02)
		# The elbow articulation (2026-11-15): the bend is spread over rings either side of the
		# joint, blending from the upper arm bone to the forearm bone, so it folds instead of
		# kinking at one ring. The joint ring is fatter: the cloth bunches over the elbow.
		var upper_len := (elbow - shoulder).length()
		for s: Array in SLEEVE_ELBOW_UPPER:
			var c: Vector3 = shoulder + a1 * maxf(upper_len - float(s[0]), 0.19)
			rings.append(_ring(c, a1, s[1], func(p: Vector3) -> Array: return on2(p, upper_arm, lower_arm, float(s[2]))))
			centres.append(c)
		rings.append(_ring(elbow, (a1 + a2).normalized(), SLEEVE_ELBOW_RADIUS,
			func(p: Vector3) -> Array: return on2(p, upper_arm, lower_arm, 0.5)))
		centres.append(elbow)
		for s: Array in SLEEVE_ELBOW_LOWER:
			var c: Vector3 = elbow + a2 * float(s[0])
			rings.append(_ring(c, a2, s[1], func(p: Vector3) -> Array: return on2(p, upper_arm, lower_arm, float(s[2]))))
			centres.append(c)
		for s: Array in SLEEVE_LOWER:
			var c: Vector3 = elbow + a2 * float(s[0])
			rings.append(_ring(c, a2, s[1], func(p: Vector3) -> Array: return on(p, lower_arm)))
			centres.append(c)
		for r in rings.size() - 1:
			for i in SLEEVE_SIDES:
				var j := (i + 1) % SLEEVE_SIDES
				var mid: Vector3 = ((rings[r][i][0] as Vector3) + (rings[r + 1][j][0] as Vector3)) * 0.5
				quad(LEATHER, rings[r][i], rings[r][j], rings[r + 1][j], rings[r + 1][i],
					mid - (centres[r] + centres[r + 1]) * 0.5)
		# The cuff's mouth: a dark disc just inside the rim, the hand comes out through it.
		var last: Array = SLEEVE_LOWER[SLEEVE_LOWER.size() - 1]
		var mouth_at: Vector3 = elbow + a2 * (float(last[0]) - CUFF_MOUTH_BACK)
		var mouth := _ring(mouth_at, a2, float(last[1]) * 0.96, func(p: Vector3) -> Array: return on(p, lower_arm))
		var hub := on(mouth_at, lower_arm)
		for i in SLEEVE_SIDES:
			tri(LINING, hub, mouth[i], mouth[(i + 1) % SLEEVE_SIDES], a2)

	func _ring(centre: Vector3, axis: Vector3, radius: float, weigh: Callable) -> Array:
		var u := (Vector3.UP - axis * Vector3.UP.dot(axis)).normalized()
		var v := axis.cross(u)
		var out := []
		for i in SLEEVE_SIDES:
			var a := TAU * (float(i) + 0.5) / float(SLEEVE_SIDES)
			out.append(weigh.call(centre + (u * cos(a) + v * sin(a)) * radius))
		return out
