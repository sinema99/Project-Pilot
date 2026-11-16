extends "res://tests/test_case.gd"

# hub2's final hand-placed dressing (docs/specs/hub2-final-pass.md): what tools/layout_hub2.gd wrote,
# the prop kits, doors, pipes and light pools. Clipping / inside-the-map is enforced by the layout tool
# itself (it refuses to save); looks are checked with probe screenshots.

const SCENE := "res://scenes/hub2.tscn"
## The editable source of the dressing; the game loads its baked form (docs/specs/hub2-load-time.md).
const SRC := "res://scenes/hub2_dressing_src.tscn"
const Hub2PipeRouterRef := preload("res://tools/hub2_pipe_router.gd")

var _nodes: Array[Node] = []

func end() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	super()

func _load() -> MissionMap:
	var scene := (load(SCENE) as PackedScene).instantiate() as MissionMap
	_nodes.append(scene)
	(Engine.get_main_loop() as SceneTree).root.add_child(scene)
	return scene

## The source dressing, added under `parent` (or the tree root) so rays and global positions work.
func _load_src(parent: Node = null) -> Node3D:
	var src := (load(SRC) as PackedScene).instantiate() as Node3D
	_nodes.append(src)
	(parent if parent != null else (Engine.get_main_loop() as SceneTree).root).add_child(src)
	return src

func test_room_a_is_a_one_way_drop() -> void:
	var scene := _load()
	# A's floor is y -273 (the hall under the roof slab): the kill height sits below it, and there is
	# deliberately no lift back up.
	check(scene.kill_height < -273.0, "kill height %.0f should be below A's deepest pit" % scene.kill_height)
	check(scene.find_children("*Lift*", "", true, false).filter(func(n: Node) -> bool: return not n is Hub2Prop).is_empty(), "no lift")

func test_props_are_built_ps1_style() -> void:
	# Every kind builds a non-empty vertex-colour mesh with no textures.
	for k in Hub2Prop.Kind.values():
		var made := Hub2PropBuild.build(k, 0, 1, 0.8, true, 2.0)
		var mesh: ArrayMesh = made["mesh"]
		check(mesh.get_surface_count() > 0 and mesh.get_faces().size() > 0, "%s has geometry" % Hub2Prop.Kind.keys()[k])
		var fmt := mesh.surface_get_format(0)
		check(fmt & Mesh.ARRAY_FORMAT_COLOR != 0, "%s carries vertex colours" % Hub2Prop.Kind.keys()[k])
		var mat := mesh.surface_get_material(0) as StandardMaterial3D
		check(mat != null and mat.vertex_color_use_as_albedo and mat.albedo_texture == null, "%s: plain vertex-colour material" % Hub2Prop.Kind.keys()[k])

func test_wear_changes_the_colours_not_the_shape_count() -> void:
	var clean := Hub2PropBuild.build(Hub2Prop.Kind.CABINET, 0, 4, 0.0, false, 2.0)["mesh"] as ArrayMesh
	var worn := Hub2PropBuild.build(Hub2Prop.Kind.CABINET, 0, 4, 1.0, false, 2.0)["mesh"] as ArrayMesh
	check(worn.surface_get_array_len(0) > clean.surface_get_array_len(0), "weathering cuts faces into cells for the colour to change across")

func test_plants_and_hanging_things_have_no_collision() -> void:
	for k in [Hub2Prop.Kind.MOSS, Hub2Prop.Kind.TUFT, Hub2Prop.Kind.SHRUB, Hub2Prop.Kind.VINE, Hub2Prop.Kind.LAMP_HIGHBAY]:
		eq((Hub2PropBuild.build(k, 0, 1, 0.8, false, 2.0)["boxes"] as Array).size(), 0, "%s is walk-through" % Hub2Prop.Kind.keys()[k])
	check((Hub2PropBuild.build(Hub2Prop.Kind.TREE, 0, 1, 0.8, false, 2.0)["boxes"] as Array).size() == 1, "tree trunks are solid")

func test_a_terminal_lights_its_screens_only_when_powered() -> void:
	var on := Hub2PropBuild.build(Hub2Prop.Kind.TERMINAL, 1, 2, 0.8, true, 2.0)["mesh"] as ArrayMesh
	var off := Hub2PropBuild.build(Hub2Prop.Kind.TERMINAL, 1, 2, 0.8, false, 2.0)["mesh"] as ArrayMesh
	var crt := false
	for i in on.get_surface_count():
		crt = crt or on.surface_get_material(i) == Hub2PropBuild.crt_material()
	check(crt, "powered terminal has the CRT surface")
	for i in off.get_surface_count():
		check(off.surface_get_material(i) != Hub2PropBuild.crt_material(), "a dead terminal has dark glass")

