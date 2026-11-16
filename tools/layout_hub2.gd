extends SceneTree

# hub2 final dressing, hand-placed (docs/specs/hub2-final-pass.md). Writes every object into
# scenes/hub2_dressing_src.tscn under one group per area, each named for why it is there, then
# CHECKS the result and refuses to save if anything clips:
#   - collision boxes of two objects overlap (exact oriented-box test, 4 cm tolerance)
#   - a collision box cuts into the map shell (shape query against hub2.glb's collision)
#   - an object has open sky straight above it (= it is outside the map)
#   godot --headless --path . --script tools/layout_hub2.gd [-- --force]
# Then bake: godot --headless --path . --script tools/bake_hub2_dressing.gd
#
# No scatter: every position below is written by hand from the ray survey (tools/survey_hub2_*.gd).
# Re-running replaces the whole dressing; once a room is hand-edited in the editor, stop running this.

const SCENE := "res://scenes/hub2_dressing_src.tscn"
const WORLD_SCALE := 0.6
const PK := Hub2Piece.Kind
const HK := Hub2Prop.Kind
const PS := Hub2PipeRun.Service

const FY_B := 21.78       # B yard + mid galleries + mid cross corridors
const FY_E := 43.56       # E level, plant room, B balcony
const FY_S := 29.04       # spawn platform
const FY_C := 30.95       # C dock hall, C link
const FY_LEDGE := 38.2    # C's south dock ledge
const FY_A := -272.77     # A hall
const FY_D := -93.91      # D shaft bottom
const ROOF_D := 58.08     # D roof

var _phys: Node3D
var _ss: PhysicsDirectSpaceState3D
var _frames := 0
var _root: Node3D
var _grp: Node3D
var _names := {}
## [node, Transform3D global box centre, half extents, tag] for the overlap test
var _boxes: Array = []
## pairs of tags allowed to touch (rubble piles are built from pieces that lean into each other)
const PILE_TAG := "pile"
var _errors: PackedStringArray = []
var _counts := {}
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_phys = Node3D.new()
	var glb: Node3D = (load("res://assets/hub2.glb") as PackedScene).instantiate()
	glb.scale = Vector3.ONE * WORLD_SCALE
	_phys.add_child(glb)
	root.add_child(_phys)


func _physics_process(_d: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_ss = _phys.get_world_3d().direct_space_state
	_rng.seed = 20261115
	var packed: PackedScene = load(SCENE)
	_root = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	for c in _root.get_children():
		_root.remove_child(c)
		c.free()
	_spawn()
	_d_shaft()
	_galleries()
	_corridors_mid()
	_c_link_and_east()
	_c_dock()
	_e_level()
	_plant_room()
	_pipes()
	_b_yard()
	_b_rooms()
	_b_balcony()
	_a_hall()
	_check()
	var total := 0
	for k in _counts:
		total += _counts[k]
	print("layout_hub2: %d objects  %s" % [total, _counts])
	if not _errors.is_empty():
		for e in _errors:
			print("FAIL ", e)
		print("layout_hub2: %d problems" % _errors.size())
		if not "--force" in OS.get_cmdline_user_args():
			print("layout_hub2: NOT saved (fix the problems or pass -- --force)")
			_root.free()
			return true
	var out := PackedScene.new()
	var err := out.pack(_root)
	if err == OK:
		err = ResourceSaver.save(out, SCENE)
	print("layout_hub2: saved %s: %s" % [SCENE, error_string(err)])
	_root.free()
	return true


# -- placing ----------------------------------------------------------------------------------

func _group(n: String) -> void:
	_grp = _root.get_node_or_null(n) as Node3D
	if _grp == null:
		_grp = Node3D.new()
		_grp.name = n
		_root.add_child(_grp)
		_grp.owner = _root


func _own(n: Node3D, name: String) -> void:
	var base := name.validate_node_name()
	var k := "%s/%s" % [_grp.name, base]
	var i: int = _names.get(k, 0)
	_names[k] = i + 1
	n.name = base if i == 0 else "%s_%d" % [base, i + 1]
	_grp.add_child(n)
	n.owner = _root
	_counts[_grp.name] = _counts.get(_grp.name, 0) + 1


func _basis(yaw_deg: float, o: Dictionary) -> Basis:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	if o.has("pitch"):
		b = b * Basis(Vector3.BACK, deg_to_rad(o["pitch"]))
	if o.has("roll"):
		b = b * Basis(Vector3.RIGHT, deg_to_rad(o["roll"]))
	if o.has("basis"):
		b = o["basis"]
	return b


## A Hub2Piece. o: v, st, size, text, lit, name, seed, wear, pitch/roll (deg), basis, tag, sky_ok, pool_radius, pool_tint
func P(kind: int, pos: Vector3, yaw := 0.0, o := {}) -> Hub2Piece:
	var n := Hub2Piece.new()
	n.kind = kind
	n.variant = o.get("v", 0)
	n.state = o.get("st", 0)
	n.size = o.get("size", Vector3.ONE)
	n.text = o.get("text", "")
	n.powered = o.get("lit", false)
	n.prop_seed = o.get("seed", _rng.randi_range(0, 3))
	n.wear = o.get("wear", 0.85)
	if o.has("pool_radius"):
		n.pool_radius = o["pool_radius"]
	if o.has("pool_tint"):
		n.pool_tint = o["pool_tint"]
	n.transform = Transform3D(_basis(yaw, o), pos)
	if kind == PK.BULKHEAD and n.size.x > 12.0:
		_errors.append("bulkhead %s is %.1f m wide: its span was measured inside a room" % [o.get("name", "?"), n.size.x])
	_own(n, o.get("name", Hub2Piece.Kind.keys()[kind].capitalize().replace(" ", "")))
	var made := Hub2Piece.build_cached(n.kind, n.variant, n.state, n.prop_seed, n.wear, n.size, n.text, n.powered)
	_register(n, made["boxes"], o)
	return n


## An existing Hub2Prop (crates, racking, wall kit, lamps, growth). o: v, lit, length, name, seed, pitch/roll, pool_radius, pool_tint
func H(kind: int, pos: Vector3, yaw := 0.0, o := {}) -> Hub2Prop:
	var n := Hub2Prop.new()
	n.kind = kind
	n.variant = o.get("v", 0)
	n.powered = o.get("lit", false)
	n.length = o.get("length", 2.0)
	n.prop_seed = o.get("seed", _rng.randi_range(0, 3))
	n.wear = o.get("wear", 0.85)
	if o.has("pool_radius"):
		n.pool_radius = o["pool_radius"]
	if o.has("pool_tint"):
		n.pool_tint = o["pool_tint"]
	n.transform = Transform3D(_basis(yaw, o), pos)
	_own(n, o.get("name", Hub2Prop.Kind.keys()[kind].capitalize().replace(" ", "")))
	var made := Hub2Prop.build_cached(n.kind, n.variant, n.prop_seed, n.wear, n.powered, n.length)
	_register(n, made["boxes"], o)
	return n


func _register(n: Node3D, boxes: Array, o: Dictionary) -> void:
	for b: Array in boxes:
		var local := Transform3D(b[2] if b.size() > 2 else Basis.IDENTITY, b[0])
		var g := n.transform * local
		_boxes.append([n, g, (b[1] as Vector3) * 0.5, o.get("tag", ""), o.get("sky_ok", false), o.get("wall_ok", false)])


## A door in a doorway. type Hub2Door.Type; o: width, height, gap, open, keypad, name
func DOOR(type: int, pos: Vector3, yaw: float, o := {}) -> Hub2Door:
	var d := Hub2Door.new()
	d.type = type
	d.width = o.get("width", 4.2)
	d.height = o.get("height", 4.4)
	d.gap = o.get("gap", 1.0)
	d.start_open = o.get("open", false)
	d.keypad = o.get("keypad", 1)
	d.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos)
	_own(d, o.get("name", "Door"))
	return d


## A pipe polyline through world points. o: service, mount (Vector3 toward the surface), sag, snapped, name
func PIPE(pts: Array, radius: float, o := {}) -> Hub2PipeRun:
	var p := Hub2PipeRun.new()
	p.points = PackedVector3Array(pts)
	p.radius = radius
	p.service = o.get("service", PS.STEEL)
	p.mount_dir = o.get("mount", Vector3.UP)
	p.mount_gap = o.get("gap", radius + 0.15)
	p.sag = o.get("sag", false)
	p.snapped = o.get("snapped", false)
	p.fittings_seed = _rng.randi_range(0, 99999)
	p.wear = 0.85
	_own(p, o.get("name", "Pipe"))
	return p


## A railing run from a to b (same y), split into equal pieces of at most 6 m. broken = indices to break.
func RAIL(a: Vector3, b: Vector3, broken: Array = [], o := {}) -> void:
	var d := b - a
	var L := Vector2(d.x, d.z).length()
	var n := maxi(int(ceil(L / 6.0)), 1)
	var yaw := rad_to_deg(atan2(-d.z, d.x))
	for i in n:
		var c := a + d * ((i + 0.5) / n)
		var oo := o.duplicate()
		oo["size"] = Vector3(L / n - 0.05, 1, 1)
		oo["v"] = 1 if i in broken else 0
		oo["name"] = o.get("name", "Railing")
		P(PK.RAILING, c, yaw, oo)


# -- queries ----------------------------------------------------------------------------------

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.hit_back_faces = true
	return _ss.intersect_ray(q)


## Floor height straight under p (searching down from p.y).
func fl(x: float, z: float, from_y: float) -> float:
	var r := _ray(Vector3(x, from_y, z), Vector3(x, from_y - 40.0, z))
	if r.is_empty():
		_errors.append("no floor under (%.1f, %.1f) from y %.1f" % [x, z, from_y])
		return from_y
	return (r["position"] as Vector3).y


## Walls either side of p along `axis` (unit X or Z) at p.y + 1.5, and the lintel above:
## {centre: Vector3 on the floor between the walls, width, height}.
func span(p: Vector3, axis: Vector3) -> Dictionary:
	var h := p + Vector3.UP * 1.5
	var r0 := _ray(h, h - axis * 40.0)
	var r1 := _ray(h, h + axis * 40.0)
	var up := _ray(p + Vector3.UP * 0.2, p + Vector3.UP * 60.0)
	if r0.is_empty() or r1.is_empty() or up.is_empty():
		_errors.append("span: open at %s along %s" % [p, axis])
		return {"centre": p, "width": 8.0, "height": 7.3}
	var a: Vector3 = r0["position"]
	var b: Vector3 = r1["position"]
	var c := (a + b) * 0.5
	return {"centre": Vector3(c.x, p.y, c.z), "width": a.distance_to(b), "height": (up["position"] as Vector3).y - p.y}


# -- checks -----------------------------------------------------------------------------------

func _check() -> void:
	# 1. pairwise oriented-box overlap (spatial hash on 8 m cells)
	var cells := {}
	for i in _boxes.size():
		var g: Transform3D = _boxes[i][1]
		var key := Vector3i(floori(g.origin.x / 8.0), floori(g.origin.y / 8.0), floori(g.origin.z / 8.0))
		for dx in [-2, -1, 0, 1, 2]:
			for dy in [-1, 0, 1]:
				for dz in [-2, -1, 0, 1, 2]:
					var k2 := key + Vector3i(dx, dy, dz)
					if not cells.has(k2):
						cells[k2] = []
		(cells[key] as Array).append(i)
	var seen := {}
	for i in _boxes.size():
		var bi: Array = _boxes[i]
		var gi: Transform3D = bi[1]
		var key := Vector3i(floori(gi.origin.x / 8.0), floori(gi.origin.y / 8.0), floori(gi.origin.z / 8.0))
		for dx in [-2, -1, 0, 1, 2]:
			for dy in [-1, 0, 1]:
				for dz in [-2, -1, 0, 1, 2]:
					for j: int in cells.get(key + Vector3i(dx, dy, dz), []):
						if j <= i:
							continue
						var bj: Array = _boxes[j]
						if bi[0] == bj[0]:
							continue
						if bi[3] != "" and bi[3] == bj[3]:
							continue
						if _obb_overlap(gi, bi[2] - Vector3.ONE * 0.04, bj[1], (bj[2] as Vector3) - Vector3.ONE * 0.04):
							var pk := "%s|%s" % [(bi[0] as Node).name, (bj[0] as Node).name]
							if not seen.has(pk):
								seen[pk] = true
								_errors.append("overlap: %s/%s <-> %s/%s at %s" % [(bi[0] as Node).get_parent().name, (bi[0] as Node).name,
									(bj[0] as Node).get_parent().name, (bj[0] as Node).name, gi.origin.snapped(Vector3.ONE * 0.1)])
	# 2. boxes cutting into the map shell; 3. open sky above
	var shape := BoxShape3D.new()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	var sky_seen := {}
	for b: Array in _boxes:
		var g: Transform3D = b[1]
		var he: Vector3 = b[2]
		if not b[5]:
			shape.size = (he * 2.0 - Vector3.ONE * 0.12).max(Vector3.ONE * 0.02)
			q.transform = g
			if not _ss.intersect_shape(q, 1).is_empty():
				_errors.append("in map: %s/%s box at %s size %s" % [(b[0] as Node).get_parent().name, (b[0] as Node).name, g.origin.snapped(Vector3.ONE * 0.1), (he * 2.0).snapped(Vector3.ONE * 0.1)])
		var n := b[0] as Node3D
		if not b[4] and not sky_seen.has(n):
			sky_seen[n] = true
			var o := n.transform.origin + Vector3.UP * 0.3
			var up := _ray(o, o + Vector3.UP * 300.0)
			# A's floor under the shaft mouth really is open to the sky (the shaft rises to the top)
			var in_mouth := o.y < -150.0 and Vector2(o.x - 4.0, o.z + 232.0).length() < 52.0
			if up.is_empty() and not in_mouth:
				_errors.append("outside (sky above): %s/%s at %s" % [n.get_parent().name, n.name, n.transform.origin.snapped(Vector3.ONE * 0.1)])


