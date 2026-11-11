class_name ArrivalGrowth
extends Node3D

# 200 years of growth on the abandoned base in the arrival shot (docs/specs/cutscene-arrival.md,
# revision 5). Cold-climate: the same spruce as the forest (ArrivalForest.spruce_mesh), low dark
# scrub (bare mounds: snow doesn't hold on it, so the patches read dark against the snow roof; a
# step greener since R6, still darker than the moss), and moss / lichen-ivy a step greener and lighter than the spruce (darker read as grey streaks), with
# snow sitting on top of it.
#
# - Roofs (spec R5-3): scrub where 200 years of needles and grit collected: the foot of every wall
#   standing on the roof, the deck's corners, lines along the structural joints, round whatever
#   stands on the roof, the rim of the collapse hole. Each roof sample scores how sheltered it is
#   (plus a break-up noise) and the best `roof_cover` of them grow; the more sheltered, the older,
#   thicker and taller. Scrub also comes up through the structure where ArrivalBase left room
#   (`tree_slots`: the hole, the roofless sheds, skylight slots, yards). No tree grows on the
#   building (R5b): trees only stand on the land, in the rubble at the wall's foot.
# - Walls (spec R5-4): curtains hang from every face ArrivalBase lists (`walls`) in vertical strips
#   of uneven length, runs of them with bare wall between; growth climbs ~20 m up the faces that
#   stand on the ground or a roof; rust and water streaks down some of the bare wall.
# - The road and the power cut (spec R5-5) have grown back: young, low trees on their snow.
#
# GENERATED like ArrivalLand: no owner, nothing saved into the .tscn. Built after Base and Forest.

const CEL_BASE := "res://resources/cel_ground.tres"
const C_MOSS := Color(0.2, 0.31, 0.19)
const C_SCRUB := Color(0.13, 0.22, 0.15)
const C_SNOW := Color(0.8, 0.83, 0.88)
const C_RUST_STREAK := Color(0.36, 0.27, 0.2)
const C_WATER_STREAK := Color(0.33, 0.33, 0.32)

@export var growth_seed := 2129
## Towers whose caps grow no scrub (the boss arena plays on RightWide's). None in the shot.
@export var bare_caps := PackedStringArray()
## Share of each roof that grows (spec R5-3): the Lower deck and the right extension, and the upper
## tiers (more exposed).
@export_range(0.0, 1.0, 0.01) var low_cover := 0.35
@export_range(0.0, 1.0, 0.01) var tier_cover := 0.15
## Roof sample spacing (m): one tree or scrub clump per sample that grows.
@export var cell := 5.0
## Scrub mound heights (m) from the youngest patch edge to the oldest heart.
@export var scrub_height := Vector2(2.0, 6.0)
## Curtain strips: width range (m), and length range of the short fringes and the long tongues (m).
@export var strip_width := Vector2(4.0, 9.0)
@export var fringe := Vector2(3.0, 12.0)
@export var tongue := Vector2(14.0, 80.0)
## How far growth climbs from the ground or a roof (m), and how much of a climbing face it covers.
@export var climb := 20.0
@export_range(0.0, 1.0, 0.01) var climb_cover := 0.7
## Streaks on a stretch of bare wall: the chance, and their length range (m).
@export_range(0.0, 1.0, 0.01) var streak_chance := 0.35
@export var streak_length := Vector2(6.0, 26.0)
## Young trees on the road and in the power cut (m).
@export var young_height := Vector2(4.0, 9.0)

## Per roof deck: the share of its samples that grew (spec R5-3), for the tests.
var coverage := {}
## Counts, for the tests: roof clumps, clumps up through the structure, curtains, young trees.
var roof_clumps := 0
var slot_clumps := 0
var curtains := 0
var young_trees := 0

var _base: ArrivalBase
var _land: ArrivalLand
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _trees: Array[Transform3D] = []
var _scrubs: Array[Transform3D] = []
## The roof blocks' centres and reach (m), so a roof sample only measures the ones near it.
var _block_disc: Array[Vector3] = []


