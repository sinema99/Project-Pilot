extends SceneTree

# Writes hub2's storage-facility dressing into scenes/hub2_dressing_src.tscn (docs/specs/hub2-storage.md).
#   godot --headless --path . --script tools/gen_hub2_dressing.gd
# The game loads the BAKED form, scenes/hub2_dressing.scn: re-run tools/bake_hub2_dressing.gd after this
# (docs/specs/hub2-load-time.md).
#
# Rooms (world metres, Map scale 0.6; see docs/specs/hub2-plan.png):
#   A  storage hall under the -164 roof slab, floor -273, shaft mouth overhead, sealed hangar door in the south bay -> Dressing/A
#   B  tall hall west of the shaft, floor 22, ceiling 69                -> Dressing/B
#   C  low room east of the shaft, floor 31, ceiling 47                 -> Dressing/C
#   halls: everything else walkable above y 25 (wall kit, lamps) -> Dressing/Halls
#   pipes: NOT here, tools/gen_hub2_pipes.gd -> Dressing/Pipes (run it after this)
#
# Each room's group is wiped and rebuilt from the tables + seeded scatter below, so the output is
# the same every run. Once the user hand-edits a room, put its name in LOCKED and it is left alone.
#
# How it finds the room: a physics copy of hub2.glb (collision only) for floor / wall / clearance
# rays. Every placement is
# checked against the map and against what was already placed (an AABB list), so nothing sits in a
# wall, a door or another prop.

const SCENE := "res://scenes/hub2_dressing_src.tscn"
## C is locked since 2026-11-15: room C now carries hand-built cover and a crane fix (tools/gen_hub2_c_cover.gd).
const LOCKED: Array[String] = ["C"]
const SEED := 20261114
const WORLD_SCALE := 0.6
const WEAR := 0.8

const ROOM_A := Rect2(-94, -430, 196, 308)     # x, z, w, d
const ROOM_B := Rect2(-161, -147, 99, 189)
const ROOM_C := Rect2(70.5, -135.5, 40.5, 49.0)
## Room A (2026-11-14 correction): the enclosed hall under the -164 roof slab.
const A_FLOOR := -273.0
const A_CEILING := -164.0
## The hollow shaft's axis; its mouth (radius 35-49 m) opens into A's ceiling over this.
const SHAFT_AXIS := Vector3(4, -273, -232)
## Where a drop down the D shaft lands (north rim of the mouth): inside the open boss floor, so it stays clear.
const A_LANDING := AABB(Vector3(-16, -278, -208), Vector3(32, 20, 36))
## The lit patch under the mouth where everything green grows.
const A_ISLAND := Rect2(-30, -268, 68, 58)
## Room A storage hall layout (2026-11-14): distances u are from the hall's centre line (x = 0).
const A_BLOCK_Z0 := -424.0
const A_BLOCK_Z1 := -128.0
const A_ROW_PITCH := CargoContainer.WIDTH + 0.3
const A_COL_PITCH := CargoContainer.LENGTH + 0.3
## Outer edge of container block A (4 rows, 3-6 high) and of block B (3 rows, 1-3 high); aisle between them.
const A_BLOCK_A_U := 88.3
const A_BLOCK_B_U := 73.1
## Painted bay line at the edge of the open boss floor (|x| < this is bare).
const A_BAY_LINE_U := 63.4
## Wall crane runway height above the floor and how far a jib reaches into the hall.
const A_RAIL_H := 76.0
const A_JIB_REACH := 34.0
## z of the pillars in the side walls (bulkhead lamps).
const A_ARCH_Z: Array[float] = [-412.0, -358.0, -298.0, -226.0, -142.0]

var _phys: Node3D
var _ss: PhysicsDirectSpaceState3D
var _frames := 0
var _rng := RandomNumberGenerator.new()
var _placed: Array[AABB] = []
var _root: Node
var _group: Node3D
var _counts := {}
var _container_scene: PackedScene
var _lit_lamps := 0
var _overlaps := 0


func _initialize() -> void:
	_phys = Node3D.new()
	var glb: Node3D = (load("res://assets/hub2.glb") as PackedScene).instantiate()
	glb.scale = Vector3.ONE * WORLD_SCALE
	_phys.add_child(glb)
	root.add_child(_phys)
	_container_scene = load("res://scenes/cargo_container.tscn")