static func _obb_overlap(a: Transform3D, ha: Vector3, b: Transform3D, hb: Vector3) -> bool:
	var A := [a.basis.x.normalized(), a.basis.y.normalized(), a.basis.z.normalized()]
	var Bx := [b.basis.x.normalized(), b.basis.y.normalized(), b.basis.z.normalized()]
	var t := b.origin - a.origin
	var axes: Array = A + Bx
	for i in 3:
		for j in 3:
			var c: Vector3 = (A[i] as Vector3).cross(Bx[j])
			if c.length_squared() > 1e-8:
				axes.append(c.normalized())
	for ax: Vector3 in axes:
		var ra := absf((A[0] as Vector3).dot(ax)) * ha.x + absf((A[1] as Vector3).dot(ax)) * ha.y + absf((A[2] as Vector3).dot(ax)) * ha.z
		var rb := absf((Bx[0] as Vector3).dot(ax)) * hb.x + absf((Bx[1] as Vector3).dot(ax)) * hb.y + absf((Bx[2] as Vector3).dot(ax)) * hb.z
		if absf(t.dot(ax)) > ra + rb:
			return false
	return true


# -- helpers for freight ----------------------------------------------------------------------

const L20 := 6.058
const L40 := 12.192
const CH := 2.591

## Livery: 60 % operator.
func livery() -> int:
	var r := _rng.randf()
	if r < 0.6:
		return 0 if _rng.randf() < 0.5 else 5
	return 1 + _rng.randi() % 4


## A container leaning with its lower end on the floor at `foot` (world, floor height), rising
## along `yaw` onto a support edge `e` metres away (horizontal) that is `h` metres up.
func LEAN(kind: int, foot: Vector3, yaw: float, h: float, e: float, o := {}) -> Hub2Piece:
	var L := L20 if kind == PK.BOX20 else L40
	var th := atan2(h + 0.04, e)
	var dir := Vector3(cos(deg_to_rad(yaw)), 0, -sin(deg_to_rad(yaw)))
	var origin := foot + dir * (L * 0.5 * cos(th)) + Vector3.UP * (L * 0.5 * sin(th))
	var oo := o.duplicate()
	oo["basis"] = Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.BACK, th)
	oo["wall_ok"] = true   # its foot edge rests on the floor
	return P(kind, origin, yaw, oo)


# ============================================================================================
# D: spawn platform (x -11..11, z 12..93, floor 29.04). Story: the freight spine's gate 5
# checkpoint. Evacuation: a loader stopped mid-turn with its pallet raised, freight left on the
# floor, the checkpoint's last-stand sandbags. Exit east down a stair to the gallery passage.
# ============================================================================================
func _spawn() -> void:
	_group("D_Spawn")
	var y := FY_S
	# checkpoint in the 9 m neck (z 48..58, x -5..5) where the platform pinches between two drops
	P(PK.SCANNER_ARCH, Vector3(-0.5, y, 53.0), 0.0, {"name": "ScannerArch_Gate5"})
	P(PK.JERSEY, Vector3(2.9, y, 53.0), 90.0, {"v": 2, "name": "Jersey_LaneDivider"})
	P(PK.JERSEY, Vector3(-3.7, y, 53.0), 90.0, {"v": 2, "name": "Jersey_LaneDivider"})
	P(PK.BOOTH, Vector3(-7.4, y, 70.4), 180.0, {"name": "GuardBooth_Gate5"})
	P(PK.WEAPON_RACK, Vector3(-11.6, y, 74.0), 90.0, {"name": "ArmsRack_Emptied", "wall_ok": true})
	# last stand: sandbags at the north mouth of the neck, facing the shaft; spent cans
	P(PK.SANDBAGS, Vector3(-2.6, y, 45.6), 0.0, {"size": Vector3(4.2, 1.1, 1), "name": "Sandbags_LastStand"})
	P(PK.SANDBAGS, Vector3(3.4, y, 45.2), -22.0, {"size": Vector3(2.6, 1.1, 1), "name": "Sandbags_LastStand"})
	P(PK.CANS, Vector3(-2.0, y, 47.4), 0.0, {"name": "Cans_LastStand"})
	P(PK.TAG, Vector3(-11.6, y + 1.9, 78.0), 90.0, {"v": 1, "st": 1, "size": Vector3(1.0, 1, 1), "name": "Tag_X_Emptied"})
	P(PK.STENCIL, Vector3(-11.6, y + 4.4, 81.5), 90.0, {"text": "CHECKPOINT 5", "size": Vector3(0.12, 1, 1), "v": 1, "name": "Stencil_Checkpoint"})
	P(PK.EMERGENCY_LAMP, Vector3(-11.6, y + 3.4, 72.0), 90.0, {"v": 2, "lit": true, "name": "Beacon_Gate5_Red", "wall_ok": true})
	P(PK.EMERGENCY_LAMP, Vector3(10.6, y + 3.4, 72.0), -90.0, {"v": 2, "lit": true, "name": "Beacon_Gate5_Red", "wall_ok": true})
	# shaft edge
	RAIL(Vector3(-10.9, y, 12.7), Vector3(10.9, y, 12.7), [2], {"name": "Railing_ShaftEdge"})
	# evacuation mess
	P(PK.LOADER, Vector3(-4.2, y, 33.5), 140.0, {"v": 1, "name": "Loader_StoppedMidTurn"})
	H(HK.PALLET, Vector3(-0.6, y, 27.8), 20.0, {"v": 2, "name": "Pallet_Dropped"})
	H(HK.CRATE_WOOD, Vector3(0.9, y, 26.0), 47.0, {"v": 0, "name": "Crate_SpilledFromPallet"})
	H(HK.CRATE_WOOD, Vector3(-2.3, y, 25.6), -15.0, {"v": 3, "name": "Crate_SpilledFromPallet"})
	P(PK.POD, Vector3(5.6, y, 39.0), 82.0, {"v": 0, "name": "Pod_AwaitingPickup"})
	P(PK.CONE, Vector3(2.5, y, 44.5), 0.0, {"name": "Cone"})
	P(PK.CONE, Vector3(3.6, y, 31.0), 0.0, {"v": 1, "name": "Cone_Knocked"})
	P(PK.PAPERS, Vector3(-3.0, y, 47.0), 0.0, {"size": Vector3(3, 1, 2), "name": "Papers_Manifests"})
	P(PK.BAY_NUMBER, Vector3(0.0, y, 49.0), 0.0, {"text": "G5", "size": Vector3(0.32, 1, 1), "lit": true, "name": "BayNumber_Projected_Flicker"})
	P(PK.HOLO_RING, Vector3(4.2, y, 86.0), 0.0, {"name": "HoloSign_Dead"})
	P(PK.LED_STRIP, Vector3(10.6, y + 6.0, 82.0), -90.0, {"size": Vector3(18, 1, 1), "lit": true, "name": "LedStrip_HalfDead"})
	P(PK.LED_STRIP, Vector3(-11.6, y + 6.0, 82.0), 90.0, {"size": Vector3(18, 1, 1), "name": "LedStrip_Dead"})
	H(HK.EXTINGUISHER, Vector3(-11.6, y, 88.0), 90.0, {"name": "Extinguisher", "wall_ok": true})
	H(HK.CABINET, Vector3(10.6, y, 88.5), -90.0, {"v": 1, "name": "Cabinet_GateControl", "wall_ok": true})
	P(PK.DRUM, Vector3(7.8, y, 20.0), 0.0, {"v": 2, "st": 1, "name": "Drum_Tipped"})
	P(PK.POD, Vector3(-8.2, y, 84.0), 90.0, {"v": 0, "name": "Pod_Queued"})
	P(PK.POD, Vector3(-8.2, y, 90.0), 90.0, {"v": 1, "name": "Pod_Queued"})
	H(HK.PALLET, Vector3(7.6, y, 78.0), 0.0, {"v": 0, "name": "Pallet_Wrapped_Queued"})
	H(HK.PALLET, Vector3(7.6, y, 80.6), 0.0, {"v": 2, "name": "Pallet_Queued"})
	H(HK.PALLET_JACK, Vector3(5.6, y, 79.2), -80.0, {"name": "PalletJack_Left"})
	P(PK.TAG, Vector3(10.6, y + 1.8, 74.0), -90.0, {"v": 0, "st": 1, "size": Vector3(1.2, 1, 1), "roll": 180.0, "name": "Tag_Arrow_ToGate", "wall_ok": true})
	P(PK.DRUM, Vector3(9.2, y, 18.6), 0.0, {"v": 2, "name": "Drum"})
	# side gate to the east gallery: shutter (open) in a bulkhead, landing + stair down 7.3 m
	# the gate opening in the east wall (survey: z 21.25..28.25, lintel 9.6)
	var s := {"centre": Vector3(11.0, y, 24.75), "width": 7.0, "height": 9.6}
	P(PK.BULKHEAD, Vector3(10.85, y, s["centre"].z), 90.0, {"size": Vector3(s["width"] - 0.06, minf(s["height"], 9.5), 0), "v": 1, "text": "GATE 5", "wall_ok": true, "name": "Bulkhead_SideGate"})
	_group("Doors")
	DOOR(Hub2Door.Type.SHUTTER, Vector3(10.85, y, s["centre"].z), 90.0, {"width": 4.2, "height": 4.4, "open": true, "name": "Shutter_SideGate"})
	_group("D_Spawn")
	P(PK.DECK, Vector3(14.3, FY_B, 24.9), 0.0, {"size": Vector3(4.2, FY_S - FY_B, 5.8), "tag": "stair", "name": "Landing_SideGate"})
	P(PK.STAIR, Vector3(14.9, FY_B, 11.9), 0.0, {"size": Vector3(2.4, FY_S - FY_B, 10.1), "tag": "stair", "wall_ok": true, "name": "Stair_DownToGallery"})
	RAIL(Vector3(16.6, y, 22.2), Vector3(16.6, y, 27.6), [], {"tag": "stair", "name": "Railing_Landing"})


# ============================================================================================
# D shaft: the spine's ceiling mag-rail (cut where the roof door opens), one carrier stalled with its
# 40 ft still clamped, a box that fell to the bottom.
# ============================================================================================
func _d_shaft() -> void:
	_group("D_Shaft")
	P(PK.RAIL, Vector3(0, ROOF_D, -1.5), 90.0, {"size": Vector3(25.0, 1.0, 1), "name": "MagRail_SouthStub"})
	P(PK.RAIL, Vector3(0, ROOF_D, -143.0), 90.0, {"size": Vector3(76.0, 1.0, 1), "name": "MagRail_North"})
	P(PK.CARRIER, Vector3(0, ROOF_D - 1.0 - 0.85, -152.0), 90.0, {"v": 0, "name": "Carrier_StalledWithBox"})
	PIPE([Vector3(0, ROOF_D - 1.7, -14.0), Vector3(0.3, ROOF_D - 6.5, -14.6)], 0.04, {"service": PS.STEEL, "mount": Vector3.UP, "name": "Cable_RailEndHanging"})
	PIPE([Vector3(0, ROOF_D - 1.7, -105.0), Vector3(-0.4, ROOF_D - 9.0, -104.2)], 0.04, {"service": PS.STEEL, "mount": Vector3.UP, "name": "Cable_RailEndHanging"})
	P(PK.BOX20, Vector3(-2.0, FY_D, -70.0), 63.0, {"v": livery(), "st": 3, "name": "Box_FellOffTheSpine"})
	P(PK.DEBRIS, Vector3(3.5, FY_D, -64.0), 0.0, {"size": Vector3(5, 1, 4), "name": "Debris"})
	P(PK.RAILING, Vector3(4.0, FY_D, -78.0), 30.0, {"v": 1, "size": Vector3(5.5, 1, 1), "pitch": 80.0, "name": "Railing_FellFromGallery", "wall_ok": true})


