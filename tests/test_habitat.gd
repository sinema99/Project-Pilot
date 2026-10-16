extends "res://tests/test_case.gd"

# Covers the 2026-09-30 habitat. See docs/specs/mead-habitat.md.
#
# What it fences is what a reshuffle of the generator could break without a single error: the
# cab deck and its causeway have to be solid at the height the node is offset by, the lake has to
# stay a no-collider surface over a solid bed, the bridge has to be a deck you can stand on that
# actually reaches the tower, the tower has to be solid, and none of it may be saved into the
# scene file.

const HABITAT_SCENE := preload("res://scenes/habitat.tscn")


func _spawn() -> Node3D:
	var h := HABITAT_SCENE.instantiate() as Node3D
	(Engine.get_main_loop() as SceneTree).root.add_child(h)
	return h


func _drop(node: Node) -> void:
	if is_instance_valid(node):
		if node.get_parent():
			node.get_parent().remove_child(node)
		node.free()


# All the colliders / visual nodes of every section.
func _hull_children(h: Node3D) -> Array[Node]:
	var out: Array[Node] = []
	for sec: Array in h.SECTIONS:
		var n := h.get_node_or_null(NodePath(sec[0] + "/Hull"))
		if n:
			out.append_array(n.get_children())
	return out


func _vis_children(h: Node3D) -> Array[Node]:
	var out: Array[Node] = []
	for sec: Array in h.SECTIONS:
		var n := h.get_node_or_null(NodePath(sec[0] + "/Visual"))
		if n:
			out.append_array(n.get_children())
	return out


# Every box collider in the habitat as a local-space AABB.
func _solids(h: Node3D) -> Array[AABB]:
	var out: Array[AABB] = []
	for cs in _hull_children(h):
		var c := cs as CollisionShape3D
		if c and c.shape is BoxShape3D:
			var half := (c.shape as BoxShape3D).size * 0.5
			out.append(c.transform * AABB(-half, half * 2.0))
	return out


func _stand_at(solids: Array[AABB], x: float, y: float, z: float) -> bool:
	for a in solids:
		if absf(a.end.y - y) < 0.05 and x >= a.position.x and x <= a.end.x \
				and z >= a.position.z and z <= a.end.z:
			return true
	return false


func _covered(solids: Array[AABB], p: Vector3) -> bool:
	for a in solids:
		if a.has_point(p):
			return true
	return false


func test_the_cab_walkway_is_solid_from_the_cab_to_the_causeway_end() -> void:
	begin("habitat: the walkway deck is solid at DECK_Y under the cab and out along the causeway")
	var h := _spawn()
	var s := _solids(h)
	check(_stand_at(s, 0.0, h.DECK_Y, h.VANTAGE.z), "deck under the vantage")
	check(_stand_at(s, 0.0, h.DECK_Y, h.CAB_Z0 + 2.0), "deck inside the cab")
	check(_stand_at(s, 0.0, h.DECK_Y, h.WALK_END + h.causeway_length - 2.0), "deck at the far end of the causeway")
	_drop(h)
	end()


func test_the_vantage_marker_is_where_the_camera_belongs() -> void:
	begin("habitat: the CabVantage marker sits above the deck at eye height")
	var h := _spawn()
	var m := h.get_node_or_null("CabVantage") as Marker3D
	check(m != null, "the habitat generates a CabVantage marker")
	if m:
		approx(m.position.y - h.DECK_Y, 1.7, 0.05, "eye height over the deck")
	_drop(h)
	end()


func test_the_lake_is_water_over_a_solid_bed() -> void:
	begin("habitat: the water has no collider and the bed under it is solid")
	var h := _spawn()
	var s := _solids(h)
	check(h.find_child("Water", true, false) != null, "the lake has a Water surface")
	check(_stand_at(s, -10.0, h.BED_Y, -30.0), "a solid top at the bed height in open water")
	check(not _covered(s, Vector3(-10.0, h.WATER_Y + 0.2, -30.0)),
		"nothing solid at the water line in open water")
	check(not (h.find_child("Water", true, false) is CollisionObject3D), "the water surface is not a physics body")
	_drop(h)
	end()


func test_the_bridge_reaches_the_tower_and_the_tower_is_solid() -> void:
	begin("habitat: the rock bridge is a deck that runs into the solid tower")
	var h := _spawn()
	var s := _solids(h)
	var zc: float = (h.BRIDGE_Z0 + h.BRIDGE_Z1) * 0.5
	check(_stand_at(s, -40.0, h.BRIDGE_TOP - 0.4, zc), "bridge slab top, mid span")
	check(_stand_at(s, h.TOWER_X0 - 0.5, h.BRIDGE_TOP - 0.4, zc), "bridge slab top, at the tower face")
	check(_covered(s, Vector3(h.TOWER_X0 + 2.0, 60.0, zc)), "the tower is solid above the bridge")
	check(_covered(s, Vector3(h.TOWER_X1 - 1.0, h.TOWER_TOP - 3.0, zc)), "and reaches the vault")
	_drop(h)
	end()


func test_plants_are_batched_and_never_solid() -> void:
	begin("habitat: crops and trees are MultiMeshes and add no colliders")
	var h := _spawn()
	var mm_count := 0
	var instances := 0
	for child in _vis_children(h):
		var mmi := child as MultiMeshInstance3D
		if mmi:
			mm_count += 1
			instances += mmi.multimesh.instance_count
	check(mm_count > 10, "a batch per mesh and colour")
	check(instances > 10000, "thousands of crop and tree instances")
	for cs in _hull_children(h):
		check(cs is CollisionShape3D, "Hull holds only collision shapes")
	_drop(h)
	end()


func test_nothing_generated_is_owned() -> void:
	begin("habitat: no generated child has an owner, so none of it reaches the .tscn")
	var h := _spawn()
	var owned := 0
	var stack: Array[Node] = [h]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for child in n.get_children():
			# The section nodes are stored in habitat.tscn on purpose: they are the handles.
			var is_section := (h.SECTIONS as Array).any(func(sec: Array) -> bool: return sec[0] == String(child.name))
			if child.owner != null and not is_section:
				owned += 1
			stack.append(child)
	eq(owned, 0, "owned generated children")
	_drop(h)
	end()


func test_rebuilding_does_not_stack_geometry() -> void:
	begin("habitat: a rebuild replaces the map instead of adding a second one")
	var h := _spawn()
	var before := _hull_children(h).size()
	h._build()
	eq(_hull_children(h).size(), before, "collider count after a rebuild")
	_drop(h)
	end()


func test_moving_a_section_moves_its_colliders() -> void:
	begin("habitat: a section is a handle - its colliders follow it, and hiding it removes them")
	var h := _spawn()
	var tower := h.get_node("Tower") as Node3D
	var probe := Vector3(40.0, 60.0, -58.0)
	var world_probe := h.to_global(probe)
	check(_covered(_solids(h), probe), "the tower is where it was built")
	tower.position = Vector3(0.0, 0.0, 200.0)
	var moved := h.to_global(tower.get_node("Hull").get_child(0).position)
	check(tower.get_node("Hull").get_child_count() > 0, "the tower has colliders of its own")
	check(tower.to_global(probe).is_equal_approx(world_probe + Vector3(0.0, 0.0, 200.0)),
		"a point in the tower follows the node")
	tower.position = Vector3.ZERO
	tower.visible = false
	h._build()
	eq(tower.get_node("Hull").get_child_count() if tower.has_node("Hull") else 0, 0, "hidden tower has no colliders")
	_drop(h)
	end()