func _physics_process(_d: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_ss = _phys.get_world_3d().direct_space_state
	var packed: PackedScene = load(SCENE)
	_root = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	# The source scene's root IS the Dressing node (rooms A, B, C, Halls are its children).
	var dressing := _root as Node3D
	for room in ["B", "C", "A", "Halls"]:
		if room in LOCKED:
			print("%s locked, kept" % room)
			_keep_obstacles(dressing.get_node_or_null(room))
			continue
		var g := dressing.get_node_or_null(room)
		if g != null:
			dressing.remove_child(g)
			g.free()
		_group = Node3D.new()
		_group.name = room
		dressing.add_child(_group)
		_group.owner = _root
		_rng.seed = SEED + hash(room)
		_counts.clear()
		match room:
			"A": _room_a()
			"B": _room_b()
			"C": _room_c()
			"Halls": _halls()
		print("%s: %s" % [room, _counts])
	# No draw-call merge: tried 2026-11-14 (Hub2PropBatch, 40 m cells) - draws 592 -> 99 but triangles
	# doubled (whole cells drawn) and every view got slower (B aisle 123 -> 98 fps). Unmerged B is 123+ fps.
	var old_batch := dressing.get_node_or_null("Batch")
	if old_batch != null:
		dressing.remove_child(old_batch)
		old_batch.free()
	var out := PackedScene.new()
	var err := out.pack(_root)
	if err == OK:
		err = ResourceSaver.save(out, SCENE)
	print("saved %s: %s (lit lamps %d, overlaps %d)" % [SCENE, error_string(err), _lit_lamps, _overlaps])
	_root.free()
	return true


# -- queries ----------------------------------------------------------------------------------

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	return _ss.intersect_ray(PhysicsRayQueryParameters3D.create(a, b))


## Floor height under p (searching down from p.y), or NAN.
func _floor(p: Vector3, depth := 6.0) -> float:
	var r := _ray(p, p + Vector3.DOWN * depth)
	if r.is_empty() or (r["normal"] as Vector3).y < 0.8:
		return NAN
	return (r["position"] as Vector3).y


## True when a box (centre, size, yaw) is clear of the map and of everything placed.
func _clear(centre: Vector3, size: Vector3, yaw := 0.0, map_only := false) -> bool:
	var aabb := _aabb(centre, size, yaw)
	if not map_only:
		for a in _placed:
			if a.grow(-0.05).intersects(aabb):
				return false
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = size - Vector3.ONE * 0.1
	q.shape = bs
	q.transform = Transform3D(Basis(Vector3.UP, yaw), centre)
	return _ss.intersect_shape(q, 1).is_empty()


func _aabb(centre: Vector3, size: Vector3, yaw: float) -> AABB:
	var b := Basis(Vector3.UP, yaw)
	var ext := (b.x * size.x * 0.5).abs() + (b.y * size.y * 0.5).abs() + (b.z * size.z * 0.5).abs()
	return AABB(centre - ext, ext * 2.0)


## True when the footprint (centre on the floor, size, yaw) has floor under all four corners at ~y.
func _flat(centre: Vector3, size: Vector3, yaw: float, tol := 0.25) -> bool:
	var b := Basis(Vector3.UP, yaw)
	for sx in [-0.45, 0.45]:
		for sz in [-0.45, 0.45]:
			var p := centre + b * Vector3(sx * size.x, 0, sz * size.z)
			var f := _floor(p + Vector3.UP * 1.0, 3.0)
			if is_nan(f) or absf(f - centre.y) > tol:
				return false
	return true


func _keep_obstacles(g: Node) -> void:
	if g == null:
		return
	for n in g.find_children("*", "Node3D", true, false):
		_placed.append(AABB((n as Node3D).position - Vector3.ONE, Vector3.ONE * 2.0))


# -- node makers --------------------------------------------------------------------------------

func _own(n: Node3D, parent: Node3D = null) -> Node3D:
	var p := _group if parent == null else parent
	p.add_child(n)
	n.owner = _root
	return n


func _sub(name: String) -> Node3D:
	var g := _group.get_node_or_null(name) as Node3D
	if g == null:
		g = Node3D.new()
		g.name = name
		_own(g)
	return g


func _count(key: String) -> void:
	_counts[key] = int(_counts.get(key, 0)) + 1


## A prop at `xf`. `size` (if given) registers its footprint so later props avoid it.
func _prop(kind: Hub2Prop.Kind, xf: Transform3D, variant := 0, sub := "", size := Vector3.ZERO,
		powered := false, length := 2.0) -> Hub2Prop:
	var p := Hub2Prop.new()
	p.name = "%s%d" % [Hub2Prop.Kind.keys()[kind].to_pascal_case(), int(_counts.get(Hub2Prop.Kind.keys()[kind], 0))]
	p.kind = kind
	p.variant = variant
	p.prop_seed = _rng.randi() % 9973
	p.wear = WEAR
	p.powered = powered
	p.length = length
	p.transform = xf
	_own(p, _sub(sub) if sub != "" else null)
	_count(Hub2Prop.Kind.keys()[kind])
	if size != Vector3.ZERO:
		# Props only (wall kit sits against the map on purpose).
		var mine := _aabb(xf.origin + Vector3(0, size.y * 0.5 + 0.1, 0), size, xf.basis.get_euler().y)
		if _placed.any(func(a: AABB) -> bool: return a.grow(-0.05).intersects(mine)):
			push_warning("gen_hub2_dressing: %s at %s overlaps something already placed" % [p.name, xf.origin])
			_overlaps += 1
		_placed.append(_aabb(xf.origin + Vector3(0, size.y * 0.5, 0), size, xf.basis.get_euler().y))
	if p.is_lit_lamp():
		_lit_lamps += 1
	return p


const PALETTE_MUTED := [CargoContainer.Palette.BROWN, CargoContainer.Palette.BLUE, CargoContainer.Palette.GREY,
	CargoContainer.Palette.TEAL, CargoContainer.Palette.ORANGE_RED, CargoContainer.Palette.BLACK]
const PALETTE_LOUD := [CargoContainer.Palette.ORANGE, CargoContainer.Palette.PALE_YELLOW, CargoContainer.Palette.CYAN]

func _palette() -> CargoContainer.Palette:
	if _rng.randf() < 0.12:
		return PALETTE_LOUD[_rng.randi() % PALETTE_LOUD.size()]
	return PALETTE_MUTED[_rng.randi() % PALETTE_MUTED.size()]


func _container(xf: Transform3D, sub := "Containers", register := true) -> CargoContainer:
	var c: CargoContainer = _container_scene.instantiate()
	c.name = "Container%d" % int(_counts.get("container", 0))
	c.palette = _palette()
	c.wear = WEAR
	c.wear_seed = _rng.randi() % 4
	c.transform = xf
	_own(c, _sub(sub))
	_count("container")
	if register:
		_placed.append(_world_box_aabb(xf, Vector3(CargoContainer.LENGTH, CargoContainer.HEIGHT, CargoContainer.WIDTH)))
	return c


## AABB of a bottom-centred box of `size` under transform xf.
static func _world_box_aabb(xf: Transform3D, size: Vector3) -> AABB:
	var a := AABB(xf * Vector3(0, size.y * 0.5, 0), Vector3.ZERO)
	for sx in [-0.5, 0.5]:
		for sy in [0.0, 1.0]:
			for sz in [-0.5, 0.5]:
				a = a.expand(xf * Vector3(sx * size.x, sy * size.y, sz * size.z))
	return a


func _yaw_xf(p: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), p)


# -- shared dressing -----------------------------------------------------------------------------

## A neat pallet stack / crate cluster at p.
func _crate_cluster(p: Vector3, yaw: float, messy: bool, sub := "Crates") -> void:
	var b := Basis(Vector3.UP, yaw)
	var n := _rng.randi_range(2, 5)
	for i in n:
		var off := b * Vector3((i % 3) * 1.35 - 1.35, 0, int(i / 3) * 1.15)
		var at := p + off
		var kind_roll := _rng.randf()
		var y := yaw + (_rng.randf_range(-0.6, 0.6) if messy else _rng.randf_range(-0.03, 0.03))
		var f := _floor(at + Vector3.UP * 1.5, 4.0)
		if is_nan(f):
			continue
		at.y = f
		if kind_roll < 0.35:
			if _clear(at + Vector3(0, 0.8, 0), Vector3(1.2, 1.5, 1.0), y):
				_prop(Hub2Prop.Kind.PALLET, _yaw_xf(at, y), 1 + _rng.randi() % 2, sub, Vector3(1.2, 1.5, 1.0))
		elif kind_roll < 0.7:
			var v := _rng.randi() % 3
			var hgt := [0.8, 0.9, 0.8][v] as float
			if _clear(at + Vector3(0, 0.5, 0), Vector3(2.0, 1.0, 1.0), y):
				_prop(Hub2Prop.Kind.CRATE_WOOD, _yaw_xf(at, y), v, sub, Vector3(1.2, hgt, 1.0))
				if not messy and _rng.randf() < 0.5:
					_prop(Hub2Prop.Kind.CRATE_WOOD, _yaw_xf(at + Vector3(0, hgt, 0), y + _rng.randf_range(-0.05, 0.05)), 0, sub)
		elif kind_roll < 0.85:
			if _clear(at + Vector3(0, 0.5, 0), Vector3(1.6, 1.0, 1.0), y):
				_prop(Hub2Prop.Kind.CRATE_METAL, _yaw_xf(at, y), [0, 2][_rng.randi() % 2], sub, Vector3(1.6, 1.0, 1.0))
		else:
			if _clear(at + Vector3(0, 0.8, 0), Vector3(0.6, 1.5, 0.45), y):
				_prop(Hub2Prop.Kind.TOTE, _yaw_xf(at, y), 3 if not messy else _rng.randi() % 3, sub, Vector3(0.6, 1.5, 0.45))
	if messy:
		# A few strays tipped over.
		for i in _rng.randi_range(1, 3):
			var at := p + b * Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(1.5, 4))
			var f := _floor(at + Vector3.UP * 1.5, 4.0)
			if is_nan(f) or not _clear(Vector3(at.x, f + 0.5, at.z), Vector3(1.0, 1.0, 1.0)):
				continue
			var tip := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5 if _rng.randf() < 0.5 else 0.0)
			_prop(Hub2Prop.Kind.CRATE_WOOD, Transform3D(tip, Vector3(at.x, f + (0.4 if tip.y.y < 0.5 else 0.0), at.z)), [0, 3][_rng.randi() % 2], sub, Vector3(1, 1, 1))