# ============================================================================================
# D galleries: service walkways along both sides of the shaft at 21.78 (mid) and 43.56 (E).
# Rails on the shaft edge, emergency lamps on the battery circuit, fire points, a few jobs left mid-way.
# ============================================================================================
func _galleries() -> void:
	_group("D_Galleries")
	for side in [-1.0, 1.0]:
		var ex: float = 12.35 * side
		# mid level: breaks at the two bridges
		for r in [[10.5, -37.0], [-44.0, -126.0], [-133.0, -180.5]]:
			RAIL(Vector3(ex, FY_B, r[0]), Vector3(ex, FY_B, r[1]), [3] if side > 0 and r[0] == -44.0 else [], {"name": "Railing_ShaftEdge_Mid"})
		for r in [[10.0, -126.0], [-133.0, -181.0]]:
			RAIL(Vector3(ex, FY_E, r[0]), Vector3(ex, FY_E, r[1]), [8] if side < 0 and r[0] == 10.0 else [], {"name": "Railing_ShaftEdge_E"})
	# bridge rails (mid N + S, E N)
	for z in [-133.2, -125.8]:
		RAIL(Vector3(-11.9, FY_B, z), Vector3(11.9, FY_B, z), [], {"name": "Railing_BridgeN"})
		RAIL(Vector3(-11.9, FY_E, z), Vector3(11.9, FY_E, z), [], {"name": "Railing_BridgeN_E"})
	for z in [-44.2, -36.8]:
		RAIL(Vector3(-11.9, FY_B, z), Vector3(11.9, FY_B, z), [1] if z < -40 else [], {"name": "Railing_BridgeS"})
	# outer walls: x -21.x (west, faces +x) / +21.x (east, faces -x)
	var wx := {-1.0: -21.0, 1.0: 21.0}
	for side in [-1.0, 1.0]:
		var hit := _ray(Vector3(16.0 * side, FY_B + 1.5, -100.0), Vector3(30.0 * side, FY_B + 1.5, -100.0))
		if not hit.is_empty():
			wx[side] = (hit["position"] as Vector3).x
	print("gallery walls: ", wx)
	var lamp_i := 0
	for lvl in [FY_B, FY_E]:
		for side in [-1.0, 1.0]:
			var x: float = wx[side] - 0.04 * side
			var yaw := 90.0 if side < 0 else -90.0
			var z := 2.0
			while z > -178.0:
				if absf(z + 129.5) < 6.0 or absf(z + 40.5) < 6.0:
					z -= 6.0
					continue
				lamp_i += 1
				P(PK.EMERGENCY_LAMP, Vector3(x, lvl + 3.6, z), yaw, {"v": lamp_i % 2, "lit": lamp_i % 3 == 0, "name": "EmergencyLamp_Battery"})
				if lamp_i % 2 == 0:
					H(HK.HOSE_REEL, Vector3(x - 0.02 * side, lvl, z - 4.0), yaw, {"name": "FirePoint_HoseReel"})
					H(HK.EXTINGUISHER, Vector3(x - 0.02 * side, lvl, z - 5.6), yaw, {"name": "FirePoint_Extinguisher"})
				else:
					H(HK.JUNCTION_BOX, Vector3(x - 0.02 * side, lvl + 1.4, z - 4.0), yaw, {"length": 2.5, "name": "JunctionBox_SpinePower"})
				z -= 34.0
	# west mid gallery: freight waiting at z -90; drums + a dead drone
	P(PK.POD, Vector3(-16.6, FY_B, -88.0), 92.0, {"v": 1, "name": "Pod_StagedForSpine"})
	H(HK.CRATE_METAL, Vector3(-18.9, FY_B, -96.5), 4.0, {"v": 1, "name": "Crate_Staged"})
	H(HK.CRATE_METAL, Vector3(-18.9, FY_B, -98.4), -3.0, {"v": 0, "name": "Crate_Staged"})
	P(PK.DRONE, Vector3(-15.0, FY_B, -150.0), 40.0, {"v": 2, "name": "Drone_Fallen"})
	P(PK.CONE, Vector3(-14.2, FY_B, -61.0), 0.0, {"name": "Cone"})
	# east mid gallery: drone bay on the wall (facing the shaft) at z -80
	P(PK.DRONE_RACK, Vector3(wx[1.0] - 0.02, FY_B, -80.0), -90.0, {"v": 1, "name": "DroneRack_SpineInspection"})
	P(PK.STENCIL, Vector3(wx[1.0] - 0.02, FY_B + 4.2, -76.0), -90.0, {"text": "SPINE MAINT 2", "size": Vector3(0.09, 1, 1), "name": "Stencil_SpineMaint"})
	# blockage 1: ceiling panel + pipe collapse across the east mid gallery at z -6 (VAULT, ~1 m x 0.6 m)
	_blockage_vault(wx[1.0], 12.4, -6.0)
	# E west gallery: someone slept here
	P(PK.TARP, Vector3(wx[-1.0] + 0.1, FY_E, -62.0), 90.0, {"size": Vector3(3.2, 1.5, 2.0), "v": 1, "name": "Tarp_LeanTo"})
	P(PK.BEDROLL, Vector3(wx[-1.0] + 1.2, FY_E, -62.0), 90.0, {"v": 1, "name": "Bedroll"})
	P(PK.CANS, Vector3(wx[-1.0] + 2.8, FY_E, -59.5), 0.0, {"name": "Cans"})
	P(PK.CHEMLIGHT, Vector3(wx[-1.0] + 2.6, FY_E, -64.0), 30.0, {"lit": true, "name": "Chemlight_Camp"})
	P(PK.TAG, Vector3(wx[-1.0] + 0.02, FY_E + 1.6, -57.0), 90.0, {"v": 3, "st": 1, "size": Vector3(0.9, 1, 1), "name": "Tag_Tally_DaysHere"})


## Blockage 1 (decision 6): a ceiling panel came down with a cable tray and a pipe; slab chunks + debris
## make a ridge ~1.0 m tall, 0.6 m deep across the gallery from the wall at wall_x to the shaft edge.
func _blockage_vault(wall_x: float, edge_x: float, z: float) -> void:
	var x0 := edge_x + 0.1
	var x1 := wall_x - 0.1
	var w := x1 - x0
	var n := int(ceil(w / 2.2))
	for i in n:
		var cx := lerpf(x0, x1, (i + 0.5) / n)
		P(PK.SLAB, Vector3(cx, FY_B, z + _rng.randf_range(-0.08, 0.08)), 0.0, {"size": Vector3(w / n / 0.8 + 0.2, 1.0, 0.75), "tag": PILE_TAG, "name": "Slab_CollapseRidge"})
	P(PK.CEIL_PANEL, Vector3((x0 + x1) * 0.5, FY_B, z + 1.6), 8.0, {"size": Vector3(w * 0.8, 1, 1.6), "tag": PILE_TAG, "name": "CeilingPanel_Fallen"})
	P(PK.CABLE_TRAY, Vector3((x0 + x1) * 0.5 - 0.5, FY_B, z - 1.3), -12.0, {"size": Vector3(w * 0.9, 1, 1), "tag": PILE_TAG, "name": "CableTray_Fallen"})
	P(PK.DEBRIS, Vector3((x0 + x1) * 0.5, FY_B, z), 0.0, {"size": Vector3(w, 1, 3.4), "name": "Debris_Collapse"})
	# the gap in the ceiling it fell from: hanging wires + a snapped pipe
	PIPE([Vector3(x1 - 0.4, FY_B + 7.0, z - 4.0), Vector3(x1 - 0.4, FY_B + 7.0, z + 0.4)], 0.2, {"service": PS.WATER, "mount": Vector3.UP, "snapped": true, "name": "Pipe_SnappedAboveCollapse"})
	PIPE([Vector3(x0 + 2.0, FY_B + 7.2, z + 0.3), Vector3(x0 + 2.4, FY_B + 4.6, z + 0.6)], 0.02, {"mount": Vector3.UP, "name": "Wire_Hanging"})
	PIPE([Vector3(x0 + 4.0, FY_B + 7.2, z - 0.2), Vector3(x0 + 3.8, FY_B + 3.9, z - 0.4)], 0.02, {"mount": Vector3.UP, "name": "Wire_Hanging"})


# ============================================================================================
# Mid cross corridors (21.78): B's two entrances and the service runs to the east corridor.
# ============================================================================================
func _corridors_mid() -> void:
	_group("Corridors_Mid")
	# B north entrance: roll-up shutter (left open by the evacuation), red beacon
	var sn := span(Vector3(-57.6, FY_B, -129.0), Vector3.BACK)
	P(PK.BULKHEAD, Vector3(-57.6, FY_B, sn["centre"].z), 90.0, {"size": Vector3(sn["width"] - 0.06, minf(sn["height"], 7.3), 0), "v": 1, "text": "YARD B N", "wall_ok": true, "name": "Bulkhead_YardNorth"})
	P(PK.EMERGENCY_LAMP, Vector3(-57.4, FY_B + 5.6, sn["centre"].z + 3.0), 90.0, {"v": 2, "lit": true, "name": "Beacon_YardNorth"})
	# B south entrance: personnel door in a sealed bulkhead
	var ss := span(Vector3(-57.6, FY_B, -40.5), Vector3.BACK)
	P(PK.BULKHEAD, Vector3(-57.6, FY_B, ss["centre"].z), 90.0, {"size": Vector3(ss["width"] - 0.06, minf(ss["height"], 7.3), 0.0), "v": 0, "text": "YARD B S", "wall_ok": true, "name": "Bulkhead_YardSouth"})
	_group("Doors")
	DOOR(Hub2Door.Type.SHUTTER, Vector3(-57.6, FY_B, sn["centre"].z), 90.0, {"width": 4.2, "height": 4.4, "open": true, "name": "Shutter_YardNorth"})
	DOOR(Hub2Door.Type.SWING, Vector3(-57.6, FY_B, ss["centre"].z), 90.0, {"keypad": 2, "name": "Door_YardSouth"})
	_group("Corridors_Mid")
	# north corridor (x -57..-21): traffic route; jersey chicane, totes left on a pallet, dead LEDs
	P(PK.JERSEY, Vector3(-44.0, FY_B, -131.4), 0.0, {"v": 2, "name": "Jersey_Chicane"})
	P(PK.JERSEY, Vector3(-38.0, FY_B, -126.7), 0.0, {"v": 2, "name": "Jersey_Chicane"})
	H(HK.PALLET, Vector3(-30.5, FY_B, -131.6), 0.0, {"v": 1, "name": "Pallet_Totes"})
	P(PK.LED_STRIP, Vector3(-40.0, FY_B + 6.6, -132.8), 0.0, {"size": Vector3(14, 1, 1), "lit": true, "name": "LedStrip_FewAlive"})
	P(PK.TAG, Vector3(-50.0, FY_B + 1.8, -132.85), 0.0, {"v": 0, "st": 0, "size": Vector3(1.1, 1, 1), "roll": 180.0, "name": "Tag_Arrow_ToYard"})
	# south corridor: a ceiling panel down (not blocking), papers blown along
	P(PK.CEIL_PANEL, Vector3(-36.0, FY_B, -40.0), 70.0, {"size": Vector3(3.0, 1, 1.4), "name": "CeilingPanel_Down"})
	P(PK.PAPERS, Vector3(-44.0, FY_B, -41.0), 0.0, {"size": Vector3(3, 1, 3), "name": "Papers"})
	P(PK.LED_STRIP, Vector3(-40.0, FY_B + 6.6, -37.1), 180.0, {"size": Vector3(14, 1, 1), "name": "LedStrip_Dead"})
	P(PK.EMERGENCY_LAMP, Vector3(-28.0, FY_B + 4.0, -37.15), 180.0, {"v": 1, "lit": true, "name": "EmergencyLamp_Amber"})
	# east halves to the east corridor (x 21..34)
	P(PK.CONE, Vector3(26.0, FY_B, -128.0), 0.0, {"name": "Cone"})
	P(PK.CONE, Vector3(27.2, FY_B, -130.6), 0.0, {"v": 1, "name": "Cone_Knocked"})
	P(PK.TAG, Vector3(30.0, FY_B + 1.8, -132.85), 0.0, {"v": 0, "st": 2, "size": Vector3(1.0, 1, 1), "name": "Tag_Arrow_ToDock"})