func test_cranes_build_and_rebuild_without_piling_children() -> void:
	for t in [Hub2Crane.Type.BRIDGE, Hub2Crane.Type.POLAR, Hub2Crane.Type.WALL]:
		var c := Hub2Crane.new()
		c.type = t
		_nodes.append(c)
		(Engine.get_main_loop() as SceneTree).root.add_child(c)
		var n := c.get_child_count()
		check(n > 0 and c.get_node("Visual") != null, "crane %d built" % t)
		c.hook_drop = 5.0
		eq(c.get_child_count(), n, "rebuild replaces its parts")

func test_a_pipe_sags_and_bends_round_corners_with_capped_ends() -> void:
	var p := Hub2PipeRun.new()
	_nodes.append(p)
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	p.points = PackedVector3Array([Vector3.ZERO, Vector3(20, 0, 0)])
	var straight := (p.get_node("Visual") as MeshInstance3D).mesh.get_aabb()
	p.sag = true
	var sagged := (p.get_node("Visual") as MeshInstance3D).mesh.get_aabb()
	check(sagged.position.y < straight.position.y - 1.0, "the span dips down")
	p.sag = false
	p.end_b = Hub2PipeRun.End.WALL
	p.end_b_normal = Vector3.LEFT
	var capped := (p.get_node("Visual") as MeshInstance3D).mesh.get_aabb()
	check(capped.end.x > straight.end.x + 0.2, "a WALL end carries on into the wall")
	check(capped.size.z > straight.size.z + 0.1, "with a sleeve plate wider than the pipe")
	# A 90 degree corner: the elbow cuts inside the corner point.
	p.points = PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0), Vector3(10, 0, 10)])
	var em := Hub2PipeRun.elbow_mid(p.points, 1, p.radius)
	check((em[0] as Vector3).distance_to(Vector3(10, 0, 0)) > 0.05, "elbow passes inside the corner")
	check(absf((em[1] as Vector3).dot(Vector3(1, 0, 1).normalized()) - 1.0) < 0.01, "elbow runs diagonally at its middle")

func test_the_baked_dressing_matches_its_source() -> void:
	var scene := _load()
	var baked := scene.get_node("Dressing") as Hub2DressingBaked
	check(baked != null, "hub2 carries the baked dressing")
	check(scene.find_children("*", "Hub2Prop", true, false).is_empty(), "no code-built props left in the game scene")
	check(scene.get_child_count() < 40, "the scene is a handful of nodes (got %d)" % scene.get_child_count())
	var src := _load_src()
	var boxes := 0
	for c in src.find_children("*", "CollisionShape3D", true, false):
		if (c as CollisionShape3D).shape is BoxShape3D:
			boxes += 1
	var baked_boxes := 0
	for c in baked.find_children("*", "CollisionShape3D", true, false):
		if not _under_door(c):
			baked_boxes += 1
	eq(baked_boxes, boxes, "every box collider survived the bake (re-run tools/bake_hub2_dressing.gd if not)")
	check(baked.get_child_count() > 100, "merged chunks exist")
func test_the_hangar_seam_follows_the_drawing() -> void:
	var lt := 46.0
	# Straight down from the top left of centre, a diagonal step at mid height, straight down to the floor right of centre.
	check(Hub2PropBuild.hangar_seam_x(lt, lt) < 0.0, "top of the seam is left of centre")
	eq(snappedf(Hub2PropBuild.hangar_seam_x(lt * 0.8, lt), 0.01), snappedf(Hub2PropBuild.hangar_seam_x(lt, lt), 0.01), "straight at the top")
	check(Hub2PropBuild.hangar_seam_x(0.0, lt) > 0.0, "bottom of the seam is right of centre")
	var step := Hub2PropBuild.hangar_seam_x(lt * 0.42, lt) - Hub2PropBuild.hangar_seam_x(lt * 0.58, lt)
	check(absf(step) > 3.0, "the diagonal step moves the seam several metres (%.1f)" % step)


