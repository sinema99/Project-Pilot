extends SceneTree

# Rewrites hub2's pipes (docs/specs/hub2-pipe-routing.md) in scenes/hub2_dressing_src.tscn: removes every
# old Hub2PipeRun (and the vines the old generator hung off sagging ones), routes new ones with
# Hub2PipeRouter into the top-level `Pipes` group, refuses to save if any pipe end is loose.
#   godot --headless --path . --script tools/gen_hub2_pipes.gd
# Then bake: powershell -File tools/godot_bg.ps1 --script tools/bake_hub2_dressing.gd (windowed, hidden).
# Run it again after tools/gen_hub2_dressing.gd (which no longer makes pipes).

const SRC := "res://scenes/hub2_dressing_src.tscn"
const Router := preload("res://tools/hub2_pipe_router.gd")
const SEED := 20261115
const WORLD_SCALE := 0.6
const WEAR := 0.8
## Seeds (wall/ceiling creases) a route is tried from, as a share of the eligible ones.
const SEED_CHANCE := 0.65
## Chance a wall-wall inside corner gets a drop (with / without a bundle bending in it to tee into).
const DROP_TEE := 0.6
const DROP_FREE := 0.25
const ROOM_A := Rect2(-94, -430, 196, 308)
const SHAFT_AXIS := Vector3(4, -273, -232)
const SHAFT_CLEAR := 56.0
const A_LANDING := AABB(Vector3(-16, -278, -208), Vector3(32, 20, 36))

var _phys: Node3D
var _glb: Node3D
var _root: Node3D
var _frames := 0
var _old_len := 0.0