# ============================================================================================
# East corridor (ramps 21.8 -> 30.8) and the C link, with blockage 2 (scavenger sandbag barricade).
# ============================================================================================
func _c_link_and_east() -> void:
	_group("C_Link")
	H(HK.PALLET_JACK, Vector3(38.5, FY_C, -100.0), 15.0, {"name": "PalletJack_Abandoned"})
	H(HK.CRATE_WOOD, Vector3(39.6, FY_C, -95.0), 8.0, {"v": 1, "name": "Crate_OffTheJack"})
	P(PK.EMERGENCY_LAMP, Vector3(34.8, 30.8 + 3.8, -110.0), 90.0, {"v": 1, "lit": true, "name": "EmergencyLamp_Amber"})
	P(PK.LED_STRIP, Vector3(42.3, 30.8 + 5.8, -95.0), -90.0, {"size": Vector3(20, 1, 1), "name": "LedStrip_Dead"})
	# blockage 2 at x 53: sandbags across the link facing west, a crate to step on, chem lights onward
	var s := span(Vector3(53.0, FY_C, -108.5), Vector3.BACK)
	P(PK.SANDBAGS, Vector3(53.0, FY_C, s["centre"].z), 90.0, {"size": Vector3(s["width"] - 0.15, 1.0, 1), "name": "Sandbags_Barricade_Blockage2"})
	H(HK.CRATE_WOOD, Vector3(51.6, FY_C, s["centre"].z - 2.5), 4.0, {"v": 0, "name": "Crate_StepUp"})
	P(PK.TAG, Vector3(53.5, FY_C + 2.2, s["centre"].z - s["width"] * 0.5 + 0.03), 0.0, {"v": 2, "st": 0, "size": Vector3(1.0, 1, 1), "name": "Tag_Skull_KeepOut"})
	for i in 3:
		P(PK.CHEMLIGHT, Vector3(57.0 + i * 4.0, FY_C, s["centre"].z + (0.6 if i % 2 == 0 else -0.5)), 30.0 * i, {"lit": true, "name": "Chemlight_Trail"})
	# C entrance: shutter in a bulkhead at the link's east end
	var sc := span(Vector3(68.6, FY_C, -108.0), Vector3.BACK)
	P(PK.BULKHEAD, Vector3(68.6, FY_C, sc["centre"].z), 90.0, {"size": Vector3(sc["width"] - 0.06, minf(sc["height"], 7.3), 0.0), "v": 1, "text": "DOCK C", "wall_ok": true, "name": "Bulkhead_DockC"})
	_group("Doors")
	DOOR(Hub2Door.Type.SHUTTER, Vector3(68.6, FY_C, sc["centre"].z), 90.0, {"width": 4.2, "height": 4.4, "name": "Shutter_DockC"})


# ============================================================================================
# C dock hall (x 69.4..112.4, z -136..-82, floor 30.95): unpacking + inspection. Docks on the east
# wall, inspection line in the middle, foreman's office NW, racking N, refuel bay SW, stair to the
# south ledge (and on up the ramp to the plant room).
# ============================================================================================
func _c_dock() -> void:
	_group("C_Dock")
	var y := FY_C
	var crane := Hub2Crane.new()
	crane.type = Hub2Crane.Type.BRIDGE
	crane.span = 40.0
	crane.runway_length = 52.0
	crane.rail_height = 11.0
	crane.column_pitch = 17.333
	crane.bridge_z = 9.0
	crane.trolley_x = -6.0
	crane.hook_drop = 5.0
	crane.wear = 0.85
	crane.position = Vector3(90.9, y, -109.0)
	_own(crane, "BridgeCrane_DockC")
	for k in 4:
		for sx in [-1.0, 1.0]:
			var cz := -109.0 - 26.0 + k * 17.333
			_boxes.append([crane, Transform3D(Basis.IDENTITY, Vector3(90.9 + sx * 20.0, y + 5.5, cz)), Vector3(0.7, 5.5, 0.7), "", false, true])
	# docks: shutters on the east wall between crane columns, bollards
	var docks := [[-126.0, 0, "DOCK 1"], [-108.6, 1, "DOCK 2"], [-91.8, 0, "DOCK 3"]]
	for d: Array in docks:
		P(PK.SHUTTER, Vector3(112.25, y, d[0]), -90.0, {"size": Vector3(4.6, 5.0, 1), "st": d[1], "text": d[2], "wall_ok": true, "name": "DockShutter"})
		P(PK.BOLLARD, Vector3(110.6, y, d[0] - 3.4), 0.0, {"name": "Bollard_Dock"})
		P(PK.BOLLARD, Vector3(110.6, y, d[0] + 3.4), 0.0, {"name": "Bollard_Dock"})
	P(PK.EMERGENCY_LAMP, Vector3(112.3, y + 6.4, -108.6), -90.0, {"v": 3, "lit": true, "name": "Beacon_Dock2_Amber"})
	# inspection line
	P(PK.SCANNER_ARCH, Vector3(84.5, y, -110.0), 90.0, {"name": "CargoScanner"})
	P(PK.INSPECT_TABLE, Vector3(91.0, y, -110.0), 0.0, {"name": "InspectionTable_A"})
	P(PK.INSPECT_TABLE, Vector3(94.1, y, -110.0), 0.0, {"name": "InspectionTable_B"})
	P(PK.POD, Vector3(96.0, y, -119.5), 12.0, {"v": 2, "name": "Pod_SplitForInspection"})
	H(HK.TOTE, Vector3(99.5, y, -104.5), 0.0, {"v": 2, "name": "Totes_Sorted"})
	H(HK.TOTE, Vector3(100.4, y, -104.5), 0.0, {"v": 3, "name": "Totes_Sorted"})
	H(HK.TOTE, Vector3(101.3, y, -104.5), 0.0, {"v": 1, "name": "Totes_Sorted"})
	H(HK.CRATE_METAL, Vector3(88.0, y, -104.5), 90.0, {"v": 2, "name": "Crate_Opened"})
	H(HK.PALLET, Vector3(103.5, y, -114.0), 90.0, {"v": 0, "name": "Pallet_Wrapped_Unchecked"})
	H(HK.PALLET_JACK, Vector3(101.0, y, -116.8), -60.0, {"name": "PalletJack"})
	P(PK.TAG, Vector3(96.0 - 1.2, y + 1.3, -118.3), 12.0, {"v": 1, "st": 0, "size": Vector3(0.6, 1, 1), "name": "Tag_X_Emptied", "sky_ok": false})
	# racking along the north wall
	for i in 5:
		H(HK.RACKING, Vector3(80.5 + i * 2.75, y, -135.1), 0.0, {"v": 1 if i == 3 else 0, "name": "Racking_NorthWall"})
	H(HK.CRATE_WOOD, Vector3(86.0, y, -132.8), 25.0, {"v": 2, "name": "Crate_KnockedOffRack"})
	# foreman's office, NW corner
	P(PK.CABIN, Vector3(75.6, y, -134.3), 0.0, {"v": 0, "name": "Cabin_ForemanOffice"})
	_group("Doors")
	DOOR(Hub2Door.Type.SWING, Vector3(75.6 - 1.1, y + 0.2, -134.3 + 1.21), 0.0, {"keypad": 1, "name": "Door_ForemanOffice"})
	_group("C_Dock")
	P(PK.DESK, Vector3(77.4, y + 0.22, -134.6), 0.0, {"v": 1, "name": "Desk_Foreman_Ransacked"})
	P(PK.CHAIR, Vector3(76.2, y + 0.22, -133.6), 40.0, {"v": 1, "name": "Chair_Tipped"})
	# refuel bay SW: fuel point fed by the gas line, a loader parked at it
	H(HK.FUEL_STATION, Vector3(78.0, y, -90.6), 0.0, {"name": "FuelPoint_GasLineSink"})
	P(PK.LOADER, Vector3(83.5, y, -95.0), 90.0, {"v": 0, "name": "Loader_ParkedAtFuel"})
	P(PK.PUDDLE, Vector3(78.6, y, -93.6), 0.0, {"size": Vector3(2.4, 1, 1.6), "name": "Puddle_FuelSpill"})
	# dead high-bays, one down on the floor
	for p: Vector2 in [Vector2(80, -125), Vector2(100, -125), Vector2(80, -98), Vector2(100, -98)]:
		H(HK.LAMP_HIGHBAY, Vector3(p.x, 46.9, p.y), 0.0, {"length": 3.0, "name": "HighBay_Dead"})
	H(HK.LAMP_HIGHBAY, Vector3(90.0, y + 0.6, -124.0), 0.0, {"length": 0.1, "roll": 95.0, "name": "HighBay_FallenSmashed"})
	P(PK.DEBRIS, Vector3(90.0, y, -124.6), 0.0, {"size": Vector3(2.0, 1, 1.6), "name": "Debris_Glass"})
	# stair to the south ledge (7.25 m) + landing deck against the ledge face, rails on the ledge edge
	var rise := FY_LEDGE - y
	P(PK.STAIR, Vector3(89.6, y, -89.6), 90.0, {"size": Vector3(2.2, rise, 10.0), "tag": "stair", "wall_ok": true, "name": "Stair_ToDockLedge"})
	P(PK.DECK, Vector3(101.2, y, -88.7), 0.0, {"size": Vector3(3.2, rise, 2.4), "tag": "stair", "name": "Landing_DockLedge"})
	RAIL(Vector3(70.0, FY_LEDGE, -87.3), Vector3(99.4, FY_LEDGE, -87.3), [2], {"name": "Railing_LedgeEdge"})
	RAIL(Vector3(103.0, FY_LEDGE, -87.3), Vector3(112.0, FY_LEDGE, -87.3), [], {"name": "Railing_LedgeEdge"})
	P(PK.STENCIL, Vector3(70.0, y + 5.0, -135.9 + 0.02), 0.0, {"text": "KADE FREIGHT  DOCK C", "size": Vector3(0.12, 1, 1), "name": "Stencil_DockC", "sky_ok": true})