func _ready() -> void:
	_base = get_node(^"../Base") as ArrivalBase
	_land = get_node(^"../Land") as ArrivalLand
	_rng.seed = growth_seed
	_noise.seed = growth_seed
	_noise.frequency = 1.0 / 45.0
	for blk in _base.roof_blocks:
		var c := ArrivalBase._centroid(blk)
		var reach := 0.0
		for q in blk:
			reach = maxf(reach, c.distance_to(q))
		_block_disc.append(Vector3(c.x, c.y, reach))
	for deck in _base.deck_list():
		_grow_roof(deck)
	for slot in _base.tree_slots:
		_grow_slot(slot)
	for pile in _base.rubble:
		# Saplings in a talus on the land; one that fell onto a lower deck only scrubs over.
		var on_roof := pile.y > _land.height(pile.x, pile.z) + 2.0
		for k in _rng.randi_range(3, 6):
			var p := Vector2(pile.x, pile.z) + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(2.0, 11.0)
			if on_roof:
				_scrub(Vector3(p.x, pile.y, p.y), _rng.randf_range(1.5, 3.5))
			else:
				_tree(Vector3(p.x, _land.height(p.x, p.y), p.y), _rng.randf_range(3.0, 8.0))
	for cap in _base.caps:
		if not bare_caps.has(cap.tower):
			_grow_cap(cap)
	_grow_young()
	_build_trees()
	_build_walls()


# --- roofs -------------------------------------------------------------------------------------

func _grow_roof(deck: Dictionary) -> void:
	var poly: PackedVector2Array = deck.poly
	var top: float = deck.top
	var cover := low_cover if top <= 0.0 else tier_cover
	var above := _base.decks_above(top)
	var uppers: Array[PackedVector2Array] = []
	for d in _base.deck_list():
		if d.top > top:
			uppers.append(d.poly)
	var inner := ArrivalBase._inset(poly, 3.0)
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
	var samples: Array[Dictionary] = []
	var y := box.position.y
	while y < box.end.y:
		var x := box.position.x
		while x < box.end.x:
			var p := Vector2(x, y) + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4)) * cell
			x += cell
			if not Geometry2D.is_point_in_polygon(p, inner):
				continue
			if ArrivalBase._any_inside(PackedVector2Array([p]), above):
				continue
			if ArrivalBase._any_inside(PackedVector2Array([p]), _base.roof_blocks):
				continue
			samples.append({p = p, score = _shelter(p, poly, uppers)})
		y += cell
	if samples.is_empty():
		return
	samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var grow := int(round(samples.size() * cover))
	coverage[deck.name] = float(grow) / samples.size()
	if grow == 0:
		return
	var bar: float = samples[grow - 1].score
	var best: float = samples[0].score
	for k in grow:
		var smp: Dictionary = samples[k]
		var age := clampf((smp.score - bar) / maxf(best - bar, 0.001), 0.0, 1.0)
		var at := Vector3(smp.p.x, top, smp.p.y)
		# Scrub carpets the patch, thicker and taller toward the heart; a clump fewer than R5 had
		# (spec R6-4), so a patch breaks into clumps instead of one dark stain.
		for j in (3 if age > 0.45 else 2):
			var off := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.5, cell * 0.6)
			var h := lerpf(scrub_height.x, scrub_height.y, pow(age, 0.7)) * _rng.randf_range(0.75, 1.15)
			_scrub(at + Vector3(off.x, 0.0, off.y), h)
		roof_clumps += 1