## One racking bay at p (back against a wall when yaw faces into the room) filled with crates.
func _rack_bay(p: Vector3, yaw: float, bent := false, sub := "Racking") -> void:
	var xf := _yaw_xf(p, yaw)
	_prop(Hub2Prop.Kind.RACKING, xf, 1 if bent else 0, sub, Vector3(2.8, 5.4, 1.2))
	for li in Hub2PropBuild.RACK_LEVELS.size():
		var ly: float = Hub2PropBuild.RACK_LEVELS[li]
		for slot in 2:
			var roll := _rng.randf()
			if roll < 0.25:
				continue
			var local := Vector3(-0.65 + slot * 1.3, ly + (0.0 if li > 0 else 0.0), 0)
			if bent and li == 1:
				local.y -= 0.2
			var at := xf * local
			if roll < 0.6:
				_prop(Hub2Prop.Kind.PALLET, _yaw_xf(at, yaw + PI * 0.5), 1 + _rng.randi() % 2, sub)
			elif roll < 0.85:
				_prop(Hub2Prop.Kind.CRATE_WOOD, _yaw_xf(at, yaw + _rng.randf_range(-0.1, 0.1)), _rng.randi() % 2, sub)
			else:
				_prop(Hub2Prop.Kind.TOTE, _yaw_xf(at, yaw), 3, sub)
	if bent:
		# What fell off it.
		for i in 3:
			var at := xf * Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(1.0, 2.6))
			var f := _floor(at + Vector3.UP * 2.0, 4.0)
			if not is_nan(f):
				var tip := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.FORWARD, _rng.randf_range(-0.4, 0.4))
				_prop(Hub2Prop.Kind.CRATE_WOOD, Transform3D(tip, Vector3(at.x, f, at.z)), [0, 3][i % 2], sub)


## Walls of a rectangle room: inward-facing spots every `pitch` m along each wall at floor y.
## Returns [{p (on the wall at floor y), yaw (prop +Z points into the room), wall}] where the wall
## is solid from the floor to 3 m (no doors).
func _wall_spots(rect: Rect2, floor_y: float, pitch: float) -> Array:
	var out: Array = []
	var walls := [
		[Vector3(rect.position.x, 0, 0), Vector3(-1, 0, 0), "W"],
		[Vector3(rect.end.x, 0, 0), Vector3(1, 0, 0), "E"],
		[Vector3(0, 0, rect.position.y), Vector3(0, 0, -1), "N"],
		[Vector3(0, 0, rect.end.y), Vector3(0, 0, 1), "S"],
	]
	for w in walls:
		var d: Vector3 = w[1]
		var along := Vector3(d.z, 0, d.x).abs()
		var start := rect.position.y if along.z > 0.0 else rect.position.x
		var span := rect.size.y if along.z > 0.0 else rect.size.x
		var s := pitch * 0.5
		while s < span:
			var inner := Vector3(rect.get_center().x, floor_y + 1.5, rect.get_center().y)
			if along.z > 0.0:
				inner = Vector3((w[0] as Vector3).x - d.x * 2.0, floor_y + 1.5, start + s)
			else:
				inner = Vector3(start + s, floor_y + 1.5, (w[0] as Vector3).z - d.z * 2.0)
			var hit := _ray(inner, inner + d * 8.0)
			var hit_hi := _ray(inner + Vector3.UP * 1.5, inner + Vector3.UP * 1.5 + d * 8.0)
			if not hit.is_empty() and not hit_hi.is_empty() and absf((hit["normal"] as Vector3).y) < 0.3:
				var wp: Vector3 = hit["position"]
				var n: Vector3 = hit["normal"]
				out.append({"p": Vector3(wp.x, floor_y, wp.z), "yaw": atan2(n.x, n.z), "wall": w[2], "n": n})
			s += pitch
	return out


## Wall-kit item on a wall spot (cabinet, junction box, hose reel, extinguisher, terminal).
func _wall_kit(spot: Dictionary, kind: Hub2Prop.Kind, variant := 0, powered := false, sub := "WallKit") -> void:
	var xf := Transform3D(Basis(Vector3.UP, spot["yaw"]), (spot["p"] as Vector3) + (spot["n"] as Vector3) * 0.02)
	var depth := 0.5
	var w := 1.4 if kind == Hub2Prop.Kind.CABINET else (variant + 1) * 0.95 + 0.4 if kind == Hub2Prop.Kind.TERMINAL else 1.0
	var c := xf * Vector3(0, 1.2, depth * 0.5)
	if not _clear(c, Vector3(w, 2.2, depth), spot["yaw"]):
		return
	_prop(kind, xf, variant, sub, Vector3(w, 2.4, depth + 0.4), powered, 2.5)


func _vines_from(p: Vector3, count: int, max_len: float, sub := "Overgrowth") -> void:
	for i in count:
		var at := p + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
		_prop(Hub2Prop.Kind.VINE, _yaw_xf(at, _rng.randf() * TAU), 0, sub, Vector3.ZERO, false, _rng.randf_range(1.0, max_len))


func _floor_plants(rect: Rect2, y_hint: float, tufts: int, moss: int, shrubs: int, sub := "Overgrowth",
		near_wall := false) -> void:
	for kind_n in [[Hub2Prop.Kind.TUFT, tufts], [Hub2Prop.Kind.MOSS, moss], [Hub2Prop.Kind.SHRUB, shrubs]]:
		var placed := 0
		var tries := 0
		while placed < int(kind_n[1]) and tries < int(kind_n[1]) * 8:
			tries += 1
			var x := _rng.randf_range(rect.position.x, rect.end.x)
			var z := _rng.randf_range(rect.position.y, rect.end.y)
			if near_wall:
				# Hug a random wall.
				match _rng.randi() % 4:
					0: x = rect.position.x + _rng.randf_range(0.3, 2.0)
					1: x = rect.end.x - _rng.randf_range(0.3, 2.0)
					2: z = rect.position.y + _rng.randf_range(0.3, 2.0)
					_: z = rect.end.y - _rng.randf_range(0.3, 2.0)
			var f := _floor(Vector3(x, y_hint + 3.0, z), 8.0)
			if is_nan(f) or absf(f - y_hint) > 4.0:
				continue
			var at := Vector3(x, f, z)
			var k: Hub2Prop.Kind = kind_n[0]
			if k == Hub2Prop.Kind.SHRUB and not _clear(at + Vector3(0, 0.6, 0), Vector3(1.4, 1.0, 1.4)):
				continue
			if k != Hub2Prop.Kind.SHRUB:
				var inside := false
				for a in _placed:
					if a.has_point(at + Vector3(0, 0.3, 0)):
						inside = true
						break
				if inside:
					continue
			_prop(k, _yaw_xf(at, _rng.randf() * TAU), _rng.randi() % 2, sub)
			placed += 1


## Moss on top of a few containers (their roofs collect dirt and seeds).
func _moss_on_containers(chance: float, sub := "Overgrowth") -> void:
	var g := _group.get_node_or_null("Containers")
	if g == null:
		return
	for c in g.get_children():
		var cc := c as CargoContainer
		if cc == null or cc.transform.basis.y.y < 0.95 or _rng.randf() > chance:
			continue
		var top := cc.transform * Vector3(_rng.randf_range(-2, 2), CargoContainer.HEIGHT, 0)
		if _ray(top + Vector3.UP * 0.6, top + Vector3.UP * 0.05).is_empty():
			_prop(Hub2Prop.Kind.MOSS, _yaw_xf(top, _rng.randf() * TAU), _rng.randi() % 2, sub)