# ============================================================================================
# E level: NW overlook (sniper nest), the B-E link blast door (blockage 4), the big collapse in the
# south corridor (blockage 3).
# ============================================================================================
func _e_level() -> void:
	_group("E_Level")
	var y := FY_E
	# overlook door
	var so := span(Vector3(-29.4, y, -130.5), Vector3.BACK)
	P(PK.BULKHEAD, Vector3(-30.2, y, so["centre"].z), 90.0, {"size": Vector3(so["width"] - 0.06, minf(so["height"], 7.3), 0.0), "v": 0, "text": "OBS 1", "wall_ok": true, "name": "Bulkhead_Overlook"})
	_group("Doors")
	DOOR(Hub2Door.Type.SWING, Vector3(-30.2, y, so["centre"].z), 90.0, {"keypad": 1, "name": "Door_Overlook"})
	_group("E_Level")
	# overlook room (x -42..-30, z -162..-126), open west edge: rails + a sandbag nest
	RAIL(Vector3(-40.6, y, -161.4), Vector3(-40.6, y, -150.5), [], {"name": "Railing_OverlookEdge"})
	RAIL(Vector3(-40.6, y, -144.0), Vector3(-40.6, y, -126.6), [1], {"name": "Railing_OverlookEdge"})
	P(PK.SANDBAGS, Vector3(-40.3, y, -147.25), 90.0, {"size": Vector3(6.2, 1.1, 1), "name": "Sandbags_SniperNest"})
	P(PK.BEDROLL, Vector3(-37.9, y, -147.0), 0.0, {"v": 2, "name": "Bedroll_Nest"})
	P(PK.CANS, Vector3(-37.0, y, -144.0), 0.0, {"name": "Cans_Nest"})
	P(PK.DRUM, Vector3(-35.0, y, -151.0), 0.0, {"v": 3, "st": 2, "name": "BurnBarrel_Cold"})
	P(PK.TAG, Vector3(-31.0 + 0.0, y + 1.7, -158.0), -90.0, {"v": 3, "st": 3, "size": Vector3(1.2, 1, 1), "name": "Tag_Tally"})
	# blockage 4: B balcony <-> E south corridor, unpowered blast door jammed 1 m apart (squeeze)
	var sb := span(Vector3(-50.0, y, -42.0), Vector3.BACK)
	var bh: float = minf(sb["height"], 7.3)
	P(PK.BULKHEAD, Vector3(-50.0, y, sb["centre"].z), 90.0, {"size": Vector3(sb["width"] - 0.06, bh, 0.0), "v": 2, "wall_ok": true, "name": "Bulkhead_BlastFrame_BalconyLink"})
	_group("Doors")
	DOOR(Hub2Door.Type.BLAST, Vector3(-50.0, y, sb["centre"].z), 90.0, {"width": sb["width"] - 1.6, "height": bh - 1.0, "gap": 1.0, "name": "BlastDoor_Jammed_Blockage4"})
	_group("E_Level")
	# blockage 3: the big collapse in the south corridor (x 44..52): slabs climb to ~2.3 m, a 0.9 m
	# squeeze along the north wall under a leaning slab
	var sc := span(Vector3(48.0, y, -42.0), Vector3.BACK)
	var zn: float = sc["centre"].z - sc["width"] * 0.5   # north wall
	var zs: float = sc["centre"].z + sc["width"] * 0.5
	var zc := (zn + 0.95 + zs) * 0.5
	var w := zs - (zn + 0.95)
	P(PK.SLAB, Vector3(46.0, y, zc), 90.0, {"size": Vector3(w / 0.8 - 0.2, 1.2, 2.6), "roll": 9.0, "tag": PILE_TAG, "wall_ok": true, "name": "Slab_Collapse_Base"})
	P(PK.SLAB, Vector3(49.0, y, zc - 0.2), 84.0, {"size": Vector3(w / 0.8 - 0.3, 1.4, 2.4), "roll": -7.0, "tag": PILE_TAG, "wall_ok": true, "name": "Slab_Collapse_Base"})
	P(PK.SLAB, Vector3(47.4, y + 1.0, zc + 0.3), 101.0, {"size": Vector3(w / 0.8 - 1.2, 0.7, 2.6), "roll": 14.0, "pitch": 6.0, "tag": PILE_TAG, "name": "Slab_Collapse_Top"})
	P(PK.SLAB, Vector3(51.8, y, zc + 0.2), 95.0, {"size": Vector3(w / 0.8 - 0.4, 0.9, 2.0), "roll": -16.0, "tag": PILE_TAG, "wall_ok": true, "name": "Slab_Collapse_Tail"})
	P(PK.CEIL_PANEL, Vector3(44.2, y, zc), 80.0, {"size": Vector3(w - 0.4, 1, 1.6), "tag": PILE_TAG, "name": "CeilingPanel_InCollapse"})
	P(PK.REBAR, Vector3(45.6, y + 1.3, zc - 0.4), 120.0, {"tag": PILE_TAG, "name": "Rebar_InCollapse"})
	P(PK.SLAB, Vector3(48.2, y + 1.6, zn + 0.6), 90.0, {"size": Vector3(4.2, 0.35, 1.2), "pitch": 0.0, "roll": -38.0, "tag": PILE_TAG, "wall_ok": true, "name": "Slab_LeaningOverSqueeze"})
	P(PK.CABLE_TRAY, Vector3(47.0, y + 2.2, zc), 80.0, {"size": Vector3(w - 0.6, 1, 1), "tag": PILE_TAG, "name": "CableTray_InCollapse"})
	P(PK.REBAR, Vector3(50.0, y + 1.0, zc + 0.6), 30.0, {"tag": PILE_TAG, "name": "Rebar_InCollapse"})
	P(PK.DEBRIS, Vector3(43.4, y, zc), 0.0, {"size": Vector3(3.4, 1, w), "name": "Debris_CollapseFront"})
	P(PK.DEBRIS, Vector3(41.0, y, zc + 0.8), 0.0, {"size": Vector3(2.0, 1, 2.4), "name": "Debris_CollapseSpill"})
	P(PK.DEBRIS, Vector3(53.8, y, zc), 0.0, {"size": Vector3(2.0, 1, w), "name": "Debris_CollapseBack"})
	PIPE([Vector3(47.5, 50.4, zs - 0.5), Vector3(47.5, 47.9, zs - 1.2)], 0.02, {"mount": Vector3.UP, "name": "Wire_Hanging"})


# ============================================================================================
# Plant room (x 81..119, z -68..-19, floor 43.56, ceiling ~58.9): where the pipe network starts.
# Two tanks, three pumps, control panel; the west door; blockage 5 (burst header + fallen cabinet).
# ============================================================================================
func _plant_room() -> void:
	_group("E_PlantRoom")
	var y := FY_E
	# room x 77.6..111.6, z -65.6..-16.4; W door z -44.1..-36.6 (from the corridor), E door same z (to
	# the outer void walk: welded shut), N opening x 91.1..102.1 (ramp down to the C ledge)
	P(PK.TANK_V, Vector3(107.4, y, -23.4), 0.0, {"size": Vector3(2.2, 8.0, 1), "text": "T-1 WATER", "name": "Tank_T1_Water"})
	P(PK.TANK_V, Vector3(107.8, y, -59.6), 0.0, {"size": Vector3(1.9, 7.0, 1), "text": "T-2 FUEL GAS", "name": "Tank_T2_Gas"})
	P(PK.PUMP, Vector3(98.0, y, -23.4), 180.0, {"name": "Pump_P1_WaterMain"})
	P(PK.PUMP, Vector3(98.0, y, -29.4), 180.0, {"name": "Pump_P2_FireMain"})
	P(PK.PUMP, Vector3(98.0, y, -59.6), 180.0, {"v": 1, "name": "Pump_P3_MotorPulled"})
	var wx := 77.6
	H(HK.TERMINAL, Vector3(wx + 0.02, y, -58.0), 90.0, {"v": 2, "lit": true, "name": "Terminal_PumpControl_Alarm", "wall_ok": true})
	H(HK.CABINET, Vector3(wx + 0.02, y, -53.6), 90.0, {"v": 0, "name": "Cabinet_MCC", "wall_ok": true})
	H(HK.CABINET, Vector3(wx + 0.02, y, -52.0), 90.0, {"v": 2, "name": "Cabinet_MCC", "wall_ok": true})
	P(PK.STENCIL, Vector3(wx + 0.02, y + 6.0, -62.0), 90.0, {"text": "PUMP HOUSE 2", "size": Vector3(0.14, 1, 1), "name": "Stencil_PumpHouse"})
	P(PK.EMERGENCY_LAMP, Vector3(wx + 0.02, y + 4.0, -47.0), 90.0, {"v": 1, "lit": true, "name": "EmergencyLamp_Amber_Door", "wall_ok": true})
	for p: Vector2 in [Vector2(88, -28), Vector2(88, -56), Vector2(102, -42)]:
		H(HK.LAMP_HIGHBAY, Vector3(p.x, 58.7, p.y), 0.0, {"length": 3.5, "name": "HighBay_Dead"})
	P(PK.DRUM, Vector3(102.5, y, -18.3), 0.0, {"v": 0, "name": "Drum_Treatment"})
	P(PK.DRUM, Vector3(103.3, y, -17.6), 0.0, {"v": 0, "name": "Drum_Treatment"})
	P(PK.DRUM, Vector3(104.6, y, -18.5), 0.0, {"v": 0, "st": 1, "name": "Drum_Tipped"})
	# filter skids + a valve manifold on the south wall, a spare pump pallet, catwalk over T-1
	P(PK.TANK_V, Vector3(90.0, y, -19.8), 0.0, {"size": Vector3(1.0, 3.0, 1), "text": "F-1", "name": "Filter_F1"})
	P(PK.TANK_V, Vector3(93.0, y, -19.8), 0.0, {"size": Vector3(1.0, 3.0, 1), "text": "F-2", "name": "Filter_F2"})
	PIPE([Vector3(86.0, y + 2.6, -16.9), Vector3(104.0, y + 2.6, -16.9)], 0.16, {"service": PS.WATER, "mount": Vector3.BACK, "name": "Manifold_SouthWall"})
	PIPE([Vector3(90.0, y + 4.6, -19.8), Vector3(90.0, y + 4.6, -16.9), Vector3(90.0, y + 2.6, -16.9)], 0.1, {"service": PS.WATER, "mount": Vector3.UP, "name": "Filter_F1_to_Manifold"})
	PIPE([Vector3(93.0, y + 4.6, -19.8), Vector3(93.0, y + 4.6, -16.9), Vector3(93.0, y + 2.6, -16.9)], 0.1, {"service": PS.WATER, "mount": Vector3.UP, "name": "Filter_F2_to_Manifold"})
	H(HK.PALLET, Vector3(86.0, y, -60.5), 10.0, {"v": 1, "name": "Pallet_SparePump"})
	H(HK.CABINET, Vector3(wx + 0.02, y, -26.0), 90.0, {"v": 1, "name": "Cabinet_Spares", "wall_ok": true})
	H(HK.WORKBENCH, Vector3(wx + 0.5, y, -31.0), 90.0, {"name": "Workbench_PumpHouse"})
	P(PK.DECK, Vector3(110.0, y, -31.0), 0.0, {"size": Vector3(3.0, 6.0, 3.0), "name": "Catwalk_T1Valves"})
	P(PK.LADDER, Vector3(110.0, y, -32.45), 180.0, {"size": Vector3(1, 6.0, 1), "name": "Ladder_Catwalk"})
	H(HK.LAMP_HIGHBAY, Vector3(94.0, y + 0.5, -45.0), 0.0, {"length": 0.1, "roll": 80.0, "name": "HighBay_Fallen"})
	P(PK.DEBRIS, Vector3(94.5, y, -45.4), 0.0, {"size": Vector3(1.8, 1, 1.4), "name": "Debris_Glass"})
	# east door to the outer walk: welded shut
	var se := span(Vector3(113.0, y, -40.35), Vector3.BACK)
	P(PK.BULKHEAD, Vector3(111.75, y, se["centre"].z), -90.0, {"size": Vector3(se["width"] - 0.06, minf(se["height"], 7.3), 0.0), "v": 3, "text": "SEALED", "wall_ok": true, "name": "Bulkhead_Welded_OuterWalk"})
	# west door from the E south corridor
	var sd := span(Vector3(76.4, y, -40.35), Vector3.BACK)
	var dz: float = sd["centre"].z
	P(PK.BULKHEAD, Vector3(77.3, y, dz), 90.0, {"size": Vector3(sd["width"] - 0.06, minf(sd["height"], 7.3), 0.0), "v": 0, "text": "PUMPS", "wall_ok": true, "name": "Bulkhead_PumpHouse"})
	_group("Doors")
	DOOR(Hub2Door.Type.SWING, Vector3(77.3, y, dz), 90.0, {"keypad": 1, "name": "Door_PumpHouse"})
	_group("E_PlantRoom")
	# blockage 5: the header burst and fell across the way in; a cabinet came down beside it
	P(PK.PIPE_FALLEN, Vector3(80.6, y, dz + 0.4), 90.0, {"size": Vector3(9.0, 1, 1), "name": "Header_Burst_Blockage5"})
	H(HK.CABINET, Vector3(82.3, y + 0.5, dz - 6.4), 0.0, {"v": 1, "pitch": 0.0, "roll": -90.0, "name": "Cabinet_Fallen"})
	PIPE([Vector3(80.6, 58.3, dz - 9.0), Vector3(80.6, 58.3, dz - 4.4)], 0.42, {"service": PS.WATER, "mount": Vector3.UP, "snapped": true, "name": "Header_SnappedEnd"})
	P(PK.PUDDLE, Vector3(82.4, y, dz - 1.6), 0.0, {"size": Vector3(5.0, 1, 7.0), "name": "Puddle_UnderBurst"})
	P(PK.STAIN, Vector3(wx + 0.02, y + 9.0, dz - 7.0), 90.0, {"size": Vector3(2.5, 8.0, 1), "name": "Stain_Leak"})
	H(HK.MOSS, Vector3(81.0, y, dz - 4.0), 20.0, {"v": 0, "name": "Moss_UnderLeak"})
	H(HK.MOSS, Vector3(84.6, y, dz + 1.0), 70.0, {"v": 1, "name": "Moss_UnderLeak"})
	H(HK.TUFT, Vector3(83.4, y, dz - 3.4), 0.0, {"v": 0, "name": "Tuft_UnderLeak"})


