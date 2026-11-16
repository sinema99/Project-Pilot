extends "res://tests/test_case.gd"

# The cargo container: a solid 20 ft box in ten colours, built in code. See docs/specs/cargo-container.md.

const SCENE := "res://scenes/cargo_container.tscn"
const HUB2 := "res://scenes/hub2.tscn"

var _nodes: Array = []

func end() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	super()

func _make(p: int) -> CargoContainer:
	var c := (load(SCENE) as PackedScene).instantiate() as CargoContainer
	c.palette = p
	(Engine.get_main_loop() as SceneTree).root.add_child(c)
	_nodes.append(c)
	return c

func test_it_is_a_20ft_box_with_one_shell_collider() -> void:
	var c := _make(CargoContainer.Palette.BLUE)
	var shapes := c.find_children("*", "CollisionShape3D", true, false)
	eq(shapes.size(), 1, "one collision shape")
	var box := (shapes[0] as CollisionShape3D).shape as BoxShape3D
	check(box != null and box.size.is_equal_approx(Vector3(6.058, 2.591, 2.438)), "shell box is 6.058 x 2.591 x 2.438")
	var mi := c.get_node("Visual") as MeshInstance3D
	var aabb := mi.get_aabb()
	check(absf(aabb.size.x - 6.058) < 0.05 and absf(aabb.size.y - 2.591) < 0.05 and absf(aabb.size.z - 2.438) < 0.05,
		"mesh bounds match the 20 ft size, got %s" % aabb.size)
	check(absf(aabb.position.y) < 0.01, "origin is at the bottom")

func test_ten_palettes_give_ten_different_meshes() -> void:
	eq(CargoContainer.Palette.size(), 10, "ten palettes")
	var seen := {}
	for p in CargoContainer.Palette.values():
		var m := CargoContainer.mesh_for(p)
		check(m.get_surface_count() == 1 and m.get_faces().size() > 0, "palette %d has geometry" % p)
		seen[m] = true
	eq(seen.size(), 10, "each palette is its own mesh")
	check(CargoContainer.mesh_for(CargoContainer.Palette.TEAL) == CargoContainer.mesh_for(CargoContainer.Palette.TEAL), "meshes are shared per colour")

func test_changing_the_palette_rebuilds_without_piling_up_children() -> void:
	var c := _make(CargoContainer.Palette.PINK)
	var before := c.get_child_count()
	c.palette = CargoContainer.Palette.GREY
	eq(c.get_child_count(), before, "no extra children after a palette change")
	eq((c.get_node("Visual") as MeshInstance3D).mesh, CargoContainer.mesh_for(CargoContainer.Palette.GREY), "visual wears the new palette")

func test_the_staging_slab_is_gone_and_hub2_containers_are_worn() -> void:
	# docs/specs/hub2-storage.md: the generator placed the containers in the rooms and removed the row.
	var scene := (load(HUB2) as PackedScene).instantiate()
	_nodes.append(scene)
	(Engine.get_main_loop() as SceneTree).root.add_child(scene)
	check(scene.get_node_or_null("CargoContainers") == null, "the staging row was replaced by the dressing")
	var count := 0
	# The game scene holds the baked dressing; the containers live in its source scene.
	var src := (load("res://scenes/hub2_dressing_src.tscn") as PackedScene).instantiate()
	_nodes.append(src)
	scene.add_child(src)
	for c in src.find_children("*", "CargoContainer", true, false):
		count += 1
		check((c as CargoContainer).wear > 0.5, "%s is weathered" % c.name)
	check(count > 100, "the yards hold containers (got %d)" % count)

func test_wear_is_off_by_default_and_a_worn_mesh_differs() -> void:
	var c := _make(CargoContainer.Palette.TEAL)
	eq(c.wear, 0.0, "clean outside hub2")
	eq((c.get_node("Visual") as MeshInstance3D).mesh, CargoContainer.mesh_for(CargoContainer.Palette.TEAL), "clean = the shared preset mesh")
	c.wear = 0.8
	var worn := (c.get_node("Visual") as MeshInstance3D).mesh as ArrayMesh
	check(worn != CargoContainer.mesh_for(CargoContainer.Palette.TEAL), "worn wears its own mesh")
	eq(worn.surface_get_array_len(0), CargoContainer.mesh_for(CargoContainer.Palette.TEAL).surface_get_array_len(0), "same geometry")
	var a: PackedColorArray = worn.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var b: PackedColorArray = CargoContainer.mesh_for(CargoContainer.Palette.TEAL).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var changed := 0
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			changed += 1
	check(changed > a.size() / 4, "weathering changed the vertex colours (%d of %d)" % [changed, a.size()])