# -- room B: the main container yard -------------------------------------------------------------

func _room_b() -> void:
	var fy := 21.78
	# Two bridge cranes on Z runways, twin runway line down the middle.
	# Crane 1's span is 26 (was 42): its east runway at x -74.5 stays outside the control room box on
	# B's east wall (interior x -72.4..-61.8) instead of cutting through its floor (docs/specs/hub2-control-room.md).
	var cranes := [[-134.0, 44.0, -18.0, 4.0, 12.0, 0.0], [-87.5, 26.0, 22.0, -6.0, 19.0, 4.0]]
	var runway := 184.0
	var zc := -52.5
	var ci := 0
	for c in cranes:
		var crane := Hub2Crane.new()
		crane.name = "BridgeCrane%d" % ci
		crane.type = Hub2Crane.Type.BRIDGE
		crane.span = c[1]
		crane.runway_length = runway
		crane.rail_height = 22.0
		crane.column_pitch = 23.0
		crane.bridge_z = c[2]
		crane.trolley_x = c[3]
		crane.hook_drop = c[4]
		crane.dangling = c[5]
		crane.wear = WEAR
		crane.position = Vector3(c[0], fy, zc)
		_own(crane, _sub("Cranes"))
		_count("crane")
		# Columns as obstacles.
		var z := -runway * 0.5
		while z <= runway * 0.5 + 0.01:
			for side in [-1.0, 1.0]:
				_placed.append(AABB(Vector3(c[0] + side * c[1] * 0.5 - 0.7, fy, zc + z - 0.7), Vector3(1.4, 22, 1.4)))
			z += crane.column_pitch
		ci += 1
	# The first crane's spreader hangs off its hook holding nothing; the second is just a hook.
	var hook0 := Vector3(-134.0 + 4.0, fy + 22.0 - 12.0, zc - 18.0)
	_prop(Hub2Prop.Kind.SPREADER, _yaw_xf(hook0 + Vector3(0, -2.2, 0), PI * 0.5), 0, "Cranes", Vector3.ZERO, false, 1.6)

	# Container blocks: under each crane two blocks of 4 wide with a 6 m aisle, three Z blocks of
	# five rows. Containers run along Z (doors north).
	var pitch_x := CargoContainer.WIDTH + 0.35
	var pitch_z := CargoContainer.LENGTH + 0.5
	var z_blocks := [-140.0, -102.0, -64.0]
	for c in cranes:
		var cx: float = c[0]
		for bx in [-1, 1]:
			var x0: float = cx + bx * (3.0 + pitch_x * 2.0) - pitch_x * 1.5
			for zb: float in z_blocks:
				for col in 4:
					for row in 5:
						if _rng.randf() < 0.12:
							continue   # an empty slot
						var x := x0 + col * pitch_x
						var z := zb + pitch_z * 0.5 + row * pitch_z
						var hgt := 1 + int(_rng.randf() < 0.6) + int(_rng.randf() < 0.35)
						var base := Vector3(x, fy, z)
						if not _clear(base + Vector3(0, 1.3, 0), Vector3(CargoContainer.WIDTH, 2.5, CargoContainer.LENGTH)):
							continue
						for level in hgt:
							var yaw := PI * 0.5 + _rng.randf_range(-0.012, 0.012)
							var off := Vector3.ZERO
							if level > 0 and _rng.randf() < 0.07:
								yaw += _rng.randf_range(-0.08, 0.08)   # askew
							if level == hgt - 1 and level > 0 and _rng.randf() < 0.04:
								off = Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(1.8, 2.4) * (1.0 if _rng.randf() < 0.5 else -1.0))
								_count("slid")
							_container(_yaw_xf(base + off + Vector3(0, level * CargoContainer.HEIGHT, 0), yaw))
	# Painted bay lines on the floor: thin yellow strips along each aisle (as flat props would cost a
	# lot of nodes; one BayLines mesh instead).
	_bay_lines(fy, cranes, z_blocks, pitch_x, pitch_z)

	# North end (z 0..40): staging / service area.
	var north := 10.0
	_prop(Hub2Prop.Kind.REACH_STACKER, _yaw_xf(Vector3(-126.0, fy, north + 4.0), 0.3), 0, "Vehicles", Vector3(11, 4, 4))
	for f in [[Vector3(-142.0, fy, 25.0), 1.2, 0], [Vector3(-76.0, fy, 16.0), -2.1, 1]]:
		_prop(Hub2Prop.Kind.FORKLIFT, _yaw_xf(f[0], f[1]), f[2], "Vehicles", Vector3(3.6, 2.3, 1.4))
	_prop(Hub2Prop.Kind.PALLET_JACK, _yaw_xf(Vector3(-128.0, fy, 31.0), 0.8), 0, "Vehicles", Vector3(1.6, 1.2, 0.8))
	# Fuel / charge station and workbench against the north wall.
	var spots := _wall_spots(ROOM_B, fy, 6.0)
	var north_spots := spots.filter(func(s: Dictionary) -> bool: return s["wall"] == "S")
	var west_spots := spots.filter(func(s: Dictionary) -> bool: return s["wall"] == "W")
	var east_spots := spots.filter(func(s: Dictionary) -> bool: return s["wall"] == "E")
	if north_spots.size() > 6:
		var s0: Dictionary = north_spots[2]
		_prop(Hub2Prop.Kind.FUEL_STATION, Transform3D(Basis(Vector3.UP, s0["yaw"]), (s0["p"] as Vector3) + (s0["n"] as Vector3) * 0.9), 0, "Service", Vector3(3.4, 2.2, 1.4))
		var s1: Dictionary = north_spots[4]
		_prop(Hub2Prop.Kind.WORKBENCH, Transform3D(Basis(Vector3.UP, s1["yaw"]), (s1["p"] as Vector3) + (s1["n"] as Vector3) * 0.45), 0, "Service", Vector3(2.2, 2.0, 1.0))
		# Racking along the rest of the north wall.
		var i := 0
		for s in north_spots.slice(7):
			var p: Vector3 = (s["p"] as Vector3) + (s["n"] as Vector3) * 0.7
			if _clear(p + Vector3(0, 2.8, 0), Vector3(2.8, 5.4, 1.2), s["yaw"]):
				_rack_bay(p, s["yaw"], i == 3)
			i += 1
	# Staging crate clusters in the north area, some neat, a messy spill.
	for k in 9:
		var p := Vector3(_rng.randf_range(-155.0, -68.0), fy, _rng.randf_range(2.0, 36.0))
		_crate_cluster(p, _rng.randf() * TAU if k % 3 == 2 else PI * 0.5 * (_rng.randi() % 2), k % 3 == 2)
	# Crates along the bay lines between blocks.
	for k in 14:
		var zb: float = z_blocks[_rng.randi() % z_blocks.size()] - 3.0
		var p := Vector3(_rng.randf_range(-155.0, -68.0), fy, zb)
		_crate_cluster(p, PI * 0.5, _rng.randf() < 0.3)
	# Crane control post: a terminal bank on the east wall, plus a few singles and wall kit.
	if east_spots.size() > 10:
		_wall_kit(east_spots[east_spots.size() / 2], Hub2Prop.Kind.TERMINAL, 3, true, "Terminals")
		_wall_kit(east_spots[east_spots.size() / 2 + 2], Hub2Prop.Kind.CABINET, 0)
		_wall_kit(east_spots[east_spots.size() / 2 - 2], Hub2Prop.Kind.CABINET, 1)
	_scatter_wall_kit(west_spots + east_spots, 0.35, 0.25)
	# Lamps: high-bays on a grid from the ceiling (between crane runways and walls), floods on the cranes.
	_highbays(ROOM_B, fy, 69.3, 16.0, 7.0)
	for c in cranes:
		for side in [-1.0, 1.0]:
			var at := Vector3(c[0] + side * (c[1] * 0.5 - 2.0), fy + 22.0 - 0.2, zc + c[2] + 2.2)
			_prop(Hub2Prop.Kind.FLOODLIGHT, _yaw_xf(at, 0.0), 0, "Lamps", Vector3.ZERO, _rng.randf() < 0.6)
	# Overgrowth: medium, under the roof openings / along walls, on container roofs, from girders.
	_floor_plants(ROOM_B, fy, 160, 60, 14, "Overgrowth", true)
	_floor_plants(ROOM_B, fy, 60, 20, 4)
	_moss_on_containers(0.12)
	for c in cranes:
		for k in 4:
			var at := Vector3(c[0] + _rng.randf_range(-c[1] * 0.5, c[1] * 0.5), fy + 22.0 + 0.1, zc + c[2] + (1.6 if k % 2 == 0 else -1.6))
			_vines_from(at, 2, 6.0)