func _under_door(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is Hub2Door:
			return true
		p = p.get_parent()
	return false

func test_every_area_has_its_group() -> void:
	var src := _load_src()
	for g in ["D_Spawn", "D_Shaft", "D_Galleries", "Corridors_Mid", "C_Link", "C_Dock", "E_Level", "E_PlantRoom", "Pipes", "B_Yard", "B_Rooms", "B_Balcony", "A_Hall", "Doors"]:
		var n := src.get_node_or_null(g)
		check(n != null and n.get_child_count() > 0, "Dressing/%s is filled" % g)
	var total := src.find_children("*", "Node3D", false, false).size()
	var objects := 0
	for g in src.get_children():
		objects += g.get_child_count()
	check(objects > 600 and objects < 1000, "hand-placed object count in budget (%d)" % objects)

func test_every_piece_kind_builds_ps1_style() -> void:
	for k in Hub2Piece.Kind.values():
		var made := Hub2PieceBuild.build(k, 0, 0, 1, 0.8, Vector3(3, 2, 2), "AB-1", true)
		var mesh: ArrayMesh = made["mesh"]
		check(mesh.get_surface_count() > 0, "%s has geometry" % Hub2Piece.Kind.keys()[k])
		if mesh.get_surface_count() > 0:
			check(mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR != 0, "%s carries vertex colours" % Hub2Piece.Kind.keys()[k])

func test_container_states_change_the_shell() -> void:
	var closed := Hub2PieceBuild.build(Hub2Piece.Kind.BOX20, 0, 0, 1, 0.8, Vector3.ONE, "", false)
	var open := Hub2PieceBuild.build(Hub2Piece.Kind.BOX20, 0, 1, 1, 0.8, Vector3.ONE, "", false)
	eq((closed["boxes"] as Array).size(), 1, "a closed box is one solid")
	check((open["boxes"] as Array).size() >= 5, "an open box is walk-in (floor, roof, walls)")
	var crushed: ArrayMesh = Hub2PieceBuild.build(Hub2Piece.Kind.BOX20, 0, 3, 1, 0.8, Vector3.ONE, "", false)["mesh"]
	check(crushed.get_faces().size() > 0, "a crushed box still builds")

func test_doors_open_and_blast_doors_do_not() -> void:
	var src := _load_src()
	var doors := src.find_children("*", "Hub2Door", true, false)
	check(doors.size() >= 12, "12+ doors (%d)" % doors.size())
	var swing := 0
	var blast := 0
	for d in doors:
		if (d as Hub2Door).type == Hub2Door.Type.SWING:
			swing += 1
		if (d as Hub2Door).type == Hub2Door.Type.BLAST:
			blast += 1
	check(swing >= 6 and blast >= 1, "personnel doors and a jammed blast door (%d swing, %d blast)" % [swing, blast])
	var d := Hub2Door.new()
	_nodes.append(d)
	(Engine.get_main_loop() as SceneTree).root.add_child(d)
	check(not d.is_open, "starts shut")
	d.toggle()
	check(d.is_open, "F opens it")

func test_every_pipe_end_goes_into_a_surface_or_another_pipe() -> void:
	# docs/specs/hub2-pipe-routing.md: no loose ends. tools/gen_hub2_pipes.gd ray-checks every WALL end
	# against the map before it saves; here: every end is capped, every tee sits on another pipe.
	var src := _load_src()
	var pipes := src.find_children("*", "Hub2PipeRun", true, false)
	check(pipes.size() >= 40, "pipe runs exist (%d)" % pipes.size())
	var segs: Array = []
	var bends := 0
	for n in pipes:
		var p := n as Hub2PipeRun
		check(p.points.size() >= 2, "%s is a run, not a point" % p.name)
		check(p.end_a != Hub2PipeRun.End.OPEN and p.end_b != Hub2PipeRun.End.OPEN, "%s has both ends capped" % p.get_path())
		bends += maxi(p.points.size() - 2, 0)
		for i in p.points.size() - 1:
			segs.append([p, p.global_transform * p.points[i], p.global_transform * p.points[i + 1]])
	check(bends >= 40, "pipes go round corners (%d bends)" % bends)
	var tees := 0
	for n in pipes:
		var p := n as Hub2PipeRun
		for e in 2:
			if (p.end_a if e == 0 else p.end_b) != Hub2PipeRun.End.TEE:
				continue
			tees += 1
			var at := p.global_transform * (p.points[0] if e == 0 else p.points[p.points.size() - 1])
			var on := false
			for sg: Array in segs:
				if sg[0] != p and Hub2PipeRouterRef.seg_dist(at, at, sg[1], sg[2]) < p.tee_radius + 0.05:
					on = true
					break
			check(on, "%s tees into another pipe" % p.get_path())
	check(tees > 0, "some drops tee into a bundle")

func test_lit_pieces_feed_the_pools() -> void:
	var scene := _load()
	var src := _load_src()
	var pools := scene.get_node("LampPools") as Hub2LampPools
	var lit := pools.collect(src).size()
	check(lit > 10 and lit <= Hub2LampPools.LAMP_MAX, "light only from story sources, all fit (%d)" % lit)
