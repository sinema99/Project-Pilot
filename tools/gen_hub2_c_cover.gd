extends SceneTree

# Room C enemy cover (docs/specs/hub2-room-c-cover.md): fixes the bridge crane's column mounts that stand
# in the dock ledge / ramp, and writes the Dressing/C/Cover group (jersey-barrier runs, plate shields,
# crate piles, a container pair, a crate tower) into scenes/hub2_dressing_src.tscn.
#   godot --headless --path . --script tools/gen_hub2_c_cover.gd
# Re-runnable: it replaces C/Cover and the crane's skip list, and touches nothing else in C (the room
# generator tools/gen_hub2_dressing.gd must NOT regenerate C once this exists: "C" is in its LOCKED list).
# Then bake: powershell -ExecutionPolicy Bypass -File tools/godot_bg.ps1 --script tools/bake_hub2_dressing.gd
# (a windowed bake: a headless one saves empty container MultiMeshes).
#
# Every piece is shape-checked against hub2.glb AND the rest of room C's dressing (a copy of C is added to
# the physics world), against earlier cover, and against the keep-clear zones: the 4 m lane from the west
# entrance to the ramp foot, the entrance mouth and the ramp foot. Seeded and deterministic.

const SCENE := "res://scenes/hub2_dressing_src.tscn"
const SEED := 20261115
const WORLD_SCALE := 0.6
const WEAR := 0.8
const FY := 30.95
const ROOM := Rect2(70.5, -135.5, 40.5, 49.0)   # x, z, w, d: the same rect the room generator uses
## Keep-clear (world x, z): the lane runs entrance -> ramp foot, LANE_HALF each side of the line.
const ENTRANCE := Vector2(70.5, -108.0)
const RAMP_FOOT := Vector2(104.0, -100.0)
const LANE_HALF := 2.0
const ENTRANCE_R := 6.5
## The flat in front of the ramp, plus the ramp itself.
const FOOT_RECT := Rect2(98.0, -110.0, 15.0, 14.0)
const CLUSTER_GAP := 7.0
const EYE := 1.7
const LONG_SIGHT := 20.0

var _phys: Node3D
var _dress: Node3D
var _ss: PhysicsDirectSpaceState3D
var _frames := 0
var _rng := RandomNumberGenerator.new()
var _root: Node
var _c: Node3D
var _cover: Node3D
var _container_scene: PackedScene
## Cover boxes placed so far (AABB), cluster centres, and the full-height ones for the sightline score.
var _placed: Array[AABB] = []
var _centres: Array[Vector2] = []
var _tall: Array[AABB] = []
var _counts := {}
var _sight_rays: Array = []


func _initialize() -> void:
	_phys = Node3D.new()
	var glb: Node3D = (load("res://assets/hub2.glb") as PackedScene).instantiate()
	glb.scale = Vector3.ONE * WORLD_SCALE
	_phys.add_child(glb)
	root.add_child(_phys)
	_container_scene = load("res://scenes/cargo_container.tscn")
	# A copy of room C's existing dressing, with colliders, so shape queries see what is already there.
	var src := (load(SCENE) as PackedScene).instantiate() as Node3D
	for ch in src.get_children():
		if ch.name != &"C":
			src.remove_child(ch)
			ch.free()
	var old := src.get_node("C").get_node_or_null("Cover")
	if old != null:
		old.get_parent().remove_child(old)
		old.free()
	_dress = src
	root.add_child(_dress)