func _bay_lines(fy: float, cranes: Array, z_blocks: Array, pitch_x: float, pitch_z: float) -> void:
	var kit := PropKit.new(0.6, 77)
	kit.cell = 2.0
	var yellow := Color(0.78, 0.62, 0.12)
	for c in cranes:
		for bx in [-1, 1]:
			var x0: float = c[0] + bx * (3.0 + pitch_x * 2.0) - pitch_x * 1.5 - pitch_x * 0.5
			var x1 := x0 + pitch_x * 4.0
			for zb: float in z_blocks:
				var z0 := zb + 0.1
				var z1 := zb + pitch_z * 5.0 + 0.4
				for edge in [[Vector3(x0, 0, z0), Vector3(x1, 0, z0)], [Vector3(x0, 0, z1), Vector3(x1, 0, z1)],
						[Vector3(x0, 0, z0), Vector3(x0, 0, z1)], [Vector3(x1, 0, z0), Vector3(x1, 0, z1)]]:
					var a: Vector3 = edge[0]
					var b: Vector3 = edge[1]
					var lo := Vector3(minf(a.x, b.x) - 0.08, fy + 0.005, minf(a.z, b.z) - 0.08)
					var hi := Vector3(maxf(a.x, b.x) + 0.08, fy + 0.02, maxf(a.z, b.z) + 0.08)
					kit.box(lo, hi, yellow)
	var mi := MeshInstance3D.new()
	mi.name = "BayLines"
	mi.mesh = kit.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_own(mi)


func _scatter_wall_kit(spots: Array, kit_chance: float, terminal_chance: float) -> void:
	for s: Dictionary in spots:
		var r := _rng.randf()
		if r > kit_chance:
			continue
		var pick := _rng.randf()
		if pick < terminal_chance:
			_wall_kit(s, Hub2Prop.Kind.TERMINAL, 0, _rng.randf() < 0.25, "Terminals")
		elif pick < 0.45:
			_wall_kit(s, Hub2Prop.Kind.CABINET, _rng.randi() % 2)
		elif pick < 0.65:
			_wall_kit(s, Hub2Prop.Kind.JUNCTION_BOX)
		elif pick < 0.82:
			_wall_kit(s, Hub2Prop.Kind.HOSE_REEL)
		else:
			_wall_kit(s, Hub2Prop.Kind.EXTINGUISHER)


## High-bay lamps hanging from the ceiling on a grid; ~1 in 3 dead, a couple crooked.
func _highbays(rect: Rect2, fy: float, ceil_hint: float, pitch: float, hang_above_floor: float) -> void:
	var x := rect.position.x + pitch * 0.5
	while x < rect.end.x:
		var z := rect.position.y + pitch * 0.5
		while z < rect.end.y:
			var up := _ray(Vector3(x, fy + 3.0, z), Vector3(x, ceil_hint + 5.0, z))
			if not up.is_empty():
				var cy: float = (up["position"] as Vector3).y
				var length := clampf(cy - (fy + hang_above_floor) - 0.6, 0.5, 6.0)
				var dead := _rng.randf() < 0.33
				var crooked := _rng.randf() < 0.06
				var lamp := _prop(Hub2Prop.Kind.LAMP_HIGHBAY, _yaw_xf(Vector3(x, cy, z), _rng.randf() * TAU), 1 if crooked else 0,
					"Lamps", Vector3.ZERO, not dead, length)
				# Its pool has to reach the floor from up there.
				lamp.pool_radius = (cy - length - 0.6 - fy) + 9.0
			z += pitch
		x += pitch


# -- room C: the loading bay ----------------------------------------------------------------------