# ============================================================================================
# Pipes: every run has a source (plant room tank / pump) and a sink (floor penetration, hose reel,
# standpipe, fuel point). Coordinates traced along real corners; one run per mounting surface.
# ============================================================================================
func _pipes() -> void:
	_group("Pipes")
	var y := FY_E
	# pump hookups (pump yaw 180: suction at x+1.15 y+0.65, discharge at x-0.35 y+1.7)
	var noz := Vector3(107.4 - 2.2 - 0.4, y + 1.6, -23.4)
	PIPE([noz, Vector3(101.4, y + 1.6, -23.4), Vector3(101.4, y + 0.65, -23.4), Vector3(99.15, y + 0.65, -23.4)], 0.18, {"service": PS.WATER, "mount": Vector3.DOWN, "name": "Water_T1_to_P1"})
	PIPE([Vector3(101.4, y + 1.6, -23.4), Vector3(101.4, y + 1.6, -29.4), Vector3(101.4, y + 0.65, -29.4), Vector3(99.15, y + 0.65, -29.4)], 0.15, {"service": PS.FIRE, "mount": Vector3.DOWN, "name": "Fire_T1_to_P2"})
	var cz := -43.5
	var cy := 50.1
	# water main: P1 up to the roof, west to the door, then along the corridor north wall
	PIPE([Vector3(97.65, y + 1.7, -23.4), Vector3(97.65, 57.0, -23.4), Vector3(80.0, 57.0, -23.4), Vector3(80.0, 57.0, cz), Vector3(78.4, 57.0, cz), Vector3(78.4, cy, cz)],
		0.2, {"service": PS.WATER, "mount": Vector3.UP, "name": "WaterMain_P1_Riser"})
	PIPE([Vector3(78.4, cy, cz), Vector3(20.1, cy, cz)], 0.2, {"service": PS.WATER, "mount": Vector3.FORWARD, "name": "WaterMain_Corridor"})
	PIPE([Vector3(20.1, cy, cz), Vector3(20.1, cy, -120.0), Vector3(20.1, y + 0.05, -120.0)], 0.2, {"service": PS.WATER, "mount": Vector3.RIGHT, "name": "WaterMain_Gallery_to_FloorPenetration"})
	# fire main: P2, same route one pipe lower, then south along the gallery to the reel
	PIPE([Vector3(97.65, y + 1.7, -29.4), Vector3(97.65, 56.3, -29.4), Vector3(80.6, 56.3, -29.4), Vector3(80.6, 56.3, cz + 0.55), Vector3(79.0, 56.3, cz + 0.55), Vector3(79.0, cy - 0.55, cz + 0.55)],
		0.15, {"service": PS.FIRE, "mount": Vector3.UP, "name": "FireMain_P2_Riser"})
	PIPE([Vector3(79.0, cy - 0.55, cz + 0.55), Vector3(19.6, cy - 0.55, cz + 0.55)], 0.15, {"service": PS.FIRE, "mount": Vector3.FORWARD, "name": "FireMain_Corridor"})
	PIPE([Vector3(19.6, cy - 0.55, cz + 0.55), Vector3(19.6, cy - 0.55, -4.0), Vector3(19.6, y + 1.9, -4.0)], 0.15, {"service": PS.FIRE, "mount": Vector3.RIGHT, "name": "FireMain_Gallery_to_HoseReel"})
	H(HK.HOSE_REEL, Vector3(20.66, y, -4.0), -90.0, {"name": "HoseReel_FireMainEnd", "wall_ok": true})
	# the water main comes out of the mid gallery ceiling below, crosses the N bridge on its deck
	# edge and runs to the yard north standpipe
	PIPE([Vector3(20.1, 29.0, -120.0), Vector3(20.1, 27.9, -120.0), Vector3(20.1, 27.9, -132.3), Vector3(12.6, 27.9, -132.3)], 0.2, {"service": PS.WATER, "mount": Vector3.UP, "name": "WaterMain_MidGallery"})
	PIPE([Vector3(12.6, 27.9, -132.3), Vector3(12.6, 22.4, -132.3), Vector3(-12.6, 22.4, -132.3), Vector3(-12.6, 27.9, -132.3)], 0.2, {"service": PS.WATER, "mount": Vector3.DOWN, "name": "WaterMain_BridgeN"})
	PIPE([Vector3(-12.6, 27.9, -132.3), Vector3(-55.8, 27.9, -132.3), Vector3(-55.8, FY_B + 1.4, -132.3)], 0.2, {"service": PS.WATER, "mount": Vector3.UP, "name": "WaterMain_CrossN_to_Standpipe"})
	H(HK.HOSE_REEL, Vector3(-55.8, FY_B, -132.95), 0.0, {"name": "Standpipe_YardNorth", "wall_ok": true})
	# gas: T-2 top -> north through the opening -> down the ramp -> along under C's ceiling at the
	# ledge -> down the ledge face -> into the fuel point pump column in C's SW bay
	var t2 := Vector3(107.8, y + 1.3 + 7.0 + 0.4, -59.6)
	PIPE([t2, Vector3(107.8, 57.2, -59.6), Vector3(107.8, 57.2, -64.8), Vector3(96.6, 57.2, -64.8), Vector3(96.6, 49.6, -64.8), Vector3(96.6, 49.6, -66.4),
		Vector3(96.6, 47.4, -73.0), Vector3(96.6, 45.6, -80.0), Vector3(96.6, 45.6, -84.6), Vector3(77.2, 45.6, -84.6), Vector3(77.2, 45.6, -87.9),
		Vector3(77.2, FY_C + 3.0, -87.9), Vector3(77.2, FY_C + 3.0, -90.6), Vector3(77.2, FY_C + 1.95, -90.6)],
		0.12, {"service": PS.GAS, "mount": Vector3.UP, "name": "GasLine_T2_to_FuelPoint"})


# ============================================================================================
# B yard (x -151..-58, z -159..53, floor 21.78, roof 69.3): bulk container storage under one gantry
# crane (its second bridge fell). Blocks of 40 ft boxes 2 long x 6 wide, aisles, a vehicle road on
# both sides, the main scavenger camp in a pocket of block T west, charging bay south.
# ============================================================================================
func _b_yard() -> void:
	_group("B_Yard")
	var y := FY_B
	var crane := Hub2Crane.new()
	crane.type = Hub2Crane.Type.BRIDGE
	crane.span = 64.0
	crane.runway_length = 190.0
	crane.rail_height = 26.0
	crane.column_pitch = 23.75
	crane.bridge_z = 10.0
	crane.trolley_x = 6.0
	crane.hook_drop = 13.0
	crane.dangling = 0.0
	crane.wear = 0.85
	crane.position = Vector3(-106.0, y, -55.0)
	_own(crane, "GantryCrane_Yard")
	for k in 9:
		for sx in [-1.0, 1.0]:
			_boxes.append([crane, Transform3D(Basis.IDENTITY, Vector3(-106.0 + sx * 32.0, y + 11.0, -55.0 - 95.0 + k * 23.75)), Vector3(0.7, 11.0, 0.7), "", false, true])
	# evacuation: a 20 ft left hanging on the spreader at the hook (hook at y 21.78 + 26 - 13)
	var hook := Vector3(-106.0 + 6.0, y + 26.0 - 13.0, -55.0 + 10.0)
	H(HK.SPREADER, hook + Vector3(0, -2.2, 0), 90.0, {"length": 1.6, "name": "Spreader_StillHolding"})
	P(PK.BOX20, hook + Vector3(0, -2.2 - CH - 0.35, 0), 90.0, {"v": 0, "name": "Box_LeftHangingOnSpreader"})
	# the second bridge: fell into the cross aisle, two 20s crushed beside it
	P(PK.GIRDER_FALLEN, Vector3(-99.5, y, -71.0), 2.0, {"size": Vector3(40.0, 1, 1), "name": "CraneBridge_Fallen"})
	P(PK.BOX20, Vector3(-127.0, y, -71.6), 90.0, {"v": livery(), "st": 3, "name": "Box_CrushedByGirder", "tag": "girder"})
	P(PK.GIRDER_FALLEN, Vector3(-127.2, y + 1.15, -71.4), 182.0, {"size": Vector3(22.0, 1, 1), "pitch": -6.0, "name": "CraneBridge_Fallen_BrokenEnd", "wall_ok": true, "tag": "girder"})
	P(PK.BOX20, Vector3(-92.0, y, -66.5), -14.0, {"v": livery(), "st": 3, "name": "Box_CrushedByGirder"})
	P(PK.DEBRIS, Vector3(-106.0, y, -74.4), 0.0, {"size": Vector3(14.0, 1, 2.0), "name": "Debris_GirderImpact"})
	# container blocks: x columns [west pair -127.8/-115.4], [east pair -96.8/-84.4]; z bands
	var bands := {"N": -143.0, "M": -114.0, "S": -55.0, "T": -26.0}
	for band: String in bands:
		for col in 2:
			var xs: Array = [-127.8, -115.4] if col == 0 else [-96.8, -84.4]
			for row in 6:
				var z: float = bands[band] + 1.35 + row * 2.7
				for e in 2:
					var x: float = xs[e]
					# the camp pocket: block T west, rows 1-3 of the west box are gone
					if band == "T" and col == 0 and e == 0 and row >= 1 and row <= 3:
						continue
					# blockage 6 aisle: keep z -103..-99 free in block M near the aisle ends? (the aisle is x -109.2..-103)
					var h := 1 + (1 if _rng.randf() < 0.55 else 0) + (1 if _rng.randf() < 0.18 else 0)
					if band == "T" and col == 0:
						h = 2
					for lvl in h:
						var st := 0
						if lvl == 0 and _rng.randf() < 0.3:
							st = 1 if _rng.randf() < 0.6 else 2
						if lvl == 0 and band == "S" and col == 1 and row == 2 and e == 1:
							st = 4
						var slide := _rng.randf_range(-0.12, 0.12) if lvl > 0 else 0.0
						P(PK.BOX40, Vector3(x + slide, y + lvl * CH, z), 180.0 if e == 0 else 0.0, {"v": livery(), "st": st, "name": "Box40_Block%s" % band})
	# blockage 6: a 20 ft toppled onto its side across the central aisle of block M
	P(PK.BOX20, Vector3(-106.1, y + 1.219, -103.0), 0.0, {"v": 3, "roll": 90.0, "name": "Box_Toppled_Blockage6"})
	# the scavenger camp in the block T pocket (x -134..-122, z -24.7..-14.2)
	var cc := Vector3(-127.8, y, -19.3)
	P(PK.CAMPFIRE, cc + Vector3(0.5, 0, 0.2), 0.0, {"lit": true, "name": "Campfire_Camp"})
	P(PK.TARP, cc + Vector3(1.8, 0, -4.6), 0.0, {"size": Vector3(5.0, 2.2, 2.6), "v": 0, "name": "Tarp_CampShelter"})
	P(PK.BEDROLL, cc + Vector3(0.2, 0, -3.6), 90.0, {"v": 0, "name": "Bedroll_Camp"})
	P(PK.BEDROLL, cc + Vector3(3.6, 0, -3.4), 95.0, {"v": 2, "name": "Bedroll_Camp"})
	P(PK.BEDROLL, cc + Vector3(-4.0, 0, 2.6), 10.0, {"v": 1, "name": "Bedroll_Camp"})
	H(HK.CRATE_WOOD, cc + Vector3(-2.2, 0, 0.0), 12.0, {"v": 0, "name": "Crate_Seat"})
	H(HK.CRATE_WOOD, cc + Vector3(2.8, 0, 1.6), -20.0, {"v": 0, "name": "Crate_Seat"})
	P(PK.DRUM, cc + Vector3(-4.6, 0, -2.8), 0.0, {"v": 3, "st": 2, "lit": true, "name": "BurnBarrel_Camp"})
	P(PK.CANS, cc + Vector3(-1.0, 0, 2.0), 0.0, {"name": "Cans_Camp"})
	P(PK.PAPERS, cc + Vector3(3.0, 0, -0.5), 0.0, {"size": Vector3(1.6, 1, 1.2), "name": "Papers_Camp"})
	P(PK.STRING_LIGHT, cc + Vector3(-5.6, CH * 2.0 - 0.4, -4.9), 0.0, {"size": Vector3(11.0, 1.0, 1), "lit": true, "name": "StringLight_Camp"})
	P(PK.SANDBAGS, cc + Vector3(-6.3, 0, 0.3), 90.0, {"size": Vector3(4.2, 1.1, 1), "name": "Sandbags_CampMouth"})
	P(PK.TAG, Vector3(-134.0 - 0.02, y + 1.7, -12.2), -90.0, {"v": 4, "st": 2, "size": Vector3(1.0, 1, 1), "name": "Tag_CampMark", "sky_ok": true})
	# chem-light trail from the north entrance down the east road to the camp road
	var trail := [Vector3(-62.0, y, -127.5), Vector3(-67.0, y, -115.0), Vector3(-68.0, y, -98.0), Vector3(-68.5, y, -82.0), Vector3(-69.0, y, -60.0),
		Vector3(-68.0, y, -40.0), Vector3(-70.0, y, -1.5), Vector3(-90.0, y, -1.5), Vector3(-110.0, y, -1.5), Vector3(-137.5, y, -2.0), Vector3(-137.8, y, -10.0)]
	for i in trail.size():
		P(PK.CHEMLIGHT, trail[i], 37.0 * i, {"lit": i % 3 != 2, "name": "Chemlight_TrailToCamp"})
	# charging bay south: loader bays + exoframe cradles + reach stacker abandoned mid-turn
	for i in 4:
		var bx := -128.0 + i * 5.0
		P(PK.BAY_NUMBER, Vector3(bx, y, 23.5), 180.0, {"text": "L%d" % (i + 1), "size": Vector3(0.22, 1, 1), "name": "BayPaint_Loader"})
		if i != 2:
			P(PK.LOADER, Vector3(bx, y, 19.0), 90.0, {"v": 2 if i == 3 else 0, "name": "Loader_Charging" if i != 3 else "Loader_BurntInBay"})
	for i in 3:
		P(PK.EXOFRAME, Vector3(-100.0 + i * 3.4, y, 35.6), 180.0, {"v": 1 if i == 1 else 0, "name": "Exoframe_Cradle"})
	P(PK.STENCIL, Vector3(-102.0, y + 0.02, 30.0), 0.0, {"text": "CHG", "size": Vector3(0.3, 1, 1), "v": 1, "pitch": 0.0, "roll": -90.0, "name": "FloorPaint_CHG"})
	H(HK.REACH_STACKER, Vector3(-86.0, y, 13.0), 32.0, {"name": "ReachStacker_MidTurn"})
	P(PK.CONE, Vector3(-80.0, y, 9.0), 0.0, {"name": "Cone"})
	P(PK.CONE, Vector3(-78.5, y, 11.5), 0.0, {"v": 1, "name": "Cone_Knocked"})
	# emergency beacons inside both entrances, dead floods on the crane columns
	P(PK.EMERGENCY_LAMP, Vector3(-59.0, y + 9.0, -122.0), -90.0, {"v": 2, "lit": true, "name": "Beacon_EntranceN", "wall_ok": true})
	P(PK.EMERGENCY_LAMP, Vector3(-59.0, y + 9.0, -33.0), -90.0, {"v": 2, "lit": true, "name": "Beacon_EntranceS", "wall_ok": true})
	for k in [1, 3, 5, 7]:
		H(HK.FLOODLIGHT, Vector3(-74.0 - 0.8, y + 18.0, -150.0 + k * 23.75), -90.0, {"name": "Flood_OnColumn_Dead"})
	# skylight (broken) over the girder: B's daylight
	P(PK.SKYLIGHT, Vector3(-106.0, 69.3, -72.0), 0.0, {"size": Vector3(14.0, 44.0, 10.0), "name": "Skylight_Frame", "sky_ok": true})