# How sheltered roof point `p` is, 0..1 and a little over: by a wall standing on the roof (an upper
# deck's outline it is outside of), in a corner of its own deck, along a joint line in from the edge,
# round something standing on the roof, by the collapse hole's rim. Plus a break-up noise so the
# patches are ragged.
func _shelter(p: Vector2, poly: PackedVector2Array, uppers: Array[PackedVector2Array]) -> float:
	var s := 0.0
	for up in uppers:
		if not Geometry2D.is_point_in_polygon(p, up):
			s = maxf(s, 1.0 - smoothstep(0.0, 32.0, ArrivalBase._boundary_distance(p, up)))
	var corner := INF
	for q in poly:
		corner = minf(corner, p.distance_to(q))
	s = maxf(s, 1.0 - smoothstep(10.0, 60.0, corner))
	var edge := ArrivalBase._boundary_distance(p, poly)
	s = maxf(s, (1.0 - smoothstep(4.0, 22.0, edge)) * 0.55)
	# Joints: every `bay` along the edge, a crack running straight in.
	var outward := ArrivalBase._orientation(poly)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		var inward := -Vector2(e.y, -e.x) * outward
		var along := (p - a).dot(e)
		var depth := (p - a).dot(inward)
		if along < 0.0 or along > a.distance_to(b) or depth < 0.0 or depth > 80.0:
			continue
		var off := absf(fposmod(along + _base.bay * 0.5, _base.bay) - _base.bay * 0.5)
		s = maxf(s, (1.0 - smoothstep(2.0, 9.0, off)) * (1.0 - depth / 80.0) * 0.85)
	for i in _block_disc.size():
		var disc := _block_disc[i]
		if p.distance_to(Vector2(disc.x, disc.y)) < disc.z + 14.0:
			s = maxf(s, (1.0 - smoothstep(0.0, 14.0, ArrivalBase._boundary_distance(p, _base.roof_blocks[i]))) * 0.8)
	if _base.hole != Vector3.INF:
		var d := p.distance_to(Vector2(_base.hole.x, _base.hole.z)) - ArrivalShot.HOLE.radius
		s = maxf(s, 1.0 - smoothstep(0.0, 30.0, d))
	return s + _noise.get_noise_2d(p.x, p.y) * 0.35


# Scrub up through the structure: `count` clumps at random inside the slot's outline, standing on
# its floor (no trees on the building, R5b).
func _grow_slot(slot: Dictionary) -> void:
	var poly: PackedVector2Array = slot.poly
	if poly.size() < 3:
		return
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
	var h: Vector2 = slot.height
	var placed := 0
	var tries := 0
	while placed < slot.count and tries < slot.count * 20:
		tries += 1
		var p := box.position + box.size * Vector2(_rng.randf(), _rng.randf())
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		_scrub(Vector3(p.x, slot.y, p.y), _rng.randf_range(minf(h.x, scrub_height.y), minf(h.y, scrub_height.y)))
		placed += 1
		slot_clumps += 1


# A few clumps of scrub on each tower's rim top, between the upper step and the edge.
func _grow_cap(cap: Dictionary) -> void:
	var poly: PackedVector2Array = cap.poly
	var c := ArrivalBase._centroid(poly)
	var placed := 0
	var tries := 0
	while placed < 6 and tries < 60:
		tries += 1
		var p := c + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(cap.inner + 3.0, cap.inner * 1.55)
		if Geometry2D.is_point_in_polygon(p, ArrivalBase._inset(poly, 3.0)):
			_scrub(Vector3(p.x, cap.y, p.y), _rng.randf_range(1.5, 3.5))
			placed += 1


# The road and the power cut grown back (spec R5-5): young trees, lower than the forest, scattered
# on their snow, thick enough to read as a lighter textured strip, thin enough that the line shows.
func _grow_young() -> void:
	var path := _land.road_path
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var n := int(a.distance_to(b) / 2.5)
		var half := _land.road_width * 0.5 + _land.road_verge
		for k in n:
			if _rng.randf() > 0.75:
				continue
			var p := a.lerp(b, (k + _rng.randf()) / maxf(n, 1)) + (b - a).normalized().orthogonal() * _rng.randf_range(-half, half)
			_tree(Vector3(p.x, _land.height(p.x, p.y) + 0.2, p.y), _rng.randf_range(young_height.x, young_height.y))
			young_trees += 1
	var shot := get_parent() as ArrivalShot
	var pc := ArrivalShot.POWER_CUT
	var w := shot.on_plane(pc.from.x, pc.from.y, 0.0)
	var from := Vector2(w.x, w.z)
	var e := shot.at_distance(pc.to.x, pc.to.y, pc.distance)
	var to := Vector2(e.x, e.z)
	var dir := (to - from).normalized()
	var across := dir.orthogonal()
	var decks: Array[PackedVector2Array] = []
	for d in _base.deck_list():
		decks.append(ArrivalBase._inset(d.poly, -20.0))
	var t := 0.0
	while t < from.distance_to(to):
		for j in 4:
			if _rng.randf() > 0.8:
				continue
			var p := from + dir * (t + _rng.randf_range(0.0, 6.0)) + across * _rng.randf_range(-_land.cut_width * 0.45, _land.cut_width * 0.45)
			if ArrivalBase._any_inside(PackedVector2Array([p]), decks):
				continue
			_tree(Vector3(p.x, _land.height(p.x, p.y) - 0.3, p.y), _rng.randf_range(young_height.x + 1.0, young_height.y))
			young_trees += 1
		t += 6.0


