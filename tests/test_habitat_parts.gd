extends "res://tests/test_case.gd"

# Covers the 2026-09-30 habitat part library. See docs/specs/habitat-parts.md.
#
# Fences: every catalogued part has a scene and builds something, solid parts have colliders and
# the rest have none, parts stand on the floor and are where the layout says, none of the
# generated geometry is owned (so it never reaches a .tscn), and the library scene holds one
# instance of every part with no two footprints overlapping.

const PART_SCRIPT := preload("res://scripts/habitat_part.gd")
const LIBRARY := preload("res://scenes/habitat_parts.tscn")


func _spawn(n: Node) -> Node:
	(Engine.get_main_loop() as SceneTree).root.add_child(n)
	return n


func _drop(node: Node) -> void:
	if is_instance_valid(node):
		if node.get_parent():
			node.get_parent().remove_child(node)
		node.free()


func _part(kind: String) -> Node3D:
	var n := Node3D.new()
	n.set_script(PART_SCRIPT)
	n.set("kind", kind)
	return _spawn(n) as Node3D


func test_every_part_has_a_scene_and_builds_geometry() -> void:
	begin("habitat parts: each catalogue entry has a scene that builds meshes")
	for p: Array in PART_SCRIPT.PARTS:
		var path := "res://scenes/habitat_parts/%s.tscn" % p[0]
		check(ResourceLoader.exists(path), "%s has a scene" % p[0])
		var n := _part(p[0])
		var meshes := 0
		var stack: Array[Node] = [n]
		while not stack.is_empty():
			var c: Node = stack.pop_back()
			if c is MeshInstance3D or c is MultiMeshInstance3D:
				meshes += 1
			stack.append_array(c.get_children())
		check(meshes > 0, "%s builds something" % p[0])
		_drop(n)
	end()


func test_solid_parts_have_colliders_and_the_rest_have_none() -> void:
	begin("habitat parts: the solid flag in the catalogue matches the colliders")
	for p: Array in PART_SCRIPT.PARTS:
		var n := _part(p[0])
		var shapes := n.get_node("Hull").get_child_count()
		if p[6]:
			check(shapes > 0, "%s is solid" % p[0])
		else:
			eq(shapes, 0, "%s has no colliders" % p[0])
		_drop(n)
	end()


func test_a_solid_part_stands_on_the_floor() -> void:
	begin("habitat parts: a ground tile's collider top is at y = 0")
	var n := _part("ground_grass")
	var top := -INF
	for cs in n.get_node("Hull").get_children():
		var c := cs as CollisionShape3D
		top = maxf(top, c.position.y + (c.shape as BoxShape3D).size.y * 0.5)
	approx(top, 0.0, 0.01, "tile top")
	_drop(n)
	end()


func test_parts_keep_the_habitat_heights() -> void:
	begin("habitat parts: the walkway deck is 16 m up and the bridge slab top 19.6 m")
	var n := _part("walkway_pier")
	var deck := -INF
	for cs in n.get_node("Hull").get_children():
		var c := cs as CollisionShape3D
		var size := (c.shape as BoxShape3D).size
		if absf(size.x - PART_SCRIPT.WALK_HALF * 2.0) < 0.01:
			deck = maxf(deck, c.position.y + size.y * 0.5)
	approx(deck, PART_SCRIPT.DECK_Y, 0.05, "walkway deck height")
	_drop(n)
	var b := _part("rock_bridge")
	var slab := -INF
	for cs in b.get_node("Hull").get_children():
		var c := cs as CollisionShape3D
		var top: float = c.position.y + (c.shape as BoxShape3D).size.y * 0.5
		if top < PART_SCRIPT.BRIDGE_TOP - 0.1:
			slab = maxf(slab, top)
	approx(slab, PART_SCRIPT.BRIDGE_TOP - 0.4, 0.05, "bridge slab top")
	_drop(b)
	end()


func test_swapping_kind_replaces_the_geometry() -> void:
	begin("habitat parts: changing kind rebuilds instead of stacking")
	var n := _part("ground_grass")
	var before := n.get_node("Hull").get_child_count()
	n.set("kind", "ground_soil")
	eq(n.get_node("Hull").get_child_count(), before, "collider count after a swap")
	n.set("kind", "tree")
	eq(n.get_node("Hull").get_child_count(), 0, "a tree has no colliders")
	_drop(n)
	end()


func test_tower_height_is_adjustable() -> void:
	begin("habitat parts: tower_height changes the column")
	var n := _part("tower")
	var tall := 0.0
	for cs in n.get_node("Hull").get_children():
		var c := cs as CollisionShape3D
		if c.shape is BoxShape3D:
			tall = maxf(tall, (c.shape as BoxShape3D).size.y)
	approx(tall, 70.0, 0.01, "default column height")
	n.set("tower_height", 100.0)
	tall = 0.0
	for cs in n.get_node("Hull").get_children():
		var c := cs as CollisionShape3D
		if c.shape is BoxShape3D:
			tall = maxf(tall, (c.shape as BoxShape3D).size.y)
	approx(tall, 100.0, 0.01, "height after the change")
	_drop(n)
	end()


func test_nothing_generated_is_owned() -> void:
	begin("habitat parts: no generated child has an owner, so none of it reaches a .tscn")
	var n := _part("hydro_bed")
	var owned := 0
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		for child in c.get_children():
			if child.owner != null:
				owned += 1
			stack.append(child)
	eq(owned, 0, "owned generated children")
	_drop(n)
	end()


func test_the_library_holds_every_part_once_without_overlap() -> void:
	begin("habitat parts: the library scene has each part, labelled, footprints apart")
	var lib := _spawn(LIBRARY.instantiate())
	var kinds := {}
	var rects: Array[Rect2] = []
	for c in lib.get_children():
		var part := c as Node3D
		if part == null or not part.has_method("_p_tree"):
			continue
		kinds[part.get("kind")] = true
		check(part.has_node("PartLabel"), "%s has a label" % part.get("kind"))
		var e: Array = PART_SCRIPT.entry_for(part.get("kind"))
		rects.append(Rect2(part.position.x + float(e[4]) - float(e[2]) * 0.5,
			part.position.z + float(e[5]) - float(e[3]) * 0.5, e[2], e[3]))
	eq(kinds.size(), PART_SCRIPT.PARTS.size(), "distinct parts in the library")
	var overlaps := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				overlaps += 1
	eq(overlaps, 0, "overlapping footprints")
	_drop(lib)
	end()


func test_the_library_floor_is_solid_with_a_pit_under_the_water_tile() -> void:
	begin("habitat parts: floor is solid everywhere but the water tile's hole")
	var lib := _spawn(LIBRARY.instantiate())
	var solids: Array[AABB] = []
	for cs in lib.get_node("Hull").get_children():
		var c := cs as CollisionShape3D
		if c and c.shape is BoxShape3D:
			var half := (c.shape as BoxShape3D).size * 0.5
			solids.append(c.transform * AABB(-half, half * 2.0))
	var water: Node3D = null
	for c in lib.get_children():
		if c.get("kind") == "water_tile":
			water = c
	check(water != null, "the library has a water tile")
	var p := Vector3(water.position.x, -1.0, water.position.z)
	var hit_pit := false
	var hit_floor := false
	for a in solids:
		if a.has_point(p):
			hit_pit = true
		if a.has_point(Vector3(5.0, -1.0, 5.0)):
			hit_floor = true
	check(not hit_pit, "no floor over the water tile")
	check(hit_floor, "floor elsewhere")
	_drop(lib)
	end()