func _initialize() -> void:
	_phys = Node3D.new()
	_glb = (load("res://assets/hub2.glb") as PackedScene).instantiate()
	_glb.scale = Vector3.ONE * WORLD_SCALE
	_phys.add_child(_glb)
	root.add_child(_phys)
	_root = (load(SRC) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	_strip_old_pipes()
	root.add_child(_root)


func _crane_solids() -> void:
	# Cranes have no collision: give the router their visual mesh as a solid.
	var cranes := 0
	for c in _root.find_children("*", "Hub2Crane", true, false):
		for mi: MeshInstance3D in c.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			cs.shape = mi.mesh.create_trimesh_shape()
			body.add_child(cs)
			root.add_child(body)
			body.global_transform = mi.global_transform
			cranes += 1
	print("crane solids: %d" % cranes)
	print("cranes %d" % _root.find_children("*", "Hub2Crane", true, false).size())


func _strip_old_pipes() -> void:
	var sag_mids: Array = []
	var removed := 0
	for p in _root.find_children("*", "Hub2PipeRun", true, false):
		var pr := p as Hub2PipeRun
		if pr.name == "Pipe0" and pr.points.size() >= 2:
			_old_len += pr.points[0].distance_to(pr.points[pr.points.size() - 1])
		if pr.sag and pr.points.size() >= 2:
			sag_mids.append(_xf_of(pr) * pr.points[0].lerp(pr.points[pr.points.size() - 1], 0.5))
	for gpath in ["Halls/Pipes", "Pipes"]:
		var g := _root.get_node_or_null(gpath)
		if g != null:
			removed += g.find_children("*", "Hub2PipeRun", true, false).size()
			g.get_parent().remove_child(g)
			g.free()
	var vines := 0
	for v in _root.find_children("*", "Hub2Prop", true, false):
		var hp := v as Hub2Prop
		if hp.kind != Hub2Prop.Kind.VINE:
			continue
		var at := _xf_of(hp).origin
		for m: Vector3 in sag_mids:
			if absf(at.y - m.y) < 0.6 and Vector2(at.x - m.x, at.z - m.z).length() < 2.2:
				hp.get_parent().remove_child(hp)
				hp.free()
				vines += 1
				break
	print("old pipes removed: %d (sag vines removed: %d), old bundle length %.0f m" % [removed, vines, _old_len])


static func _xf_of(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c is Node3D:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


func _physics_process(_d: float) -> bool:
	_frames += 1
	if _frames == 2:
		_crane_solids()
	if _frames < 5:
		return false
	var router := Router.new()
	router.ss = _phys.get_world_3d().direct_space_state
	router.map_root = _glb
	router.rng.seed = SEED
	var services := [Hub2PipeRun.Service.STEEL, Hub2PipeRun.Service.FIRE, Hub2PipeRun.Service.GAS, Hub2PipeRun.Service.WATER]

	var scn: Node = (load("res://assets/hub2.glb") as PackedScene).instantiate()
	var bake := Hub2WearBake.new()
	for mi: MeshInstance3D in scn.find_children("*", "MeshInstance3D", true, false):
		bake.add_mesh(str(mi.name), mi.mesh, _rel(mi, scn))
	scn.free()
	bake._prepare()

	var seeds: Array = []
	var drops: Array = []
	for L: Dictionary in bake._lines:
		var a: Vector3 = L["a"]
		var b: Vector3 = L["b"]
		var dir: Vector3 = L["dir"]
		var n: Vector3 = L["n"]
		var mid := (a + b) * 0.5
		var in_a := _in_a(mid)
		# A's ceiling slab is a separate piece cut into its walls: those joints are seams, not creases
		# (crease_frame's rays still check there is a wall and a ceiling).
		if L["cls"] != Hub2WearBake.CLS_CONCAVE and not (in_a and L["cls"] == Hub2WearBake.CLS_SEAM):
			continue
		if not in_a and (mid.y < -60.0 or mid.y > 140.0):
			continue
		if absf(dir.y) < 0.05 and float(L["len"]) >= 6.0 and n.y < -0.3:
			seeds.append([mid, dir, in_a])
		elif absf(dir.y) > 0.95 and float(L["len"]) >= 3.0 and absf(n.y) < 0.1:
			drops.append([mid, n, dir, in_a])
	seeds = _dedupe(seeds, 2.0)
	drops = _dedupe(drops, 0.5)
	router.rng.seed = SEED
	_shuffle(seeds, router.rng)
	_shuffle(drops, router.rng)
	print("seeds %d, drop corners %d" % [seeds.size(), drops.size()])

	var t0 := Time.get_ticks_msec()
	for sd: Array in seeds:
		if router.rng.randf() > SEED_CHANCE:
			continue
		var mid: Vector3 = sd[0]
		if router._pipe_near(mid + Vector3.DOWN * 1.0, mid + Vector3.DOWN * 1.0, 2.5):
			router._stat("seed_covered")
			continue
		var fr := router.crease_frame(mid, sd[1])
		if fr.is_empty():
			router._stat("seed_no_frame")
			continue
		if sd[2] and A_LANDING.has_point(mid):
			continue
		var below := router._hit(mid + Vector3.DOWN * 1.5 - (fr["w"] as Vector3), mid + Vector3.DOWN * 120.0 - (fr["w"] as Vector3))
		if below.is_empty():
			router._stat("seed_no_floor")
			continue
		router.route_from(fr, services, 320.0 if sd[2] else 130.0)
	for dc: Array in drops:
		router.drop_at(dc[0], dc[1], dc[2], services, 320.0 if dc[3] else 130.0, DROP_FREE, DROP_TEE)
	print("routing took %d ms; stats %s" % [Time.get_ticks_msec() - t0, router.stats])

	var bad := router.loose_ends()
	if not bad.is_empty():
		for s in bad.slice(0, 20):
			print("LOOSE: ", s)
		print("REFUSED: %d loose pipe ends, nothing saved" % bad.size())
		quit(1)
		return true

	root.remove_child(_root)
	var g := Node3D.new()
	g.name = "Pipes"
	_root.add_child(g)
	g.owner = _root
	var count := 0
	for ri in router.routes.size():
		var rg := Node3D.new()
		rg.name = "Route%d" % ri
		g.add_child(rg)
		rg.owner = _root
		var pipes: Array = router.routes[ri]
		for k in pipes.size():
			var pd: Dictionary = pipes[k]
			var pts: PackedVector3Array = pd["points"]
			var centre := Vector3.ZERO
			for p in pts:
				centre += p
			centre /= pts.size()
			var local := PackedVector3Array()
			for p in pts:
				local.append(p - centre)
			var pr := Hub2PipeRun.new()
			pr.name = "Pipe%d" % k
			pr.position = centre
			pr.points = local
			pr.radius = pd["radius"]
			pr.service = pd["service"]
			pr.mount_dirs = pd["mount_dirs"]
			pr.mount_dir = (pd["mount_dirs"] as PackedVector3Array)[0]
			pr.mount_gap = pd["mount_gap"]
			pr.sag = pd["sag"]
			pr.end_a = pd["end_a"]
			pr.end_b = pd["end_b"]
			pr.end_a_normal = pd["end_a_normal"]
			pr.end_b_normal = pd["end_b_normal"]
			pr.tee_radius = pd.get("tee_radius", 0.3)
			pr.fittings_seed = router.rng.randi() % 99991
			pr.wear = WEAR
			pr.view_range = pd["view"]
			rg.add_child(pr)
			pr.owner = _root
			count += 1
	var out := PackedScene.new()
	var err := out.pack(_root)
	if err == OK:
		err = ResourceSaver.save(out, SRC)
	print("saved %s: %s (%d routes, %d pipes)" % [SRC, error_string(err), router.routes.size(), count])
	_root.free()
	quit(0 if err == OK else 1)
	return true


func _in_a(p: Vector3) -> bool:
	if p.y > -150.0 or p.y < -290.0 or not ROOM_A.has_point(Vector2(p.x, p.z)):
		return false
	return Vector2(p.x - SHAFT_AXIS.x, p.z - SHAFT_AXIS.z).length() > SHAFT_CLEAR


static func _dedupe(list: Array, near: float) -> Array:
	var out: Array = []
	var cells := {}
	for e: Array in list:
		var p: Vector3 = e[0]
		var key := Vector3i((p / near).round())
		if cells.has(key):
			continue
		cells[key] = true
		out.append(e)
	return out


static func _shuffle(list: Array, r: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := r.randi() % (i + 1)
		var t: Variant = list[i]
		list[i] = list[j]
		list[j] = t


static func _rel(node: Node3D, root_node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root_node:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