func _physics_process(_d: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	_ss = _phys.get_world_3d().direct_space_state
	_root = (load(SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	_c = _root.get_node("C") as Node3D
	var old := _c.get_node_or_null("Cover")
	if old != null:
		_c.remove_child(old)
		old.free()
	_rng.seed = SEED
	_fix_crane()
	_cover = Node3D.new()
	_cover.name = "Cover"
	_c.add_child(_cover)
	_cover.owner = _root
	_cover.set_meta(&"lane_from", ENTRANCE)
	_cover.set_meta(&"lane_to", RAMP_FOOT)
	_cover.set_meta(&"lane_half", LANE_HALF)
	_cover.set_meta(&"entrance_r", ENTRANCE_R)
	_cover.set_meta(&"foot_rect", FOOT_RECT)
	_sight_setup()
	var before := _sight_long()
	_build_full(2)
	_build_piles(3)
	_build_runs(5)
	print("cover: %s" % _counts)
	print("sightlines over %d m at eye height: %d of %d rays before, %d after" % [int(LONG_SIGHT), before, _sight_rays.size(), _sight_long()])
	var out := PackedScene.new()
	var err := out.pack(_root)
	if err == OK:
		err = ResourceSaver.save(out, SCENE)
	print("saved %s: %s" % [SCENE, error_string(err)])
	_root.free()
	return true


# -- crane -----------------------------------------------------------------------------------------

## Skip every runway column whose footprint stands in the map.
func _fix_crane() -> void:
	var crane := _c.get_node("Cranes/BridgeCrane") as Hub2Crane
	var skip := PackedVector2Array()
	for slot in crane.column_slots():
		var x := crane.position.x + slot.x * crane.span * 0.5
		var z := crane.position.z + slot.y
		var h := crane.rail_height - 0.8
		var hit := _hits_map(Vector3(x, crane.position.y + 0.25 + (h - 0.25) * 0.5, z), Vector3(1.2, h - 0.25, 1.2), 0.0)
		print("crane column side %+d z %.2f (world %.2f, %.2f): %s" % [int(slot.x), slot.y, x, z, "IN THE MAP, skipped" if hit else "clear"])
		if hit:
			skip.append(slot)
	crane.skip_columns = skip


# -- queries ---------------------------------------------------------------------------------------

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	return _ss.intersect_ray(PhysicsRayQueryParameters3D.create(a, b))


func _floor(p: Vector3, depth := 3.0) -> float:
	var r := _ray(p, p + Vector3.DOWN * depth)
	if r.is_empty() or (r["normal"] as Vector3).y < 0.8:
		return NAN
	return (r["position"] as Vector3).y


func _shape_hits(centre: Vector3, size: Vector3, yaw: float) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = size - Vector3.ONE * 0.1
	q.shape = bs
	q.transform = Transform3D(Basis(Vector3.UP, yaw), centre)
	return _ss.intersect_shape(q, 32)


func _hits_map(centre: Vector3, size: Vector3, yaw: float) -> bool:
	for h: Dictionary in _shape_hits(centre, size, yaw):
		if _phys.is_ancestor_of(h["collider"] as Node):
			return true
	return false


func _aabb(centre: Vector3, size: Vector3, yaw: float) -> AABB:
	var b := Basis(Vector3.UP, yaw)
	var ext := (b.x * size.x * 0.5).abs() + (b.y * size.y * 0.5).abs() + (b.z * size.z * 0.5).abs()
	return AABB(centre - ext, ext * 2.0)


## Keep-clear zones: the lane, the entrance mouth, the ramp foot. `r` = the piece's half footprint.
func _in_keep_clear(p: Vector2, r: float) -> bool:
	if Geometry2D.get_closest_point_to_segment(p, ENTRANCE, RAMP_FOOT).distance_to(p) < LANE_HALF + r:
		return true
	if p.distance_to(ENTRANCE) < ENTRANCE_R + r:
		return true
	return FOOT_RECT.grow(r).has_point(p)


## A box standing on the floor at p (bottom centre), size, yaw: on flat floor, clear of the map, the
## existing dressing, earlier cover and the keep-clear zones.
func _fits(p: Vector3, size: Vector3, yaw: float) -> bool:
	if not ROOM.grow(-0.4).has_point(Vector2(p.x, p.z)):
		return false
	var r := maxf(size.x, size.z) * 0.5
	if _in_keep_clear(Vector2(p.x, p.z), r):
		return false
	var b := Basis(Vector3.UP, yaw)
	for sx in [-0.45, 0.0, 0.45]:
		for sz in [-0.45, 0.0, 0.45]:
			var f := _floor(p + b * Vector3(sx * size.x, 0, sz * size.z) + Vector3.UP * 1.0, 2.5)
			if is_nan(f) or absf(f - FY) > 0.2:
				return false
	var centre := p + Vector3(0, size.y * 0.5 + 0.05, 0)
	var mine := _aabb(centre, size, yaw)
	for a in _placed:
		if a.grow(0.02).intersects(mine):
			return false
	return _shape_hits(centre, size, yaw).is_empty()


func _reserve(p: Vector3, size: Vector3, yaw: float, tall := false) -> void:
	var a := _aabb(p + Vector3(0, size.y * 0.5, 0), size, yaw)
	_placed.append(a)
	if tall:
		_tall.append(a)


func _spaced(p: Vector2) -> bool:
	for c in _centres:
		if c.distance_to(p) < CLUSTER_GAP:
			return false
	return true


func _count(key: String) -> void:
	_counts[key] = int(_counts.get(key, 0)) + 1


# -- node makers -----------------------------------------------------------------------------------

func _own(n: Node3D) -> Node3D:
	_cover.add_child(n)
	n.owner = _root
	return n


func _xf(p: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), p)


func _prop(kind: Hub2Prop.Kind, xf: Transform3D, variant: int, length := 2.0) -> void:
	var p := Hub2Prop.new()
	p.name = "%s%d" % [Hub2Prop.Kind.keys()[kind].to_pascal_case(), int(_counts.get(Hub2Prop.Kind.keys()[kind], 0))]
	p.kind = kind
	p.variant = variant
	p.prop_seed = _rng.randi() % 9973
	p.wear = WEAR
	p.length = length
	p.transform = xf
	_own(p)
	_count(Hub2Prop.Kind.keys()[kind])


func _container(xf: Transform3D) -> void:
	var c: CargoContainer = _container_scene.instantiate()
	c.name = "Container%d" % int(_counts.get("Container", 0))
	var palette := [CargoContainer.Palette.BROWN, CargoContainer.Palette.BLUE, CargoContainer.Palette.GREY,
		CargoContainer.Palette.TEAL, CargoContainer.Palette.ORANGE_RED, CargoContainer.Palette.BLACK]
	c.palette = palette[_rng.randi() % palette.size()]
	c.wear = WEAR
	c.wear_seed = _rng.randi() % 4
	c.transform = xf
	_own(c)
	_count("Container")


func _candidate(margin := 3.0) -> Vector2:
	return Vector2(_rng.randf_range(ROOM.position.x + margin, ROOM.end.x - margin),
		_rng.randf_range(ROOM.position.y + margin, ROOM.end.y - margin))


## Mostly wall-aligned, a little off.
func _yaw() -> float:
	return (0.0 if _rng.randf() < 0.5 else PI * 0.5) + _rng.randf_range(-0.35, 0.35)


# -- clusters --------------------------------------------------------------------------------------

## Full-height cover: the first is a container pair in an L, the second a tall crate stack. Each goes
## where it cuts the most long sightlines.
func _build_full(count: int) -> void:
	for i in count:
		var best_score := 1 << 30
		var best: Dictionary = {}
		for k in 90:
			var c := _candidate(5.0)
			if not _spaced(c):
				continue
			var yaw := _yaw()
			var plan := _plan_container_l(Vector3(c.x, FY, c.y), yaw) if i == 0 else _plan_tower(Vector3(c.x, FY, c.y), yaw)
			if plan.is_empty():
				continue
			var score := _sight_long(plan["boxes"])
			if score < best_score:
				best_score = score
				best = plan
		if best.is_empty():
			push_warning("gen_hub2_c_cover: no spot for full-height cluster %d" % i)
			continue
		for b: Dictionary in best["pieces"]:
			if b["type"] == "container":
				_container(b["xf"])
			else:
				_prop(b["kind"], b["xf"], b["variant"])
		for b: Array in best["reserve"]:
			_reserve(b[0], b[1], b[2], true)
		_centres.append(best["centre"])
		_count("full")


func _plan_container_l(p: Vector3, yaw: float) -> Dictionary:
	var size := Vector3(CargoContainer.LENGTH, CargoContainer.HEIGHT, CargoContainer.WIDTH)
	var b := Basis(Vector3.UP, yaw)
	var p2 := p + b * Vector3(CargoContainer.LENGTH * 0.5 + CargoContainer.WIDTH * 0.5 + 0.5, 0, CargoContainer.LENGTH * 0.5 - CargoContainer.WIDTH * 0.5 + 0.4)
	var yaw2 := yaw + PI * 0.5
	var n0 := _placed.size()
	var ok := _fits(p, size, yaw)
	if ok:
		_reserve(p, size, yaw)
		ok = _fits(p2, size, yaw2)
	_placed.resize(n0)
	if not ok:
		return {}
	return {
		"centre": Vector2(p.x, p.z),
		"pieces": [{"type": "container", "xf": _xf(p, yaw)}, {"type": "container", "xf": _xf(p2, yaw2)}],
		"reserve": [[p, size, yaw], [p2, size, yaw2]],
		"boxes": [_aabb(p + Vector3(0, size.y * 0.5, 0), size, yaw), _aabb(p2 + Vector3(0, size.y * 0.5, 0), size, yaw2)],
	}


## Two columns of three wooden crates (2.7 m) and a locker beside them.
func _plan_tower(p: Vector3, yaw: float) -> Dictionary:
	var b := Basis(Vector3.UP, yaw)
	var size := Vector3(3.4, 2.8, 1.1)
	var mid := p + b * Vector3(0.45, 0, 0)
	if not _fits(mid, size, yaw):
		return {}
	var pieces: Array = []
	for cx in [-0.65, 0.65]:
		for lvl in 3:
			var at := p + b * Vector3(cx + _rng.randf_range(-0.04, 0.04), 0, _rng.randf_range(-0.03, 0.03)) + Vector3(0, lvl * 0.9, 0)
			pieces.append({"type": "prop", "kind": Hub2Prop.Kind.CRATE_WOOD, "variant": 1, "xf": _xf(at, yaw + _rng.randf_range(-0.05, 0.05))})
	pieces.append({"type": "prop", "kind": Hub2Prop.Kind.CRATE_METAL, "variant": 1, "xf": _xf(p + b * Vector3(1.7, 0, 0), yaw + 0.05)})
	return {
		"centre": Vector2(p.x, p.z),
		"pieces": pieces,
		"reserve": [[mid, size, yaw]],
		"boxes": [_aabb(mid + Vector3(0, 1.4, 0), size, yaw)],
	}


## Piles of crates, pallet loads and a metal chest, one or two high.
func _build_piles(count: int) -> void:
	var made := 0
	var tries := 0
	while made < count and tries < 600:
		tries += 1
		var c := _candidate(3.5)
		if not _spaced(c):
			continue
		var yaw := _yaw()
		var b := Basis(Vector3.UP, yaw)
		var cells := [Vector3(-0.9, 0, 0), Vector3(0.9, 0, 0), Vector3(0, 0, 1.3), Vector3(0, 0, -1.3)]
		var placed := 0
		var plan: Array = []
		var n0 := _placed.size()
		for i in cells.size():
			var at := Vector3(c.x, FY, c.y) + b * (cells[i] as Vector3)
			var roll := _rng.randf()
			var y := yaw + _rng.randf_range(-0.18, 0.18)
			if i < 2:
				if roll < 0.5:
					plan.append(_pile_piece(at, y, Hub2Prop.Kind.CRATE_WOOD, 1, Vector3(1.2, 0.9, 1.0), true))
				elif roll < 0.8:
					plan.append(_pile_piece(at, y, Hub2Prop.Kind.PALLET, 1 + _rng.randi() % 2, Vector3(1.2, 1.5, 1.0), false))
				else:
					plan.append(_pile_piece(at, y, Hub2Prop.Kind.CRATE_WOOD, 0, Vector3(0.8, 0.8, 0.8), true))
			else:
				plan.append(_pile_piece(at, y, Hub2Prop.Kind.CRATE_METAL, 2, Vector3(1.6, 1.0, 1.0), true))
		var kept: Array = []
		for d: Dictionary in plan:
			if _fits(d["at"], d["size"], d["yaw"]):
				_reserve(d["at"], d["size"], d["yaw"])
				kept.append(d)
				placed += 1
		_placed.resize(n0)
		if placed < 3:
			continue
		for d: Dictionary in kept:
			_reserve(d["at"], d["size"], d["yaw"])
			_prop(d["kind"], _xf(d["at"], d["yaw"]), d["variant"])
			if d["stack"] and _rng.randf() < 0.55:
				var top: Vector3 = (d["at"] as Vector3) + Vector3(0, (d["size"] as Vector3).y, 0)
				_prop(Hub2Prop.Kind.CRATE_WOOD, _xf(top, d["yaw"] + _rng.randf_range(-0.12, 0.12)), 0)
				var a := _placed.pop_back() as AABB
				a.size.y += 0.8
				_placed.append(a)
		_centres.append(c)
		_count("pile")
		made += 1
	if made < count:
		push_warning("gen_hub2_c_cover: only %d of %d crate piles fitted" % [made, count])


func _pile_piece(at: Vector3, y: float, kind: Hub2Prop.Kind, variant: int, size: Vector3, stack: bool) -> Dictionary:
	return {"at": at, "yaw": y, "kind": kind, "variant": variant, "size": size, "stack": stack}


## Runs of two or three jersey barriers end to end, now and then with a plate shield at one end.
func _build_runs(count: int) -> void:
	var made := 0
	var tries := 0
	var piece := 3.0
	while made < count and tries < 800:
		tries += 1
		var c := _candidate(3.0)
		if not _spaced(c):
			continue
		var yaw := _yaw()
		var b := Basis(Vector3.UP, yaw)
		var n := 2 + _rng.randi() % 2
		var striped := _rng.randf() < 0.4
		var plan: Array = []
		for i in n:
			var off := (i - (n - 1) * 0.5) * (piece + 0.2)
			plan.append({"at": Vector3(c.x, FY, c.y) + b * Vector3(off, 0, 0), "yaw": yaw + _rng.randf_range(-0.03, 0.03),
				"kind": Hub2Prop.Kind.JERSEY_BARRIER, "variant": 1 if (striped and i % 2 == 0) or _rng.randf() < 0.15 else 0,
				"size": Vector3(piece, 1.1, 0.6)})
		if _rng.randf() < 0.75:
			var end := (n * 0.5) * (piece + 0.2) + 1.5
			var turn := _rng.randf_range(-0.5, 0.5)
			plan.append({"at": Vector3(c.x, FY, c.y) + b * Vector3(end, 0, 0.5), "yaw": yaw + turn,
				"kind": Hub2Prop.Kind.PLATE_SHIELD, "variant": _rng.randi() % 2, "size": Vector3(2.1, 1.12, 0.6)})
		var n0 := _placed.size()
		var ok := true
		var keep: Array = []
		for d: Dictionary in plan:
			if _fits(d["at"], d["size"], d["yaw"]):
				_reserve(d["at"], d["size"], d["yaw"])
				keep.append(d)
			elif d["kind"] == Hub2Prop.Kind.JERSEY_BARRIER:
				ok = false
				break
			else:
				print("  shield left out (does not fit) near ", c)
		_placed.resize(n0)
		if not ok:
			continue
		for d: Dictionary in keep:
			_reserve(d["at"], d["size"], d["yaw"])
			_prop(d["kind"], _xf(d["at"], d["yaw"]), d["variant"], piece)
		_centres.append(c)
		_count("run")
		made += 1
	if made < count:
		push_warning("gen_hub2_c_cover: only %d of %d barrier runs fitted" % [made, count])


# -- sightlines ------------------------------------------------------------------------------------
# Eye-height rays from a grid of floor points in 16 directions. The first distance of each comes from the
# physics world (walls, racking, existing containers); full-height cover is cut in analytically.

func _sight_setup() -> void:
	_sight_rays.clear()
	var x := ROOM.position.x + 3.0
	while x < ROOM.end.x - 2.0:
		var z := ROOM.position.y + 3.0
		while z < ROOM.end.y - 2.0:
			var o := Vector3(x, FY + EYE, z)
			var f := _floor(Vector3(x, FY + 1.0, z), 2.5)
			if not is_nan(f) and absf(f - FY) < 0.2 and _shape_hits(Vector3(x, FY + 1.0, z), Vector3(0.6, 1.8, 0.6), 0.0).is_empty():
				for k in 16:
					var a := TAU * k / 16.0
					var dir := Vector3(cos(a), 0, sin(a))
					var hit := _ray(o, o + dir * 70.0)
					var d := 70.0 if hit.is_empty() else (hit["position"] as Vector3).distance_to(o)
					_sight_rays.append([o, dir, d])
			z += 4.0
		x += 4.0


## Rays still longer than LONG_SIGHT with `extra` (cover about to be placed) and everything tall placed.
func _sight_long(extra: Array = []) -> int:
	var n := 0
	for r: Array in _sight_rays:
		var d: float = r[2]
		if d <= LONG_SIGHT:
			continue
		for a: AABB in _tall:
			d = minf(d, _ray_aabb_xz(r[0], r[1], a, d))
		for a: AABB in extra:
			d = minf(d, _ray_aabb_xz(r[0], r[1], a, d))
		if d > LONG_SIGHT:
			n += 1
	return n


## Distance along a horizontal ray to a full-height box (slab test on x and z), or `limit`.
static func _ray_aabb_xz(o: Vector3, dir: Vector3, a: AABB, limit: float) -> float:
	var t0 := 0.0
	var t1 := limit
	for ax in [0, 2]:
		var lo: float = a.position[ax]
		var hi: float = a.end[ax]
		if absf(dir[ax]) < 1e-6:
			if o[ax] < lo or o[ax] > hi:
				return limit
		else:
			var ta := (lo - o[ax]) / dir[ax]
			var tb := (hi - o[ax]) / dir[ax]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
	if o.y > a.end.y or t0 > t1:
		return limit
	return t0