func _room_c() -> void:
	var fy := 30.95
	var rect := ROOM_C
	# Smaller bridge crane over the whole room.
	var crane := Hub2Crane.new()
	crane.name = "BridgeCrane"
	crane.type = Hub2Crane.Type.BRIDGE
	crane.span = rect.size.x - 3.0
	crane.runway_length = rect.size.y - 2.0
	crane.rail_height = 11.0
	crane.column_pitch = 11.75
	crane.bridge_z = 8.0
	crane.trolley_x = -5.0
	crane.hook_drop = 6.0
	crane.wear = WEAR
	crane.position = Vector3(rect.get_center().x, fy, rect.get_center().y)
	_own(crane, _sub("Cranes"))
	_count("crane")
	var z := -crane.runway_length * 0.5
	while z <= crane.runway_length * 0.5 + 0.01:
		for side in [-1.0, 1.0]:
			_placed.append(AABB(Vector3(crane.position.x + side * crane.span * 0.5 - 0.7, fy, crane.position.z + z - 0.7), Vector3(1.4, 11, 1.4)))
		z += crane.column_pitch
	var spots := _wall_spots(rect, fy, 3.0)
	# Containers: a single row along the south wall (z min), one stacked.
	var x := rect.position.x + 5.0
	var placed := 0
	while x < rect.end.x - 4.0 and placed < 5:
		var p := Vector3(x, fy, rect.position.y + CargoContainer.WIDTH * 0.5 + 1.2)
		if _clear(p + Vector3(0, 1.3, 0), Vector3(CargoContainer.LENGTH, 2.5, CargoContainer.WIDTH)):
			_container(_yaw_xf(p, _rng.randf_range(-0.02, 0.02)))
			if placed == 2:
				_container(_yaw_xf(p + Vector3(0.2, CargoContainer.HEIGHT, 0), 0.03))
			placed += 1
		x += CargoContainer.LENGTH + 0.8
	# Dock doors + levellers on the east wall where it is solid.
	var east := spots.filter(func(s: Dictionary) -> bool: return s["wall"] == "E")
	var docks := 0
	for i in range(1, east.size(), 2):
		if docks >= 2:
			break
		var s: Dictionary = east[i]
		var xf := Transform3D(Basis(Vector3.UP, s["yaw"]), (s["p"] as Vector3) + (s["n"] as Vector3) * 0.02)
		if _clear(xf * Vector3(0, 2.5, 1.4), Vector3(4.6, 4.8, 2.6), s["yaw"]):
			_prop(Hub2Prop.Kind.DOCK_DOOR, xf, docks % 2, "Dock", Vector3(4.6, 5.2, 0.6))
			_prop(Hub2Prop.Kind.DOCK_LEVELLER, xf, 0, "Dock", Vector3.ZERO)
			_placed.append(_aabb(xf * Vector3(0, 0.5, 1.5), Vector3(2.4, 1.0, 3.0), s["yaw"]))
			docks += 1
	# Racking along the west wall, dock office terminals + workbench at the north end of it.
	var west := spots.filter(func(s: Dictionary) -> bool: return s["wall"] == "W")
	for i in west.size():
		var s: Dictionary = west[i]
		var p: Vector3 = (s["p"] as Vector3) + (s["n"] as Vector3) * 0.7
		if i < 3:
			continue
		if i % 1 == 0 and _clear(p + Vector3(0, 2.8, 0), Vector3(2.8, 5.4, 1.2), s["yaw"]):
			_rack_bay(p, s["yaw"], i == 7)
	if west.size() > 2:
		_wall_kit(west[0], Hub2Prop.Kind.TERMINAL, 2, true, "Terminals")
		var s1: Dictionary = west[2]
		_prop(Hub2Prop.Kind.WORKBENCH, Transform3D(Basis(Vector3.UP, s1["yaw"]), (s1["p"] as Vector3) + (s1["n"] as Vector3) * 0.45), 0, "Service", Vector3(2.2, 2.0, 1.0))
	# Machines.
	var lift_p := Vector3(rect.get_center().x + 6.0, fy, rect.get_center().y + 4.0)
	_prop(Hub2Prop.Kind.SCISSOR_LIFT, _yaw_xf(lift_p, 0.4), 0, "Vehicles", Vector3(2.6, 3.8, 1.4))
	for k in 2:
		var p := Vector3(rect.get_center().x + _rng.randf_range(-12, 12), fy, rect.get_center().y + _rng.randf_range(-8, 14))
		if _clear(p + Vector3(0, 0.6, 0), Vector3(1.6, 1.2, 0.8)):
			_prop(Hub2Prop.Kind.PALLET_JACK, _yaw_xf(p, _rng.randf() * TAU), 0, "Vehicles", Vector3(1.6, 1.2, 0.8))
	# Crates: neat staging lanes in the middle, a toppled spill.
	for k in 6:
		var p := Vector3(rect.position.x + 10.0 + (k % 3) * 8.0, fy, rect.get_center().y + (k / 3) * 7.0 - 2.0)
		_crate_cluster(p, 0.0, k == 4)
	_scatter_wall_kit(spots.filter(func(s: Dictionary) -> bool: return s["wall"] == "N" or s["wall"] == "S"), 0.4, 0.3)
	_highbays(rect, fy, 47.0, 10.0, 5.0)
	for s: Dictionary in spots:
		if _rng.randf() < 0.08:
			var xf := Transform3D(Basis(Vector3.UP, s["yaw"]), (s["p"] as Vector3) + Vector3.UP * 3.2 + (s["n"] as Vector3) * 0.02)
			_prop(Hub2Prop.Kind.LAMP_BULKHEAD, xf, 0, "Lamps", Vector3.ZERO, _rng.randf() < 0.6)
	_floor_plants(rect, fy, 40, 14, 2, "Overgrowth", true)
	for s: Dictionary in spots:
		if _rng.randf() < 0.06:
			_prop(Hub2Prop.Kind.MOSS, Transform3D(Basis(Vector3.UP, s["yaw"]), (s["p"] as Vector3) + (s["n"] as Vector3) * 0.01), 2, "Overgrowth")


# -- room A: the enclosed hall under the roof slab -------------------------------------------------
# 2026-11-14 correction (docs/specs/hub2-storage.md "Room A correction"): A is the dark hall at y -273 under
# the -164 roof slab, not the slab itself. The hollow shaft opens into its ceiling over SHAFT_AXIS; the one
# natural light falls through that mouth, and everything alive grows in that light.

func _room_a() -> void:
	# Room A is the main storage hall (docs/specs/hub2-storage.md "Room A storage hall", 2026-11-14): two bands of
	# neat storage along the long walls, wall-mounted cranes over them, the whole middle left bare for the boss,
	# and a sealed hangar door filling the south bay. Every placement is ray-checked against the real mesh.
	var fy := A_FLOOR
	for side in [-1.0, 1.0]:
		_a_band(side, fy)
	_a_cranes(fy)
	_a_door(fy)
	_a_bay_lines(fy)
	# Overgrowth: only a flat patch of moss and short grass in the light column (nothing tall, no trees), a
	# little moss at wall bases and on container roofs.
	_floor_plants(A_ISLAND, fy, 120, 40, 0, "Overgrowth")
	_floor_plants(ROOM_A, fy, 0, 14, 0, "Overgrowth", true)
	_moss_on_containers(0.12)
	# Caged bulkheads on the wall at each pillar, both sides, mostly dead.
	var lit := 0
	var lamps := 0
	for zc in A_ARCH_Z:
		for side in [-1.0, 1.0]:
			for dz in [-5.0, 5.0]:
				var wu := _a_wall_u(side, zc + dz, 6.0)
				if is_nan(wu) or lamps >= 16:
					continue
				var xf := Transform3D(Basis(Vector3.UP, -side * PI * 0.5), Vector3(side * (wu - 0.02), fy + 6.0, zc + dz))
				var on := lit < 2 and _rng.randf() < 0.3
				lit += int(on)
				_prop(Hub2Prop.Kind.LAMP_BULKHEAD, xf, 0, "Lamps", Vector3.ZERO, on)
				lamps += 1
	# The one natural light: a faint cold column from the mouth to the floor, and its large floor pool.
	var ceil_y := A_CEILING - 2.0
	var shaft := _prop(Hub2Prop.Kind.LIGHT_SHAFT, _yaw_xf(Vector3(SHAFT_AXIS.x, ceil_y, SHAFT_AXIS.z), 0.0), 0, "Lamps", Vector3.ZERO, true, ceil_y - fy)
	shaft.pool_radius = 40.0
	shaft.pool_tint = Color(0.40, 0.55, 0.90, 0.55)
	print("A: %d bulkheads (%d lit)" % [lamps, lit])


## Distance from the hall's centre line to the wall at (z, height above floor) on `side`, or NAN.
func _a_wall_u(side: float, z: float, h: float) -> float:
	var o := Vector3(0.0, A_FLOOR + h, z)
	var r := _ray(o, o + Vector3(side * 160.0, 0.0, 0.0))
	if r.is_empty() or absf((r["normal"] as Vector3).x) < 0.5:
		return NAN
	return absf((r["position"] as Vector3).x)


