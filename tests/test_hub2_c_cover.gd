extends "res://tests/test_case.gd"

# Room C enemy cover + crane column fix (docs/specs/hub2-room-c-cover.md), read from the editable source
# scene that tools/gen_hub2_c_cover.gd wrote.

const SRC := "res://scenes/hub2_dressing_src.tscn"

var _nodes: Array[Node] = []

func end() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	super()

func _src() -> Node3D:
	var src := (load(SRC) as PackedScene).instantiate() as Node3D
	_nodes.append(src)
	(Engine.get_main_loop() as SceneTree).root.add_child(src)
	return src

## A box pulled in by up to 0.08 m a side (never inverted) so boxes that merely touch do not count.
func _shrunk(a: AABB) -> AABB:
	var d := Vector3(minf(0.08, a.size.x * 0.4), minf(0.08, a.size.y * 0.4), minf(0.08, a.size.z * 0.4))
	return AABB(a.position + d, a.size - d * 2.0)

## World-space AABB of every collision box under a node.
func _boxes(n: Node) -> Array[AABB]:
	var out: Array[AABB] = []
	for cs in n.find_children("*", "CollisionShape3D", true, false):
		var shape := (cs as CollisionShape3D).shape as BoxShape3D
		if shape == null:
			continue
		var xf := (cs as CollisionShape3D).global_transform
		var a := AABB(xf * (-shape.size * 0.5), Vector3.ZERO)
		for sx in [-0.5, 0.5]:
			for sy in [-0.5, 0.5]:
				for sz in [-0.5, 0.5]:
					a = a.expand(xf * (Vector3(sx, sy, sz) * shape.size))
		out.append(a)
	return out

func test_cover_group_has_the_mix() -> void:
	var cover := _src().get_node_or_null("C/Cover")
	check(cover != null, "C/Cover exists")
	if cover == null:
		return
	var jersey := 0
	var shields := 0
	var crates := 0
	var containers := 0
	for ch in cover.get_children():
		if ch is Hub2Prop:
			match (ch as Hub2Prop).kind:
				Hub2Prop.Kind.JERSEY_BARRIER: jersey += 1
				Hub2Prop.Kind.PLATE_SHIELD: shields += 1
				Hub2Prop.Kind.CRATE_WOOD, Hub2Prop.Kind.CRATE_METAL, Hub2Prop.Kind.PALLET: crates += 1
		elif ch is CargoContainer:
			containers += 1
	check(jersey >= 8, "jersey barriers in runs (%d)" % jersey)
	check(shields >= 1, "a plate shield (%d)" % shields)
	check(crates >= 10, "crate piles (%d)" % crates)
	check(containers >= 2, "full-height containers (%d)" % containers)

func test_cover_is_clear_of_the_lane_entrance_and_ramp_foot() -> void:
	var cover := _src().get_node("C/Cover") as Node3D
	var from: Vector2 = cover.get_meta(&"lane_from")
	var to: Vector2 = cover.get_meta(&"lane_to")
	var half: float = cover.get_meta(&"lane_half")
	var ent_r: float = cover.get_meta(&"entrance_r")
	var foot: Rect2 = cover.get_meta(&"foot_rect")
	for a in _boxes(cover):
		var c := Vector2(a.get_center().x, a.get_center().z)
		var r := minf(a.size.x, a.size.z) * 0.5
		check(Geometry2D.get_closest_point_to_segment(c, from, to).distance_to(c) >= half + r - 0.6, "lane clear at %s" % c)
		check(c.distance_to(from) >= ent_r, "entrance mouth clear at %s" % c)
		check(not foot.intersects(Rect2(a.position.x, a.position.z, a.size.x, a.size.z)), "ramp foot clear at %s" % c)
	for i in 8:
		var p := from.lerp(to, i / 7.0)
		for a in _boxes(cover):
			check(not Rect2(a.position.x, a.position.z, a.size.x, a.size.z).intersects(Rect2(p.x - half + 0.2, p.y - half + 0.2, half * 2 - 0.4, half * 2 - 0.4)), "4 m lane open at %s" % p)

func test_cover_pieces_do_not_overlap_each_other_or_existing_dressing() -> void:
	var src := _src()
	var mine: Array[AABB] = []
	var others: Array[AABB] = []
	for n in src.get_node("C").get_children():
		if n.name == &"Cover":
			continue
		if n.name == &"Cranes":
			continue
		others.append_array(_boxes(n))
	for ch in src.get_node("C/Cover").get_children():
		for a in _boxes(ch):
			mine.append(a)
	for i in mine.size():
		for j in range(i + 1, mine.size()):
			# Stacked crates touch by design (the bottom of one is the top of the other).
			check(not _shrunk(mine[i]).intersects(_shrunk(mine[j])), "cover piece %d overlaps cover piece %d" % [i, j])
		for o in others:
			check(not _shrunk(mine[i]).intersects(_shrunk(o)), "cover piece %d overlaps existing room C dressing at %s" % [i, o.get_center()])

func test_cover_rests_on_the_floor_and_is_solid() -> void:
	var cover := _src().get_node("C/Cover") as Node3D
	for ch in cover.get_children():
		check(not _boxes(ch).is_empty(), "%s has collision" % ch.name)
		check((ch as Node3D).position.y > 30.9 and (ch as Node3D).position.y < 35.0, "%s stands on room C's floor or on cover (y %.2f)" % [ch.name, (ch as Node3D).position.y])

func test_crane_skips_columns_that_stand_in_the_map() -> void:
	var src := _src()
	var crane := src.get_node("C/Cranes/BridgeCrane") as Hub2Crane
	check(crane.skip_columns.size() >= 1, "some column is skipped")
	var slots := crane.column_slots()
	var expect := slots.size() - crane.skip_columns.size()
	var cols := 0
	for b in crane.find_children("Box*", "CollisionShape3D", true, false):
		var s := (b as CollisionShape3D).shape as BoxShape3D
		if s.size.is_equal_approx(Vector3(0.8, crane.rail_height - 0.8, 0.8)):
			cols += 1
	eq(cols, expect, "only the kept columns carry collision")
	for s in crane.skip_columns:
		check(crane.is_column_skipped(s.x, s.y), "skip list answers true")
	# The girder and rails are untouched: same visual node, still there.
	check(crane.get_node_or_null("Visual") != null, "crane still has its mesh")

func test_new_prop_kinds_build_solid_with_collision() -> void:
	for k in [Hub2Prop.Kind.JERSEY_BARRIER, Hub2Prop.Kind.PLATE_SHIELD]:
		for v in 2:
			var made := Hub2PropBuild.build(k, v, 3, 0.8, false, 3.0)
			check((made["mesh"] as ArrayMesh).get_faces().size() > 0, "%s v%d builds" % [Hub2Prop.Kind.keys()[k], v])
			eq((made["boxes"] as Array).size(), 1, "%s v%d has one collision box" % [Hub2Prop.Kind.keys()[k], v])
			var box: Vector3 = (made["boxes"] as Array)[0][1]
			check(box.y > 1.0 and box.y < 1.3, "%s is about 1.1 m high (vaultable)" % Hub2Prop.Kind.keys()[k])
