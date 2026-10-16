extends "res://tests/test_case.gd"

# Covers the 2026-09-30 pipe hall. See docs/specs/pipe-hall.md.
#
# What it fences is what a reshuffle of the generator could break without a single error: the
# hall has to be reachable (a causeway that stops short of the jump grid's slab is a hall nobody
# can enter), the floor has to sit at the height the slab does, the catwalks have to be solid,
# the grind rail has to register as a rail, and none of it may be saved into the scene file.

const HALL_SCENE := preload("res://scenes/pipe_hall.tscn")
## The jump grid's +Z slab edge, local to the hall: world z 25 minus the hall's z of 84.
const SLAB_EDGE_LOCAL_Z := -59.0


func _spawn() -> Node3D:
	var hall := HALL_SCENE.instantiate() as Node3D
	(Engine.get_main_loop() as SceneTree).root.add_child(hall)
	return hall


func _drop(node: Node) -> void:
	if is_instance_valid(node):
		if node.get_parent():
			node.get_parent().remove_child(node)
		node.free()


# Every solid in the hall as a world-space AABB of its collision shape.
func _solids(hall: Node3D) -> Array[AABB]:
	var out: Array[AABB] = []
	for cs in hall.get_node("Hull").get_children():
		var c := cs as CollisionShape3D
		if c and c.shape is BoxShape3D:
			var half := (c.shape as BoxShape3D).size * 0.5
			var box := AABB(-half, half * 2.0)
			out.append(c.transform * box)
	return out


# Is there a solid whose top face is at `y`, covering the point (x, z)?
func _stand_at(solids: Array[AABB], x: float, y: float, z: float) -> bool:
	for a in solids:
		if absf(a.end.y - y) < 0.05 and x >= a.position.x and x <= a.end.x \
				and z >= a.position.z and z <= a.end.z:
			return true
	return false


func test_causeway_reaches_the_slab_and_the_floor() -> void:
	begin("pipe hall: the causeway runs from the jump grid's edge to the door")
	var hall := _spawn()
	var solids := _solids(hall)
	check(_stand_at(solids, 0.0, 0.0, SLAB_EDGE_LOCAL_Z + 0.5),
		"a solid at y = 0 stands at the slab edge, so the causeway meets it")
	check(_stand_at(solids, 0.0, 0.0, -hall.HALF_Z - 1.0), "and one just outside the door")
	check(_stand_at(solids, 0.0, 0.0, 0.0), "and the hall floor is at y = 0 too")
	_drop(hall)
	end()


func test_the_catwalks_are_solid() -> void:
	begin("pipe hall: catwalk A, B and platform C have decks you can stand on")
	var hall := _spawn()
	var solids := _solids(hall)
	check(_stand_at(solids, 0.0, 14.0, 3.0), "catwalk A deck at y = 14")
	check(_stand_at(solids, -20.0, 7.0, -14.0), "catwalk B deck at y = 7")
	check(_stand_at(solids, 40.0, 20.0, -1.5), "platform C deck at y = 20")
	_drop(hall)
	end()


func test_the_grind_rail_is_a_real_rail() -> void:
	begin("pipe hall: the grind rail joins the rails group and has a ride")
	var hall := _spawn()
	var rail := hall.get_node_or_null("GrindRail")
	check(rail != null, "the hall generates a GrindRail")
	if rail:
		check(rail.is_in_group("rails"), "it is in the `rails` group pilot9 looks rails up by")
		check(rail.ride_length() > 20.0, "and it is a long ride, not a stub")
		check(rail.get_node_or_null("Tube") != null, "with a tube to look at")
	_drop(hall)
	end()


func test_nothing_generated_is_owned() -> void:
	begin("pipe hall: no generated child has an owner, so none of it reaches the .tscn")
	var hall := _spawn()
	var owned := 0
	var stack: Array[Node] = [hall]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for child in n.get_children():
			if child.owner != null:
				owned += 1
			stack.append(child)
	eq(owned, 0, "owned generated children")
	_drop(hall)
	end()


func test_rebuilding_does_not_stack_geometry() -> void:
	begin("pipe hall: a rebuild replaces the hall instead of adding a second one")
	var hall := _spawn()
	var before := hall.get_node("Hull").get_child_count()
	hall._build()
	# queue_free defers, so look through the name rather than the child count of the root.
	eq(hall.get_node("Hull").get_child_count(), before, "collider count after a rebuild")
	_drop(hall)
	end()