## One long-wall band, wall outward-in: racking, a forklift aisle, container block A (4 rows, 3-6 high), an
## aisle, container block B (3 rows, 1-3 high), the bay line. Blocks are 4 containers long with a 9 m cross gap.
func _a_band(side: float, fy: float) -> void:
	var yaw_in := -side * PI * 0.5   # prop +Z points into the room
	# 1. Racking against the wall: runs of 5-9 bays, then a 4-8 m gap.
	var z := A_BLOCK_Z0 + 2.0
	var left := _rng.randi_range(5, 9)
	var bays := 0
	while z < A_BLOCK_Z1 - 2.0:
		if left <= 0:
			z += _rng.randf_range(4.0, 8.0)
			left = _rng.randi_range(5, 9)
			continue
		var wu := _a_wall_u(side, z, 1.5)
		if not is_nan(wu):
			var p := Vector3(side * (wu - 0.62), fy, z)
			var f := _floor(p + Vector3.UP * 2.0, 4.0)
			if not is_nan(f) and absf(f - fy) < 0.3:
				p.y = f
				if _clear(p + Vector3(0, 2.8, 0), Vector3(2.8, 5.4, 1.2), yaw_in):
					_rack_bay(p, yaw_in, _rng.randf() < 0.04)
					bays += 1
		z += 2.8
		left -= 1
	# 2. Container blocks.
	var zb := A_BLOCK_Z0
	var gaps: Array[float] = []
	var stacks := 0
	while zb + 4.0 * A_COL_PITCH <= A_BLOCK_Z1 + 0.5:
		for zone in 2:
			var rows := 4 if zone == 0 else 3
			var u0 := A_BLOCK_A_U if zone == 0 else A_BLOCK_B_U
			var lo := 3 if zone == 0 else 1
			var hi := 6 if zone == 0 else 3
			for col in 4:
				var h := _rng.randi_range(lo, hi)
				for row in rows:
					h = clampi(h + [-1, 0, 0, 1][_rng.randi() % 4], lo, hi)
					if _rng.randf() < 0.07:
						continue   # an empty slot
					var u := u0 - CargoContainer.WIDTH * 0.5 - row * A_ROW_PITCH
					if _a_stack(side, fy, u, zb + A_COL_PITCH * (col + 0.5), h):
						stacks += 1
		gaps.append(zb + 4.0 * A_COL_PITCH + 4.5)
		zb += 4.0 * A_COL_PITCH + 9.0
	# 3. Crates in the cross gaps: pallet stacks, a few messy.
	for gz in gaps:
		for u in [A_BLOCK_A_U - 6.0, A_BLOCK_B_U - 5.0]:
			_crate_cluster(Vector3(side * u, fy, gz - 1.5), PI * 0.5, _rng.randf() < 0.3)
	# 4. Parked vehicles in the aisle and the alcoves behind it.
	var vehicles := [[Hub2Prop.Kind.FORKLIFT, 0, Vector3(3.6, 2.3, 1.4)], [Hub2Prop.Kind.FORKLIFT, 1, Vector3(3.6, 2.3, 1.4)],
		[Hub2Prop.Kind.REACH_STACKER, 0, Vector3(11, 4, 4)], [Hub2Prop.Kind.PALLET_JACK, 0, Vector3(1.6, 1.2, 0.8)],
		[Hub2Prop.Kind.PALLET_JACK, 0, Vector3(1.6, 1.2, 0.8)]]
	for v: Array in vehicles:
		for attempt in 40:
			var vz := _rng.randf_range(A_BLOCK_Z0 + 8.0, A_BLOCK_Z1 - 8.0)
			var vu := _rng.randf_range(A_BLOCK_A_U + 1.0, 91.0)
			var f := _floor(Vector3(side * vu, fy + 3.0, vz), 8.0)
			var vyaw := PI * 0.5 + _rng.randf_range(-0.15, 0.15)
			var sz: Vector3 = v[2]
			if is_nan(f) or absf(f - fy) > 0.3 or not _clear(Vector3(side * vu, f + sz.y * 0.5 + 0.1, vz), sz, vyaw):
				continue
			_prop(v[0], _yaw_xf(Vector3(side * vu, f, vz), vyaw), v[1], "Vehicles", sz)
			break
	print("A band %s: %d racking bays, %d container stacks" % ["W" if side < 0.0 else "E", bays, stacks])


## A stack of `hgt` containers (long axis along Z) at distance u from the centre line, z along the wall.
## Placed only on flat floor with the whole stack clear of the map and of what is already placed, so
## nothing floats and nothing clips. Returns whether it was placed.
func _a_stack(side: float, fy: float, u: float, z: float, hgt: int) -> bool:
	var x := side * u
	var f := _floor(Vector3(x, fy + 3.0, z), 8.0)
	if is_nan(f) or absf(f - fy) > 0.4:
		return false
	var base := Vector3(x, f, z)
	var total := hgt * CargoContainer.HEIGHT
	if not _flat(base, Vector3(CargoContainer.LENGTH, 0.0, CargoContainer.WIDTH), PI * 0.5, 0.3):
		return false
	if not _clear(base + Vector3(0, total * 0.5 + 0.05, 0), Vector3(CargoContainer.LENGTH, total - 0.2, CargoContainer.WIDTH), PI * 0.5):
		return false
	for level in hgt:
		var yaw := PI * 0.5 + _rng.randf_range(-0.012, 0.012)
		var off := Vector3.ZERO
		if level > 0 and _rng.randf() < 0.07:
			yaw += _rng.randf_range(-0.06, 0.06)   # askew
		if level == hgt - 1 and level > 0 and _rng.randf() < 0.04:
			off = Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(1.2, 2.2) * (1.0 if _rng.randf() < 0.5 else -1.0))
			_count("slid")
		_container(_yaw_xf(base + off + Vector3(0, level * CargoContainer.HEIGHT, 0), yaw))
	return true


## Wall-mounted cranes: one runway girder per long wall on gusset brackets at the pillars, three cantilever
## jibs on each reaching over the band (never past A_JIB_REACH), hooks parked at different heights.
func _a_cranes(fy: float) -> void:
	var z0 := (A_BLOCK_Z0 + A_BLOCK_Z1) * 0.5
	var run := A_BLOCK_Z1 - A_BLOCK_Z0 + 8.0
	for side in [-1.0, 1.0]:
		# Where the pillars are at rail height (wall closer than the recesses).
		var pillar_zs: Array[float] = []
		var min_u := INF
		var zs := z0 - run * 0.5
		while zs <= z0 + run * 0.5:
			var u := _a_wall_u(side, zs, A_RAIL_H)
			if not is_nan(u) and u < 98.0:
				pillar_zs.append(zs)
				min_u = minf(min_u, u)
			zs += 1.0
		if is_inf(min_u):
			min_u = 94.0
		# Brackets: start, middle and end of each pillar run, in the crane's local z.
		var brackets := PackedFloat32Array()
		var k := 0
		while k < pillar_zs.size():
			var j := k
			while j + 1 < pillar_zs.size() and pillar_zs[j + 1] - pillar_zs[j] < 1.5:
				j += 1
			for zw in [pillar_zs[k] + 2.5, (pillar_zs[k] + pillar_zs[j]) * 0.5, pillar_zs[j] - 2.5]:
				brackets.append((zw - z0) * (1.0 if side < 0.0 else -1.0))
			k = j + 1
		var bridge_world := [-205.0, -300.0, -385.0] if side < 0.0 else [-165.0, -255.0, -345.0]
		var bz := PackedFloat32Array()
		var tx := PackedFloat32Array()
		var drops := PackedFloat32Array()
		for i in 3:
			bz.append((bridge_world[i] - z0) * (1.0 if side < 0.0 else -1.0))
			tx.append(_rng.randf_range(10.0, A_JIB_REACH - 4.0))
			drops.append(A_RAIL_H - _rng.randf_range(22.0, 36.0))
		var crane := Hub2Crane.new()
		crane.name = "WallCrane%s" % ("W" if side < 0.0 else "E")
		crane.type = Hub2Crane.Type.WALL
		crane.runway_length = run
		crane.span = A_JIB_REACH
		crane.rail_height = A_RAIL_H
		crane.bracket_zs = brackets
		crane.bridge_zs = bz
		crane.trolley_xs = tx
		crane.hook_drops = drops
		crane.wear = WEAR
		crane.position = Vector3(side * min_u, fy, z0)
		crane.rotation.y = 0.0 if side < 0.0 else PI
		_own(crane, _sub("Cranes"))
		_count("crane")
		# A floodlight under each jib tip, aimed back in over the band; the odd one is lit.
		for i in 3:
			var lx := A_JIB_REACH - 1.0
			var lz := bz[i]
			var world := Vector3(side * min_u + (lx if side < 0.0 else -lx), fy + A_RAIL_H + 1.2, z0 + (lz if side < 0.0 else -lz))
			var flood := _prop(Hub2Prop.Kind.FLOODLIGHT, _yaw_xf(world, -side * PI * 0.5), 0, "Lamps", Vector3.ZERO, i == 1 and _rng.randf() < 0.7)
			flood.pool_radius = 26.0
		print("A crane %s: %d brackets, wall u %.1f" % ["W" if side < 0.0 else "E", brackets.size(), min_u])