## B's west wall x at z (between the concrete wedges it is a plain wall near x -162).
func _b_wall(z: float) -> float:
	# the wall leans out as it rises: the innermost hit between the floor and 3.5 m is the face
	var best := -INF
	for h in [0.15, 1.0, 2.0, 3.5]:
		var r := _ray(Vector3(-140.0, FY_B + h, z), Vector3(-190.0, FY_B + h, z))
		if not r.is_empty():
			best = maxf(best, (r["position"] as Vector3).x)
	if best == -INF:
		_errors.append("no B west wall at z %.1f" % z)
		return -162.0
	return best


# ============================================================================================
# B rooms against the west wall, in the gaps between the concrete wedges (wedges at z -141..-122,
# -93..-74, -32..-13, 14..33 are solid, not rooms):
#   z -121..-94 workshop shed, z -73..-48 yard office cabins (2 + 1 on top) + generator cage,
#   z -12..13 crew cabins (lockers / break).
# ============================================================================================
func _b_rooms() -> void:
	_group("B_Rooms")
	var y := FY_B
	# workshop shed (open front east)
	var sx := _b_wall(-108.0) + 3.75
	P(PK.SHED, Vector3(sx, y, -108.0), 90.0, {"size": Vector3(13.0, 5.0, 7.0), "name": "Shed_Workshop"})
	P(PK.VEHICLE_LIFT, Vector3(sx + 0.4, y, -111.0), 90.0, {"v": 1, "name": "VehicleLift_LoaderUp"})
	P(PK.TOOL_WALL, Vector3(sx - 3.38, y, -103.2), 90.0, {"name": "ToolWall_Stripped"})
	H(HK.WORKBENCH, Vector3(sx - 2.6, y, -103.2), 90.0, {"name": "Workbench"})
	P(PK.DRUM, Vector3(sx - 2.7, y, -114.6), 0.0, {"v": 4, "name": "Drum_Oil"})
	P(PK.DRUM, Vector3(sx - 1.6, y, -115.6), 0.0, {"v": 4, "st": 1, "name": "Drum_Oil_Tipped"})
	P(PK.PUDDLE, Vector3(sx + 1.0, y, -116.4), 0.0, {"size": Vector3(2.4, 1, 1.8), "name": "Puddle_OilLeak"})
	P(PK.STENCIL, Vector3(sx - 3.4, y + 3.9, -112.5), 90.0, {"text": "WORKSHOP", "size": Vector3(0.1, 1, 1), "name": "Stencil_Workshop"})
	# yard office: two cabins facing the yard + one stacked on top, landing deck + stair up
	var cx := _b_wall(-62.0) + 1.4
	P(PK.CABIN, Vector3(cx, y, -66.0), 90.0, {"v": 0, "name": "Cabin_YardOffice"})
	P(PK.CABIN, Vector3(cx, y, -59.4), 90.0, {"v": 2, "name": "Cabin_YardStore"})
	P(PK.CABIN, Vector3(cx, y + 2.9, -62.7), 90.0, {"v": 0, "st": 1, "name": "Cabin_CraneDispatch"})
	P(PK.DECK, Vector3(cx + 2.6, y, -62.2), 0.0, {"size": Vector3(2.6, 3.1, 3.2), "tag": "stair", "name": "Deck_DispatchLanding"})
	P(PK.STAIR, Vector3(cx + 8.5, y, -62.2), -90.0, {"size": Vector3(1.2, 3.1, 4.6), "tag": "stair", "wall_ok": true, "name": "Stair_ToDispatch"})
	_group("Doors")
	# cabin yaw 90: local +X -> world -Z, local +Z -> world +X. door local (-1.1, 0.2, 1.21)
	DOOR(Hub2Door.Type.SWING, Vector3(cx + 1.21, y + 0.2, -66.0 + 1.1), 90.0, {"keypad": 0, "name": "Door_YardOffice"})
	DOOR(Hub2Door.Type.SWING, Vector3(cx + 1.21, y + 0.2, -59.4), 90.0, {"keypad": 0, "name": "Door_YardStore"})
	DOOR(Hub2Door.Type.SWING, Vector3(cx + 1.21, y + 3.1, -62.7 + 1.1), 90.0, {"keypad": 0, "name": "Door_CraneDispatch"})
	_group("B_Rooms")
	P(PK.DESK, Vector3(cx - 0.7, y + 0.22, -67.4), 90.0, {"v": 1, "name": "Desk_YardOffice"})
	P(PK.BOARD, Vector3(cx - 1.16, y + 0.22, -64.3), 90.0, {"text": "YARD B", "name": "Board_YardMap"})
	P(PK.CHAIR, Vector3(cx + 0.3, y + 0.22, -68.0), 0.0, {"v": 1, "name": "Chair_Tipped"})
	H(HK.TERMINAL, Vector3(cx - 1.16, y + 3.12, -63.7), 90.0, {"v": 0, "lit": true, "name": "Terminal_Dispatch_Alarm"})
	P(PK.DESK, Vector3(cx - 0.4, y + 3.12, -61.6), 90.0, {"v": 0, "name": "Desk_Dispatch"})
	H(HK.CRATE_METAL, Vector3(cx - 0.4, y + 0.22, -57.9), 90.0, {"v": 1, "name": "Crate_Store"})
	H(HK.CRATE_METAL, Vector3(cx - 0.4, y + 0.22, -60.7), 90.0, {"v": 2, "name": "Crate_Store_Pried"})
	# generator cage
	var gx := _b_wall(-40.0) + 1.5
	P(PK.GENERATOR, Vector3(gx, y, -40.6), 90.0, {"name": "Generator_YardPower"})
	P(PK.FUEL_TANK, Vector3(gx, y, -35.2), 90.0, {"text": "DIESEL", "name": "FuelTank_Generator"})
	P(PK.FENCE, Vector3(gx + 2.2, y, -38.25), 90.0, {"size": Vector3(12.3, 1, 1), "v": 1, "name": "Fence_GeneratorCage"})
	P(PK.FENCE, Vector3(gx + 0.45, y, -44.45), 0.0, {"size": Vector3(3.4, 1, 1), "name": "Fence_GeneratorCage"})
	P(PK.FENCE, Vector3(gx + 0.45, y, -32.05), 0.0, {"size": Vector3(3.4, 1, 1), "name": "Fence_GeneratorCage"})
	P(PK.TAG, Vector3(gx + 2.27, y + 1.6, -36.0), 90.0, {"v": 1, "st": 1, "size": Vector3(0.8, 1, 1), "name": "Tag_X_NoFuel"})
	# generator conduit to the nearest crane column (feeds the runway)
	PIPE([Vector3(gx + 0.6, y + 2.6, -41.2), Vector3(gx + 0.6, y + 6.0, -41.2), Vector3(-138.8, y + 6.0, -41.2), Vector3(-138.8, y + 6.0, -55.0),
		Vector3(-138.8, y + 24.0, -55.0)], 0.1, {"service": PS.STEEL, "mount": Vector3.UP, "name": "Conduit_Generator_to_Runway"})
	# crew cabins
	var kx := _b_wall(-2.5) + 1.4
	P(PK.CABIN, Vector3(kx, y, -6.0), 90.0, {"v": 1, "name": "Cabin_CrewLockers"})
	P(PK.CABIN, Vector3(kx, y, 1.0), 90.0, {"v": 1, "st": 1, "name": "Cabin_CrewBreak"})
	_group("Doors")
	DOOR(Hub2Door.Type.SWING, Vector3(kx + 1.21, y + 0.2, -6.0), 90.0, {"keypad": 0, "name": "Door_CrewLockers"})
	DOOR(Hub2Door.Type.SWING, Vector3(kx + 1.21, y + 0.2, 1.0), 90.0, {"keypad": 0, "open": true, "name": "Door_CrewBreak"})
	_group("B_Rooms")
	P(PK.LOCKERS, Vector3(kx - 0.63, y + 0.22, -7.4), 90.0, {"size": Vector3(2.5, 1, 1), "st": 1, "name": "Lockers_Pried"})
	P(PK.BENCH, Vector3(kx + 0.2, y + 0.22, -4.0), 90.0, {"name": "Bench_Lockers"})
	P(PK.TABLE, Vector3(kx - 0.1, y + 0.22, 2.2), 90.0, {"v": 1, "name": "Table_Tipped"})
	P(PK.VENDING, Vector3(kx + 1.8, y, 4.7), 90.0, {"name": "Vending_Smashed"})
	P(PK.BENCH, Vector3(kx + 3.4, y, -1.8), 90.0, {"name": "Bench_Outside"})
	P(PK.CANS, Vector3(kx + 4.0, y, 3.0), 0.0, {"name": "Cans"})


# ============================================================================================
# B balcony (floor x -70..-62, z -83..-24, 43.56): crane control post overlooking the yard.
# ============================================================================================
func _b_balcony() -> void:
	_group("B_Balcony")
	var y := FY_E
	var r := _ray(Vector3(-66.0, y + 1.5, -50.0), Vector3(-50.0, y + 1.5, -50.0))
	var ew := (r["position"] as Vector3).x if not r.is_empty() else -62.0
	var cx := ew - 1.4
	P(PK.CABIN, Vector3(cx, y, -62.0), -90.0, {"v": 0, "name": "Cabin_CraneControl"})
	_group("Doors")
	# yaw -90: local +Z -> world -X, local +X -> world +Z; door local (-1.1, 0.2, 1.21)
	DOOR(Hub2Door.Type.SWING, Vector3(cx - 1.21, y + 0.2, -62.0 - 1.1), -90.0, {"keypad": 1, "name": "Door_CraneControl"})
	_group("B_Balcony")
	P(PK.DESK, Vector3(-68.0, y, -48.0), -90.0, {"v": 0, "name": "Desk_CraneConsole"})
	P(PK.DESK, Vector3(-68.0, y, -45.8), -90.0, {"v": 1, "name": "Desk_CraneConsole"})
	P(PK.CHAIR, Vector3(-66.8, y, -48.2), -90.0, {"name": "Chair_Console"})
	P(PK.CHAIR, Vector3(-66.2, y, -44.6), 30.0, {"v": 1, "name": "Chair_Tipped"})
	P(PK.PAPERS, Vector3(-66.0, y, -47.0), 0.0, {"size": Vector3(2.0, 1, 2.5), "name": "Papers"})
	P(PK.EMERGENCY_LAMP, Vector3(ew - 0.02, y + 3.4, -36.0), -90.0, {"v": 0, "lit": true, "name": "EmergencyLamp_Red", "wall_ok": true})
	P(PK.STENCIL, Vector3(ew - 0.02, y + 5.0, -72.0), -90.0, {"text": "CRANE CONTROL", "size": Vector3(0.12, 1, 1), "v": 1, "name": "Stencil_CraneControl"})