func _tree(at: Vector3, h: float) -> void:
	var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(h, h, h))
	_trees.append(Transform3D(basis, at - Vector3.UP * 0.4))


# Scrub: a low wide mound.
func _scrub(at: Vector3, h: float) -> void:
	var wide := h * _rng.randf_range(1.8, 2.8)
	var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(wide, h, wide))
	_scrubs.append(Transform3D(basis, at - Vector3.UP * 0.3))


func _build_trees() -> void:
	var forest := get_node(^"../Forest") as ArrivalForest
	_multimesh("Trees", forest.spruce_mesh(), _trees)
	# No shadow from the scrub (spec R6-4): on the snow it was a soft halo round every clump.
	_multimesh("Scrub", _mound(), _scrubs).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	add_child(mmi)
	return mmi


# A scrub mound, 1 m across and 1 m tall: a six-sided dome in two bands.
func _mound() -> ArrayMesh:
	var st := _surface()
	var rings := [[0.0, 0.5], [0.55, 0.38], [1.0, 0.0]]
	for k in rings.size() - 1:
		for i in 6:
			var a0 := TAU * i / 6.0
			var a1 := TAU * (i + 1) / 6.0
			var p := func(ring: Array, a: float) -> Vector3: return Vector3(cos(a) * ring[1], ring[0], sin(a) * ring[1])
			var q0: Vector3 = p.call(rings[k], a0)
			var q1: Vector3 = p.call(rings[k], a1)
			var r0: Vector3 = p.call(rings[k + 1], a0)
			var r1: Vector3 = p.call(rings[k + 1], a1)
			var n := (q0 + q1 + r0 + r1).normalized()
			_tri(st, q0, q1, r1, n)
			if k < rings.size() - 2:
				_tri(st, q0, r1, r0, n)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	mesh.surface_set_material(0, _cel(C_SCRUB))
	return mesh


# --- walls -------------------------------------------------------------------------------------

func _build_walls() -> void:
	var moss := _surface()
	var snow := _surface()
	var rust := _surface()
	var water := _surface()
	for f in _base.walls:
		var a: Vector2 = f.a
		var b: Vector2 = f.b
		var length := a.distance_to(b)
		if length < 3.0:
			continue
		var e := (b - a).normalized()
		var out: Vector2 = f.out
		var top0: float = f.top
		var sag: float = f.get("sag", 0.0)
		var drop0: float = top0 - f.bottom
		# Runs of strips: the chance a strip hangs depends on whether the last one did, so curtains
		# come in sheets with bare wall between (the run's share settles at `cover`).
		var cover: float = f.cover
		var stay := 0.75
		var start := cover * (1.0 - stay) / maxf(1.0 - cover, 0.05)
		var on := _rng.randf() < cover
		var x := 0.0
		while x < length - 1.0:
			var w := minf(_rng.randf_range(strip_width.x, strip_width.y), length - x)
			# On a sagging face the strip hangs from the face's top at its middle.
			var top := top0 - sag * sin(PI * (x + w * 0.5) / length)
			var drop := drop0 - (top0 - top)
			var long := _rng.randf() < 0.55
			if on and drop > 2.0:
				var l := _rng.randf_range(tongue.x, tongue.y) if long else _rng.randf_range(fringe.x, fringe.y)
				_curtain(moss, snow, a + e * x, e, out, top, minf(l, drop), w, true)
				curtains += 1
			elif f.streaks and _rng.randf() < streak_chance and drop > 6.0:
				var c := a + e * (x + w * _rng.randf_range(0.3, 0.7))
				var sl := minf(_rng.randf_range(streak_length.x, streak_length.y), drop - 1.0)
				_strip(rust if _rng.randf() < 0.5 else water, c, e, out, 0.25, top - 0.5, top - 0.5 - sl, _rng.randf_range(0.5, 0.9))
			on = _rng.randf() < (stay if on else start)
			x += w
		if f.climb:
			x = 0.0
			while x < length - 1.0:
				var w := minf(_rng.randf_range(strip_width.x, strip_width.y), length - x)
				if _rng.randf() < climb_cover:
					var c := a + e * (x + w * 0.5) + out * 2.0
					var foot: float = f.floor if f.floor != INF else _land.height(c.x, c.y)
					var up := minf(climb * _rng.randf_range(0.5, 1.15), top0 - foot - 1.0)
					if up > 1.5:
						_curtain(moss, snow, a + e * x, e, out, foot - 2.0, up + 2.0, w, false)
				x += w
	var mesh := ArrayMesh.new()
	for pair in [[moss, C_MOSS], [snow, C_SNOW], [rust, C_RUST_STREAK], [water, C_WATER_STREAK]]:
		var st: SurfaceTool = pair[0]
		var before := mesh.get_surface_count()
		st.commit(mesh)
		if mesh.get_surface_count() > before:
			mesh.surface_set_material(before, _cel(pair[1]))
	var mi := MeshInstance3D.new()
	mi.name = "Curtains"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# One strip of growth `w` wide from `a` along `e`, just off the wall (facing `out`). Hanging
