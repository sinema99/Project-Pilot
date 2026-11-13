extends "res://tests/test_case.gd"

# hub2's industrial pass: the bake (edge / corner / seam distances per face), the loader that swaps
# the baked meshes and the decals in, and that none of it touches collision. How it LOOKS is checked
# with probe shots (tests/_probe_hub2_wear_shot.gd) and by playing.

const SCENE := "res://scenes/hub2.tscn"

var _scene: MissionMap

func end() -> void:
	if is_instance_valid(_scene):
		_scene.free()
	_scene = null
	super()

func _load() -> MissionMap:
	_scene = (load(SCENE) as PackedScene).instantiate() as MissionMap
	(Engine.get_main_loop() as SceneTree).root.add_child(_scene)
	return _scene

func _custom(mesh: ArrayMesh, slot: int) -> PackedFloat32Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0 + slot]

func test_a_box_gets_its_four_edges_on_every_top_face_vertex() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(4, 4, 4)
	var bake := Hub2WearBake.new()
	bake.add_mesh("Box", box, Transform3D.IDENTITY)
	var baked: ArrayMesh = bake.bake()["Box"]
	var pos: PackedVector3Array = baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var d := _custom(baked, 0)
	var c := _custom(baked, 1)
	var half := 2.0 * Hub2WearBake.WORLD_SCALE
	var seen_corner := false
	for v in pos.size():
		if absf(pos[v].y - 2.0) > 0.001 or absf(pos[v].x - 2.0) > 0.001 or absf(pos[v].z - 2.0) > 0.001:
			continue
		# A top-face corner at (+x, +z): two edges at distance 0, two more a face width away.
		var dists: Array = []
		for s in 4:
			check(is_equal_approx(c[v * 4 + s], Hub2WearBake.CLS_CONVEX), "a box edge is convex (class %s)" % c[v * 4 + s])
			dists.append(snappedf(d[v * 4 + s], 0.001))
		dists.sort()
		if dists[0] == 0.0 and dists[1] == 0.0 and absf(float(dists[2]) - half * 2.0) < 0.01:
			seen_corner = true
	check(seen_corner, "a top face corner vertex should sit on two edges, two faces' width from the others")

func test_two_boxes_cutting_into_each_other_leave_a_seam() -> void:
	var a := BoxMesh.new()
	a.size = Vector3(20, 2, 20)
	var b := BoxMesh.new()
	b.size = Vector3(4, 8, 4)
	var bake := Hub2WearBake.new()
	bake.add_mesh("Slab", a, Transform3D.IDENTITY)
	bake.add_mesh("Post", b, Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)))
	var baked: Dictionary = bake.bake()
	var found := false
	for mesh_name: String in baked:
		var c := _custom(baked[mesh_name], 1)
		for i in c.size():
			if is_equal_approx(c[i], Hub2WearBake.CLS_SEAM):
				found = true
	check(found, "a post sunk into a slab should leave a seam line where they meet")

func test_the_scene_dresses_every_map_mesh_and_leaves_collision_alone() -> void:
	var scene := _load()
	var wear := scene.get_node("Hub2Wear") as Hub2Wear
	check(wear.surface_material != null, "the loader should have made the surface material (are the bakes missing? run tools/bake_hub2_wear.gd)")
	var source := (load("res://assets/hub2.glb") as PackedScene).instantiate()
	var source_counts := {}
	for mi: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		source_counts[str(mi.name)] = mi.mesh.surface_get_array_len(0)
	source.free()
	var dressed := 0
	for node in scene.map.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.name == Hub2Wear.DECAL_NODE:
			continue
		dressed += 1
		check(mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).shader == Hub2Wear.SURFACE_SHADER,
			"%s should wear the industrial shader" % mi.name)
		eq(int(mi.mesh.get_meta(&"source_vertex_count", -1)), int(source_counts.get(str(mi.name), -2)), "%s's bake matches its glb mesh" % mi.name)
		var solid := false
		for c in mi.get_children():
			if c is StaticBody3D:
				solid = true
				for sh in c.get_children():
					if sh is CollisionShape3D:
						check((sh as CollisionShape3D).shape is ConcavePolygonShape3D, "collision is still the map's own trimesh")
		check(solid, "%s lost its collision" % mi.name)
	check(dressed > 0, "no map meshes")

func test_decals_are_visual_only_and_use_the_sheet() -> void:
	var scene := _load()
	var decals := scene.map.get_node_or_null(Hub2Wear.DECAL_NODE) as MeshInstance3D
	check(decals != null and decals.mesh != null and decals.mesh.get_surface_count() == 1, "the decals mesh should be there")
	if decals == null:
		return
	eq(decals.get_child_count(), 0, "decals carry no collision or children")
	eq(decals.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "decals don't cast shadows")
	var mat := decals.material_override as ShaderMaterial
	check(mat != null and mat.get_shader_parameter(&"sheet") is Texture2D and mat.get_shader_parameter(&"glow_sheet") is Texture2D, "decal sheet and glow sheet are set")
	check(decals.mesh.surface_get_array_len(0) > 600, "a kilometre-wide map should carry hundreds of decals")

func test_the_decal_sheet_is_deterministic_and_has_glow() -> void:
	var a := Hub2DecalAtlas.build()
	var b := Hub2DecalAtlas.build()
	check((a["color"] as Image).get_data() == (b["color"] as Image).get_data(), "same sheet every build")
	var lit := 0
	var glow: Image = a["glow"]
	for y in glow.get_height():
		for x in glow.get_width():
			if glow.get_pixel(x, y).a > 0.5:
				lit += 1
	check(lit > 40, "the lamps and strips should light up the glow layer (%d lit)" % lit)
	for s: Dictionary in a["sprites"]:
		var r: Rect2i = s["rect"]
		check(Rect2i(0, 0, Hub2DecalAtlas.SIZE, Hub2DecalAtlas.SIZE).encloses(r), "%s fits on the sheet" % s["name"])