# ============================================================================================
# A (floor -272.77): deep storage the spine dumped into. The heap under the shaft mouth (offset
# south of the landing strip), growth only in its light column, a neat block left in the NE,
# shutters in the pilaster recesses, two cold stores, the sealed hangar door.
# ============================================================================================
func _a_hall() -> void:
	_group("A_Hall")
	var y := FY_A
	# heap, bottom layer
	var h1 := P(PK.BOX40, Vector3(8.0, y, -250.0), 20.0, {"v": 0, "st": 3, "name": "Box_Fallen_Crushed"})
	P(PK.BOX20, Vector3(22.0, y, -259.0), -35.0, {"v": 1, "st": 2, "name": "Box_Fallen_Pried"})
	P(PK.BOX40, Vector3(-6.0, y, -266.0), 75.0, {"v": 5, "st": 4, "name": "Box_Fallen_Burnt"})
	P(PK.BOX20, Vector3(27.0, y, -240.0), 60.0, {"v": 2, "st": 3, "name": "Box_Fallen_Crushed"})
	P(PK.POD, Vector3(-9.0, y, -246.0), 10.0, {"v": 1, "name": "Pod_Fallen"})
	P(PK.BOX20, Vector3(12.0, y, -273.0), 5.0, {"v": 4, "st": 1, "name": "Box_Fallen_Open"})
	P(PK.REEFER, Vector3(34.0, y, -265.0), -80.0, {"st": 3, "name": "Reefer_Fallen_Crushed"})
	# second layer on the burnt 40 (flat roof)
	P(PK.BOX20, Vector3(-6.2, y + CH + 0.01, -265.6), 52.0, {"v": 3, "st": 0, "name": "Box_Fallen_OnTop"})
	# leaning boxes: onto the open 20's roof edge, and onto the pried 20
	var d5 := Vector3(cos(deg_to_rad(5.0)), 0, -sin(deg_to_rad(5.0)))
	var e_open := Vector3(12.0, y, -273.0) - d5 * (L20 * 0.5)
	LEAN(PK.BOX40, e_open - d5 * 9.2, 5.0, CH, 9.2, {"v": 0, "st": 0, "name": "Box_Fallen_Leaning"})
	LEAN(PK.BOX20, Vector3(22.0 + 6.0, y, -259.0 + 4.5), 145.0, CH, 4.4, {"v": 2, "st": 3, "name": "Box_Fallen_Leaning"})
	# the pile proper: three 40s side by side, two 20s across them, a third layer, one leaning in
	for i in 3:
		P(PK.BOX40, Vector3(4.0 + i * 0.4, y, -287.0 + i * 2.5), 12.0, {"v": livery(), "st": 0 if i != 1 else 4, "name": "Box_Pile_Bottom"})
	P(PK.BOX20, Vector3(4.6, y + CH + 0.01, -285.0), 104.0, {"v": livery(), "name": "Box_Pile_Mid"})
	P(PK.BOX20, Vector3(9.8, y + CH + 0.01, -286.0), 98.0, {"v": livery(), "st": 2, "name": "Box_Pile_Mid"})
	P(PK.BOX20, Vector3(7.2, y + CH * 2 + 0.02, -285.6), 15.0, {"v": livery(), "st": 3, "name": "Box_Pile_Top"})
	P(PK.DEBRIS, Vector3(-3.0, y, -282.0), 0.0, {"size": Vector3(5, 1, 6), "name": "Debris_Pile"})
	P(PK.DEBRIS, Vector3(15.0, y, -291.0), 0.0, {"size": Vector3(5, 1, 5), "name": "Debris_Pile"})
	# loader crushed: a 20 came down on its cab cage
	P(PK.LOADER, Vector3(-20.0, y, -258.0), 30.0, {"v": 2, "name": "Loader_Crushed_Burnt"})
	LEAN(PK.BOX20, Vector3(-24.6, y, -253.2), -60.0, 2.8, 4.3, {"v": 5, "st": 3, "name": "Box_OnLoaderCab"})
	# spilled cargo
	for c in [Vector3(15.2, y, -269.5), Vector3(16.4, y, -268.0), Vector3(18.0, y, -271.5), Vector3(25.0, y, -254.0), Vector3(-3.0, y, -244.5)]:
		H(HK.CRATE_WOOD if _rng.randf() < 0.5 else HK.CRATE_METAL, c, _rng.randf() * 360.0, {"v": _rng.randi() % 4, "name": "Crate_Spilled"})
	H(HK.TOTE, Vector3(-12.6, y, -242.0), 30.0, {"v": 1, "name": "Tote_Spilled"})
	P(PK.DEBRIS, Vector3(4.0, y, -258.0), 0.0, {"size": Vector3(6, 1, 5), "name": "Debris_Heap"})
	P(PK.DEBRIS, Vector3(-14.0, y, -262.0), 0.0, {"size": Vector3(4, 1, 4), "name": "Debris_Heap"})
	P(PK.PAPERS, Vector3(14.0, y, -264.0), 0.0, {"size": Vector3(5, 1, 4), "name": "Papers_Manifests"})
	# light column + growth only in it (water comes down the shaft: puddles)
	var shaft := H(HK.LIGHT_SHAFT, Vector3(4.0, -168.0, -232.0), 0.0, {"lit": true, "length": -168.0 - y, "name": "LightColumn_ShaftMouth", "pool_radius": 40.0, "pool_tint": Color(0.40, 0.55, 0.90, 0.55)})
	shaft = shaft
	P(PK.PUDDLE, Vector3(0.0, y, -228.0), 0.0, {"size": Vector3(9, 1, 6), "name": "Puddle_ShaftDrip"})
	P(PK.PUDDLE, Vector3(16.0, y, -236.0), 0.0, {"size": Vector3(6, 1, 8), "name": "Puddle_ShaftDrip"})
	var growth := [[HK.SHRUB, Vector3(-3.5, y, -231.0)], [HK.SHRUB, Vector3(5.0, y, -226.0)], [HK.SHRUB, Vector3(19.5, y, -232.5)], [HK.TREE, Vector3(-11.0, y, -238.0)],
		[HK.TREE, Vector3(13.5, y, -228.5)], [HK.MOSS, Vector3(2.0, y, -229.0)], [HK.MOSS, Vector3(-6.0, y, -235.0)], [HK.MOSS, Vector3(10.0, y, -238.0)],
		[HK.MOSS, Vector3(17.0, y, -240.0)], [HK.MOSS, Vector3(8.0, y + CH, -250.0)], [HK.MOSS, Vector3(-6.0, y + CH * 2 + 0.01, -265.6)]]
	for g: Array in growth:
		H(g[0], g[1], _rng.randf() * 360.0, {"v": _rng.randi() % 3, "name": "Growth_InLight"})
	for i in 14:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(2.0, 22.0)
		var p := Vector3(4.0 + cos(a) * r, y, -232.0 + sin(a) * r * 0.8)
		H(HK.TUFT, p, _rng.randf() * 360.0, {"v": _rng.randi() % 3, "name": "Tuft_InLight"})
	# neat block left in the NE corner (3 x 3 x 2, never moved)
	for ix in 3:
		for iz in 3:
			for lvl in 2:
				P(PK.BOX20, Vector3(74.0 + ix * 6.5, y + lvl * CH, -417.0 + iz * 2.75), 0.0, {"v": 0, "st": 0, "wear": 0.6, "name": "Box_NeatBlock"})
	P(PK.LOADER, Vector3(80.5, y, -405.0), 180.0, {"v": 0, "name": "Loader_ParkedAtBlock"})
	# recesses between the pilasters: shutters on the back walls, two cold stores
	var rec := [[-382.5, 35.0], [-326.5, 31.0], [-262.5, 51.0], [-185.0, 56.0], [-124.0, 20.0]]
	var n := 0
	for side in [-1.0, 1.0]:
		var wall := 0.0
		for r: Array in rec:
			n += 1
			var zc: float = r[0]
			var hit := _ray(Vector3(90.0 * side, y + 3.0, zc), Vector3(115.0 * side, y + 3.0, zc))
			wall = (hit["position"] as Vector3).x if not hit.is_empty() else 104.0 * side
			var yaw := 90.0 if side < 0.0 else -90.0
			if side < 0.0 and zc == -326.5:
				_cold_store(Vector3(wall - side * 4.4, y, zc), yaw, true)
				continue
			if side > 0.0 and zc == -262.5:
				_cold_store(Vector3(wall - side * 4.4, y, zc), yaw, false)
				continue
			P(PK.SHUTTER, Vector3(wall - side * 0.12, y, zc), yaw, {"size": Vector3(minf(r[1] - 8.0, 12.0), 8.0, 1), "st": 1 if n % 3 == 0 else 0, "text": "CS-%02d" % n, "wall_ok": true, "name": "Shutter_ColdStoreBay"})
			P(PK.BAY_NUMBER, Vector3(wall - side * 9.0, y, zc), yaw, {"text": "A%d" % n, "size": Vector3(0.4, 1, 1), "name": "BayPaint"})
	# sealed hangar door in the south bay
	var back := _ray(Vector3(0.0, y + 3.0, -440.0), Vector3(0.0, y + 3.0, -500.0))
	var upr := _ray(Vector3(0.0, y + 3.0, -466.0), Vector3(0.0, y + 200.0, -466.0))
	if not back.is_empty() and not upr.is_empty():
		var wz: float = (back["position"] as Vector3).z
		var hh: float = (upr["position"] as Vector3).y - y - 0.3
		H(HK.HANGAR_DOOR, Vector3(0.0, y, wz + 0.02), 0.0, {"length": hh, "name": "HangarDoor_Sealed", "wall_ok": true})
		P(PK.EMERGENCY_LAMP, Vector3(-36.0, y + 6.0, wz + 0.3), 0.0, {"v": 2, "lit": true, "name": "Beacon_HangarDoor", "wall_ok": true})
		P(PK.EMERGENCY_LAMP, Vector3(36.0, y + 6.0, wz + 0.3), 0.0, {"v": 2, "lit": true, "name": "Beacon_HangarDoor", "wall_ok": true})
	P(PK.STENCIL, Vector3(-30.0, y + 14.0, -433.9), 0.0, {"text": "DEEP STORE A", "size": Vector3(0.5, 1, 1), "name": "Stencil_DeepStoreA", "wall_ok": true})


## A walk-in cold store built into a pilaster recess (12 x 5 x 8, front faces the hall).
## flooded = water + growth inside under a leak; else the scavenger who did not leave.
func _cold_store(pos: Vector3, yaw: float, flooded: bool) -> void:
	P(PK.COLD_CAGE, pos, yaw, {"size": Vector3(12.0, 5.0, 8.0), "name": "ColdStore_Flooded" if flooded else "ColdStore_Body"})
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var at := func(lx: float, lz: float) -> Vector3: return pos + b * Vector3(lx, 0.15, lz)
	if flooded:
		P(PK.PUDDLE, at.call(1.0, -0.5), yaw, {"size": Vector3(9.0, 1, 6.0), "name": "Water_ColdStore"})
		for i in 4:
			H(HK.MOSS, at.call(-3.0 + i * 2.0, -2.0 + (i % 2) * 2.5), _rng.randf() * 360.0, {"v": i % 2, "name": "Moss_ColdStore"})
		H(HK.SHRUB, at.call(3.5, -2.5), 0.0, {"v": 1, "name": "Shrub_ColdStore"})
		H(HK.VINE, pos + b * Vector3(1.5, 5.0, 3.6), yaw, {"length": 3.5, "name": "Vine_FromRoofLeak"})
	else:
		P(PK.BODY, at.call(2.0, -3.3), yaw, {"name": "Body_Scavenger"})
		P(PK.CANS, at.call(0.5, -2.0), 0.0, {"name": "Cans_Body"})
		P(PK.CHEMLIGHT, at.call(1.2, -1.2), 20.0, {"name": "Chemlight_Dead"})
		P(PK.PAPERS, at.call(-1.0, -2.2), 0.0, {"size": Vector3(1.2, 1, 1.0), "name": "Papers_Body"})
		P(PK.TAG, pos + b * Vector3(-3.5, 2.0, 4.02), yaw, {"v": 2, "st": 0, "size": Vector3(0.9, 1, 1), "name": "Tag_Skull_ColdStore"})