# (`down`): from `y` down `l` m with a ragged lower edge (a long tongue somewhere along it) and snow
# along its top. Climbing: from `y` up `l` m with a ragged upper edge.
func _curtain(moss: SurfaceTool, snow: SurfaceTool, a: Vector2, e: Vector2, out: Vector2, y: float, l: float, w: float,
		down: bool) -> void:
	var n := maxi(int(w / 1.5), 2)
	var sign_ := -1.0 if down else 1.0
	var tip := _rng.randi_range(0, n)
	var edge := PackedFloat32Array()
	for k in n + 1:
		var reach := l * (1.0 if k == tip else _rng.randf_range(0.35, 0.8))
		if k == 0 or k == n:
			reach = l * _rng.randf_range(0.15, 0.4)
		edge.append(reach)
	var off := out * 0.5
	var nrm := Vector3(out.x, 0.0, out.y)
	for k in n:
		var p0 := a + e * w * float(k) / n + off
		var p1 := a + e * w * float(k + 1) / n + off
		var q0 := Vector3(p0.x, y, p0.y)
		var q1 := Vector3(p1.x, y, p1.y)
		var r0 := q0 + Vector3.UP * sign_ * edge[k]
		var r1 := q1 + Vector3.UP * sign_ * edge[k + 1]
		_tri(moss, q0, q1, r1, nrm)
		_tri(moss, q0, r1, r0, nrm)
	if down:
		var s0 := a + off * 1.1
		var s1 := a + e * w + off * 1.1
		_tri(snow, Vector3(s0.x, y + 0.3, s0.y), Vector3(s1.x, y + 0.3, s1.y), Vector3(s1.x, y - 1.0, s1.y), nrm)
		_tri(snow, Vector3(s0.x, y + 0.3, s0.y), Vector3(s1.x, y - 1.0, s1.y), Vector3(s0.x, y - 1.0, s0.y), nrm)


# A streak down the wall: `half` either side of `c`, from `y0` down to `y1`, narrowing below.
func _strip(st: SurfaceTool, c: Vector2, e: Vector2, out: Vector2, off: float, y0: float, y1: float, half: float) -> void:
	var p := c + out * off
	var nrm := Vector3(out.x, 0.0, out.y)
	var a := p - e * half
	var b := p + e * half
	var a1 := p - e * half * 0.4
	var b1 := p + e * half * 0.4
	_tri(st, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b1.x, y1, b1.y), nrm)
	_tri(st, Vector3(a.x, y0, a.y), Vector3(b1.x, y1, b1.y), Vector3(a1.x, y1, a1.y), nrm)


func _surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


# One flat-shaded triangle, wound so its front faces `want`.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3) -> void:
	if (c - a).cross(b - a).dot(want) < 0.0:
		var swap := b
		b = c
		c = swap
	for v in [a, b, c]:
		st.set_normal(want)
		st.add_vertex(v)


func _cel(col: Color) -> ShaderMaterial:
	var m := (load(CEL_BASE) as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("color", col)
	m.next_pass = null
	return m