## The sealed hangar door in the south bay, mounted on the bay's back wall.
func _a_door(fy: float) -> void:
	var back := _ray(Vector3(0.0, fy + 3.0, -440.0), Vector3(0.0, fy + 3.0, -500.0))
	var up := _ray(Vector3(0.0, fy + 3.0, -466.0), Vector3(0.0, fy + 200.0, -466.0))
	if back.is_empty() or up.is_empty():
		push_warning("gen_hub2_dressing: no bay back wall / ceiling found for the hangar door")
		return
	var wz: float = (back["position"] as Vector3).z
	var height: float = (up["position"] as Vector3).y - fy - 0.3
	# The bay's back wall must be flat and in one plane across the door's width.
	for x in [-36.0, -18.0, 18.0, 36.0]:
		var r := _ray(Vector3(x, fy + 3.0, -440.0), Vector3(x, fy + 3.0, -500.0))
		if r.is_empty() or absf((r["position"] as Vector3).z - wz) > 4.0:
			push_warning("gen_hub2_dressing: bay back wall is not flat at x %.0f (z %s vs %.1f)" % [x, str(r.get("position")), wz])
	var door := _prop(Hub2Prop.Kind.HANGAR_DOOR, _yaw_xf(Vector3(0.0, fy, wz + 0.02), 0.0), 0, "Door",
		Vector3(Hub2PropBuild.HANGAR_W + 1.6, height, 3.4), false, height)
	print("A door: wall z %.1f, height %.1f, %s" % [wz, height, door.name])


## Painted bay lines on the floor at the edge of the open middle, along both bands.
func _a_bay_lines(fy: float) -> void:
	var kit := PropKit.new(0.6, 78)
	kit.cell = 2.0
	var yellow := Color(0.78, 0.62, 0.12)
	for side in [-1.0, 1.0]:
		var z := A_BLOCK_Z0
		while z < A_BLOCK_Z1:
			var f := _floor(Vector3(side * A_BAY_LINE_U, fy + 3.0, z + 3.0), 8.0)
			if not is_nan(f) and absf(f - fy) < 0.3:
				kit.box(Vector3(minf(side * (A_BAY_LINE_U - 0.18), side * (A_BAY_LINE_U + 0.18)), fy + 0.005, z),
					Vector3(maxf(side * (A_BAY_LINE_U - 0.18), side * (A_BAY_LINE_U + 0.18)), fy + 0.02, z + 6.0), yellow)
			z += 8.0   # dashed
	var mi := MeshInstance3D.new()
	mi.name = "BayLines"
	mi.mesh = kit.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_own(mi)


# -- halls: pipes, wall kit, lamps, the odd crate pile ---------------------------------------------

func _halls() -> void:
	# Pipes are routed by tools/gen_hub2_pipes.gd into the top-level Pipes group (docs/specs/hub2-pipe-routing.md):
	# re-run it after this generator.
	# Walkable hall floor cells (not A/B/C, indoor or the spawn platform), wall-adjacent spots.
	var cells: Array = []
	var x := -60.0
	while x < 125.0:
		var z := -190.0
		while z < 100.0:
			if not _in_rooms(x, z):
				var y := 140.0
				for k in 6:
					var r := _ray(Vector3(x, y, z), Vector3(x, 20.0, z))
					if r.is_empty():
						break
					var p: Vector3 = r["position"]
					if (r["normal"] as Vector3).y > 0.8 and p.y > 24.0:
						var up := _ray(p + Vector3.UP * 0.5, p + Vector3.UP * 3.0)
						if up.is_empty():
							cells.append(p)
					y = p.y - 0.5
			z += 3.0
		x += 3.0
	var wall_spots: Array = []
	for p: Vector3 in cells:
		for d in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			var h := _ray(p + Vector3.UP * 1.5, p + Vector3.UP * 1.5 + d * 2.0)
			var h2 := _ray(p + Vector3.UP * 2.8, p + Vector3.UP * 2.8 + d * 2.0)
			if not h.is_empty() and not h2.is_empty() and absf((h["normal"] as Vector3).y) < 0.3:
				var n: Vector3 = h["normal"]
				var wp: Vector3 = h["position"]
				wall_spots.append({"p": Vector3(wp.x, p.y, wp.z), "yaw": atan2(n.x, n.z), "n": n, "wall": "H"})
	# Thin them: keep spots >= 9 m apart.
	wall_spots.shuffle()
	var kept: Array = []
	for s: Dictionary in wall_spots:
		var ok := true
		for k: Dictionary in kept:
			if (k["p"] as Vector3).distance_to(s["p"]) < 9.0:
				ok = false
				break
		if ok:
			kept.append(s)
	print("halls: %d floor cells, %d wall spots, %d kept" % [cells.size(), wall_spots.size(), kept.size()])
	var i := 0
	for s: Dictionary in kept:
		match i % 6:
			0, 3:
				var xf := Transform3D(Basis(Vector3.UP, s["yaw"]), (s["p"] as Vector3) + Vector3.UP * 3.0 + (s["n"] as Vector3) * 0.02)
				_prop(Hub2Prop.Kind.LAMP_BULKHEAD, xf, 0, "Lamps", Vector3.ZERO, _rng.randf() < 0.65)
			1:
				_wall_kit(s, Hub2Prop.Kind.TERMINAL, _rng.randi() % 2, _rng.randf() < 0.3, "Terminals")
			2:
				_wall_kit(s, [Hub2Prop.Kind.CABINET, Hub2Prop.Kind.JUNCTION_BOX][_rng.randi() % 2], _rng.randi() % 2)
			4:
				_wall_kit(s, [Hub2Prop.Kind.HOSE_REEL, Hub2Prop.Kind.EXTINGUISHER][_rng.randi() % 2])
			5:
				if _rng.randf() < 0.5:
					_crate_cluster((s["p"] as Vector3) + (s["n"] as Vector3) * 1.2, s["yaw"], true)
				else:
					_prop(Hub2Prop.Kind.MOSS, Transform3D(Basis(Vector3.UP, s["yaw"]), (s["p"] as Vector3) + (s["n"] as Vector3) * 0.01), 2, "Overgrowth")
		i += 1
	# Sparse floor moss.
	for k in range(0, cells.size(), 23):
		var p: Vector3 = cells[k]
		if _rng.randf() < 0.5:
			_prop([Hub2Prop.Kind.MOSS, Hub2Prop.Kind.TUFT][_rng.randi() % 2], _yaw_xf(p, _rng.randf() * TAU), 0, "Overgrowth")


func _in_rooms(x: float, z: float) -> bool:
	return ROOM_B.grow(3.0).has_point(Vector2(x, z)) or ROOM_C.grow(2.0).has_point(Vector2(x, z))
